import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sessao_loja.dart';

class ListaComprasService {
  SupabaseClient get _supabase {
    final cliente = SessaoLoja.supabaseLoja;
    if (cliente == null) {
      throw Exception('Conexao da loja nao configurada.');
    }
    return cliente;
  }

  String get _mercadoId => SessaoLoja.mercadoIdObrigatorio;
  String get _mercadoCodigo => SessaoLoja.mercadoCodigoObrigatorio;

  String get _usuarioNome {
    final nome = SessaoLoja.usuarioNome?.trim() ?? '';
    if (nome.isNotEmpty) return nome;
    final login = SessaoLoja.usuarioLogin?.trim() ?? '';
    return login.isEmpty ? 'Usuario' : login;
  }

  String get _apiBaseUrl {
    var url = SessaoLoja.apiBaseUrl?.trim() ?? '';
    if (url.isEmpty) {
      throw Exception('Nenhuma API configurada para esta loja.');
    }
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return url;
  }

  String _texto(dynamic valor, {String fallback = ''}) {
    final convertido = valor?.toString().trim() ?? '';
    return convertido.isEmpty || convertido.toLowerCase() == 'null'
        ? fallback
        : convertido;
  }

  double _numero(dynamic valor) {
    if (valor is num) return valor.toDouble();
    var convertido = _texto(valor).replaceAll('R\$', '').replaceAll(' ', '');
    if (convertido.contains(',')) {
      convertido = convertido.replaceAll('.', '').replaceAll(',', '.');
    }
    return double.tryParse(convertido) ?? 0;
  }

  String eanProduto(Map<String, dynamic> produto) {
    return _texto(
      produto['ean_principal'] ??
          produto['ean'] ??
          produto['codigo_barras'] ??
          produto['codigo'],
    );
  }

  String produtoId(Map<String, dynamic> produto) {
    return _texto(
      produto['produto_id'] ?? produto['id'] ?? eanProduto(produto),
    );
  }

  Future<Map<String, dynamic>> criarLista() async {
    final resposta = await _supabase.rpc(
      'criar_lista_compras',
      params: {
        'p_mercado_id': _mercadoId,
        'p_mercado_codigo': _mercadoCodigo,
        'p_usuario_nome': _usuarioNome,
      },
    );

    if (resposta is Map) {
      return Map<String, dynamic>.from(resposta);
    }
    if (resposta is List && resposta.isNotEmpty && resposta.first is Map) {
      return Map<String, dynamic>.from(resposta.first as Map);
    }
    throw Exception('A criação da lista não retornou confirmação.');
  }

  Future<Map<String, dynamic>> adicionarProduto(
    Map<String, dynamic> produto,
  ) async {
    final ean = eanProduto(produto);
    final id = produtoId(produto);
    if (ean.isEmpty || id.isEmpty) {
      throw Exception('Produto sem identificador ou EAN.');
    }

    final resposta = await _supabase.rpc(
      'adicionar_item_lista_compras',
      params: {
        'p_mercado_id': _mercadoId,
        'p_mercado_codigo': _mercadoCodigo,
        'p_produto_id': id,
        'p_ean': ean,
        'p_nome_produto': _texto(
          produto['nome_produto'] ?? produto['descricao'] ?? produto['produto'],
          fallback: 'Produto',
        ),
        'p_unidade': _texto(
          produto['sigla_saida'] ??
              produto['unidade'] ??
              produto['unidade_medida'],
        ),
        'p_estoque_inicial': _numero(
          produto['estoque_atual'] ?? produto['estoque'],
        ),
        'p_usuario_nome': _usuarioNome,
      },
    );

    late Map<String, dynamic> resultado;
    if (resposta is Map) {
      resultado = Map<String, dynamic>.from(resposta);
    } else if (resposta is List &&
        resposta.isNotEmpty &&
        resposta.first is Map) {
      resultado = Map<String, dynamic>.from(resposta.first as Map);
    } else {
      throw Exception('A lista nao retornou confirmacao da inclusao.');
    }

    // A inclusao nao deve falhar se a API estiver temporariamente indisponivel.
    // Nesse caso, o resumo sera atualizado quando o usuario abrir o item.
    try {
      final itemId = _texto(resultado['item_id']);
      if (itemId.isNotEmpty) {
        final resumo = await buscarResumoProduto(ean);
        await atualizarResumoItem(itemId: itemId, resumo: resumo);
        resultado['resumo_atualizado'] = true;
      }
    } catch (_) {
      resultado['resumo_atualizado'] = false;
    }

    return resultado;
  }

  Future<Map<String, dynamic>?> carregarListaAtiva() async {
    final resposta = await _supabase
        .from('listas_compras')
        .select(
          'id, status, criado_por_nome, criado_em, atualizado_em, exportado_em, arquivo_nome',
        )
        .eq('mercado_id', _mercadoId)
        .eq('status', 'ATIVA')
        .order('criado_em', ascending: false)
        .limit(1)
        .maybeSingle();

    return resposta == null ? null : Map<String, dynamic>.from(resposta);
  }

  Future<List<Map<String, dynamic>>> carregarItens(String listaId) async {
    final resposta = await _supabase
        .from('lista_compras_itens')
        .select(
          'id, lista_id, produto_id, ean, nome_produto, unidade, fornecedor_selecionado, preco_referencia, quantidade_pedida, estoque_snapshot, vendas_30_dias_snapshot, compras_recentes, criado_em, atualizado_em',
        )
        .eq('lista_id', listaId)
        .order('criado_em', ascending: true);

    return List<Map<String, dynamic>>.from(resposta);
  }

  Future<Map<String, dynamic>> buscarResumoProduto(String ean) async {
    final url = Uri.parse(
      '$_apiBaseUrl/produto/ean/${Uri.encodeComponent(ean)}/resumo-compras',
    );
    final resposta = await http.get(url).timeout(const Duration(seconds: 25));
    dynamic dados;
    try {
      dados = jsonDecode(resposta.body);
    } catch (_) {
      dados = null;
    }

    if (resposta.statusCode < 200 || resposta.statusCode >= 300) {
      final mensagem = dados is Map ? _texto(dados['erro']) : '';
      throw Exception(
        mensagem.isEmpty
            ? 'Erro HTTP ${resposta.statusCode} ao consultar compras.'
            : mensagem,
      );
    }
    if (dados is! Map) {
      throw Exception('Resposta invalida da API ao consultar compras.');
    }
    return Map<String, dynamic>.from(dados);
  }

  Future<void> configurarItem({
    required String itemId,
    required String fornecedor,
    required double precoReferencia,
    required double quantidadePedida,
    required double estoqueAtual,
    required double vendas30Dias,
    required List<Map<String, dynamic>> comprasRecentes,
  }) async {
    await _supabase
        .from('lista_compras_itens')
        .update({
          'fornecedor_selecionado': fornecedor,
          'preco_referencia': precoReferencia,
          'quantidade_pedida': quantidadePedida,
          'estoque_snapshot': estoqueAtual,
          'vendas_30_dias_snapshot': vendas30Dias,
          'compras_recentes': comprasRecentes,
        })
        .eq('id', itemId);
  }

  Future<void> atualizarResumoItem({
    required String itemId,
    required Map<String, dynamic> resumo,
  }) async {
    final comprasRaw = resumo['compras_recentes'];
    final compras = comprasRaw is List
        ? comprasRaw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .take(2)
              .toList()
        : <Map<String, dynamic>>[];

    await _supabase
        .from('lista_compras_itens')
        .update({
          'estoque_snapshot': _numero(resumo['estoque_atual']),
          'vendas_30_dias_snapshot': _numero(resumo['qtd_vendida_30_dias']),
          'compras_recentes': compras,
        })
        .eq('id', itemId);
  }

  Future<void> removerItem(String itemId) async {
    await _supabase.from('lista_compras_itens').delete().eq('id', itemId);
  }

  Future<void> registrarExportacao({
    required String listaId,
    required String arquivoNome,
  }) async {
    await _supabase
        .from('listas_compras')
        .update({
          'exportado_em': DateTime.now().toIso8601String(),
          'arquivo_nome': arquivoNome,
        })
        .eq('id', listaId);
  }

  Future<void> finalizarLista(String listaId) async {
    await _supabase
        .from('listas_compras')
        .update({
          'status': 'FINALIZADA',
          'finalizado_em': DateTime.now().toIso8601String(),
        })
        .eq('id', listaId)
        .eq('status', 'ATIVA');
  }
}

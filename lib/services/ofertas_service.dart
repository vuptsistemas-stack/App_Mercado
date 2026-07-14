import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/produto.dart';
import 'api_service.dart';
import 'sessao_mercado_cliente.dart' as sessao;

class OfertaProdutoHome {
  final String id;
  final String origemPreco;
  final String tipoOferta;
  final Produto produto;
  final double? precoApp;
  final double? precoApiReferencia;
  final Map<String, dynamic> dadosOriginais;

  const OfertaProdutoHome({
    required this.id,
    required this.origemPreco,
    this.tipoOferta = 'OFERTA',
    required this.produto,
    this.precoApp,
    this.precoApiReferencia,
    this.dadosOriginais = const {},
  });

  bool get usaPrecoApp => origemPreco.trim().toUpperCase() == 'APP';
  bool get usaPrecoApi => !usaPrecoApp;
  bool get ehSuperOferta => tipoOferta.trim().toUpperCase() == 'SUPER_OFERTA';
}

class OfertasService {
  OfertasService._();

  static SupabaseClient get _supabase => Supabase.instance.client;

  static Future<List<OfertaProdutoHome>> listarOfertasAtivas({
    int limite = 12,
    String tipoOferta = 'OFERTA',
  }) async {
    try {
      final tipoFiltro = tipoOferta.trim().toUpperCase() == 'SUPER_OFERTA'
          ? 'SUPER_OFERTA'
          : 'OFERTA';

      final limiteConsulta = (limite * 20).clamp(50, 300).toInt();

      final resposta = await _supabase
          .from('produto_ofertas')
          .select()
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .eq('ativo', true)
          .eq('tipo_oferta', tipoFiltro)
          .order('criado_em', ascending: false)
          .limit(limiteConsulta);

      final dados = List<Map<String, dynamic>>.from(resposta);

      final resultado = <OfertaProdutoHome>[];

      for (final oferta in dados.where(_ofertaDentroDoPeriodo)) {
        final item = await _montarOfertaHome(oferta);

        if (item != null) {
          resultado.add(item);
        }

        if (resultado.length >= limite) {
          break;
        }
      }

      return resultado;
    } catch (_) {
      return [];
    }
  }

  static Future<Produto> aplicarPrecoOfertaAtiva(Produto produto) async {
    try {
      final oferta = await buscarOfertaAtivaPorProduto(produto);

      if (oferta == null) {
        return produto;
      }

      final origemPreco = _texto(oferta['origem_preco']).toUpperCase();

      if (origemPreco != 'APP') {
        return produto;
      }

      final precoApp = _numero(oferta['preco_app']);

      if (precoApp <= 0) {
        return produto;
      }

      return produtoComPreco(produto, precoApp);
    } catch (_) {
      return produto;
    }
  }

  static Future<Map<String, dynamic>?> buscarOfertaAtivaPorProduto(
    Produto produto,
  ) async {
    final ean = produto.ean.trim();
    final produtoId = produto.produtoId;

    try {
      List<dynamic> resposta = [];

      if (ean.isNotEmpty) {
        resposta = await _supabase
            .from('produto_ofertas')
            .select()
            .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
            .eq('ativo', true)
            .eq('ean', ean)
            .order('criado_em', ascending: false)
            .limit(5);
      }

      if (resposta.isEmpty && produtoId > 0) {
        resposta = await _supabase
            .from('produto_ofertas')
            .select()
            .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
            .eq('ativo', true)
            .eq('produto_id', produtoId.toString())
            .order('criado_em', ascending: false)
            .limit(5);
      }

      final ofertas = List<Map<String, dynamic>>.from(resposta);

      for (final oferta in ofertas) {
        if (_ofertaDentroDoPeriodo(oferta)) {
          return oferta;
        }
      }
    } catch (_) {}

    return null;
  }

  static Produto produtoComPreco(Produto produto, double preco) {
    final dados = Map<String, dynamic>.from(produto.toJson());

    dados['preco'] = preco;
    dados['preco_venda'] = preco;
    dados['valor'] = preco;
    dados['valor_venda'] = preco;
    dados['preco_app'] = preco;

    return Produto.fromJson(dados);
  }

  static Future<OfertaProdutoHome?> _montarOfertaHome(
    Map<String, dynamic> oferta,
  ) async {
    final origemPreco = _texto(oferta['origem_preco']).toUpperCase();
    final origemFinal = origemPreco == 'APP' ? 'APP' : 'API';
    final tipoOferta = _tipoOferta(oferta);

    final produtoApi = await _buscarProdutoOfertaNaApi(oferta);
    Produto? produtoFinal;
    final produtoEncontradoNaApi = produtoApi != null;

    if (origemFinal == 'API') {
      final precoReferencia = _numero(oferta['preco_api_referencia']);
      produtoFinal = produtoApi ?? _produtoBasicoOferta(oferta, precoReferencia);
    } else {
      final precoApp = _numero(oferta['preco_app']);

      if (precoApp <= 0) {
        return null;
      }

      final base = produtoApi ?? _produtoBasicoOferta(oferta, precoApp);
      produtoFinal = produtoComPreco(base, precoApp);
    }

    if (produtoFinal == null || produtoFinal.nome.trim().isEmpty) {
      return null;
    }

    if (produtoEncontradoNaApi &&
        !await ApiService.deveExibirProdutoNoApp(produtoFinal)) {
      return null;
    }

    return OfertaProdutoHome(
      id: _texto(oferta['id']),
      origemPreco: origemFinal,
      tipoOferta: tipoOferta,
      produto: produtoFinal,
      precoApp: _numeroOuNull(oferta['preco_app']),
      precoApiReferencia: _numeroOuNull(oferta['preco_api_referencia']),
      dadosOriginais: Map<String, dynamic>.from(oferta),
    );
  }

  static Future<Produto?> _buscarProdutoOfertaNaApi(
    Map<String, dynamic> oferta,
  ) async {
    final ean = _texto(oferta['ean']);
    final nome = _texto(oferta['nome_produto']);

    if (ean.isNotEmpty) {
      final produtos = await ApiService.buscarProdutos(ean);

      if (produtos.isNotEmpty) {
        return produtos.first;
      }
    }

    if (nome.isNotEmpty) {
      final produtos = await ApiService.buscarProdutos(nome);

      if (produtos.isNotEmpty) {
        return produtos.first;
      }
    }

    return null;
  }

  static Produto _produtoBasicoOferta(
    Map<String, dynamic> oferta,
    double preco,
  ) {
    final nome = _texto(oferta['nome_produto']);
    final ean = _texto(oferta['ean']);
    final produtoId = _texto(oferta['produto_id']);

    return Produto.fromJson({
      'produto_id': produtoId,
      'id': produtoId,
      'nome_produto': nome,
      'nome': nome,
      'descricao': nome,
      'ean_principal': ean,
      'ean': ean,
      'codigo_barras': ean,
      'preco': preco,
      'preco_venda': preco,
      'valor': preco,
      'valor_venda': preco,
      'estoque': _numero(oferta['estoque']),
      'estoque_atual': _numero(oferta['estoque_atual'] ?? oferta['estoque']),
      'quantidade': _numero(oferta['quantidade'] ?? oferta['estoque']),
      'saldo': _numero(oferta['saldo'] ?? oferta['estoque']),
      'sigla_saida': _texto(oferta['sigla_saida']).isEmpty
          ? 'UN'
          : _texto(oferta['sigla_saida']),
      'unidade': _texto(oferta['unidade']).isEmpty
          ? _texto(oferta['unidade_medida'])
          : _texto(oferta['unidade']),
      'unidade_medida': _texto(oferta['unidade_medida']).isEmpty
          ? 'UN'
          : _texto(oferta['unidade_medida']),
      'imagem_url': _texto(oferta['imagem_url']),
    });
  }

  static bool _ofertaDentroDoPeriodo(Map<String, dynamic> oferta) {
    final agora = DateTime.now();

    final dataInicio = _data(oferta['data_inicio']);
    final dataFim = _data(oferta['data_fim']);

    if (dataInicio != null && agora.isBefore(dataInicio)) {
      return false;
    }

    if (dataFim != null && agora.isAfter(dataFim)) {
      return false;
    }

    return true;
  }

  static String _tipoOferta(Map<String, dynamic> oferta) {
    final tipo = _texto(oferta['tipo_oferta']).toUpperCase();

    if (tipo == 'SUPER_OFERTA') {
      return 'SUPER_OFERTA';
    }

    return 'OFERTA';
  }

  static DateTime? _data(dynamic valor) {
    final texto = _texto(valor);

    if (texto.isEmpty) {
      return null;
    }

    return DateTime.tryParse(texto)?.toLocal();
  }

  static String _texto(dynamic valor) {
    return valor?.toString().trim() ?? '';
  }

  static double _numero(dynamic valor) {
    if (valor == null) {
      return 0;
    }

    if (valor is num) {
      return valor.toDouble();
    }

    var texto = valor.toString().trim();

    if (texto.isEmpty) {
      return 0;
    }

    texto = texto
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll('.', '')
        .replaceAll(',', '.');

    return double.tryParse(texto) ?? 0;
  }

  static double? _numeroOuNull(dynamic valor) {
    final numero = _numero(valor);

    if (numero <= 0) {
      return null;
    }

    return numero;
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/central_service.dart';
import '../../services/sessao_loja.dart';
import 'scanner.dart';

class BalancoPage extends StatefulWidget {
  final bool podeGerarTxt;

  const BalancoPage({super.key, this.podeGerarTxt = false});

  @override
  State<BalancoPage> createState() => _BalancoPageState();
}

enum _TelaBalanco { menu, novaColeta, coletasFinalizadas }

class _BalancoPageState extends State<BalancoPage> {
  final buscaController = TextEditingController();
  final quantidadeController = TextEditingController();

  final List<_ItemBalanco> itens = [];
  final List<_ListaBalancoResumo> listasAdmin = [];
  List<Map<String, dynamic>> resultados = [];

  String? listaAtualId;
  String tipoDocumentoAtual = '';
  String nomeArquivoAtual = '';
  String clienteNomeAtual = '';
  DateTime? filtroDataColetas;
  String filtroStatusColetas = 'TODOS';
  _TelaBalanco telaAtual = _TelaBalanco.menu;

  bool buscando = false;
  bool gerando = false;
  bool salvandoLista = false;
  bool carregandoListas = false;
  bool balancoAtivo = true;
  bool tokenApiCarregado = false;
  String tokenApi = '';

  static Color get cor => SessaoLoja.corPrimaria;
  static Color get fundo => SessaoLoja.corFundo;

  bool get podeGerarTxt {
    final perfil = SessaoLoja.usuarioPerfil?.trim().toLowerCase();

    return widget.podeGerarTxt ||
        SessaoLoja.usuarioAdminLoja ||
        SessaoLoja.usuarioAcessoTotal ||
        perfil == 'master' ||
        perfil == 'admin_master' ||
        perfil == 'master_central';
  }

  SupabaseClient get supabase {
    return SessaoLoja.supabaseLoja ?? Supabase.instance.client;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      inicializarBalanco();
    });
  }

  @override
  void dispose() {
    buscaController.dispose();
    quantidadeController.dispose();
    super.dispose();
  }

  String? get apiBaseUrl {
    final url = SessaoLoja.apiBaseUrl?.trim();

    if (url == null || url.isEmpty) return null;
    if (url.endsWith('/')) return url.substring(0, url.length - 1);

    return url;
  }

  String get mercadoIdObrigatorio {
    final id = SessaoLoja.mercadoId?.trim() ?? '';

    if (id.isEmpty) {
      throw Exception('Loja nao identificada.');
    }

    return id;
  }

  String get mercadoCodigoObrigatorio {
    final codigo = SessaoLoja.mercadoCodigo?.trim() ?? '';

    if (codigo.isEmpty) {
      throw Exception('Codigo da loja nao identificado.');
    }

    return codigo;
  }

  String get usuarioIdAtual {
    return SessaoLoja.usuarioId?.trim() ?? '';
  }

  String get usuarioNomeAtual {
    final nome = SessaoLoja.usuarioNome?.trim() ?? '';
    if (nome.isNotEmpty) return nome;

    final login = SessaoLoja.usuarioLogin?.trim() ?? '';
    return login.isEmpty ? 'Usuario' : login;
  }

  Future<void> inicializarBalanco() async {
    await carregarTokenApiSeNecessario();
    await carregarListaAberta();
    await carregarListasAdmin();
  }

  Future<void> carregarTokenApiSeNecessario() async {
    if (tokenApiCarregado) return;
    tokenApiCarregado = true;

    final mercadoId = SessaoLoja.mercadoId?.trim();
    if (mercadoId == null || mercadoId.isEmpty) return;

    try {
      final conexao = await CentralService().buscarConexaoMercado(mercadoId);
      tokenApi = conexao['estoque_update_token']?.toString().trim() ?? '';
    } catch (_) {
      tokenApi = '';
    }
  }

  Map<String, String> headersApi() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (tokenApi.isNotEmpty) {
      headers['x-api-key'] = tokenApi;
    }
    return headers;
  }

  Future<void> carregarListaAberta() async {
    final userId = usuarioIdAtual;

    if (userId.isEmpty) {
      return;
    }

    try {
      final lista = await supabase
          .from('balanco_listas')
          .select(
            'id, status, tipo_documento, nome_arquivo_informado, cliente_nome',
          )
          .eq('mercado_id', mercadoIdObrigatorio)
          .eq('criado_por_user_id', userId)
          .eq('status', 'ABERTO')
          .order('criado_em', ascending: false)
          .limit(1)
          .maybeSingle();

      if (lista == null) {
        if (!mounted) return;
        setState(() {
          listaAtualId = null;
          tipoDocumentoAtual = '';
          nomeArquivoAtual = '';
          clienteNomeAtual = '';
          itens.clear();
        });
        return;
      }

      final listaId = texto(lista['id']);
      if (listaId.isEmpty) {
        return;
      }

      final itensBanco = await supabase
          .from('balanco_lista_itens')
          .select('ean, nome_produto, quantidade')
          .eq('lista_id', listaId)
          .order('criado_em', ascending: false);

      if (!mounted) return;

      setState(() {
        listaAtualId = listaId;
        tipoDocumentoAtual = normalizarTipoDocumento(
          texto(lista['tipo_documento'], fallback: 'BALANCO'),
        );
        nomeArquivoAtual = texto(lista['nome_arquivo_informado']);
        clienteNomeAtual = texto(lista['cliente_nome']);
        balancoAtivo = true;
        itens
          ..clear()
          ..addAll(
            List<Map<String, dynamic>>.from(itensBanco).map(
              (item) => _ItemBalanco(
                ean: texto(item['ean']),
                nome: texto(item['nome_produto'], fallback: 'Produto'),
                quantidade: numeroQuantidade(texto(item['quantidade'])) ?? 0,
              ),
            ),
          );
      });
    } catch (e) {
      mostrarMensagem(
        'Nao foi possivel carregar lista aberta: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    }
  }

  Future<void> carregarListasAdmin() async {
    setState(() => carregandoListas = true);

    try {
      var consulta = supabase
          .from('balanco_listas')
          .select(
            'id, status, tipo_documento, nome_arquivo_informado, cliente_nome, total_itens, criado_por_nome, criado_por_login, criado_em, enviado_em, gerado_em, arquivo_nome',
          )
          .eq('mercado_id', mercadoIdObrigatorio)
          .inFilter('status', ['ENVIADO', 'GERADO']);

      if (!podeGerarTxt && usuarioIdAtual.isNotEmpty) {
        consulta = consulta.eq('criado_por_user_id', usuarioIdAtual);
      }

      if (filtroStatusColetas != 'TODOS') {
        consulta = consulta.eq('status', filtroStatusColetas);
      }

      final dataFiltro = filtroDataColetas;
      if (dataFiltro != null) {
        final inicio = DateTime(
          dataFiltro.year,
          dataFiltro.month,
          dataFiltro.day,
        );
        final fim = inicio.add(const Duration(days: 1));

        consulta = consulta
            .gte('criado_em', inicio.toUtc().toIso8601String())
            .lt('criado_em', fim.toUtc().toIso8601String());
      }

      final resposta = await consulta
          .order('criado_em', ascending: false)
          .limit(100);

      if (!mounted) return;

      setState(() {
        listasAdmin
          ..clear()
          ..addAll(
            List<Map<String, dynamic>>.from(resposta).map(
              (item) => _ListaBalancoResumo(
                id: texto(item['id']),
                status: texto(item['status']),
                tipoDocumento: normalizarTipoDocumento(
                  texto(item['tipo_documento'], fallback: 'BALANCO'),
                ),
                nomeArquivoInformado: texto(item['nome_arquivo_informado']),
                clienteNome: texto(item['cliente_nome']),
                totalItens: int.tryParse(texto(item['total_itens'])) ?? 0,
                criadoPor: texto(
                  item['criado_por_nome'] ?? item['criado_por_login'],
                  fallback: 'Usuario',
                ),
                criadoEm: texto(item['criado_em']),
                enviadoEm: texto(item['enviado_em']),
                geradoEm: texto(item['gerado_em']),
                arquivoNome: texto(item['arquivo_nome']),
              ),
            ),
          );
        carregandoListas = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => carregandoListas = false);
      mostrarMensagem(
        'Nao foi possivel carregar listas: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    }
  }

  Future<void> garantirListaAberta() async {
    if (listaAtualId != null && listaAtualId!.isNotEmpty) {
      return;
    }

    final userId = usuarioIdAtual;

    if (userId.isEmpty) {
      throw Exception('Usuario da loja nao identificado.');
    }

    if (!tipoDocumentoValido(tipoDocumentoAtual)) {
      throw Exception('Informe o tipo do arquivo antes de continuar.');
    }

    if (
        tipoDocumentoAtual == 'TRANSF_INTERCOMPANY' &&
        clienteNomeAtual.isEmpty) {
      throw Exception('Selecione o cliente da transferência intercompany.');
    }

    if (
        tipoDocumentoAtual != 'TRANSF_INTERCOMPANY' &&
        nomeArquivoAtual.isEmpty) {
      throw Exception('Informe o nome do arquivo antes de continuar.');
    }

    final dados = {
      'mercado_id': mercadoIdObrigatorio,
      'mercado_codigo': mercadoCodigoObrigatorio,
      'criado_por_user_id': userId,
      'criado_por_nome': usuarioNomeAtual,
      'criado_por_login': SessaoLoja.usuarioLogin,
      'criado_por_perfil': SessaoLoja.usuarioPerfil,
      'status': 'ABERTO',
      'tipo_documento': tipoDocumentoAtual,
      'nome_arquivo_informado': nomeArquivoAtual,
      'cliente_nome': clienteNomeAtual.isEmpty ? null : clienteNomeAtual,
      'total_itens': 0,
    };

    final resposta = await supabase
        .from('balanco_listas')
        .insert(dados)
        .select('id')
        .single();

    listaAtualId = texto(resposta['id']);
  }

  Future<void> atualizarTotalLista() async {
    final listaId = listaAtualId;
    if (listaId == null || listaId.isEmpty) return;

    await supabase
        .from('balanco_listas')
        .update({'total_itens': itens.length})
        .eq('id', listaId);
  }

  Future<void> salvarItemBanco(_ItemBalanco item) async {
    await garantirListaAberta();

    final listaId = listaAtualId;
    if (listaId == null || listaId.isEmpty) {
      throw Exception('Lista de balanco nao criada.');
    }

    final existente = await supabase
        .from('balanco_lista_itens')
        .select('id')
        .eq('lista_id', listaId)
        .eq('ean', item.ean)
        .limit(1)
        .maybeSingle();

    final dados = {
      'lista_id': listaId,
      'mercado_id': mercadoIdObrigatorio,
      'mercado_codigo': mercadoCodigoObrigatorio,
      'ean': item.ean,
      'nome_produto': item.nome,
      'quantidade': item.quantidade,
    };

    if (existente == null) {
      await supabase.from('balanco_lista_itens').insert(dados);
    } else {
      await supabase
          .from('balanco_lista_itens')
          .update(dados)
          .eq('id', texto(existente['id']));
    }
  }

  Future<List<_ItemBalanco>> carregarItensLista(String listaId) async {
    final resposta = await supabase
        .from('balanco_lista_itens')
        .select('ean, nome_produto, quantidade')
        .eq('lista_id', listaId)
        .order('criado_em', ascending: true);

    return List<Map<String, dynamic>>.from(resposta).map((item) {
      return _ItemBalanco(
        ean: texto(item['ean']),
        nome: texto(item['nome_produto'], fallback: 'Produto'),
        quantidade: numeroQuantidade(texto(item['quantidade'])) ?? 0,
      );
    }).toList();
  }

  Future<void> atualizarStatusLista({
    required String listaId,
    required String status,
    String? arquivoNome,
  }) async {
    final dados = <String, dynamic>{'status': status};

    if (status == 'ENVIADO') {
      dados['enviado_em'] = DateTime.now().toIso8601String();
    }

    if (status == 'GERADO') {
      dados['gerado_em'] = DateTime.now().toIso8601String();
      dados['gerado_por_user_id'] = usuarioIdAtual;
      dados['gerado_por_nome'] = usuarioNomeAtual;
      dados['arquivo_nome'] = arquivoNome;
    }

    await supabase.from('balanco_listas').update(dados).eq('id', listaId);
  }

  bool somenteNumeros(String valor) {
    return RegExp(r'^[0-9]+$').hasMatch(valor);
  }

  List extrairLista(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['produtos'] is List) return data['produtos'];
    if (data is Map && data['data'] is List) return data['data'];
    if (data is Map && data['resultado'] is List) return data['resultado'];
    if (data is Map && data['results'] is List) return data['results'];
    return [];
  }

  String texto(dynamic valor, {String fallback = ''}) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? fallback : texto;
  }

  String nomeProduto(Map<String, dynamic> produto) {
    final nome = texto(
      produto['nome_produto'] ??
          produto['descricao'] ??
          produto['produto'] ??
          produto['nome'],
    );

    return nome.isEmpty ? 'Produto' : nome;
  }

  String eanProduto(Map<String, dynamic> produto) {
    return texto(
      produto['ean_principal'] ??
          produto['ean'] ??
          produto['codigo_barras'] ??
          produto['codigo'],
    );
  }

  String precoProduto(Map<String, dynamic> produto) {
    final preco =
        produto['preco_venda'] ?? produto['preco'] ?? produto['valor'];
    final valor = texto(preco);
    return valor.isEmpty ? '0' : valor;
  }

  double? numeroQuantidade(String valor) {
    final limpo = valor.trim().replaceAll(',', '.');
    final numero = double.tryParse(limpo);

    if (numero == null || numero <= 0) {
      return null;
    }

    return numero;
  }

  String quantidadeTxt(double valor) {
    if (valor == valor.roundToDouble()) {
      return valor.toStringAsFixed(0);
    }

    var texto = valor.toStringAsFixed(3);
    while (texto.contains('.') && texto.endsWith('0')) {
      texto = texto.substring(0, texto.length - 1);
    }
    if (texto.endsWith('.')) {
      texto = texto.substring(0, texto.length - 1);
    }
    return texto.replaceAll('.', ',');
  }

  String codigoCurto(String id) {
    if (id.length <= 8) return id.toUpperCase();
    return id.substring(0, 8).toUpperCase();
  }

  String dataResumo(String valor) {
    final data = DateTime.tryParse(valor)?.toLocal();
    if (data == null) return '-';

    String dois(int numero) => numero.toString().padLeft(2, '0');
    return '${dois(data.day)}/${dois(data.month)}/${data.year} ${dois(data.hour)}:${dois(data.minute)}';
  }

  bool tipoDocumentoValido(String valor) {
    return const {
      'COLETA',
      'BALANCO',
      'AVARIA',
      'VALIDADE',
      'TRANSF_INTERCOMPANY',
      'TRANSF_INTERNA_SETOR',
    }.contains(valor.trim().toUpperCase());
  }

  String normalizarTipoDocumento(String valor) {
    final tipo = valor.trim().toUpperCase();
    return tipoDocumentoValido(tipo) ? tipo : 'BALANCO';
  }

  String rotuloTipoDocumento(String valor) {
    switch (normalizarTipoDocumento(valor)) {
      case 'COLETA':
        return 'Coleta';
      case 'AVARIA':
        return 'Avaria';
      case 'VALIDADE':
        return 'Validade';
      case 'TRANSF_INTERCOMPANY':
        return 'Transf. intercompany';
      case 'TRANSF_INTERNA_SETOR':
        return 'Transf. interna/setor';
      default:
        return 'Balanço';
    }
  }

  IconData iconeTipoDocumento(String valor) {
    switch (normalizarTipoDocumento(valor)) {
      case 'COLETA':
        return Icons.playlist_add_check_outlined;
      case 'AVARIA':
        return Icons.broken_image_outlined;
      case 'VALIDADE':
        return Icons.event_busy_outlined;
      case 'TRANSF_INTERCOMPANY':
        return Icons.swap_horiz_outlined;
      case 'TRANSF_INTERNA_SETOR':
        return Icons.compare_arrows_outlined;
      default:
        return Icons.inventory_outlined;
    }
  }

  bool nomeArquivoAutomatico(String tipoDocumento) {
    return normalizarTipoDocumento(tipoDocumento) == 'TRANSF_INTERCOMPANY';
  }

  String descricaoNomeArquivo({
    required String tipoDocumento,
    required String nomeArquivo,
    required String clienteNome,
    String arquivoGerado = '',
  }) {
    if (arquivoGerado.isNotEmpty) return arquivoGerado;
    if (!nomeArquivoAutomatico(tipoDocumento)) {
      return nomeArquivo.isEmpty ? 'Nome do arquivo não informado' : nomeArquivo;
    }
    if (clienteNome.isEmpty) return 'Cliente não selecionado';
    return 'Automático: data_$clienteNome.txt';
  }

  String normalizarNomeArquivo(String valor) {
    final nome = valor.trim();
    if (nome.toLowerCase().endsWith('.txt')) return nome;
    return '$nome.txt';
  }

  String? validarNomeArquivo(String valor) {
    final nome = valor.trim();
    if (nome.isEmpty) return 'Informe o nome do arquivo.';
    if (nome == '.' || nome == '..' || nome.startsWith('.')) {
      return 'Informe um nome de arquivo válido.';
    }
    if (RegExp(r'[\\/:*?"<>|]').hasMatch(nome)) {
      return 'O nome contém caracteres não permitidos.';
    }
    if (normalizarNomeArquivo(nome).length > 180) {
      return 'Use um nome com no máximo 176 caracteres.';
    }
    return null;
  }

  String dataFiltroTexto(DateTime? data) {
    if (data == null) return 'Todas as datas';

    String dois(int numero) => numero.toString().padLeft(2, '0');
    return '${dois(data.day)}/${dois(data.month)}/${data.year}';
  }

  String textoStatusColeta(String status) {
    switch (status.toUpperCase()) {
      case 'GERADO':
        return 'Gerado';
      case 'ENVIADO':
        return 'Salvo';
      default:
        return status.isEmpty ? '-' : status;
    }
  }

  void mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? Colors.red : cor,
      ),
    );
  }

  Future<void> buscarProduto() async {
    if (!balancoAtivo) {
      mostrarMensagem('Esta lista já foi gerada. Inicie uma nova lista.');
      return;
    }

    final busca = buscaController.text.trim();

    if (busca.isEmpty) {
      mostrarMensagem('Digite ou escaneie o EAN do produto.', erro: true);
      return;
    }

    final api = apiBaseUrl;

    if (api == null) {
      mostrarMensagem('Nenhuma API configurada para esta loja.', erro: true);
      return;
    }

    setState(() {
      buscando = true;
      resultados = [];
    });

    try {
      Uri url;

      if (somenteNumeros(busca)) {
        final codigo = busca.padLeft(14, '0');
        url = Uri.parse('$api/produto/ean/$codigo');
      } else {
        final descricao = Uri.encodeComponent(busca);
        url = Uri.parse('$api/produto/descricao/$descricao');
      }

      final response = await http.get(url).timeout(const Duration(seconds: 20));

      if (!mounted) return;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 404) {
          mostrarMensagem('Produto não cadastrado.', erro: true);
          return;
        }

        mostrarMensagem(
          'Erro na API. HTTP: ${response.statusCode}',
          erro: true,
        );
        return;
      }

      final data = jsonDecode(response.body);
      final lista = extrairLista(data)
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      if (lista.length == 1) {
        await abrirQuantidade(lista.first);
        return;
      }

      if (lista.length > 1) {
        setState(() {
          resultados = lista;
        });
        return;
      }

      if (data is Map && data['error'] != null) {
        mostrarMensagem('Produto não cadastrado.', erro: true);
        return;
      }

      if (data is Map) {
        await abrirQuantidade(Map<String, dynamic>.from(data));
        return;
      }

      mostrarMensagem('Produto não cadastrado.', erro: true);
    } catch (e) {
      mostrarMensagem('Erro de conexao. Verifique a API da loja.', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          buscando = false;
        });
      }
    }
  }

  Future<void> abrirQuantidade(Map<String, dynamic> produto) async {
    final ean = eanProduto(produto);

    if (ean.isEmpty) {
      mostrarMensagem('Produto sem EAN/codigo de barras.', erro: true);
      return;
    }

    _ItemBalanco? existente;
    for (final item in itens) {
      if (item.ean == ean) {
        existente = item;
        break;
      }
    }
    quantidadeController.text = existente == null
        ? ''
        : quantidadeTxt(existente.quantidade);

    final quantidade = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Quantidade do balanco'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nomeProduto(produto),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'EAN: $ean',
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantidadeController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Quantidade',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) {
                  final valor = numeroQuantidade(quantidadeController.text);
                  if (valor != null) {
                    Navigator.pop(context, valor);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: cor,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final valor = numeroQuantidade(quantidadeController.text);
                if (valor == null) {
                  return;
                }
                Navigator.pop(context, valor);
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );

    if (quantidade == null) {
      return;
    }

    final item = _ItemBalanco(
      ean: ean,
      nome: nomeProduto(produto),
      quantidade: quantidade,
    );

    setState(() => salvandoLista = true);

    try {
      await salvarItemBanco(item);

      if (!mounted) return;

      setState(() {
        final index = itens.indexWhere((atual) => atual.ean == ean);

        if (index >= 0) {
          itens[index] = item;
        } else {
          itens.insert(0, item);
        }

        resultados = [];
        buscaController.clear();
      });

      await atualizarTotalLista();
    } catch (e) {
      mostrarMensagem(
        'Nao foi possivel salvar o item na lista: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() => salvandoLista = false);
      }
    }
  }

  Future<void> abrirScanner() async {
    if (!balancoAtivo) {
      mostrarMensagem('Esta lista já foi gerada. Inicie uma nova lista.');
      return;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerPage(
          onDetect: (codigo) {
            final ean = codigo.padLeft(14, '0');
            buscaController.text = ean;
            buscarProduto();
          },
        ),
      ),
    );
  }

  String conteudoTxt(List<_ItemBalanco> itensTxt) {
    return itensTxt
        .map((item) => '${item.ean};${quantidadeTxt(item.quantidade)}')
        .join('\n');
  }

  Future<List<String>> buscarClientesTransferencia() async {
    final api = apiBaseUrl;
    if (api == null) {
      throw Exception('Nenhuma API configurada para esta loja.');
    }

    await carregarTokenApiSeNecessario();

    final response = await http
        .get(
          Uri.parse('$api/coletor-balanco/clientes-intercompany'),
          headers: headersApi(),
        )
        .timeout(const Duration(seconds: 20));

    dynamic resposta;
    try {
      resposta = jsonDecode(response.body);
    } catch (_) {
      resposta = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final erro = resposta is Map ? texto(resposta['erro']) : '';
      throw Exception(
        erro.isEmpty
            ? 'A API recusou a consulta. HTTP ${response.statusCode}.'
            : erro,
      );
    }

    final dados = resposta is Map ? resposta['clientes'] : null;
    if (dados is! List) {
      throw Exception('A API retornou uma lista de clientes inválida.');
    }

    return dados
        .map((item) {
          if (item is Map) return texto(item['nome_pessoa']);
          return texto(item);
        })
        .where((nome) => nome.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Future<String> enviarTxtServidor({
    required String listaId,
    required String tipoDocumento,
    required String nomeArquivo,
    required String clienteNome,
    required List<_ItemBalanco> itensTxt,
  }) async {
    final api = apiBaseUrl;
    if (api == null) {
      throw Exception('Nenhuma API configurada para esta loja.');
    }

    await carregarTokenApiSeNecessario();

    final response = await http
        .post(
          Uri.parse('$api/coletor-balanco/arquivo'),
          headers: headersApi(),
          body: jsonEncode({
            'nome_arquivo': nomeArquivo,
            'tipo_documento': tipoDocumento,
            'cliente_nome': clienteNome,
            'conteudo': conteudoTxt(itensTxt),
            'lista_id': listaId,
            'mercado_codigo': mercadoCodigoObrigatorio,
            'usuario': usuarioNomeAtual,
          }),
        )
        .timeout(const Duration(seconds: 30));

    dynamic resposta;
    try {
      resposta = jsonDecode(response.body);
    } catch (_) {
      resposta = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final erro = resposta is Map ? texto(resposta['erro']) : '';
      throw Exception(
        erro.isEmpty
            ? 'A API recusou o arquivo. HTTP ${response.statusCode}.'
            : erro,
      );
    }

    if (resposta is! Map || resposta['sucesso'] != true) {
      throw Exception('A API não confirmou a gravação do arquivo.');
    }

    return texto(resposta['arquivo_nome'], fallback: nomeArquivo);
  }

  Future<void> salvarColeta() async {
    if (itens.isEmpty) {
      mostrarMensagem('Inclua ao menos um produto na lista.', erro: true);
      return;
    }

    if (!balancoAtivo) {
      mostrarMensagem('Esta lista já foi finalizada. Inicie uma nova lista.');
      return;
    }

    setState(() => gerando = true);

    try {
      await garantirListaAberta();
      await atualizarTotalLista();

      final listaId = listaAtualId;
      if (listaId == null || listaId.isEmpty) {
        throw Exception('Lista não encontrada.');
      }

      await atualizarStatusLista(listaId: listaId, status: 'ENVIADO');

      if (!mounted) return;

      setState(() {
        balancoAtivo = false;
        listaAtualId = null;
        gerando = false;
      });

      await carregarListasAdmin();
      mostrarMensagem('${rotuloTipoDocumento(tipoDocumentoAtual)} salva.');
      novoBalanco();
    } catch (e) {
      if (!mounted) return;

      setState(() => gerando = false);
      mostrarMensagem(
        'Erro ao salvar lista: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    }
  }

  Future<void> enviarTxtListaAdmin(_ListaBalancoResumo lista) async {
    setState(() => gerando = true);

    try {
      final itensLista = await carregarItensLista(lista.id);

      if (itensLista.isEmpty) {
        mostrarMensagem('Lista sem itens para gerar TXT.', erro: true);
        return;
      }

      var tipoDocumento = lista.tipoDocumento;
      var nomeArquivoInformado = lista.nomeArquivoInformado;
      var clienteNome = lista.clienteNome;

      if (
          (nomeArquivoAutomatico(tipoDocumento) && clienteNome.isEmpty) ||
          (!nomeArquivoAutomatico(tipoDocumento) &&
              nomeArquivoInformado.isEmpty)) {
        final configuracao = await solicitarConfiguracaoDocumento(
          tipoInicial: tipoDocumento,
          clienteInicial: clienteNome,
          titulo: 'Configurar arquivo',
        );
        if (configuracao == null) return;

        await atualizarConfiguracaoLista(lista.id, configuracao);
        tipoDocumento = configuracao.tipoDocumento;
        nomeArquivoInformado = configuracao.nomeArquivo;
        clienteNome = configuracao.clienteNome;
      }

      final nomeArquivoSalvo = await enviarTxtServidor(
        listaId: lista.id,
        tipoDocumento: tipoDocumento,
        nomeArquivo: nomeArquivoInformado,
        clienteNome: clienteNome,
        itensTxt: itensLista,
      );
      await atualizarStatusLista(
        listaId: lista.id,
        status: 'GERADO',
        arquivoNome: nomeArquivoSalvo,
      );

      await carregarListasAdmin();
      mostrarMensagem('TXT salvo no servidor: $nomeArquivoSalvo');
    } catch (e) {
      mostrarMensagem(
        'Erro ao gerar TXT: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() => gerando = false);
      }
    }
  }

  Future<void> visualizarColeta(_ListaBalancoResumo lista) async {
    setState(() => carregandoListas = true);

    try {
      final itensLista = await carregarItensLista(lista.id);

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(
              '${rotuloTipoDocumento(lista.tipoDocumento)} ${codigoCurto(lista.id)}',
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (lista.clienteNome.isNotEmpty) ...[
                    Text(
                      'Cliente: ${lista.clienteNome}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (itensLista.isEmpty)
                    const Text('Esta lista não possui itens.')
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 420),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: itensLista.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final item = itensLista[index];

                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              item.nome,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(item.ean),
                            trailing: Text(
                              quantidadeTxt(item.quantidade),
                              style: TextStyle(
                                color: cor,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fechar'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      mostrarMensagem(
        'Erro ao visualizar coleta: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() => carregandoListas = false);
      }
    }
  }

  Future<void> excluirListaAdmin(_ListaBalancoResumo lista) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir coleta'),
          content: Text(
            'Deseja excluir definitivamente a coleta ${codigoCurto(lista.id)}?\n\n'
            'Criada por: ${lista.criadoPor}\n'
            'Itens: ${lista.totalItens}\n'
            'Status: ${textoStatusColeta(lista.status)}\n\n'
            'Essa acao nao podera ser desfeita.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmou != true) return;

    setState(() => carregandoListas = true);

    try {
      await supabase
          .from('balanco_lista_itens')
          .delete()
          .eq('lista_id', lista.id);
      await supabase.from('balanco_listas').delete().eq('id', lista.id);
      await carregarListasAdmin();
      mostrarMensagem('Lista excluída.');
    } catch (e) {
      if (mounted) {
        setState(() => carregandoListas = false);
      }
      mostrarMensagem(
        'Erro ao excluir lista: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    }
  }

  Future<_ConfiguracaoDocumento?> solicitarConfiguracaoDocumento({
    String tipoInicial = 'COLETA',
    String nomeInicial = '',
    String clienteInicial = '',
    String titulo = 'Nova coleta',
  }) async {
    final nomeController = TextEditingController(
      text: nomeInicial.toLowerCase().endsWith('.txt')
          ? nomeInicial.substring(0, nomeInicial.length - 4)
          : nomeInicial,
    );
    var tipoSelecionado = normalizarTipoDocumento(tipoInicial);
    var clienteSelecionado = clienteInicial.trim();
    String? erroNome;
    String? erroCliente;
    Future<List<String>>? clientesFuture =
        nomeArquivoAutomatico(tipoSelecionado)
        ? buscarClientesTransferencia()
        : null;

    final configuracao = await showDialog<_ConfiguracaoDocumento>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void confirmar() {
              if (nomeArquivoAutomatico(tipoSelecionado)) {
                if (clienteSelecionado.isEmpty) {
                  setDialogState(
                    () => erroCliente = 'Selecione o cliente da transferência.',
                  );
                  return;
                }
              } else {
                final erro = validarNomeArquivo(nomeController.text);
                if (erro != null) {
                  setDialogState(() => erroNome = erro);
                  return;
                }
              }

              Navigator.pop(
                dialogContext,
                _ConfiguracaoDocumento(
                  tipoDocumento: tipoSelecionado,
                  nomeArquivo: nomeArquivoAutomatico(tipoSelecionado)
                      ? ''
                      : normalizarNomeArquivo(nomeController.text),
                  clienteNome: nomeArquivoAutomatico(tipoSelecionado)
                      ? clienteSelecionado
                      : '',
                ),
              );
            }

            return AlertDialog(
              title: Text(titulo),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 480,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tipo do arquivo',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: tipoSelecionado,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.description_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'COLETA', child: Text('Coleta')),
                          DropdownMenuItem(
                            value: 'BALANCO',
                            child: Text('Balanço'),
                          ),
                          DropdownMenuItem(value: 'AVARIA', child: Text('Avaria')),
                          DropdownMenuItem(
                            value: 'VALIDADE',
                            child: Text('Validade'),
                          ),
                          DropdownMenuItem(
                            value: 'TRANSF_INTERCOMPANY',
                            child: Text('Transf. intercompany'),
                          ),
                          DropdownMenuItem(
                            value: 'TRANSF_INTERNA_SETOR',
                            child: Text('Transf. interna/setor'),
                          ),
                        ],
                        onChanged: (tipo) {
                          if (tipo == null) return;
                          setDialogState(() {
                            tipoSelecionado = tipo;
                            erroNome = null;
                            erroCliente = null;
                            if (nomeArquivoAutomatico(tipo)) {
                              clientesFuture ??= buscarClientesTransferencia();
                            } else {
                              clienteSelecionado = '';
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 18),
                      if (nomeArquivoAutomatico(tipoSelecionado))
                        FutureBuilder<List<String>>(
                          future: clientesFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                title: Text('Carregando clientes...'),
                              );
                            }

                            if (snapshot.hasError) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Não foi possível carregar os clientes: '
                                    '${CentralService.mensagemErroUsuario(snapshot.error!)}',
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      setDialogState(() {
                                        clientesFuture =
                                            buscarClientesTransferencia();
                                      });
                                    },
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Tentar novamente'),
                                  ),
                                ],
                              );
                            }

                            final clientes = <String>{
                              ...?snapshot.data,
                              if (clienteSelecionado.isNotEmpty)
                                clienteSelecionado,
                            }.toList()
                              ..sort(
                                (a, b) => a.toLowerCase().compareTo(
                                  b.toLowerCase(),
                                ),
                              );

                            if (clientes.isEmpty) {
                              return const Text(
                                'Nenhum cliente elegível foi encontrado.',
                                style: TextStyle(color: Colors.red),
                              );
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                DropdownButtonFormField<String>(
                                  initialValue: clienteSelecionado.isEmpty
                                      ? null
                                      : clienteSelecionado,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: 'Cliente de destino',
                                    helperText:
                                        'O nome do TXT será criado na geração.',
                                    errorText: erroCliente,
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(
                                      Icons.business_outlined,
                                    ),
                                  ),
                                  items: clientes
                                      .map(
                                        (cliente) => DropdownMenuItem(
                                          value: cliente,
                                          child: Text(
                                            cliente,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (cliente) {
                                    setDialogState(() {
                                      clienteSelecionado = cliente ?? '';
                                      erroCliente = null;
                                    });
                                  },
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Formato: AAAA-MM-DD_nome-do-cliente.txt',
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            );
                          },
                        )
                      else
                        TextField(
                          controller: nomeController,
                          autofocus: nomeInicial.isEmpty,
                          maxLength: 176,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: 'Nome do arquivo',
                            hintText: 'Ex: Contagem Setembro',
                            helperText: 'A extensão .txt será adicionada.',
                            errorText: erroNome,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) {
                            if (erroNome != null) {
                              setDialogState(() => erroNome = null);
                            }
                          },
                          onSubmitted: (_) => confirmar(),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: confirmar,
                  icon: const Icon(Icons.check),
                  label: const Text('Confirmar'),
                  style: FilledButton.styleFrom(backgroundColor: cor),
                ),
              ],
            );
          },
        );
      },
    );

    nomeController.dispose();
    return configuracao;
  }

  Future<void> atualizarConfiguracaoLista(
    String listaId,
    _ConfiguracaoDocumento configuracao, {
    bool atualizarAtual = false,
  }) async {
    await supabase
        .from('balanco_listas')
        .update({
          'tipo_documento': configuracao.tipoDocumento,
          'nome_arquivo_informado': configuracao.nomeArquivo,
          'cliente_nome': configuracao.clienteNome.isEmpty
              ? null
              : configuracao.clienteNome,
        })
        .eq('id', listaId);

    if (atualizarAtual && mounted) {
      setState(() {
        tipoDocumentoAtual = configuracao.tipoDocumento;
        nomeArquivoAtual = configuracao.nomeArquivo;
        clienteNomeAtual = configuracao.clienteNome;
      });
    }
  }

  Future<void> editarConfiguracaoAtual() async {
    final listaId = listaAtualId;
    if (listaId == null || listaId.isEmpty || salvandoLista) return;

    final configuracao = await solicitarConfiguracaoDocumento(
      tipoInicial: tipoDocumentoAtual,
      nomeInicial: nomeArquivoAtual,
      clienteInicial: clienteNomeAtual,
      titulo: 'Editar arquivo',
    );
    if (configuracao == null) return;

    setState(() => salvandoLista = true);
    try {
      await atualizarConfiguracaoLista(
        listaId,
        configuracao,
        atualizarAtual: true,
      );
      mostrarMensagem('Dados do arquivo atualizados.');
    } catch (e) {
      mostrarMensagem(
        'Erro ao atualizar arquivo: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    } finally {
      if (mounted) setState(() => salvandoLista = false);
    }
  }

  void novoBalanco() {
    setState(() {
      itens.clear();
      resultados = [];
      buscaController.clear();
      listaAtualId = null;
      tipoDocumentoAtual = '';
      nomeArquivoAtual = '';
      clienteNomeAtual = '';
      balancoAtivo = true;
    });
  }

  Future<void> removerItem(_ItemBalanco item) async {
    if (!balancoAtivo) {
      return;
    }

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir item da coleta'),
          content: Text(
            'Deseja remover este item da coleta atual?\n\n'
            '${item.nome}\n'
            'EAN: ${item.ean}\n'
            'Quantidade: ${quantidadeTxt(item.quantidade)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir item'),
            ),
          ],
        );
      },
    );

    if (confirmou != true) {
      return;
    }

    setState(() => salvandoLista = true);

    try {
      final listaId = listaAtualId;
      if (listaId != null && listaId.isNotEmpty) {
        await supabase
            .from('balanco_lista_itens')
            .delete()
            .eq('lista_id', listaId)
            .eq('ean', item.ean);
      }

      if (!mounted) return;

      setState(() {
        itens.removeWhere((atual) => atual.ean == item.ean);
      });

      await atualizarTotalLista();
    } catch (e) {
      mostrarMensagem(
        'Nao foi possivel remover o item: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() => salvandoLista = false);
      }
    }
  }

  Future<void> abrirNovaColeta() async {
    await carregarListaAberta();

    if (!mounted) return;

    final listaExistente = listaAtualId;
    if (listaExistente != null && listaExistente.isNotEmpty) {
      if (
          (nomeArquivoAutomatico(tipoDocumentoAtual) &&
              clienteNomeAtual.isEmpty) ||
          (!nomeArquivoAutomatico(tipoDocumentoAtual) &&
              nomeArquivoAtual.isEmpty)) {
        final configuracao = await solicitarConfiguracaoDocumento(
          tipoInicial: tipoDocumentoAtual,
          clienteInicial: clienteNomeAtual,
          titulo: 'Configurar lista existente',
        );
        if (configuracao == null) return;
        try {
          await atualizarConfiguracaoLista(
            listaExistente,
            configuracao,
            atualizarAtual: true,
          );
        } catch (e) {
          mostrarMensagem(
            'Erro ao configurar lista: ${CentralService.mensagemErroUsuario(e)}',
            erro: true,
          );
          return;
        }
      }

      if (!mounted) return;
      setState(() => telaAtual = _TelaBalanco.novaColeta);
      return;
    }

    final configuracao = await solicitarConfiguracaoDocumento();
    if (configuracao == null || !mounted) return;

    setState(() {
      tipoDocumentoAtual = configuracao.tipoDocumento;
      nomeArquivoAtual = configuracao.nomeArquivo;
      clienteNomeAtual = configuracao.clienteNome;
      salvandoLista = true;
    });

    try {
      await garantirListaAberta();
      if (!mounted) return;
      setState(() => telaAtual = _TelaBalanco.novaColeta);
    } catch (e) {
      mostrarMensagem(
        'Erro ao criar lista: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    } finally {
      if (mounted) setState(() => salvandoLista = false);
    }
  }

  Future<void> abrirColetasFinalizadas() async {
    setState(() {
      telaAtual = _TelaBalanco.coletasFinalizadas;
    });

    await carregarListasAdmin();
  }

  Future<void> escolherFiltroDataColetas() async {
    final hoje = DateTime.now();
    final data = await showDatePicker(
      context: context,
      initialDate: filtroDataColetas ?? hoje,
      firstDate: DateTime(hoje.year - 2),
      lastDate: DateTime(hoje.year + 1),
    );

    if (data == null) return;

    setState(() {
      filtroDataColetas = data;
    });

    await carregarListasAdmin();
  }

  Widget cardMenuBalanco({
    required String titulo,
    required String subtitulo,
    required IconData icone,
    required VoidCallback onTap,
    String? detalhe,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cor.withValues(alpha: 0.16), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icone, color: cor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitulo,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (detalhe != null && detalhe.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        detalhe,
                        style: TextStyle(
                          color: cor,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cor),
            ],
          ),
        ),
      ),
    );
  }

  Widget menuBalanco() {
    return Column(
      children: [
        cardMenuBalanco(
          titulo: 'Nova coleta',
          subtitulo: 'Escolha a finalidade e conte os produtos.',
          icone: Icons.playlist_add_check_outlined,
          detalhe: itens.isEmpty ? null : '${itens.length} item(ns) em aberto',
          onTap: abrirNovaColeta,
        ),
        const SizedBox(height: 14),
        cardMenuBalanco(
          titulo: 'Listas finalizadas',
          subtitulo: 'Consulte as listas salvas e gere o TXT no servidor.',
          icone: Icons.folder_copy_outlined,
          detalhe: '${listasAdmin.length} lista(s) carregada(s)',
          onTap: abrirColetasFinalizadas,
        ),
      ],
    );
  }

  Widget resumoDocumentoAtual() {
    final tipo = rotuloTipoDocumento(tipoDocumentoAtual);
    final nome = descricaoNomeArquivo(
      tipoDocumento: tipoDocumentoAtual,
      nomeArquivo: nomeArquivoAtual,
      clienteNome: clienteNomeAtual,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(iconeTipoDocumento(tipoDocumentoAtual), color: cor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tipo,
                  style: TextStyle(color: cor, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  nome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1F2937),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Editar tipo e dados do arquivo',
            onPressed: salvandoLista ? null : editarConfiguracaoAtual,
            icon: const Icon(Icons.edit_outlined),
            color: cor,
          ),
        ],
      ),
    );
  }

  Widget campoBusca() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cor.withValues(alpha: 0.14), width: 1.3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: buscaController,
            enabled: balancoAtivo && !buscando && !salvandoLista,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => buscarProduto(),
            decoration: InputDecoration(
              labelText: 'EAN ou descricao do produto',
              prefixIcon: Icon(Icons.search, color: cor),
              suffixIcon: buscaController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        buscaController.clear();
                        setState(() => resultados = []);
                      },
                      icon: const Icon(Icons.close),
                    ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: balancoAtivo && !buscando && !salvandoLista
                      ? buscarProduto
                      : null,
                  icon: buscando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search),
                  label: Text(
                    buscando || salvandoLista ? 'Aguarde...' : 'Consultar',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: balancoAtivo && !buscando && !salvandoLista
                      ? abrirScanner
                      : null,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scanner'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cor,
                    side: BorderSide(color: cor),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget resultadosBusca() {
    if (resultados.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text(
          'Selecione um dos ${resultados.length} produtos encontrados',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 8),
        ...resultados.map((produto) {
          final ean = eanProduto(produto);

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: salvandoLista ? null : () => abrirQuantidade(produto),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: cor.withValues(alpha: 0.16),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, color: cor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nomeProduto(produto),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'EAN: ${ean.isEmpty ? '-' : ean} | R\$ ${precoProduto(produto)}',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: cor),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget listaBalanco() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  balancoAtivo ? 'Lista ativa' : 'Lista inativada',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: balancoAtivo
                      ? Colors.green.withValues(alpha: 0.10)
                      : Colors.grey.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${itens.length} itens',
                  style: TextStyle(
                    color: balancoAtivo ? Colors.green.shade700 : Colors.grey,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (itens.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'Nenhum produto incluído na lista.',
                  style: TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else
            ...itens.map((item) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: fundo,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.05),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.nome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF1F2937),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.ean,
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      quantidadeTxt(item.quantidade),
                      style: TextStyle(
                        color: cor,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (balancoAtivo) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Remover',
                        onPressed: salvandoLista
                            ? null
                            : () => removerItem(item),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget barraAcoes() {
    final carregandoAcao = gerando || salvandoLista;
    final tipo = rotuloTipoDocumento(tipoDocumentoAtual);

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: balancoAtivo && itens.isNotEmpty && !carregandoAcao
                ? salvarColeta
                : null,
            icon: carregandoAcao
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(carregandoAcao ? 'Salvando...' : 'Salvar $tipo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: cor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget filtrosColetasWidget() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: carregandoListas ? null : escolherFiltroDataColetas,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(dataFiltroTexto(filtroDataColetas)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cor,
                  side: BorderSide(color: cor.withValues(alpha: 0.55)),
                ),
              ),
            ),
            if (filtroDataColetas != null) ...[
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Limpar data',
                onPressed: carregandoListas
                    ? null
                    : () async {
                        setState(() => filtroDataColetas = null);
                        await carregarListasAdmin();
                      },
                icon: const Icon(Icons.close),
                color: Colors.red,
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: filtroStatusColetas,
          decoration: InputDecoration(
            labelText: 'Status da lista',
            prefixIcon: Icon(Icons.filter_list, color: cor),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          items: const [
            DropdownMenuItem(value: 'TODOS', child: Text('Todos')),
            DropdownMenuItem(value: 'ENVIADO', child: Text('Salvo')),
            DropdownMenuItem(value: 'GERADO', child: Text('Gerado')),
          ],
          onChanged: carregandoListas
              ? null
              : (valor) async {
                  if (valor == null) return;
                  setState(() => filtroStatusColetas = valor);
                  await carregarListasAdmin();
                },
        ),
      ],
    );
  }

  Widget listasAdminWidget() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Listas finalizadas',
                  style: TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Atualizar',
                onPressed: carregandoListas ? null : carregarListasAdmin,
                icon: Icon(Icons.refresh, color: cor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          filtrosColetasWidget(),
          const SizedBox(height: 8),
          if (carregandoListas)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (listasAdmin.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Nenhuma lista salva encontrada.',
                style: TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            ...listasAdmin.map((lista) {
              final gerada = lista.status == 'GERADO';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: gerada ? Colors.green.withValues(alpha: 0.06) : fundo,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: gerada
                        ? Colors.green.withValues(alpha: 0.18)
                        : cor.withValues(alpha: 0.14),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Lista ${codigoCurto(lista.id)}',
                            style: const TextStyle(
                              color: Color(0xFF1F2937),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: gerada
                                ? Colors.green.withValues(alpha: 0.12)
                                : cor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            textoStatusColeta(lista.status),
                            style: TextStyle(
                              color: gerada ? Colors.green.shade700 : cor,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${rotuloTipoDocumento(lista.tipoDocumento)} | '
                      '${descricaoNomeArquivo(
                        tipoDocumento: lista.tipoDocumento,
                        nomeArquivo: lista.nomeArquivoInformado,
                        clienteNome: lista.clienteNome,
                        arquivoGerado: lista.arquivoNome,
                      )}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cor,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${lista.totalItens} itens | ${lista.criadoPor}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Criada em ${dataResumo(lista.criadoEm)}',
                      style: const TextStyle(
                        color: Colors.black45,
                        fontSize: 12,
                      ),
                    ),
                    if (lista.geradoEm.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        'TXT concluído em ${dataResumo(lista.geradoEm)}',
                        style: const TextStyle(
                          color: Colors.black45,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (podeGerarTxt) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: 142,
                            child: OutlinedButton.icon(
                              onPressed: carregandoListas
                                  ? null
                                  : () => visualizarColeta(lista),
                              icon: const Icon(Icons.visibility_outlined),
                              label: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Visualizar lista'),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF1F2937),
                                side: BorderSide(
                                  color: Colors.black.withValues(alpha: 0.18),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 128,
                            child: OutlinedButton.icon(
                              onPressed: gerando
                                  ? null
                                  : () => enviarTxtListaAdmin(lista),
                              icon: const Icon(Icons.cloud_upload_outlined),
                              label: const Text('Gerar TXT'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: cor,
                                side: BorderSide(color: cor),
                              ),
                            ),
                          ),
                          IconButton.filledTonal(
                            tooltip: 'Excluir lista',
                            onPressed: gerando || carregandoListas
                                ? null
                                : () => excluirListaAdmin(lista),
                            icon: const Icon(Icons.delete_outline),
                            color: Colors.red,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  List<Widget> conteudoAtual() {
    switch (telaAtual) {
      case _TelaBalanco.menu:
        return [menuBalanco()];
      case _TelaBalanco.novaColeta:
        return [
          resumoDocumentoAtual(),
          const SizedBox(height: 14),
          campoBusca(),
          resultadosBusca(),
          const SizedBox(height: 14),
          listaBalanco(),
          const SizedBox(height: 14),
          barraAcoes(),
        ];
      case _TelaBalanco.coletasFinalizadas:
        return [listasAdminWidget()];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fundo,
      appBar: AppBar(
        title: const Text('Coletor/Balanço'),
        backgroundColor: cor,
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: telaAtual == _TelaBalanco.menu
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    telaAtual = _TelaBalanco.menu;
                  });
                },
              ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: conteudoAtual(),
        ),
      ),
    );
  }
}

class _ItemBalanco {
  final String ean;
  final String nome;
  final double quantidade;

  const _ItemBalanco({
    required this.ean,
    required this.nome,
    required this.quantidade,
  });
}

class _ListaBalancoResumo {
  final String id;
  final String status;
  final String tipoDocumento;
  final String nomeArquivoInformado;
  final String clienteNome;
  final int totalItens;
  final String criadoPor;
  final String criadoEm;
  final String enviadoEm;
  final String geradoEm;
  final String arquivoNome;

  const _ListaBalancoResumo({
    required this.id,
    required this.status,
    required this.tipoDocumento,
    required this.nomeArquivoInformado,
    required this.clienteNome,
    required this.totalItens,
    required this.criadoPor,
    required this.criadoEm,
    required this.enviadoEm,
    required this.geradoEm,
    required this.arquivoNome,
  });
}

class _ConfiguracaoDocumento {
  final String tipoDocumento;
  final String nomeArquivo;
  final String clienteNome;

  const _ConfiguracaoDocumento({
    required this.tipoDocumento,
    required this.nomeArquivo,
    required this.clienteNome,
  });
}

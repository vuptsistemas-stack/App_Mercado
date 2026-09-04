import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../services/central_service.dart';
import '../../services/sessao_loja.dart';

enum OrigemPrecoOferta { api, app }

enum TipoOfertaProduto { oferta, superOferta }

class OfertasPage extends StatefulWidget {
  const OfertasPage({super.key});

  @override
  State<OfertasPage> createState() => _OfertasPageState();
}

class _OfertasPageState extends State<OfertasPage> {
  static Color get vermelho => SessaoLoja.corPrimaria;
  static Color get fundo => SessaoLoja.corFundo;

  final CentralService centralService = CentralService();

  final buscaController = TextEditingController();
  final precoAppController = TextEditingController();
  final dataFimController = TextEditingController();

  Timer? debounceBusca;

  bool carregandoOfertas = true;
  bool buscandoProdutos = false;
  bool salvando = false;
  bool consultandoProdutoEdicao = false;
  bool exibirProdutosSemEstoque = true;

  String? erro;

  List<Map<String, dynamic>> produtos = [];
  List<Map<String, dynamic>> ofertas = [];

  Map<String, dynamic>? produtoSelecionado;
  String? ofertaIdEmEdicao;
  OrigemPrecoOferta origemPreco = OrigemPrecoOferta.api;
  TipoOfertaProduto tipoOferta = TipoOfertaProduto.oferta;

  @override
  void initState() {
    super.initState();
    carregarConfiguracaoExibirProdutosSemEstoque();
    carregarOfertas();
  }

  @override
  void dispose() {
    debounceBusca?.cancel();
    buscaController.dispose();
    precoAppController.dispose();
    dataFimController.dispose();
    super.dispose();
  }

  String? get apiBaseUrl {
    final url = SessaoLoja.apiBaseUrl?.trim();

    if (url == null || url.isEmpty) {
      return null;
    }

    return url.replaceAll(RegExp(r'/+$'), '');
  }

  bool get usandoPrecoApi => origemPreco == OrigemPrecoOferta.api;

  String get tipoOfertaCodigo {
    return tipoOferta == TipoOfertaProduto.superOferta
        ? 'SUPER_OFERTA'
        : 'OFERTA';
  }

  String textoTipoOfertaCodigo(dynamic valor) {
    final tipo = valor?.toString().trim().toUpperCase() ?? '';

    if (tipo == 'SUPER_OFERTA') {
      return 'Super oferta';
    }

    return 'Oferta';
  }

  TipoOfertaProduto tipoOfertaPorCodigo(dynamic valor) {
    final tipo = valor?.toString().trim().toUpperCase() ?? '';

    if (tipo == 'SUPER_OFERTA') {
      return TipoOfertaProduto.superOferta;
    }

    return TipoOfertaProduto.oferta;
  }

  Widget radioTipoOferta({
    required TipoOfertaProduto value,
    required String title,
    required String subtitle,
  }) {
    return Material(
      color: Colors.transparent,
      child: RadioListTile<TipoOfertaProduto>(
        value: value,
        groupValue: tipoOferta,
        activeColor: vermelho,
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(subtitle),
        onChanged: salvando
            ? null
            : (novoValor) {
                setState(() {
                  tipoOferta = novoValor ?? TipoOfertaProduto.oferta;
                });
              },
      ),
    );
  }

  Widget radioOrigemPreco({
    required OrigemPrecoOferta value,
    required String title,
    required String subtitle,
  }) {
    return Material(
      color: Colors.transparent,
      child: RadioListTile<OrigemPrecoOferta>(
        value: value,
        groupValue: origemPreco,
        activeColor: vermelho,
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(subtitle),
        onChanged: salvando
            ? null
            : (novoValor) {
                setState(() {
                  origemPreco = novoValor ?? OrigemPrecoOferta.api;
                });
              },
      ),
    );
  }

  String? get mercadoIdAtual {
    final id = SessaoLoja.mercadoId?.trim();

    if (id == null || id.isEmpty) {
      return null;
    }

    return id;
  }

  String mensagemAmigavelErro(Object erro) {
    final erroOriginal = erro.toString();
    final textoErro = erroOriginal.toLowerCase();
    final mensagemCentral = CentralService.mensagemErroUsuario(erro);

    if (mensagemCentral == CentralService.mensagemSemInternet) {
      return mensagemCentral;
    }

    if (textoErro.contains('jwt expired') || textoErro.contains('pgrst303')) {
      return 'Sua sessão expirou de verdade. Saia e entre novamente no sistema para continuar.';
    }

    // Quando a Edge Function retorna uma mensagem genérica de sessão/token,
    // não podemos afirmar que a sessão expirou. Para usuário de loja isso
    // normalmente indica token da loja recusado ou autorização da function.
    if (textoErro.contains('sessão expir') ||
        textoErro.contains('sessao expir')) {
      return 'Não foi possível validar sua sessão. Entre novamente para continuar.';
    }

    if (textoErro.contains('row-level security') ||
        textoErro.contains('42501') ||
        textoErro.contains('forbidden')) {
      return 'Você não tem permissão para gerenciar ofertas nesta loja.';
    }

    if (textoErro.contains('401') || textoErro.contains('unauthorized')) {
      return 'Acesso não autorizado para gerenciar ofertas nesta loja.';
    }

    if (textoErro.contains('token')) {
      return 'Não foi possível validar sua sessão. Entre novamente para continuar.';
    }

    if (textoErro.contains('acesso negado') ||
        textoErro.contains('sem permissão') ||
        textoErro.contains('permissão')) {
      return 'Você não tem permissão para gerenciar ofertas nesta loja.';
    }

    if (textoErro.contains('mercado_id')) {
      return 'Não foi possível identificar a loja atual. Entre novamente no sistema.';
    }

    return mensagemCentral;
  }

  String texto(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? '-' : texto;
  }

  String somenteNumeros(String valor) {
    return valor.replaceAll(RegExp(r'\D'), '');
  }

  String normalizarEan(String valor) {
    final numeros = somenteNumeros(valor);

    if (numeros.isEmpty) {
      return '';
    }

    if (numeros.length < 14) {
      return numeros.padLeft(14, '0');
    }

    return numeros;
  }

  double? numero(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is num) {
      return valor.toDouble();
    }

    var textoValor = valor.toString().trim();

    if (textoValor.isEmpty) {
      return null;
    }

    textoValor = textoValor
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll('.', '')
        .replaceAll(',', '.');

    return double.tryParse(textoValor);
  }

  String moeda(dynamic valor) {
    final valorNumero = numero(valor);

    if (valorNumero == null) {
      return 'R\$ 0,00';
    }

    return 'R\$ ${valorNumero.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String campoProduto(Map<String, dynamic> produto, List<String> nomes) {
    for (final nome in nomes) {
      final valor = produto[nome];

      if (valor != null && valor.toString().trim().isNotEmpty) {
        return valor.toString().trim();
      }
    }

    return '';
  }

  String nomeProduto(Map<String, dynamic> produto) {
    final nome = campoProduto(produto, [
      'nome_produto',
      'descricao',
      'nome',
      'produto',
    ]);

    return nome.isEmpty ? 'Produto' : nome;
  }

  String eanProduto(Map<String, dynamic> produto) {
    final ean = campoProduto(produto, [
      'ean_principal',
      'ean',
      'codigo_barras',
      'codigo',
      'cod_barras',
    ]);

    if (ean.isEmpty) {
      return '';
    }

    return normalizarEan(ean);
  }

  String? produtoId(Map<String, dynamic> produto) {
    final id = campoProduto(produto, [
      'produto_id',
      'id',
      'codigo_produto',
      'cod_produto',
    ]);

    return id.isEmpty ? null : id;
  }

  double? precoProduto(Map<String, dynamic> produto) {
    for (final campo in [
      'preco_venda',
      'preco',
      'valor',
      'valor_venda',
      'preco_unitario',
      'preco_promocao',
    ]) {
      final valor = numero(produto[campo]);

      if (valor != null) {
        return valor;
      }
    }

    return null;
  }

  double estoqueProduto(Map<String, dynamic> produto) {
    for (final campo in [
      'estoque_atual',
      'estoque',
      'quantidade',
      'saldo_estoque',
      'qtd_estoque',
      'saldo',
    ]) {
      final valor = numero(produto[campo]);

      if (valor != null) {
        return valor;
      }
    }

    return 0;
  }

  bool valorBool(dynamic valor, bool padrao) {
    if (valor is bool) return valor;

    if (valor is num) {
      return valor == 1;
    }

    if (valor is String) {
      final textoValor = valor.trim().toLowerCase();

      if (textoValor == 'true' || textoValor == '1' || textoValor == 'sim') {
        return true;
      }

      if (textoValor == 'false' ||
          textoValor == '0' ||
          textoValor == 'nao' ||
          textoValor == 'não') {
        return false;
      }
    }

    return padrao;
  }

  Future<bool> buscarConfiguracaoExibirProdutosSemEstoque() async {
    final supabaseLoja = SessaoLoja.supabaseLoja;
    final mercadoId = SessaoLoja.mercadoId?.trim();

    if (supabaseLoja == null || mercadoId == null || mercadoId.isEmpty) {
      return exibirProdutosSemEstoque;
    }

    try {
      final resposta = await supabaseLoja
          .from('loja_configuracoes')
          .select('exibir_produtos_sem_estoque')
          .eq('mercado_id', mercadoId)
          .limit(1)
          .maybeSingle();

      if (resposta == null) {
        return true;
      }

      return valorBool(resposta['exibir_produtos_sem_estoque'], true);
    } catch (_) {
      return exibirProdutosSemEstoque;
    }
  }

  Future<void> carregarConfiguracaoExibirProdutosSemEstoque() async {
    final valor = await buscarConfiguracaoExibirProdutosSemEstoque();

    if (!mounted) return;

    setState(() {
      exibirProdutosSemEstoque = valor;
    });
  }

  String unidadeProduto(Map<String, dynamic> produto) {
    final unidade = campoProduto(produto, [
      'sigla_saida',
      'unidade_medida',
      'unidade',
      'sigla_unidade',
      'unidade_sigla',
      'un',
      'um',
    ]);

    return unidade.isEmpty ? 'UN' : unidade;
  }

  List<Map<String, dynamic>> extrairProdutos(dynamic data) {
    if (data == null) {
      return [];
    }

    if (data is List) {
      return data
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (data is Map) {
      if (data['erro'] != null) {
        throw Exception(data['erro'].toString());
      }

      for (final campo in ['produtos', 'data', 'resultado', 'results']) {
        if (data[campo] is List) {
          return List<Map<String, dynamic>>.from(data[campo]);
        }
      }

      if (data['produto'] is Map) {
        return [Map<String, dynamic>.from(data['produto'])];
      }

      if (data['produto_id'] != null ||
          data['ean_principal'] != null ||
          data['nome_produto'] != null) {
        return [Map<String, dynamic>.from(data)];
      }
    }

    return [];
  }

  bool buscaSomenteNumeros(String valor) {
    final texto = valor.trim();

    if (texto.isEmpty) {
      return false;
    }

    return RegExp(r'^[0-9]+$').hasMatch(texto);
  }

  Future<List<Map<String, dynamic>>> buscarNaApi(String busca) async {
    final api = apiBaseUrl;

    if (api == null) {
      throw Exception('API da loja não configurada.');
    }

    final textoBusca = busca.trim();

    if (textoBusca.isEmpty) {
      return [];
    }

    final Uri url;

    if (buscaSomenteNumeros(textoBusca)) {
      final codigo = normalizarEan(textoBusca);
      url = Uri.parse('$api/produto/ean/$codigo');
    } else {
      final descricao = Uri.encodeComponent(textoBusca);
      url = Uri.parse('$api/produto/descricao/$descricao');
    }

    final resposta = await http.get(url).timeout(const Duration(seconds: 20));

    if (resposta.statusCode == 404) {
      return [];
    }

    if (resposta.statusCode != 200) {
      throw Exception('Erro na API. Código HTTP: ${resposta.statusCode}');
    }

    final data = jsonDecode(resposta.body);
    return extrairProdutos(data);
  }

  Map<String, dynamic>? localizarProdutoPorEan(
    List<Map<String, dynamic>> produtosEncontrados,
    String ean,
  ) {
    final eanNormalizado = normalizarEan(ean);

    for (final produto in produtosEncontrados) {
      if (eanProduto(produto) == eanNormalizado) {
        return produto;
      }
    }

    if (produtosEncontrados.length == 1) {
      return produtosEncontrados.first;
    }

    return null;
  }

  void agendarBusca(String valor) {
    debounceBusca?.cancel();

    final busca = valor.trim();

    if (busca.isEmpty) {
      setState(() {
        produtos = [];
        produtoSelecionado = null;
        erro = null;
        buscandoProdutos = false;
      });
      return;
    }

    // Igual ao home.dart: código/EAN numérico não dispara busca automática
    // enquanto está digitando. O usuário confirma no botão ou no Enter.
    if (buscaSomenteNumeros(busca)) {
      setState(() {
        produtos = [];
        erro = null;
        buscandoProdutos = false;
      });
      return;
    }

    if (busca.length < 3) {
      setState(() {
        produtos = [];
        produtoSelecionado = null;
        erro = null;
        buscandoProdutos = false;
      });
      return;
    }

    // Aqui é apenas sugestão de produtos. Não tira o foco do campo
    // e não seleciona o produto automaticamente.
    debounceBusca = Timer(
      const Duration(milliseconds: 500),
      () => buscarSugestoesProdutos(busca),
    );
  }

  Future<void> buscarSugestoesProdutos(String busca) async {
    final textoBusca = busca.trim();

    if (textoBusca.length < 3 || buscaSomenteNumeros(textoBusca)) {
      return;
    }

    setState(() {
      buscandoProdutos = true;
      erro = null;
      produtos = [];
      produtoSelecionado = null;
    });

    try {
      final resultado = await buscarNaApi(textoBusca);

      if (!mounted) return;

      setState(() {
        produtos = resultado;
        buscandoProdutos = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        erro = mensagemAmigavelErro(e);
        buscandoProdutos = false;
      });
    }
  }

  Future<void> buscarProdutos(String busca) async {
    final textoBusca = busca.trim();

    if (textoBusca.isEmpty) {
      return;
    }

    // Só confirma a busca quando o usuário apertar Enter ou tocar no botão.
    FocusScope.of(context).unfocus();

    setState(() {
      buscandoProdutos = true;
      erro = null;
      produtos = [];
      produtoSelecionado = null;
    });

    try {
      final resultado = await buscarNaApi(textoBusca);

      if (!mounted) return;

      if (resultado.length == 1) {
        selecionarProduto(resultado.first);

        setState(() {
          buscandoProdutos = false;
        });

        return;
      }

      setState(() {
        produtos = resultado;
        buscandoProdutos = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        erro = mensagemAmigavelErro(e);
        buscandoProdutos = false;
      });
    }
  }

  Future<void> carregarOfertas() async {
    final mercadoId = mercadoIdAtual;

    if (mercadoId == null) {
      setState(() {
        carregandoOfertas = false;
        erro =
            'Não foi possível identificar a loja atual. Saia e entre novamente.';
      });
      return;
    }

    setState(() {
      carregandoOfertas = true;
      erro = null;
    });

    try {
      final resposta = await centralService.listarProdutoOfertas(
        mercadoId: mercadoId,
      );

      if (!mounted) return;

      setState(() {
        ofertas = resposta;
        carregandoOfertas = false;
      });
    } catch (e) {
      if (!mounted) return;

      debugPrint(
        'ERRO REAL AO LISTAR OFERTAS: ${CentralService.mensagemErroUsuario(e)}',
      );

      setState(() {
        erro = mensagemAmigavelErro(e);
        carregandoOfertas = false;
      });
    }
  }

  void selecionarProduto(Map<String, dynamic> produto) {
    final precoApi = precoProduto(produto);

    setState(() {
      produtoSelecionado = produto;
      ofertaIdEmEdicao = null;
      produtos = [];
      buscaController.text = nomeProduto(produto);
      origemPreco = OrigemPrecoOferta.api;
      tipoOferta = TipoOfertaProduto.oferta;

      if (precoApi != null) {
        precoAppController.text = precoApi
            .toStringAsFixed(2)
            .replaceAll('.', ',');
      } else {
        precoAppController.clear();
      }
    });
  }

  Future<void> salvarOferta() async {
    final mercadoId = mercadoIdAtual;
    final produto = produtoSelecionado;

    if (mercadoId == null) {
      mostrarMensagem(
        'Não foi possível identificar a loja atual. Saia e entre novamente.',
        erro: true,
      );
      return;
    }

    if (produto == null) {
      mostrarMensagem('Selecione um produto primeiro.', erro: true);
      return;
    }

    final ean = eanProduto(produto);

    if (ean.isEmpty) {
      mostrarMensagem('Produto sem EAN/código de barras.', erro: true);
      return;
    }

    final precoApp = numero(precoAppController.text);

    if (!usandoPrecoApi && precoApp == null) {
      mostrarMensagem('Informe o Preço APP da oferta.', erro: true);
      return;
    }

    DateTime? dataFim;

    if (dataFimController.text.trim().isNotEmpty) {
      dataFim = DateTime.tryParse(dataFimController.text.trim());

      if (dataFim == null) {
        mostrarMensagem('Data final inválida. Use AAAA-MM-DD.', erro: true);
        return;
      }
    }

    setState(() {
      salvando = true;
    });

    try {
      final permiteProdutoSemEstoque =
          await buscarConfiguracaoExibirProdutosSemEstoque();
      final produtosAtualizados = await buscarNaApi(ean);
      final produtoConsultado = localizarProdutoPorEan(
        produtosAtualizados,
        ean,
      );

      if (produtoConsultado == null) {
        throw Exception(
          'Não foi possível localizar o produto na API para validar o estoque atual.',
        );
      }

      final produtoAtual = <String, dynamic>{...produto, ...produtoConsultado};
      final precoApi = precoProduto(produtoAtual);
      final estoqueAtual = estoqueProduto(produtoAtual);
      final unidadeAtual = unidadeProduto(produtoAtual);

      if (!mounted) return;

      setState(() {
        exibirProdutosSemEstoque = permiteProdutoSemEstoque;
        produtoSelecionado = produtoAtual;
      });

      if (!permiteProdutoSemEstoque && estoqueAtual <= 0) {
        mostrarMensagem(
          'Este produto está sem estoque. Como a loja está configurada para ocultar produtos sem estoque no app, ele não pode ser cadastrado como oferta.',
          erro: true,
        );
        return;
      }

      final dados = <String, dynamic>{
        if (ofertaIdEmEdicao != null) 'id': ofertaIdEmEdicao,
        'produto_id': produtoId(produtoAtual),
        'ean': ean,
        'nome_produto': nomeProduto(produtoAtual),
        'preco_api_referencia': precoApi,
        'origem_preco': usandoPrecoApi ? 'API' : 'APP',
        'tipo_oferta': tipoOfertaCodigo,
        'preco_app': usandoPrecoApi ? null : precoApp,
        'estoque': estoqueAtual,
        'estoque_atual': estoqueAtual,
        'quantidade': estoqueAtual,
        'saldo': estoqueAtual,
        'unidade_medida': unidadeAtual,
        'sigla_saida': unidadeAtual,
        'unidade': unidadeAtual,
        'imagem_url': campoProduto(produtoAtual, [
          'imagem_url',
          'image_url',
          'foto',
          'url_imagem',
        ]),
        'ativo': true,
        'destaque': true,
        'data_inicio': DateTime.now().toIso8601String(),
        'data_fim': dataFim?.toIso8601String(),
        'atualizado_em': DateTime.now().toIso8601String(),
      };

      await centralService.salvarProdutoOferta(
        mercadoId: mercadoId,
        oferta: dados,
      );

      if (!mounted) return;

      mostrarMensagem('Oferta salva com sucesso.');

      limparFormulario();

      await carregarOfertas();
    } catch (e) {
      if (!mounted) return;

      debugPrint(
        'ERRO REAL AO SALVAR OFERTA: ${CentralService.mensagemErroUsuario(e)}',
      );
      mostrarMensagem(mensagemAmigavelErro(e), erro: true);
    } finally {
      if (mounted) {
        setState(() {
          salvando = false;
        });
      }
    }
  }

  void limparFormulario() {
    debounceBusca?.cancel();

    setState(() {
      buscaController.clear();
      precoAppController.clear();
      dataFimController.clear();
      produtoSelecionado = null;
      ofertaIdEmEdicao = null;
      produtos = [];
      origemPreco = OrigemPrecoOferta.api;
      tipoOferta = TipoOfertaProduto.oferta;
      erro = null;
    });
  }

  Future<void> alternarOferta(Map<String, dynamic> oferta, bool ativo) async {
    final mercadoId = mercadoIdAtual;
    final ofertaId = oferta['id']?.toString() ?? '';

    if (mercadoId == null) {
      mostrarMensagem(
        'Não foi possível identificar a loja atual. Saia e entre novamente.',
        erro: true,
      );
      return;
    }

    if (ofertaId.isEmpty) {
      mostrarMensagem('Oferta sem identificação.', erro: true);
      return;
    }

    try {
      await centralService.alternarProdutoOferta(
        mercadoId: mercadoId,
        ofertaId: ofertaId,
        ativo: ativo,
      );

      await carregarOfertas();
    } catch (e) {
      debugPrint(
        'ERRO REAL AO ALTERNAR OFERTA: ${CentralService.mensagemErroUsuario(e)}',
      );
      mostrarMensagem(mensagemAmigavelErro(e), erro: true);
    }
  }

  Future<void> excluirOferta(Map<String, dynamic> oferta) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir oferta'),
        content: Text(
          'Deseja excluir a oferta de "${texto(oferta['nome_produto'])}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: vermelho,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmar != true) {
      return;
    }

    final mercadoId = mercadoIdAtual;
    final ofertaId = oferta['id']?.toString() ?? '';

    if (mercadoId == null) {
      mostrarMensagem(
        'Não foi possível identificar a loja atual. Saia e entre novamente.',
        erro: true,
      );
      return;
    }

    if (ofertaId.isEmpty) {
      mostrarMensagem('Oferta sem identificação.', erro: true);
      return;
    }

    try {
      await centralService.excluirProdutoOferta(
        mercadoId: mercadoId,
        ofertaId: ofertaId,
      );

      await carregarOfertas();
    } catch (e) {
      debugPrint(
        'ERRO REAL AO EXCLUIR OFERTA: ${CentralService.mensagemErroUsuario(e)}',
      );
      mostrarMensagem(mensagemAmigavelErro(e), erro: true);
    }
  }

  Future<void> editarOferta(Map<String, dynamic> oferta) async {
    final ofertaId = oferta['id']?.toString().trim() ?? '';
    final ean = normalizarEan(oferta['ean']?.toString() ?? '');

    setState(() {
      produtoSelecionado = {
        'produto_id': oferta['produto_id'],
        'ean_principal': oferta['ean'],
        'nome_produto': oferta['nome_produto'],
        'preco_venda': oferta['preco_api_referencia'],
        'imagem_url': oferta['imagem_url'],
      };
      ofertaIdEmEdicao = ofertaId.isEmpty ? null : ofertaId;
      consultandoProdutoEdicao = true;

      buscaController.text = texto(oferta['nome_produto']);

      origemPreco = oferta['origem_preco']?.toString().toUpperCase() == 'APP'
          ? OrigemPrecoOferta.app
          : OrigemPrecoOferta.api;

      tipoOferta = tipoOfertaPorCodigo(oferta['tipo_oferta']);

      final precoApp = numero(oferta['preco_app']);

      precoAppController.text = precoApp == null
          ? ''
          : precoApp.toStringAsFixed(2).replaceAll('.', ',');

      final dataFim = oferta['data_fim']?.toString();

      if (dataFim == null || dataFim.isEmpty) {
        dataFimController.clear();
      } else {
        dataFimController.text = dataFim.length >= 10
            ? dataFim.substring(0, 10)
            : dataFim;
      }

      produtos = [];
    });

    try {
      final produtosAtualizados = await buscarNaApi(ean);
      final produtoAtual = localizarProdutoPorEan(produtosAtualizados, ean);

      if (!mounted) return;

      if (produtoAtual == null) {
        mostrarMensagem(
          'Oferta aberta, mas não foi possível localizar o produto na API para atualizar o estoque.',
          erro: true,
        );
        return;
      }

      setState(() {
        produtoSelecionado = <String, dynamic>{
          ...produtoSelecionado!,
          ...produtoAtual,
        };
      });

      mostrarMensagem(
        'Oferta carregada. Estoque atual: ${estoqueProduto(produtoAtual).toStringAsFixed(3)} ${unidadeProduto(produtoAtual)}.',
      );
    } catch (e) {
      if (!mounted) return;

      mostrarMensagem(
        'Oferta aberta, mas não foi possível consultar o estoque atual: ${mensagemAmigavelErro(e)}',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          consultandoProdutoEdicao = false;
        });
      }
    }
  }

  void mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? Colors.red : Colors.green,
      ),
    );
  }

  Widget topo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [SessaoLoja.corPrimaria, SessaoLoja.corSecundaria],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: vermelho.withValues(alpha: 0.20),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white,
            child: Icon(Icons.campaign, color: vermelho, size: 34),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ofertas do App',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Escolha produtos para Oferta ou Super oferta no app cliente.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget campoBusca() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: caixaBranca(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Adicionar oferta',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: buscaController,
            onChanged: agendarBusca,
            onSubmitted: buscarProdutos,
            decoration: InputDecoration(
              labelText: 'Buscar produto por nome ou EAN',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: buscandoProdutos
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Buscar',
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () => buscarProdutos(buscaController.text),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          if (erro != null) ...[
            const SizedBox(height: 10),
            Text(
              erro!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
          if (produtos.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 260),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: produtos.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final produto = produtos[index];
                  final ean = eanProduto(produto);
                  final preco = precoProduto(produto);

                  return Material(
                    color: Colors.transparent,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: vermelho.withValues(alpha: 0.10),
                        child: Icon(Icons.shopping_basket, color: vermelho),
                      ),
                      title: Text(
                        nomeProduto(produto),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'EAN: ${ean.isEmpty ? '-' : ean} • Preço API: ${moeda(preco)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => selecionarProduto(produto),
                    ),
                  );
                },
              ),
            ),
          ],
          if (produtoSelecionado != null) ...[
            const SizedBox(height: 16),
            produtoSelecionadoCard(),
          ],
        ],
      ),
    );
  }

  Widget produtoSelecionadoCard() {
    final produto = produtoSelecionado!;
    final precoApi = precoProduto(produto);
    final estoqueAtual = estoqueProduto(produto);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Produto selecionado',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            nomeProduto(produto),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Text(
            'EAN: ${eanProduto(produto)}',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Text(
            'Preço atual da API: ${moeda(precoApi)}',
            style: TextStyle(color: vermelho, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          if (consultandoProdutoEdicao)
            const Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Consultando estoque atual...'),
              ],
            )
          else
            Text(
              'Estoque atual: ${estoqueAtual.toStringAsFixed(3)} ${unidadeProduto(produto)}',
              style: const TextStyle(
                color: Color(0xFF374151),
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 14),
          const Text(
            'Tipo da oferta',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          radioTipoOferta(
            value: TipoOfertaProduto.oferta,
            title: 'Oferta',
            subtitle: 'Aparece na seção Ofertas da loja.',
          ),
          radioTipoOferta(
            value: TipoOfertaProduto.superOferta,
            title: 'Super oferta',
            subtitle: 'Aparece em destaque acima das ofertas.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Origem do preço no app cliente',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          radioOrigemPreco(
            value: OrigemPrecoOferta.api,
            title: 'Preço API',
            subtitle: 'Sempre buscar o preço atualizado na API.',
          ),
          radioOrigemPreco(
            value: OrigemPrecoOferta.app,
            title: 'Preço APP',
            subtitle: 'Sempre usar o preço salvo nesta tabela.',
          ),
          TextField(
            controller: precoAppController,
            enabled: !usandoPrecoApi && !salvando,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
            ],
            decoration: InputDecoration(
              labelText: 'Preço APP',
              helperText: usandoPrecoApi
                  ? 'Desabilitado porque a oferta está usando Preço API.'
                  : 'Obrigatório quando a origem for Preço APP.',
              prefixIcon: const Icon(Icons.attach_money),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: dataFimController,
            enabled: !salvando,
            decoration: InputDecoration(
              labelText: 'Data final opcional',
              hintText: 'AAAA-MM-DD',
              prefixIcon: const Icon(Icons.calendar_today),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: salvando ? null : limparFormulario,
                  icon: const Icon(Icons.close),
                  label: const Text('Limpar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: salvando ? null : salvarOferta,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: vermelho,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: salvando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Salvar oferta'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  BoxDecoration caixaBranca() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  Widget listaOfertas() {
    if (carregandoOfertas) {
      return Container(
        padding: const EdgeInsets.all(26),
        decoration: caixaBranca(),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: caixaBranca(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Ofertas cadastradas',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Atualizar',
                onPressed: carregarOfertas,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (ofertas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: Text(
                  'Nenhuma oferta cadastrada ainda.',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            )
          else
            ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: ofertas.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final oferta = ofertas[index];
                return itemOferta(oferta);
              },
            ),
        ],
      ),
    );
  }

  Widget itemOferta(Map<String, dynamic> oferta) {
    final ativo = oferta['ativo'] == true;
    final origem = oferta['origem_preco']?.toString().toUpperCase() == 'APP'
        ? 'Preço APP'
        : 'Preço API';

    final precoTexto = origem == 'Preço APP'
        ? moeda(oferta['preco_app'])
        : 'Atualizado pela API';

    final tipoOfertaTexto = textoTipoOfertaCodigo(oferta['tipo_oferta']);
    final superOferta =
        oferta['tipo_oferta']?.toString().toUpperCase() == 'SUPER_OFERTA';

    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: ativo
              ? (superOferta
                    ? Colors.orange.withValues(alpha: 0.16)
                    : vermelho.withValues(alpha: 0.12))
              : Colors.grey.withValues(alpha: 0.15),
          child: Icon(
            ativo
                ? (superOferta
                      ? Icons.local_fire_department
                      : Icons.local_offer)
                : Icons.pause,
            color: ativo
                ? (superOferta ? Colors.orange.shade800 : vermelho)
                : Colors.grey,
          ),
        ),
        title: Text(
          texto(oferta['nome_produto']),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '$tipoOfertaTexto • EAN: ${texto(oferta['ean'])}\n'
          '$origem • $precoTexto',
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (acao) {
            if (acao == 'editar') {
              editarOferta(oferta);
            } else if (acao == 'ativar') {
              alternarOferta(oferta, true);
            } else if (acao == 'desativar') {
              alternarOferta(oferta, false);
            } else if (acao == 'excluir') {
              excluirOferta(oferta);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'editar', child: Text('Editar')),
            PopupMenuItem(
              value: ativo ? 'desativar' : 'ativar',
              child: Text(ativo ? 'Desativar' : 'Ativar'),
            ),
            const PopupMenuItem(value: 'excluir', child: Text('Excluir')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lojaConectada = mercadoIdAtual != null;

    return Scaffold(
      backgroundColor: fundo,
      appBar: AppBar(
        title: const Text('Ofertas'),
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: !lojaConectada
            ? const Center(
                child: Text(
                  'Não foi possível identificar a loja atual. Faça login novamente.',
                ),
              )
            : RefreshIndicator(
                onRefresh: carregarOfertas,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    topo(),
                    const SizedBox(height: 18),
                    campoBusca(),
                    const SizedBox(height: 18),
                    listaOfertas(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }
}

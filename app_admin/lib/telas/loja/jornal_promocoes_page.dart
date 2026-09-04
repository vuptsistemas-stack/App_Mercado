import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/central_service.dart';
import '../../services/sessao_loja.dart';

class JornalPromocoesPage extends StatefulWidget {
  const JornalPromocoesPage({super.key});

  @override
  State<JornalPromocoesPage> createState() => _JornalPromocoesPageState();
}

class _JornalPromocoesPageState extends State<JornalPromocoesPage> {
  static const List<int> quantidadesPermitidas = [1, 3, 6, 9, 12];
  static const int quantidadeMaxima = 12;

  final centralService = CentralService();
  final tituloController = TextEditingController();
  final validadeController = TextEditingController();
  final observacaoController = TextEditingController();
  final buscaController = TextEditingController();
  final precoController = TextEditingController();
  final previewKey = GlobalKey();

  Timer? debounceBusca;

  bool buscandoProdutos = false;
  bool gerandoArquivo = false;
  String? erro;

  List<Map<String, dynamic>> produtos = [];
  List<Map<String, dynamic>> itensJornal = [];
  Map<String, dynamic>? produtoSelecionado;

  Color get corPrimaria => SessaoLoja.corPrimaria;
  Color get corSecundaria => SessaoLoja.corSecundaria;
  Color get corFundo => SessaoLoja.corFundo;
  bool get quantidadeJornalValida =>
      quantidadesPermitidas.contains(itensJornal.length);

  String? get apiBaseUrl {
    final url = SessaoLoja.apiBaseUrl?.trim();
    if (url == null || url.isEmpty) return null;
    return url.replaceAll(RegExp(r'/+$'), '');
  }

  String get chaveRascunho {
    final mercado = SessaoLoja.mercadoId ?? SessaoLoja.mercadoCodigo ?? 'loja';
    return 'jornal_promocoes_rascunho_$mercado';
  }

  @override
  void initState() {
    super.initState();
    tituloController.text = 'Ofertas frescas';
    observacaoController.text = 'Ofertas validas enquanto durarem os estoques.';
    carregarRascunho();
  }

  @override
  void dispose() {
    debounceBusca?.cancel();
    tituloController.dispose();
    validadeController.dispose();
    observacaoController.dispose();
    buscaController.dispose();
    precoController.dispose();
    super.dispose();
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
    if (numeros.isEmpty) return '';
    return numeros.length >= 14 ? numeros : numeros.padLeft(14, '0');
  }

  bool buscaSomenteNumeros(String valor) {
    final texto = valor.trim();
    return texto.isNotEmpty && RegExp(r'^[0-9]+$').hasMatch(texto);
  }

  String campoProduto(Map<String, dynamic> produto, List<String> campos) {
    for (final campo in campos) {
      final valor = produto[campo];
      if (valor != null && valor.toString().trim().isNotEmpty) {
        return valor.toString().trim();
      }
    }
    return '';
  }

  String nomeProduto(Map<String, dynamic> produto) {
    return campoProduto(produto, [
      'nome_produto',
      'descricao',
      'nome',
      'produto',
      'descricao_produto',
    ]);
  }

  String eanProduto(Map<String, dynamic> produto) {
    return campoProduto(produto, [
      'ean',
      'codigo_barras',
      'ean_principal',
      'barras',
      'codigo',
    ]);
  }

  String imagemProduto(Map<String, dynamic> produto) {
    return campoProduto(produto, [
      'imagem_url',
      'image_url',
      'imagem',
      'foto',
      'url_imagem',
      'url',
      'image',
      'thumbnail',
    ]);
  }

  String unidadeProduto(Map<String, dynamic> produto) {
    return campoProduto(produto, [
      'unidade',
      'unidade_medida',
      'sigla_unidade',
      'un',
    ]).toLowerCase();
  }

  String precoJornal(Map<String, dynamic> item) {
    final unidade = item['unidade']?.toString().trim().toLowerCase() ?? '';
    return '${moeda(item['preco'])}${unidade.isEmpty ? '' : '/$unidade'}';
  }

  String get orientacaoQuantidade {
    return 'Use 1, 3, 6, 9 ou 12 produtos. Atual: '
        '${itensJornal.length}/$quantidadeMaxima.';
  }

  bool validarQuantidadeJornal(String acao) {
    if (quantidadeJornalValida) return true;
    mostrarMensagem(
      'Para $acao, o jornal deve ter 1, 3, 6, 9 ou 12 produtos. '
      'Quantidade atual: ${itensJornal.length}.',
      erro: true,
    );
    return false;
  }

  Future<String> buscarImagemProduto(Map<String, dynamic> produto) async {
    final imagemLocal = imagemProduto(produto);
    if (imagemLocal.isNotEmpty) return imagemLocal;

    final mercadoId = SessaoLoja.mercadoId;
    if (mercadoId == null || mercadoId.isEmpty) return '';

    final ean = eanProduto(produto);
    final nome = nomeProduto(produto);
    if (ean.isEmpty && nome.isEmpty) return '';

    try {
      final resposta = await centralService.buscarImagemProdutoCentral(
        mercadoId: mercadoId,
        mercadoCodigo: SessaoLoja.mercadoCodigo,
        ean: ean.isEmpty ? null : ean,
        codigoBarras: ean.isEmpty ? null : ean,
        nomeProduto: nome,
      );

      return campoProduto(resposta, [
        'imagem_url',
        'url',
        'image',
        'thumbnail',
        'url_imagem',
      ]);
    } catch (_) {
      return '';
    }
  }

  double? numero(dynamic valor) {
    if (valor == null) return null;
    var texto = valor.toString().trim();
    if (texto.isEmpty) return null;

    if (texto.contains(',') && texto.contains('.')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    } else {
      texto = texto.replaceAll(',', '.');
    }

    return double.tryParse(texto);
  }

  double? precoProduto(Map<String, dynamic> produto) {
    for (final campo in [
      'preco',
      'preco_venda',
      'valor',
      'preco_api',
      'preco_atual',
      'preco_promocional',
    ]) {
      final valor = numero(produto[campo]);
      if (valor != null) return valor;
    }
    return null;
  }

  String moeda(dynamic valor) {
    final numeroValor = valor is num ? valor.toDouble() : numero(valor);
    if (numeroValor == null) return 'R\$ 0,00';
    return 'R\$ ${numeroValor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  List<Map<String, dynamic>> extrairProdutos(dynamic data) {
    if (data is List) {
      return List<Map<String, dynamic>>.from(data);
    }

    if (data is Map) {
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

  Future<List<Map<String, dynamic>>> buscarNaApi(String busca) async {
    final api = apiBaseUrl;
    if (api == null) {
      throw Exception('API da loja nao configurada.');
    }

    final textoBusca = busca.trim();
    if (textoBusca.isEmpty) return [];

    final Uri url;
    if (buscaSomenteNumeros(textoBusca)) {
      url = Uri.parse('$api/produto/ean/${normalizarEan(textoBusca)}');
    } else {
      url = Uri.parse(
        '$api/produto/descricao/${Uri.encodeComponent(textoBusca)}',
      );
    }

    final resposta = await http.get(url).timeout(const Duration(seconds: 20));

    if (resposta.statusCode == 404) return [];
    if (resposta.statusCode != 200) {
      throw Exception('Erro na API. Codigo HTTP: ${resposta.statusCode}');
    }

    return extrairProdutos(jsonDecode(resposta.body));
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

    if (buscaSomenteNumeros(busca) || busca.length < 3) {
      setState(() {
        produtos = [];
        erro = null;
        buscandoProdutos = false;
      });
      return;
    }

    debounceBusca = Timer(
      const Duration(milliseconds: 500),
      () => buscarProdutos(busca, sugestao: true),
    );
  }

  Future<void> buscarProdutos(String busca, {bool sugestao = false}) async {
    final textoBusca = busca.trim();
    if (textoBusca.isEmpty) return;

    if (!sugestao) FocusScope.of(context).unfocus();

    setState(() {
      buscandoProdutos = true;
      produtos = [];
      erro = null;
      if (!sugestao) produtoSelecionado = null;
    });

    try {
      final resultado = await buscarNaApi(textoBusca);
      if (!mounted) return;

      if (!sugestao && resultado.length == 1) {
        selecionarProduto(resultado.first);
        setState(() => buscandoProdutos = false);
        return;
      }

      setState(() {
        produtos = resultado;
        buscandoProdutos = false;
        if (resultado.isEmpty && !sugestao) {
          erro = 'Produto nao encontrado.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        erro = CentralService.mensagemErroUsuario(e);
        buscandoProdutos = false;
      });
    }
  }

  void selecionarProduto(Map<String, dynamic> produto) {
    final preco = precoProduto(produto);

    setState(() {
      produtoSelecionado = produto;
      produtos = [];
      buscaController.text = nomeProduto(produto);
      precoController.text = preco == null
          ? ''
          : preco.toStringAsFixed(2).replaceAll('.', ',');
    });
  }

  Future<void> carregarRascunho() async {
    final prefs = await SharedPreferences.getInstance();
    final bruto = prefs.getString(chaveRascunho);
    if (bruto == null || bruto.trim().isEmpty) return;

    try {
      final data = jsonDecode(bruto);
      if (data is! Map) return;
      if (!mounted) return;

      setState(() {
        tituloController.text =
            data['titulo']?.toString() ?? tituloController.text;
        validadeController.text = data['validade']?.toString() ?? '';
        observacaoController.text =
            data['observacao']?.toString() ?? observacaoController.text;
        itensJornal = data['itens'] is List
            ? List<Map<String, dynamic>>.from(data['itens'])
            : [];
      });
      preencherImagensFaltantes();
    } catch (_) {}
  }

  Future<void> preencherImagensFaltantes() async {
    final pendentes = itensJornal
        .where((item) => (item['imagem_url']?.toString().trim() ?? '').isEmpty)
        .toList();
    if (pendentes.isEmpty) return;

    var alterou = false;
    for (final item in pendentes) {
      final imagem = await buscarImagemProduto(item);
      if (imagem.isNotEmpty) {
        item['imagem_url'] = imagem;
        alterou = true;
      }
    }

    if (!mounted || !alterou) return;
    setState(() {});
    await salvarRascunho();
  }

  Future<void> salvarRascunho() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      chaveRascunho,
      jsonEncode({
        'titulo': tituloController.text,
        'validade': validadeController.text,
        'observacao': observacaoController.text,
        'itens': itensJornal,
      }),
    );
  }

  Future<void> adicionarProduto() async {
    if (itensJornal.length >= quantidadeMaxima) {
      mostrarMensagem(
        'O jornal permite no maximo $quantidadeMaxima produtos.',
        erro: true,
      );
      return;
    }

    final produto = produtoSelecionado;
    if (produto == null) {
      mostrarMensagem('Selecione um produto primeiro.', erro: true);
      return;
    }

    final preco = numero(precoController.text);
    if (preco == null || preco <= 0) {
      mostrarMensagem('Informe o preco promocional.', erro: true);
      return;
    }

    final ean = eanProduto(produto);
    final imagem = await buscarImagemProduto(produto);
    final item = {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'nome': nomeProduto(produto),
      'ean': ean,
      'preco': preco,
      'preco_original': precoProduto(produto),
      'imagem_url': imagem,
      'unidade': unidadeProduto(produto),
    };

    setState(() {
      itensJornal.add(item);
      produtoSelecionado = null;
      produtos = [];
      buscaController.clear();
      precoController.clear();
    });

    await salvarRascunho();
    mostrarMensagem('Produto adicionado ao jornal.');
  }

  Future<void> removerProduto(Map<String, dynamic> item) async {
    setState(() {
      itensJornal.removeWhere((produto) => produto['id'] == item['id']);
    });
    await salvarRascunho();
  }

  Future<void> limparJornal() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Limpar jornal'),
        content: const Text('Deseja remover todos os produtos deste jornal?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: corPrimaria,
              foregroundColor: Colors.white,
            ),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() {
      itensJornal = [];
    });
    await salvarRascunho();
  }

  String nomeArquivoBase() {
    final loja = (SessaoLoja.mercadoCodigo ?? 'loja')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
        .toLowerCase();
    final agora = DateTime.now();
    final data =
        '${agora.year}${agora.month.toString().padLeft(2, '0')}${agora.day.toString().padLeft(2, '0')}_${agora.hour.toString().padLeft(2, '0')}${agora.minute.toString().padLeft(2, '0')}';
    return 'jornal_promocoes_${loja}_$data';
  }

  Future<void> gerarImagem() async {
    if (!validarQuantidadeJornal('gerar a imagem')) return;

    setState(() => gerandoArquivo = true);

    try {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final boundary =
          previewKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;

      if (boundary == null) {
        throw Exception('Previa do jornal ainda nao esta pronta.');
      }

      final imagem = await boundary.toImage(pixelRatio: 3);
      final byteData = await imagem.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();

      if (bytes == null) {
        throw Exception('Nao foi possivel gerar a imagem.');
      }

      final dir = await getTemporaryDirectory();
      final arquivo = File('${dir.path}/${nomeArquivoBase()}.png');
      await arquivo.writeAsBytes(bytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(arquivo.path)],
          text: 'Jornal de promocoes ${SessaoLoja.mercadoNome ?? ''}',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(CentralService.mensagemErroUsuario(e), erro: true);
    } finally {
      if (mounted) setState(() => gerandoArquivo = false);
    }
  }

  String htmlEscape(dynamic valor) {
    return const HtmlEscape().convert(valor?.toString() ?? '');
  }

  String htmlJornal() {
    String cardProduto(Map<String, dynamic> item) {
      final imagem = item['imagem_url']?.toString() ?? '';
      final imgHtml = imagem.trim().isEmpty
          ? '<div class="sem-imagem">PRODUTO</div>'
          : '<img src="${htmlEscape(imagem)}" alt="">';

      return '''
      <section class="produto">
        <span class="acento"></span>
        <div class="imagem">$imgHtml</div>
        <div class="nome">${htmlEscape(item['nome'])}</div>
        <div class="preco">${htmlEscape(precoJornal(item))}</div>
      </section>
      ''';
    }

    final classeQuantidade = itensJornal.length == 1 ? ' unico' : '';

    return '''
<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${htmlEscape(tituloController.text)}</title>
  <style>
    @page { size: A4; margin: 10mm; }
    * { box-sizing: border-box; }
    body { margin: 0; font-family: Arial, sans-serif; background: #eef1f4; color: #0b1f3a; }
    .jornal { max-width: 760px; margin: 0 auto; background: #fbfaf6; overflow: hidden; border: 1px solid #d7dce2; }
    .topo { padding: 24px 28px 20px; background: #fbfaf6; }
    .marca { display: flex; align-items: center; gap: 10px; padding-bottom: 13px; border-bottom: 2px solid ${hexCss(corSecundaria)}; color: #0b1f3a; font-size: 17px; font-weight: 900; text-transform: uppercase; }
    .marca::before { content: ''; width: 24px; height: 24px; border: 4px solid ${hexCss(corPrimaria)}; border-top: 0; display: inline-block; }
    h1 { margin: 21px 0 10px; color: #0b1f3a; font-size: 48px; line-height: .92; letter-spacing: 0; text-transform: uppercase; }
    .campanha { display: flex; align-items: center; gap: 16px; }
    .validade { display: inline-block; padding: 8px 14px; background: #f9c80e; color: #0b1f3a; font-size: 16px; font-weight: 900; text-transform: uppercase; }
    .subtitulo { color: ${hexCss(corSecundaria)}; font-size: 17px; font-weight: 700; }
    .produtos { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); padding: 0 22px 18px; }
    .produtos.unico { grid-template-columns: minmax(0, 360px); justify-content: center; }
    .produto { position: relative; display: flex; min-width: 0; min-height: 172px; padding: 14px 12px 13px; flex-direction: column; border-right: 1px solid #d7dce2; border-bottom: 1px solid #d7dce2; }
    .produto:nth-child(3n) { border-right: 0; }
    .unico .produto { min-height: 420px; border-right: 0; }
    .acento { width: 28px; height: 4px; margin-bottom: 7px; background: ${hexCss(corPrimaria)}; }
    .produto:nth-child(3n+2) .acento { background: #f9c80e; }
    .produto:nth-child(3n) .acento { background: ${hexCss(corSecundaria)}; }
    .imagem { height: 102px; display: grid; place-items: center; }
    .unico .imagem { height: 285px; }
    img { max-width: 100%; max-height: 100%; object-fit: contain; }
    .sem-imagem { color: #8a94a3; font-size: 12px; font-weight: 800; }
    .nome { margin-top: 7px; color: #0b1f3a; font-size: 14px; font-weight: 900; text-transform: uppercase; }
    .preco { margin-top: 7px; color: #0b1f3a; font-size: 28px; font-weight: 900; white-space: nowrap; }
    .unico .nome { font-size: 22px; }
    .unico .preco { font-size: 46px; }
    .rodape { padding: 15px 22px; background: #0b1f3a; color: #fff; text-align: center; font-size: 13px; font-weight: 700; }
    @media print { body { background: #fff; } .jornal { border: 0; } }
  </style>
</head>
<body>
  <main class="jornal">
    <header class="topo">
      <div class="marca">${htmlEscape(SessaoLoja.mercadoNome ?? 'Loja')}</div>
      <h1>${htmlEscape(tituloController.text)}</h1>
      <div class="campanha">
        <div class="validade">${htmlEscape(validadeController.text.isEmpty ? 'OFERTAS' : validadeController.text)}</div>
        <div class="subtitulo">Selecao especial para sua feira</div>
      </div>
    </header>
    <div class="produtos$classeQuantidade">
      ${itensJornal.map(cardProduto).join()}
    </div>
    <footer class="rodape">${htmlEscape(observacaoController.text.isEmpty ? 'Ofertas validas enquanto durarem os estoques.' : observacaoController.text)}</footer>
  </main>
</body>
</html>
''';
  }

  String hexCss(Color cor) {
    final value = cor.toARGB32() & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0')}';
  }

  Future<void> gerarHtmlImpressao() async {
    if (!validarQuantidadeJornal('gerar o arquivo de impressao')) return;

    setState(() => gerandoArquivo = true);

    try {
      final dir = await getTemporaryDirectory();
      final arquivo = File('${dir.path}/${nomeArquivoBase()}.html');
      await arquivo.writeAsString(htmlJornal());

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(arquivo.path)],
          text: 'Arquivo do jornal de promocoes para impressao.',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(CentralService.mensagemErroUsuario(e), erro: true);
    } finally {
      if (mounted) setState(() => gerandoArquivo = false);
    }
  }

  void mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? Colors.red : Colors.green,
      ),
    );
  }

  BoxDecoration caixaBranca() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  Widget topo() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: corPrimaria.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: corPrimaria.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: corPrimaria.withValues(alpha: 0.13),
            child: Icon(Icons.newspaper, color: corPrimaria, size: 30),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Jornal de promocoes',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1F2937),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Monte um encarte para imprimir ou publicar nas redes.',
                  style: TextStyle(color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget configuracaoJornal() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: caixaBranca(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dados do jornal',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: tituloController,
            onChanged: (_) => salvarRascunho(),
            decoration: InputDecoration(
              labelText: 'Titulo',
              prefixIcon: const Icon(Icons.title),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: validadeController,
            onChanged: (_) => salvarRascunho(),
            decoration: InputDecoration(
              labelText: 'Periodo de validade',
              hintText: 'Ex: 11/08 a 17/08',
              prefixIcon: const Icon(Icons.calendar_month),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: observacaoController,
            onChanged: (_) => salvarRascunho(),
            minLines: 2,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Observacao de rodape',
              prefixIcon: const Icon(Icons.notes),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
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
            'Adicionar produto',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: buscaController,
            onChanged: agendarBusca,
            onSubmitted: (valor) => buscarProdutos(valor),
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
            Text(erro!, style: const TextStyle(color: Colors.red)),
          ],
          if (produtos.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 250),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: produtos.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final produto = produtos[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: corPrimaria.withValues(alpha: 0.12),
                      child: Icon(Icons.shopping_basket, color: corPrimaria),
                    ),
                    title: Text(
                      nomeProduto(produto),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      'EAN: ${texto(eanProduto(produto))} - ${moeda(precoProduto(produto))}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => selecionarProduto(produto),
                  );
                },
              ),
            ),
          ],
          if (produtoSelecionado != null) ...[
            const SizedBox(height: 14),
            produtoSelecionadoCard(),
          ],
        ],
      ),
    );
  }

  Widget produtoSelecionadoCard() {
    final produto = produtoSelecionado!;
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
          Text(
            nomeProduto(produto),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'EAN: ${texto(eanProduto(produto))}',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: precoController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
            ],
            decoration: InputDecoration(
              labelText: 'Preco promocional',
              prefixIcon: const Icon(Icons.attach_money),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      produtoSelecionado = null;
                      precoController.clear();
                    });
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: itensJornal.length >= quantidadeMaxima
                      ? null
                      : adicionarProduto,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: corPrimaria,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget listaProdutos() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: caixaBranca(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Produtos do jornal (${itensJornal.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Limpar jornal',
                onPressed: itensJornal.isEmpty ? null : limparJornal,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: quantidadeJornalValida
                  ? const Color(0xFFECFDF3)
                  : const Color(0xFFFFF8E1),
              border: Border.all(
                color: quantidadeJornalValida
                    ? const Color(0xFF86D5A6)
                    : const Color(0xFFF2C94C),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  quantidadeJornalValida
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  size: 19,
                  color: quantidadeJornalValida
                      ? const Color(0xFF157347)
                      : const Color(0xFF8A6100),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    orientacaoQuantidade,
                    style: TextStyle(
                      color: quantidadeJornalValida
                          ? const Color(0xFF135C3A)
                          : const Color(0xFF6D5000),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (itensJornal.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Nenhum produto adicionado ainda.',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: itensJornal.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final item = itensJornal[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: corPrimaria.withValues(alpha: 0.12),
                    child: Icon(Icons.local_offer, color: corPrimaria),
                  ),
                  title: Text(
                    texto(item['nome']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    '${texto(item['ean'])} - ${moeda(item['preco'])}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (acao) {
                      if (acao == 'remover') removerProduto(item);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'remover', child: Text('Remover')),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget imagemOferta(Map<String, dynamic> item, {double tamanho = 86}) {
    final url = item['imagem_url']?.toString().trim() ?? '';
    if (url.isEmpty) {
      return SizedBox(
        width: tamanho,
        height: tamanho,
        child: Icon(
          Icons.shopping_bag,
          color: corPrimaria,
          size: tamanho * .38,
        ),
      );
    }

    return SizedBox(
      width: tamanho,
      height: tamanho,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            Icon(Icons.shopping_bag, color: corPrimaria, size: tamanho * .38),
      ),
    );
  }

  Color corAcentoProduto(int index) {
    return [corPrimaria, const Color(0xFFF9C80E), corSecundaria][index % 3];
  }

  Widget produtoPreview(
    Map<String, dynamic> item,
    int index, {
    required bool unico,
  }) {
    return Container(
      padding: EdgeInsets.fromLTRB(unico ? 18 : 8, 10, unico ? 18 : 8, 12),
      decoration: BoxDecoration(
        border: Border(
          right: !unico && index % 3 != 2
              ? const BorderSide(color: Color(0xFFD7DCE2))
              : BorderSide.none,
          bottom: const BorderSide(color: Color(0xFFD7DCE2)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: unico ? 42 : 26,
            height: 4,
            color: corAcentoProduto(index),
          ),
          const SizedBox(height: 7),
          Expanded(
            child: Center(child: imagemOferta(item, tamanho: unico ? 190 : 74)),
          ),
          const SizedBox(height: 7),
          Text(
            texto(item['nome']).toUpperCase(),
            maxLines: unico ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFF0B1F3A),
              fontWeight: FontWeight.w900,
              fontSize: unico ? 20 : 11,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              precoJornal(item),
              maxLines: 1,
              style: TextStyle(
                color: const Color(0xFF0B1F3A),
                fontWeight: FontWeight.w900,
                fontSize: unico ? 40 : 22,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget previewJornal() {
    final unico = itensJornal.length == 1;

    return RepaintBoundary(
      key: previewKey,
      child: Container(
        color: const Color(0xFFFBFAF6),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD7DCE2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 17, 18, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.shopping_cart_outlined,
                        color: corPrimaria,
                        size: 25,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          (SessaoLoja.mercadoNome ?? 'Loja').toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF0B1F3A),
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(height: 2, color: corSecundaria),
                  const SizedBox(height: 17),
                  Text(
                    tituloController.text.trim().isEmpty
                        ? 'OFERTAS FRESCAS'
                        : tituloController.text.trim().toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF0B1F3A),
                      fontSize: 33,
                      height: .94,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        color: const Color(0xFFF9C80E),
                        child: Text(
                          validadeController.text.trim().isEmpty
                              ? 'OFERTAS'
                              : validadeController.text.trim().toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF0B1F3A),
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          'Selecao especial para sua feira',
                          maxLines: 2,
                          style: TextStyle(
                            color: corSecundaria,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (itensJornal.isEmpty)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(
                  child: Text(
                    'Adicione produtos para visualizar o jornal.',
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: itensJornal.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: unico ? 1 : 3,
                  childAspectRatio: unico ? 1.12 : .65,
                ),
                itemBuilder: (_, index) =>
                    produtoPreview(itensJornal[index], index, unico: unico),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              color: const Color(0xFF0B1F3A),
              child: Text(
                observacaoController.text.trim().isEmpty
                    ? 'Ofertas validas enquanto durarem os estoques.'
                    : observacaoController.text.trim(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget acoesGeracao() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: caixaBranca(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Gerar arquivo',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            quantidadeJornalValida
                ? 'Quantidade valida. O jornal esta pronto para ser gerado.'
                : 'A geracao sera liberada com 1, 3, 6, 9 ou 12 produtos.',
            style: TextStyle(
              color: quantidadeJornalValida
                  ? const Color(0xFF157347)
                  : const Color(0xFF8A6100),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: gerandoArquivo || !quantidadeJornalValida
                      ? null
                      : gerarImagem,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: corPrimaria,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: gerandoArquivo
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.image_outlined),
                  label: const Text('Gerar imagem'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: gerandoArquivo || !quantidadeJornalValida
                      ? null
                      : gerarHtmlImpressao,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Impressao'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: corFundo,
      appBar: AppBar(
        title: const Text('Jornal de promocoes'),
        backgroundColor: corPrimaria,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            topo(),
            const SizedBox(height: 16),
            configuracaoJornal(),
            const SizedBox(height: 16),
            campoBusca(),
            const SizedBox(height: 16),
            listaProdutos(),
            const SizedBox(height: 16),
            acoesGeracao(),
            const SizedBox(height: 16),
            const Text(
              'Previa',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            previewJornal(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

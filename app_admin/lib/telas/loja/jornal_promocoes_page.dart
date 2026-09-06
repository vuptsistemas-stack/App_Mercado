import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/central_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/sessao_loja.dart';

enum _ModeloJornal { encarte, impacto, classico, essencial }

extension _ModeloJornalInfo on _ModeloJornal {
  String get titulo => switch (this) {
    _ModeloJornal.encarte => 'Encarte',
    _ModeloJornal.impacto => 'Impacto',
    _ModeloJornal.classico => 'Classico',
    _ModeloJornal.essencial => 'Essencial',
  };

  String get descricao => switch (this) {
    _ModeloJornal.encarte =>
      'Arte pronta com ofertas aplicadas na area central.',
    _ModeloJornal.impacto => 'Um produto em destaque e ofertas em grade.',
    _ModeloJornal.classico => 'Grade equilibrada para varias ofertas.',
    _ModeloJornal.essencial => 'Visual limpo, direto e facil de ler.',
  };

  IconData get icone => switch (this) {
    _ModeloJornal.encarte => Icons.wallpaper_outlined,
    _ModeloJornal.impacto => Icons.campaign_outlined,
    _ModeloJornal.classico => Icons.grid_view_rounded,
    _ModeloJornal.essencial => Icons.view_agenda_outlined,
  };
}

enum _FormatoJornal { status, feed, a4 }

extension _FormatoJornalInfo on _FormatoJornal {
  String get titulo => switch (this) {
    _FormatoJornal.status => 'Status',
    _FormatoJornal.feed => 'Instagram',
    _FormatoJornal.a4 => 'A4',
  };

  String get descricao => switch (this) {
    _FormatoJornal.status => '1080 x 1920',
    _FormatoJornal.feed => '1080 x 1350',
    _FormatoJornal.a4 => '2480 x 3508',
  };

  String get sufixo => switch (this) {
    _FormatoJornal.status => 'status',
    _FormatoJornal.feed => 'instagram',
    _FormatoJornal.a4 => 'a4',
  };

  IconData get icone => switch (this) {
    _FormatoJornal.status => Icons.phone_android_outlined,
    _FormatoJornal.feed => Icons.crop_portrait_outlined,
    _FormatoJornal.a4 => Icons.description_outlined,
  };

  int get largura => switch (this) {
    _FormatoJornal.status => 1080,
    _FormatoJornal.feed => 1080,
    _FormatoJornal.a4 => 2480,
  };

  int get altura => switch (this) {
    _FormatoJornal.status => 1920,
    _FormatoJornal.feed => 1350,
    _FormatoJornal.a4 => 3508,
  };

  double get proporcao => largura / altura;
}

class JornalPromocoesPage extends StatefulWidget {
  const JornalPromocoesPage({super.key});

  @override
  State<JornalPromocoesPage> createState() => _JornalPromocoesPageState();
}

class _JornalPromocoesPageState extends State<JornalPromocoesPage> {
  static const int quantidadeMaxima = 12;
  static const int versaoPublicacao = 2;
  static const String assetEncartePadrao =
      'assets/images/jornal_super_ofertas.jpeg';

  CentralService? _centralService;
  CentralService get centralService => _centralService ??= CentralService();
  final tituloController = TextEditingController();
  final validadeController = TextEditingController();
  final observacaoController = TextEditingController();
  final chamadaController = TextEditingController();
  final buscaController = TextEditingController();
  final precoController = TextEditingController();
  final previewKey = GlobalKey();

  Timer? debounceBusca;

  bool buscandoProdutos = false;
  bool gerandoArquivo = false;
  bool publicandoJornal = false;
  int etapaAtual = 0;
  String? erro;
  String assinaturaJornalPublicada = '';

  _ModeloJornal modeloSelecionado = _ModeloJornal.encarte;
  _FormatoJornal formatoSelecionado = _FormatoJornal.feed;
  String? caminhoEncartePersonalizado;

  List<Map<String, dynamic>> produtos = [];
  List<Map<String, dynamic>> itensJornal = [];
  Map<String, dynamic>? produtoSelecionado;

  Color get corPrimaria => SessaoLoja.corPrimaria;
  Color get corSecundaria => SessaoLoja.corSecundaria;
  Color get corFundo => SessaoLoja.corFundo;
  bool get quantidadeJornalValida =>
      itensJornal.isNotEmpty && itensJornal.length <= quantidadeMaxima;
  bool get jornalAtualPublicado =>
      assinaturaJornalPublicada.isNotEmpty &&
      assinaturaJornalPublicada == assinaturaJornalAtual();

  String? get apiBaseUrl {
    final url = SessaoLoja.apiBaseUrl?.trim();
    if (url == null || url.isEmpty) return null;
    return url.replaceAll(RegExp(r'/+$'), '');
  }

  String get chaveRascunho {
    final mercado = SessaoLoja.mercadoId ?? SessaoLoja.mercadoCodigo ?? 'loja';
    return 'jornal_promocoes_rascunho_$mercado';
  }

  String versaoEncartePersonalizado() {
    final caminho = caminhoEncartePersonalizado?.trim() ?? '';
    if (caminho.isEmpty) return '';

    try {
      final arquivo = File(caminho);
      if (!arquivo.existsSync()) return caminho;
      final stat = arquivo.statSync();
      return '$caminho:${stat.size}:${stat.modified.microsecondsSinceEpoch}';
    } catch (_) {
      return caminho;
    }
  }

  String assinaturaJornalAtual() {
    final conteudo = jsonEncode({
      'titulo': tituloController.text.trim(),
      'validade': validadeController.text.trim(),
      'observacao': observacaoController.text.trim(),
      'chamada': chamadaController.text.trim(),
      'modelo': modeloSelecionado.name,
      'formato': formatoSelecionado.name,
      'encarte': versaoEncartePersonalizado(),
      'itens': itensJornal,
    });

    var hash = 0x811C9DC5;
    for (final byte in utf8.encode(conteudo)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  @override
  void initState() {
    super.initState();
    tituloController.text = 'Ofertas da semana';
    chamadaController.text = 'Economize sem abrir mao da qualidade';
    observacaoController.text = 'Ofertas validas enquanto durarem os estoques.';
    carregarRascunho();
  }

  @override
  void dispose() {
    debounceBusca?.cancel();
    tituloController.dispose();
    validadeController.dispose();
    observacaoController.dispose();
    chamadaController.dispose();
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
    return 'Selecione de 1 a $quantidadeMaxima produtos. Atual: '
        '${itensJornal.length}/$quantidadeMaxima.';
  }

  bool validarQuantidadeJornal(String acao) {
    if (quantidadeJornalValida) return true;
    mostrarMensagem(
      'Para $acao, selecione de 1 a $quantidadeMaxima produtos. '
      'Quantidade atual: ${itensJornal.length}.',
      erro: true,
    );
    return false;
  }

  _ModeloJornal modeloDoRascunho(dynamic valor) {
    final nome = valor?.toString();
    return _ModeloJornal.values.firstWhere(
      (modelo) => modelo.name == nome,
      orElse: () => _ModeloJornal.impacto,
    );
  }

  _FormatoJornal formatoDoRascunho(dynamic valor) {
    final nome = valor?.toString();
    return _FormatoJornal.values.firstWhere(
      (formato) => formato.name == nome,
      orElse: () => _FormatoJornal.status,
    );
  }

  bool get usandoEncarte => modeloSelecionado == _ModeloJornal.encarte;

  ImageProvider<Object> get imagemEncarte {
    final caminho = caminhoEncartePersonalizado?.trim() ?? '';
    if (caminho.isNotEmpty && File(caminho).existsSync()) {
      return FileImage(File(caminho));
    }
    return const AssetImage(assetEncartePadrao);
  }

  _FormatoJornal? formatoCompativelComImagem(int largura, int altura) {
    if (largura <= 0 || altura <= 0) return null;
    final proporcao = largura / altura;
    _FormatoJornal? melhor;
    var menorDiferenca = double.infinity;

    for (final formato in _FormatoJornal.values) {
      final diferenca = (formato.proporcao - proporcao).abs();
      if (diferenca < menorDiferenca) {
        menorDiferenca = diferenca;
        melhor = formato;
      }
    }

    return menorDiferenca <= 0.025 ? melhor : null;
  }

  Future<void> selecionarEncartePersonalizado() async {
    try {
      final selecionada = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (selecionada == null) return;

      final bytes = await selecionada.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final largura = frame.image.width;
      final altura = frame.image.height;
      frame.image.dispose();
      codec.dispose();

      final formato = formatoCompativelComImagem(largura, altura);
      if (formato == null) {
        mostrarMensagem(
          'Use uma imagem 1080 x 1920, 1080 x 1350 ou na proporcao A4.',
          erro: true,
        );
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final loja = (SessaoLoja.mercadoCodigo ?? 'loja')
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
          .toLowerCase();
      final arquivo = File(
        '${dir.path}${Platform.pathSeparator}jornal_modelo_$loja.jpg',
      );
      await arquivo.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      setState(() {
        caminhoEncartePersonalizado = arquivo.path;
        modeloSelecionado = _ModeloJornal.encarte;
        formatoSelecionado = formato;
      });
      await salvarRascunho();
      mostrarMensagem('Encarte personalizado aplicado.');
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(
        'Nao foi possivel carregar o encarte: '
        '${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    }
  }

  Future<void> usarEncartePadrao() async {
    setState(() {
      caminhoEncartePersonalizado = null;
      modeloSelecionado = _ModeloJornal.encarte;
      formatoSelecionado = _FormatoJornal.feed;
    });
    await salvarRascunho();
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

      final caminhoSalvo = data['caminho_encarte']?.toString().trim() ?? '';
      final caminhoValido =
          caminhoSalvo.isNotEmpty && File(caminhoSalvo).existsSync()
          ? caminhoSalvo
          : null;

      setState(() {
        tituloController.text =
            data['titulo']?.toString() ?? tituloController.text;
        validadeController.text = data['validade']?.toString() ?? '';
        observacaoController.text =
            data['observacao']?.toString() ?? observacaoController.text;
        chamadaController.text =
            data['chamada']?.toString() ?? chamadaController.text;
        modeloSelecionado = modeloDoRascunho(data['modelo']);
        formatoSelecionado = formatoDoRascunho(data['formato']);
        caminhoEncartePersonalizado = caminhoValido;
        if (modeloSelecionado == _ModeloJornal.encarte &&
            caminhoValido == null) {
          formatoSelecionado = _FormatoJornal.feed;
        }
        itensJornal = data['itens'] is List
            ? List<Map<String, dynamic>>.from(data['itens'])
            : [];
        final versaoSalva = int.tryParse('${data['versao_publicacao'] ?? 1}');
        assinaturaJornalPublicada = versaoSalva == versaoPublicacao
            ? data['assinatura_publicada']?.toString() ?? ''
            : '';
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
        'chamada': chamadaController.text,
        'modelo': modeloSelecionado.name,
        'formato': formatoSelecionado.name,
        'caminho_encarte': caminhoEncartePersonalizado,
        'itens': itensJornal,
        'versao_publicacao': versaoPublicacao,
        'assinatura_publicada': assinaturaJornalPublicada,
      }),
    );
  }

  Future<void> publicarJornal() async {
    if (!validarQuantidadeJornal('publicar o jornal')) return;
    if (jornalAtualPublicado || publicandoJornal) return;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Publicar jornal?'),
        content: const Text(
          'O jornal será salvo para os clientes consultarem no app. Depois disso, quem permitiu notificações receberá um aviso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.campaign_outlined),
            label: const Text('Publicar'),
            style: FilledButton.styleFrom(backgroundColor: corPrimaria),
          ),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    setState(() => publicandoJornal = true);
    try {
      final imagem = await renderizarJornal(larguraMaxima: 1440);
      final resultado = await PushNotificationService.instance.publicarJornal(
        titulo: tituloController.text.trim().isEmpty
            ? 'Ofertas da semana'
            : tituloController.text,
        validade: validadeController.text,
        formato: formatoSelecionado.name,
        largura: formatoSelecionado.largura > 1440
            ? 1440
            : formatoSelecionado.largura,
        altura: formatoSelecionado.largura > 1440
            ? (formatoSelecionado.altura * 1440 / formatoSelecionado.largura)
                  .round()
            : formatoSelecionado.altura,
        imagem: imagem,
      );
      if (!resultado.jornalSalvo) {
        throw Exception(
          'O servidor não confirmou o armazenamento do jornal. Tente novamente.',
        );
      }

      if (!mounted) return;
      setState(() {
        assinaturaJornalPublicada = assinaturaJornalAtual();
      });
      await salvarRascunho();

      if (resultado.dispositivos == 0) {
        mostrarMensagem(
          'Jornal publicado. Nenhum cliente habilitou notificações ainda.',
        );
      } else if (resultado.falhas > 0) {
        mostrarMensagem(
          'Jornal publicado: ${resultado.enviados} aviso(s) enviado(s) e ${resultado.falhas} falha(s).',
        );
      } else {
        mostrarMensagem(
          'Jornal publicado e ${resultado.enviados} cliente(s) avisado(s).',
        );
      }
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(CentralService.mensagemErroUsuario(e), erro: true);
    } finally {
      if (mounted) setState(() => publicandoJornal = false);
    }
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
      'destaque': itensJornal.isEmpty,
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
      final removendoDestaque = item['destaque'] == true;
      itensJornal.removeWhere((produto) => produto['id'] == item['id']);
      if (removendoDestaque && itensJornal.isNotEmpty) {
        itensJornal.first['destaque'] = true;
      }
    });
    await salvarRascunho();
  }

  Future<void> definirDestaque(Map<String, dynamic> item) async {
    setState(() {
      for (final produto in itensJornal) {
        produto['destaque'] = produto['id'] == item['id'];
      }
    });
    await salvarRascunho();
  }

  Future<void> moverProduto(int indice, int deslocamento) async {
    final destino = indice + deslocamento;
    if (destino < 0 || destino >= itensJornal.length) return;

    setState(() {
      final item = itensJornal.removeAt(indice);
      itensJornal.insert(destino, item);
    });
    await salvarRascunho();
  }

  Future<void> editarProduto(Map<String, dynamic> item) async {
    final promocionalController = TextEditingController(
      text:
          numero(item['preco'])?.toStringAsFixed(2).replaceAll('.', ',') ?? '',
    );
    final originalController = TextEditingController(
      text:
          numero(item['preco_original'])
              ?.toStringAsFixed(2)
              .replaceAll('.', ',') ??
          '',
    );

    final resultado = await showDialog<Map<String, double?>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar oferta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              texto(item['nome']),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: originalController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Preco anterior',
                prefixText: 'R\$ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: promocionalController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Preco promocional',
                prefixText: 'R\$ ',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final promocional = numero(promocionalController.text);
              final original = numero(originalController.text);
              if (promocional == null || promocional <= 0) {
                mostrarMensagem(
                  'Informe um preco promocional valido.',
                  erro: true,
                );
                return;
              }
              Navigator.pop(dialogContext, {
                'preco': promocional,
                'preco_original': original,
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: corPrimaria,
              foregroundColor: Colors.white,
            ),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    promocionalController.dispose();
    originalController.dispose();
    if (resultado == null) return;

    setState(() {
      item['preco'] = resultado['preco'];
      item['preco_original'] = resultado['preco_original'];
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
    return 'jornal_promocoes_${loja}_${formatoSelecionado.sufixo}_$data';
  }

  double? descontoProduto(Map<String, dynamic> item) {
    final original = numero(item['preco_original']);
    final promocional = numero(item['preco']);
    if (original == null || promocional == null || original <= promocional) {
      return null;
    }
    return ((original - promocional) / original) * 100;
  }

  Future<void> prepararImagensParaExportacao() async {
    final urls = <String>{
      ...itensJornal
          .map((item) => item['imagem_url']?.toString().trim() ?? '')
          .where((url) => url.isNotEmpty),
      if ((SessaoLoja.logoUrl?.trim() ?? '').isNotEmpty)
        SessaoLoja.logoUrl!.trim(),
    };

    for (final url in urls) {
      if (!mounted) return;
      try {
        await precacheImage(NetworkImage(url), context);
      } catch (_) {}
    }

    if (usandoEncarte) {
      if (!mounted) return;
      try {
        await precacheImage(imagemEncarte, context);
      } catch (_) {}
    }
  }

  Future<ui.Image> ajustarImagemExportada(
    ui.Image origem,
    int largura,
    int altura,
  ) async {
    if (origem.width == largura && origem.height == altura) return origem;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..filterQuality = FilterQuality.high;
    canvas.drawImageRect(
      origem,
      Rect.fromLTWH(0, 0, origem.width.toDouble(), origem.height.toDouble()),
      Rect.fromLTWH(0, 0, largura.toDouble(), altura.toDouble()),
      paint,
    );
    return recorder.endRecording().toImage(largura, altura);
  }

  Future<Uint8List> renderizarJornal({int? larguraMaxima}) async {
    await prepararImagensParaExportacao();
    await Future<void>.delayed(const Duration(milliseconds: 180));

    final boundary =
        previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw Exception('Prévia do jornal ainda não está pronta.');
    }

    final larguraDestino =
        larguraMaxima != null && formatoSelecionado.largura > larguraMaxima
        ? larguraMaxima
        : formatoSelecionado.largura;
    final alturaDestino =
        (formatoSelecionado.altura *
                larguraDestino /
                formatoSelecionado.largura)
            .round();
    final proporcaoPixel = larguraDestino / boundary.size.width;
    final capturada = await boundary.toImage(pixelRatio: proporcaoPixel);
    final imagem = await ajustarImagemExportada(
      capturada,
      larguraDestino,
      alturaDestino,
    );
    final byteData = await imagem.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData?.buffer.asUint8List();

    if (!identical(capturada, imagem)) capturada.dispose();
    imagem.dispose();

    if (bytes == null || bytes.isEmpty) {
      throw Exception('Não foi possível gerar a imagem do jornal.');
    }
    return bytes;
  }

  Future<void> gerarImagem() async {
    if (!validarQuantidadeJornal('gerar a imagem')) return;

    setState(() => gerandoArquivo = true);

    try {
      final bytes = await renderizarJornal();

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
    final itens = itensOrdenadosParaPreview();
    final usaDestaque =
        modeloSelecionado == _ModeloJornal.impacto && itens.length > 1;

    String cardProduto(Map<String, dynamic> item, int index) {
      final imagem = item['imagem_url']?.toString() ?? '';
      final imgHtml = imagem.trim().isEmpty
          ? '<div class="sem-imagem">PRODUTO</div>'
          : '<img src="${htmlEscape(imagem)}" alt="">';
      final desconto = descontoProduto(item);
      final precoOriginal = numero(item['preco_original']);
      final precoAnteriorHtml = desconto != null && precoOriginal != null
          ? '<div class="preco-anterior">De ${htmlEscape(moeda(precoOriginal))}</div>'
          : '';
      final descontoHtml = desconto == null
          ? ''
          : '<div class="desconto">-${desconto.round()}%</div>';
      final classeDestaque = usaDestaque && index == 0 ? ' destaque' : '';

      return '''
      <section class="produto$classeDestaque">
        <span class="acento"></span>
        <div class="imagem">$imgHtml$descontoHtml</div>
        <div class="nome">${htmlEscape(item['nome'])}</div>
        $precoAnteriorHtml
        <div class="preco">${htmlEscape(precoJornal(item))}</div>
      </section>
      ''';
    }

    final classeQuantidade = itens.length == 1 ? ' unico' : '';
    final logo = SessaoLoja.logoUrl?.trim() ?? '';
    final logoHtml = logo.isEmpty
        ? '<span class="nome-loja">${htmlEscape(SessaoLoja.mercadoNome ?? 'Loja')}</span>'
        : '<img class="logo" src="${htmlEscape(logo)}" alt="Logo da loja">';

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
    .jornal { max-width: 760px; margin: 0 auto; background: #f4f6f8; overflow: hidden; border: 1px solid #d7dce2; }
    .topo { padding: 24px 28px 20px; background: ${modeloSelecionado == _ModeloJornal.classico
        ? '#ffffff'
        : modeloSelecionado == _ModeloJornal.essencial
        ? '#0b1f3a'
        : hexCss(corPrimaria)}; color: ${modeloSelecionado == _ModeloJornal.classico ? '#0b1f3a' : '#ffffff'}; }
    .marca { display: flex; align-items: center; justify-content: space-between; gap: 18px; padding-bottom: 14px; border-bottom: 2px solid ${modeloSelecionado == _ModeloJornal.classico ? hexCss(corPrimaria) : 'rgba(255,255,255,.45)'}; font-size: 17px; font-weight: 900; text-transform: uppercase; }
    .logo { width: 170px; height: 72px; padding: 7px; object-fit: contain; background: #fff; border-radius: 8px; }
    h1 { margin: 21px 0 8px; color: inherit; font-size: 48px; line-height: .92; letter-spacing: 0; text-transform: uppercase; }
    .chamada { margin-bottom: 14px; font-size: 17px; font-weight: 700; opacity: .88; }
    .campanha { display: flex; align-items: center; gap: 16px; }
    .validade { display: inline-block; padding: 8px 14px; background: #f9c80e; color: #0b1f3a; font-size: 16px; font-weight: 900; text-transform: uppercase; }
    .subtitulo { color: inherit; font-size: 17px; font-weight: 700; opacity: .84; }
    .produtos { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; padding: 18px 22px; }
    .produtos.unico { grid-template-columns: minmax(0, 360px); justify-content: center; }
    .produto { position: relative; display: flex; min-width: 0; min-height: 172px; padding: 14px 12px 13px; flex-direction: column; background: #fff; border: 1px solid #e2e6ea; border-radius: 10px; }
    .produto.destaque { grid-column: span 2; grid-row: span 2; min-height: 354px; }
    .unico .produto { min-height: 520px; }
    .acento { width: 28px; height: 4px; margin-bottom: 7px; background: ${hexCss(corPrimaria)}; }
    .produto:nth-child(3n+2) .acento { background: #f9c80e; }
    .produto:nth-child(3n) .acento { background: ${hexCss(corSecundaria)}; }
    .imagem { position: relative; height: 88px; display: grid; place-items: center; }
    .destaque .imagem { height: 225px; }
    .unico .imagem { height: 350px; }
    img { max-width: 100%; max-height: 100%; object-fit: contain; }
    .desconto { position: absolute; top: 0; right: 0; padding: 5px 8px; border-radius: 5px; background: ${hexCss(corPrimaria)}; color: #fff; font-size: 13px; font-weight: 900; }
    .sem-imagem { color: #8a94a3; font-size: 12px; font-weight: 800; }
    .nome { margin-top: 7px; color: #0b1f3a; font-size: 14px; font-weight: 900; text-transform: uppercase; }
    .preco-anterior { margin-top: 7px; color: #7b8490; font-size: 12px; text-decoration: line-through; }
    .preco { margin-top: 3px; color: ${hexCss(corPrimaria)}; font-size: 28px; font-weight: 900; white-space: nowrap; }
    .destaque .nome { font-size: 22px; }
    .destaque .preco { font-size: 45px; }
    .unico .nome { font-size: 22px; }
    .unico .preco { font-size: 46px; }
    .rodape { padding: 15px 22px; background: #0b1f3a; color: #fff; text-align: center; font-size: 13px; font-weight: 700; }
    @media print { body { background: #fff; } .jornal { border: 0; } }
  </style>
</head>
<body>
  <main class="jornal">
    <header class="topo">
      <div class="marca">$logoHtml</div>
      <h1>${htmlEscape(tituloController.text)}</h1>
      <div class="chamada">${htmlEscape(chamadaController.text)}</div>
      <div class="campanha">
        <div class="validade">${htmlEscape(validadeController.text.isEmpty ? 'OFERTAS' : validadeController.text)}</div>
        <div class="subtitulo">Selecao especial para sua feira</div>
      </div>
    </header>
    <div class="produtos$classeQuantidade">
      ${itens.asMap().entries.map((entry) => cardProduto(entry.value, entry.key)).join()}
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
            'Dados da campanha',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: chamadaController,
            onChanged: (_) => salvarRascunho(),
            decoration: InputDecoration(
              labelText: 'Chamada principal',
              hintText: 'Ex: Economia de verdade esta aqui',
              prefixIcon: const Icon(Icons.campaign_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
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

  Widget seletorDesignJornal() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: caixaBranca(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Design e formato',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            'O layout e ajustado automaticamente aos produtos escolhidos.',
            style: TextStyle(color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 16),
          const Text('Modelo', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_ModeloJornal>(
              showSelectedIcon: false,
              segments: _ModeloJornal.values
                  .map(
                    (modelo) => ButtonSegment<_ModeloJornal>(
                      value: modelo,
                      icon: Icon(modelo.icone, size: 18),
                      label: Text(modelo.titulo),
                    ),
                  )
                  .toList(),
              selected: {modeloSelecionado},
              onSelectionChanged: (selecao) {
                setState(() {
                  modeloSelecionado = selecao.first;
                  if (modeloSelecionado == _ModeloJornal.encarte &&
                      caminhoEncartePersonalizado == null) {
                    formatoSelecionado = _FormatoJornal.feed;
                  }
                });
                salvarRascunho();
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            modeloSelecionado.descricao,
            style: const TextStyle(color: Color(0xFF6B7280)),
          ),
          if (usandoEncarte) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 82,
                    child: AspectRatio(
                      aspectRatio: formatoSelecionado.proporcao,
                      child: Image(image: imagemEncarte, fit: BoxFit.cover),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        caminhoEncartePersonalizado == null
                            ? 'Modelo Super Ofertas'
                            : 'Encarte personalizado',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${formatoSelecionado.titulo} - '
                        '${formatoSelecionado.descricao} px',
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: selecionarEncartePersonalizado,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Trocar imagem'),
                          ),
                          if (caminhoEncartePersonalizado != null)
                            IconButton.outlined(
                              onPressed: usarEncartePadrao,
                              tooltip: 'Usar modelo padrao',
                              icon: const Icon(Icons.restart_alt),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          const Text(
            'Formato de divulgacao',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_FormatoJornal>(
              showSelectedIcon: false,
              segments: _FormatoJornal.values
                  .map(
                    (formato) => ButtonSegment<_FormatoJornal>(
                      value: formato,
                      icon: Icon(formato.icone, size: 18),
                      label: Text(formato.titulo),
                    ),
                  )
                  .toList(),
              selected: {formatoSelecionado},
              onSelectionChanged: usandoEncarte
                  ? null
                  : (selecao) {
                      setState(() => formatoSelecionado = selecao.first);
                      salvarRascunho();
                    },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${formatoSelecionado.descricao} px',
            style: TextStyle(color: corPrimaria, fontWeight: FontWeight.w800),
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
                  leading: Container(
                    width: 58,
                    height: 58,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: imagemOferta(item, tamanho: 50),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          texto(item['nome']),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (item['destaque'] == true) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: corPrimaria.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Destaque',
                            style: TextStyle(
                              color: corPrimaria,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '${precoJornal(item)}  |  EAN ${texto(item['ean'])}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (acao) {
                      switch (acao) {
                        case 'editar':
                          editarProduto(item);
                          break;
                        case 'destaque':
                          definirDestaque(item);
                          break;
                        case 'subir':
                          moverProduto(index, -1);
                          break;
                        case 'descer':
                          moverProduto(index, 1);
                          break;
                        case 'remover':
                          removerProduto(item);
                          break;
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'editar',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Editar oferta'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      if (item['destaque'] != true)
                        const PopupMenuItem(
                          value: 'destaque',
                          child: ListTile(
                            leading: Icon(Icons.star_outline),
                            title: Text('Tornar destaque'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      if (index > 0)
                        const PopupMenuItem(
                          value: 'subir',
                          child: ListTile(
                            leading: Icon(Icons.arrow_upward),
                            title: Text('Mover para cima'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      if (index < itensJornal.length - 1)
                        const PopupMenuItem(
                          value: 'descer',
                          child: ListTile(
                            leading: Icon(Icons.arrow_downward),
                            title: Text('Mover para baixo'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'remover',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Remover'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
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
    final desconto = descontoProduto(item);
    final precoOriginal = numero(item['preco_original']);

    return Container(
      padding: EdgeInsets.all(unico ? 14 : 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          modeloSelecionado == _ModeloJornal.essencial ? 4 : 10,
        ),
        border: Border.all(
          color: corAcentoProduto(index).withValues(alpha: 0.34),
        ),
        boxShadow: modeloSelecionado == _ModeloJornal.impacto
            ? const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Center(
                    child: imagemOferta(item, tamanho: unico ? 190 : 88),
                  ),
                ),
                if (desconto != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: corPrimaria,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '-${desconto.round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            texto(item['nome']).toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFF0B1F3A),
              fontWeight: FontWeight.w900,
              fontSize: unico ? 19 : 10,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 4),
          if (precoOriginal != null && desconto != null)
            Text(
              'De ${moeda(precoOriginal)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.black45,
                fontSize: unico ? 12 : 8,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              precoJornal(item),
              maxLines: 1,
              style: TextStyle(
                color: corPrimaria,
                fontWeight: FontWeight.w900,
                fontSize: unico ? 38 : 21,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> itensOrdenadosParaPreview() {
    final itens = itensJornal.map(Map<String, dynamic>.from).toList();
    final indiceDestaque = itens.indexWhere((item) => item['destaque'] == true);
    if (indiceDestaque > 0) {
      final destaque = itens.removeAt(indiceDestaque);
      itens.insert(0, destaque);
    }
    return itens;
  }

  int colunasDaGrade(int quantidade) {
    if (quantidade <= 1) return 1;
    if (quantidade <= 4) return 2;
    if (formatoSelecionado == _FormatoJornal.feed && quantidade >= 7) {
      return 4;
    }
    if (quantidade >= 10 && modeloSelecionado != _ModeloJornal.impacto) {
      return 4;
    }
    return 3;
  }

  Widget logoJornalPreview(Color corTexto) {
    final logo = SessaoLoja.logoUrl?.trim() ?? '';
    if (logo.isNotEmpty) {
      return Container(
        width: 92,
        height: 42,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Image.network(
          logo,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Icon(Icons.storefront, color: corPrimaria),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.storefront, color: corTexto, size: 22),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            (SessaoLoja.mercadoNome ?? 'Loja').toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: corTexto,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget gradeProdutosPreview(List<Map<String, dynamic>> itens) {
    if (itens.isEmpty) return const SizedBox.shrink();
    final colunas = colunasDaGrade(itens.length);
    final linhas = (itens.length / colunas).ceil();

    return LayoutBuilder(
      builder: (_, constraints) {
        const espacamento = 6.0;
        final larguraCelula =
            (constraints.maxWidth - (colunas - 1) * espacamento) / colunas;
        final alturaCelula =
            (constraints.maxHeight - (linhas - 1) * espacamento) / linhas;

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: itens.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: colunas,
            crossAxisSpacing: espacamento,
            mainAxisSpacing: espacamento,
            childAspectRatio: larguraCelula / alturaCelula,
          ),
          itemBuilder: (_, index) =>
              produtoPreview(itens[index], index, unico: itens.length == 1),
        );
      },
    );
  }

  int colunasEncarte(int quantidade) {
    if (quantidade <= 1) return 1;
    if (quantidade <= 4) return 2;
    return 3;
  }

  Widget produtoEncartePreview(Map<String, dynamic> item, int quantidade) {
    final compacto = quantidade >= 10;
    final medio = quantidade >= 7;
    final precoOriginal = numero(item['preco_original']);
    final desconto = descontoProduto(item);

    return Container(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          corPrimaria.withValues(alpha: .12),
          Colors.white,
        ),
        border: Border.all(color: corPrimaria.withValues(alpha: .50)),
        borderRadius: BorderRadius.circular(5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            flex: compacto ? 46 : 48,
            child: Padding(
              padding: EdgeInsets.all(compacto ? 2 : 4),
              child: Center(
                child: imagemOferta(
                  item,
                  tamanho: compacto
                      ? 52
                      : medio
                      ? 72
                      : quantidade <= 2
                      ? 138
                      : 98,
                ),
              ),
            ),
          ),
          Expanded(
            flex: compacto ? 54 : 52,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compacto ? 1 : 3,
                compacto ? 3 : 6,
                compacto ? 3 : 6,
                compacto ? 3 : 6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        texto(item['nome']).toUpperCase(),
                        maxLines: compacto ? 3 : 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: corPrimaria,
                          fontSize: compacto
                              ? 6.5
                              : medio
                              ? 8.5
                              : quantidade <= 2
                              ? 14
                              : 10,
                          height: 1.02,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  if (precoOriginal != null && desconto != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        'DE ${moeda(precoOriginal)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFF6B7280),
                          fontSize: compacto ? 5.5 : 7,
                          decoration: TextDecoration.lineThrough,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  Container(
                    height: compacto
                        ? 21
                        : medio
                        ? 28
                        : quantidade <= 2
                        ? 46
                        : 35,
                    padding: EdgeInsets.symmetric(
                      horizontal: compacto ? 3 : 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE30613),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        precoJornal(item),
                        maxLines: 1,
                        style: const TextStyle(
                          color: Color(0xFFFFF200),
                          fontSize: 40,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget gradeEncartePreview(List<Map<String, dynamic>> itens) {
    if (itens.isEmpty) {
      return const Center(
        child: Text(
          'Adicione produtos para visualizar o encarte.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF6B7280)),
        ),
      );
    }

    final colunas = colunasEncarte(itens.length);
    final linhas = (itens.length / colunas).ceil();

    return LayoutBuilder(
      builder: (_, constraints) {
        final espacamento = itens.length >= 10 ? 4.0 : 7.0;

        if (itens.length == 1) {
          return Center(
            child: SizedBox(
              width: constraints.maxWidth * .55,
              child: produtoEncartePreview(itens.first, itens.length),
            ),
          );
        }

        final larguraCelula =
            (constraints.maxWidth - (colunas - 1) * espacamento) / colunas;
        final alturaCelula =
            (constraints.maxHeight - (linhas - 1) * espacamento) / linhas;

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: itens.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: colunas,
            crossAxisSpacing: espacamento,
            mainAxisSpacing: espacamento,
            childAspectRatio: larguraCelula / alturaCelula,
          ),
          itemBuilder: (_, index) =>
              produtoEncartePreview(itens[index], itens.length),
        );
      },
    );
  }

  Widget logoEncartePreview() {
    final logo = SessaoLoja.logoUrl?.trim() ?? '';
    if (logo.isEmpty) return const SizedBox.shrink();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(5),
      child: Image.network(
        logo,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }

  Widget previewEncarte(List<Map<String, dynamic>> itens) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final largura = constraints.maxWidth > 420
            ? 420.0
            : constraints.maxWidth;

        return Center(
          child: SizedBox(
            width: largura,
            child: AspectRatio(
              aspectRatio: formatoSelecionado.proporcao,
              child: RepaintBoundary(
                key: previewKey,
                child: LayoutBuilder(
                  builder: (_, area) {
                    final larguraArte = area.maxWidth;
                    final alturaArte = area.maxHeight;

                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Image(image: imagemEncarte, fit: BoxFit.fill),
                        ),
                        Positioned(
                          left: larguraArte * .032,
                          top: alturaArte * .016,
                          width: larguraArte * .225,
                          height: alturaArte * .125,
                          child: logoEncartePreview(),
                        ),
                        Positioned(
                          left: larguraArte * .022,
                          top: alturaArte * .282,
                          width: larguraArte * .956,
                          height: alturaArte * .512,
                          child: gradeEncartePreview(itens),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget produtoDestaquePreview(Map<String, dynamic> item) {
    final desconto = descontoProduto(item);
    final precoOriginal = numero(item['preco_original']);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: corPrimaria.withValues(alpha: 0.28)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 9,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(flex: 5, child: imagemOferta(item, tamanho: 150)),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9C80E),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    'OFERTA DESTAQUE',
                    style: TextStyle(
                      color: Color(0xFF0B1F3A),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  texto(item['nome']).toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0B1F3A),
                    fontSize: 15,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                if (precoOriginal != null && desconto != null)
                  Text(
                    'De ${moeda(precoOriginal)}',
                    style: const TextStyle(
                      color: Colors.black45,
                      fontSize: 10,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    precoJornal(item),
                    style: TextStyle(
                      color: corPrimaria,
                      fontSize: 32,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (desconto != null)
                  Text(
                    '${desconto.round()}% de economia',
                    style: TextStyle(
                      color: corSecundaria,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget previewJornal() {
    final itens = itensOrdenadosParaPreview();
    if (usandoEncarte) return previewEncarte(itens);

    final usaDestaque =
        modeloSelecionado == _ModeloJornal.impacto && itens.length > 1;
    final destaque = usaDestaque ? itens.first : null;
    final grade = usaDestaque ? itens.skip(1).toList() : itens;

    final corTopo = switch (modeloSelecionado) {
      _ModeloJornal.encarte => corPrimaria,
      _ModeloJornal.impacto => corPrimaria,
      _ModeloJornal.classico => Colors.white,
      _ModeloJornal.essencial => const Color(0xFF0B1F3A),
    };
    final corTextoTopo = modeloSelecionado == _ModeloJornal.classico
        ? const Color(0xFF0B1F3A)
        : Colors.white;
    final corCanvas = switch (modeloSelecionado) {
      _ModeloJornal.encarte => const Color(0xFFF3F4F6),
      _ModeloJornal.impacto => const Color(0xFFF3F4F6),
      _ModeloJornal.classico => const Color(0xFFFFFBF2),
      _ModeloJornal.essencial => const Color(0xFFF8FAFC),
    };

    return LayoutBuilder(
      builder: (_, constraints) {
        final largura = constraints.maxWidth > 420
            ? 420.0
            : constraints.maxWidth;

        return Center(
          child: SizedBox(
            width: largura,
            child: AspectRatio(
              aspectRatio: formatoSelecionado.proporcao,
              child: RepaintBoundary(
                key: previewKey,
                child: Container(
                  color: corCanvas,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        flex: formatoSelecionado == _FormatoJornal.feed
                            ? 28
                            : 22,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
                          decoration: BoxDecoration(
                            color: corTopo,
                            border: modeloSelecionado == _ModeloJornal.classico
                                ? Border(
                                    bottom: BorderSide(
                                      color: corPrimaria,
                                      width: 4,
                                    ),
                                  )
                                : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: logoJornalPreview(corTextoTopo),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF9C80E),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      validadeController.text.trim().isEmpty
                                          ? 'OFERTAS'
                                          : validadeController.text
                                                .trim()
                                                .toUpperCase(),
                                      style: const TextStyle(
                                        color: Color(0xFF0B1F3A),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                tituloController.text.trim().isEmpty
                                    ? 'OFERTAS DA SEMANA'
                                    : tituloController.text
                                          .trim()
                                          .toUpperCase(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: corTextoTopo,
                                  fontSize: 27,
                                  height: .95,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                chamadaController.text.trim().isEmpty
                                    ? 'Economia de verdade esta aqui'
                                    : chamadaController.text.trim(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: corTextoTopo.withValues(alpha: .86),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        flex: formatoSelecionado == _FormatoJornal.feed
                            ? 64
                            : 70,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: itens.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Adicione produtos para visualizar o jornal.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                )
                              : Column(
                                  children: [
                                    if (destaque != null) ...[
                                      Expanded(
                                        flex:
                                            formatoSelecionado ==
                                                _FormatoJornal.feed
                                            ? 5
                                            : 4,
                                        child: produtoDestaquePreview(destaque),
                                      ),
                                      const SizedBox(height: 7),
                                    ],
                                    if (grade.isNotEmpty)
                                      Expanded(
                                        flex: destaque == null ? 10 : 6,
                                        child: gradeProdutosPreview(grade),
                                      ),
                                  ],
                                ),
                        ),
                      ),
                      Flexible(
                        flex: 8,
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 7,
                          ),
                          color: const Color(0xFF0B1F3A),
                          child: Text(
                            observacaoController.text.trim().isEmpty
                                ? 'Ofertas validas enquanto durarem os estoques.'
                                : observacaoController.text.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
            'Exportar e compartilhar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            quantidadeJornalValida
                ? '${formatoSelecionado.titulo} em ${formatoSelecionado.descricao} px.'
                : 'Adicione pelo menos um produto para gerar o jornal.',
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
                  label: const Text('Compartilhar PNG'),
                ),
              ),
              if (!usandoEncarte) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: gerandoArquivo || !quantidadeJornalValida
                        ? null
                        : gerarHtmlImpressao,
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Imprimir A4'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  gerandoArquivo ||
                      publicandoJornal ||
                      !quantidadeJornalValida ||
                      jornalAtualPublicado
                  ? null
                  : publicarJornal,
              style: FilledButton.styleFrom(
                backgroundColor: corPrimaria,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              icon: publicandoJornal
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      jornalAtualPublicado
                          ? Icons.check_circle
                          : Icons.campaign_outlined,
                    ),
              label: Text(
                publicandoJornal
                    ? 'Publicando...'
                    : jornalAtualPublicado
                    ? 'Jornal publicado'
                    : 'Publicar jornal',
              ),
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'A notificação aos clientes só é enviada por este botão.',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void abrirEtapa(int etapa) {
    if (etapa > 0 && itensJornal.isEmpty) {
      mostrarMensagem(
        'Adicione pelo menos um produto para continuar.',
        erro: true,
      );
      return;
    }
    setState(() => etapaAtual = etapa.clamp(0, 2).toInt());
  }

  Widget indicadorEtapas() {
    const titulos = ['Produtos', 'Design', 'Revisar'];
    const icones = [
      Icons.shopping_basket_outlined,
      Icons.palette_outlined,
      Icons.check_circle_outline,
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      child: Row(
        children: List.generate(titulos.length, (index) {
          final ativo = index == etapaAtual;
          final concluido = index < etapaAtual;
          final habilitado = index == 0 || itensJornal.isNotEmpty;

          return Expanded(
            child: InkWell(
              onTap: habilitado ? () => abrirEtapa(index) : null,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      concluido ? Icons.check_circle : icones[index],
                      size: 22,
                      color: ativo || concluido
                          ? corPrimaria
                          : const Color(0xFF9CA3AF),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      titulos[index],
                      style: TextStyle(
                        color: ativo || concluido
                            ? const Color(0xFF111827)
                            : const Color(0xFF9CA3AF),
                        fontSize: 12,
                        fontWeight: ativo ? FontWeight.w900 : FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 3,
                      width: ativo ? 46 : 24,
                      color: ativo
                          ? corPrimaria
                          : concluido
                          ? corPrimaria.withValues(alpha: .35)
                          : Colors.transparent,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  List<Widget> conteudoEtapa() {
    switch (etapaAtual) {
      case 0:
        return [
          topo(),
          const SizedBox(height: 16),
          campoBusca(),
          const SizedBox(height: 16),
          listaProdutos(),
        ];
      case 1:
        return [
          seletorDesignJornal(),
          if (!usandoEncarte) ...[
            const SizedBox(height: 16),
            configuracaoJornal(),
          ],
        ];
      case 2:
        return [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Previa final',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                formatoSelecionado.descricao,
                style: TextStyle(
                  color: corPrimaria,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          previewJornal(),
          const SizedBox(height: 16),
          acoesGeracao(),
        ];
      default:
        return const [];
    }
  }

  Widget navegacaoEtapas() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: Row(
          children: [
            if (etapaAtual > 0)
              OutlinedButton.icon(
                onPressed: () => abrirEtapa(etapaAtual - 1),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Voltar'),
              ),
            const Spacer(),
            if (etapaAtual < 2)
              ElevatedButton.icon(
                onPressed: itensJornal.isEmpty
                    ? null
                    : () => abrirEtapa(etapaAtual + 1),
                style: ElevatedButton.styleFrom(
                  backgroundColor: corPrimaria,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 13,
                  ),
                ),
                icon: Icon(
                  etapaAtual == 0 ? Icons.palette_outlined : Icons.visibility,
                ),
                label: Text(etapaAtual == 0 ? 'Personalizar' : 'Ver previa'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: corFundo,
      appBar: AppBar(
        title: const Text('Estudio de encartes'),
        backgroundColor: corPrimaria,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            indicadorEtapas(),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [...conteudoEtapa(), const SizedBox(height: 20)],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: navegacaoEtapas(),
    );
  }
}

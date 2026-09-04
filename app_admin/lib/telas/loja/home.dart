import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/monitor_pedidos_service.dart';
import '../../services/sessao_loja.dart';
import 'produtos_inativos_page.dart';
import 'resultado.dart';
import 'scanner.dart';

class TelaHome extends StatefulWidget {
  const TelaHome({super.key});

  @override
  State<TelaHome> createState() => _TelaHomeState();
}

class _TelaHomeState extends State<TelaHome> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();

  OverlayEntry? _overlayEntry;
  Timer? _debounce;

  List<Map<String, dynamic>> historico = [];
  List<Map<String, dynamic>> sugestoes = [];

  bool carregandoSugestoes = false;

  @override
  void initState() {
    super.initState();

    iniciarMonitorPedidos();
    carregarHistorico();

    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _controller.text.trim().isEmpty) {
        mostrarOverlayHistorico();
      } else if (!_focusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 200), removerOverlay);
      }
    });
  }

  Future<void> iniciarMonitorPedidos() async {
    try {
      await MonitorPedidosService.instance.iniciar();
    } catch (_) {
      // Não trava a tela de consulta caso o monitor ainda não consiga iniciar.
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _overlayEntry?.remove();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  String? get apiBaseUrl {
    final url = SessaoLoja.apiBaseUrl?.trim();

    if (url == null || url.isEmpty) {
      return null;
    }

    if (url.endsWith('/')) {
      return url.substring(0, url.length - 1);
    }

    return url;
  }

  bool somenteNumeros(String texto) {
    return RegExp(r'^[0-9]+$').hasMatch(texto);
  }

  String texto(dynamic valor) {
    return valor?.toString().trim() ?? '';
  }

  String formatarEstoque(dynamic valor) {
    final bruto = texto(valor);

    if (bruto.isEmpty) {
      return '-';
    }

    final numero = double.tryParse(bruto.replaceAll(',', '.'));

    if (numero == null) {
      return bruto;
    }

    if (numero == numero.roundToDouble()) {
      return numero.toInt().toString();
    }

    return numero
        .toStringAsFixed(3)
        .replaceAll('.', ',')
        .replaceFirst(RegExp(r',?0+$'), '');
  }

  String estoqueProduto(Map<String, dynamic> produto) {
    for (final campo in [
      'estoque_atual',
      'estoque',
      'quantidade',
      'saldo_estoque',
      'qtd_estoque',
      'saldo',
      'estoque_total_app',
    ]) {
      if (produto[campo] != null && texto(produto[campo]).isNotEmpty) {
        return formatarEstoque(produto[campo]);
      }
    }

    return '-';
  }

  void limpar() {
    _controller.clear();
    sugestoes.clear();
    removerOverlay();
    setState(() {});
  }

  Future<void> carregarHistorico() async {
    final prefs = await SharedPreferences.getInstance();
    final lista = prefs.getStringList('ultimas_pesquisas') ?? [];

    setState(() {
      historico = lista
          .map((item) => Map<String, dynamic>.from(jsonDecode(item)))
          .toList();
    });

    unawaited(completarHistoricoComDadosAtuais());
  }

  dynamic precoProduto(Map<String, dynamic> produto) {
    for (final campo in ['preco_venda', 'preco', 'valor', 'valor_venda']) {
      if (produto[campo] != null && texto(produto[campo]).isNotEmpty) {
        return produto[campo];
      }
    }

    return null;
  }

  Future<void> completarHistoricoComDadosAtuais() async {
    final baseUrl = apiBaseUrl;

    if (baseUrl == null || historico.isEmpty) {
      return;
    }

    var alterou = false;
    final atualizados = <Map<String, dynamic>>[];

    for (final item in historico) {
      final atual = Map<String, dynamic>.from(item);
      final ean = texto(atual['ean']);
      final temPreco = texto(atual['preco']).isNotEmpty;
      final temEstoque =
          texto(atual['estoque']).isNotEmpty && texto(atual['estoque']) != '-';

      if (ean.isEmpty || (temPreco && temEstoque)) {
        atualizados.add(atual);
        continue;
      }

      try {
        final codigo = ean.padLeft(14, '0');
        final url = Uri.parse('$baseUrl/produto/ean/$codigo');
        final response = await http
            .get(url)
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final lista = extrairLista(data);
          final produto = lista.isNotEmpty
              ? Map<String, dynamic>.from(lista.first)
              : data is Map
              ? Map<String, dynamic>.from(data)
              : null;

          if (produto != null) {
            atual['preco'] = precoProduto(produto);
            atual['estoque'] = estoqueProduto(produto);
            alterou = true;
          }
        }
      } catch (_) {
        // Historico continua aparecendo mesmo se a API nao responder.
      }

      atualizados.add(atual);
    }

    if (!alterou || !mounted) {
      return;
    }

    historico = atualizados;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'ultimas_pesquisas',
      historico.map((item) => jsonEncode(item)).toList(),
    );

    if (!mounted) {
      return;
    }

    setState(() {});

    if (_overlayEntry != null &&
        _focusNode.hasFocus &&
        _controller.text.trim().isEmpty) {
      removerOverlay();
      mostrarOverlayHistorico();
    }
  }

  Future<void> salvarHistorico(Map<String, dynamic> produto) async {
    final prefs = await SharedPreferences.getInstance();

    final nome = produto['nome_produto'] ?? 'Produto';
    final ean = produto['ean_principal'] ?? '';
    final preco = precoProduto(produto);
    final estoque = estoqueProduto(produto);

    if (ean.toString().isEmpty) return;

    historico.removeWhere((item) => item['ean'] == ean);

    historico.insert(0, {
      'nome': nome,
      'ean': ean,
      'preco': preco,
      'estoque': estoque,
    });

    if (historico.length > 10) {
      historico = historico.sublist(0, 10);
    }

    final lista = historico.map((item) => jsonEncode(item)).toList();

    await prefs.setStringList('ultimas_pesquisas', lista);

    setState(() {});
  }

  Future<void> limparHistorico() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ultimas_pesquisas');

    setState(() {
      historico.clear();
    });

    removerOverlay();
  }

  void removerOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void atualizarOverlay() {
    removerOverlay();
    mostrarOverlaySugestoes();
  }

  void mostrarOverlayHistorico() {
    if (historico.isEmpty) return;

    removerOverlay();

    _overlayEntry = criarOverlay(
      titulo: "Últimas Consultas",
      itens: historico,
      historico: true,
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void mostrarOverlaySugestoes() {
    if (sugestoes.isEmpty && !carregandoSugestoes) return;

    _overlayEntry = criarOverlay(
      titulo: "Resultados da busca",
      itens: sugestoes,
      historico: false,
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  OverlayEntry criarOverlay({
    required String titulo,
    required List<Map<String, dynamic>> itens,
    required bool historico,
  }) {
    return OverlayEntry(
      builder: (context) {
        return Positioned(
          width: MediaQuery.of(context).size.width - 40,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 62),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 300),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              titulo,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          if (historico)
                            InkWell(
                              onTap: limparHistorico,
                              child: const Text(
                                "Limpar",
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (carregandoSugestoes && !historico)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: itens.length,
                        itemBuilder: (context, index) {
                          final item = itens[index];

                          final nome = historico
                              ? item['nome']
                              : item['nome_produto'];

                          final ean = historico
                              ? texto(item['ean'])
                              : texto(item['ean_principal']);

                          final preco = historico
                              ? item['preco']
                              : precoProduto(Map<String, dynamic>.from(item));
                          final estoque = estoqueProduto(
                            Map<String, dynamic>.from(item),
                          );
                          final detalhes = [
                            "EAN: ${ean.isEmpty ? '-' : ean}",
                            "EST: $estoque",
                            "R\$ ${preco ?? 0}",
                          ].join(' | ');

                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                historico ? Icons.history : Icons.search,
                                color: Colors.blue,
                              ),
                              title: Text(
                                nome ?? 'Produto',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                detalhes,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                removerOverlay();
                                _focusNode.unfocus();

                                if (historico) {
                                  _controller.text = ean;
                                  buscar(ean);
                                } else {
                                  abrirResultado(
                                    Map<String, dynamic>.from(item),
                                  );
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void aoDigitar(String texto) {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
    }

    _debounce = Timer(const Duration(milliseconds: 500), () {
      final busca = texto.trim();

      if (busca.isEmpty) {
        sugestoes.clear();
        setState(() {});
        mostrarOverlayHistorico();
        return;
      }

      if (somenteNumeros(busca)) {
        sugestoes.clear();
        removerOverlay();
        setState(() {});
        return;
      }

      if (busca.length < 3) {
        sugestoes.clear();
        removerOverlay();
        setState(() {});
        return;
      }

      buscarSugestoes(busca);
    });
  }

  List extrairLista(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['produtos'] is List) return data['produtos'];
    if (data is Map && data['data'] is List) return data['data'];
    if (data is Map && data['resultado'] is List) return data['resultado'];
    if (data is Map && data['results'] is List) return data['results'];
    return [];
  }

  bool respostaProdutoUnicoValida(dynamic data) {
    if (data is! Map) {
      return false;
    }

    if (data['error'] != null || data['erro'] != null) {
      return false;
    }

    return texto(data['produto_id']).isNotEmpty ||
        texto(data['ean_principal']).isNotEmpty ||
        texto(data['nome_produto']).isNotEmpty;
  }

  Future<void> buscarSugestoes(String descricao) async {
    final baseUrl = apiBaseUrl;

    if (baseUrl == null) {
      setState(() {
        carregandoSugestoes = false;
        sugestoes.clear();
      });

      removerOverlay();
      return;
    }

    setState(() {
      carregandoSugestoes = true;
    });

    atualizarOverlay();

    try {
      final descricaoEncoded = Uri.encodeComponent(descricao);

      final url = Uri.parse("$baseUrl/produto/descricao/$descricaoEncoded");

      final response = await http.get(url);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final lista = extrairLista(data);

        setState(() {
          sugestoes = lista
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        });

        atualizarOverlay();
      } else {
        setState(() {
          sugestoes.clear();
        });
        removerOverlay();
      }
    } catch (e) {
      setState(() {
        sugestoes.clear();
      });
      removerOverlay();
    } finally {
      setState(() {
        carregandoSugestoes = false;
      });
      atualizarOverlay();
    }
  }

  Future<void> abrirResultado(Map<String, dynamic> produto) async {
    await salvarHistorico(produto);

    if (!mounted) return;

    setState(() {
      sugestoes.clear();
    });

    removerOverlay();

    final novoCodigo = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => TelaResultado(produto: produto)),
    );

    if (!mounted) return;

    if (novoCodigo != null && novoCodigo.isNotEmpty) {
      final codigo = novoCodigo.padLeft(14, '0');
      _controller.text = codigo;
      buscar(codigo);
    }
  }

  bool get consultaInativosLiberada {
    return SessaoLoja.temPermissao('produtos_inativos');
  }

  Uri montarUrlBuscaProduto(
    String baseUrl,
    String busca, {
    required bool inativos,
    int? pagina,
    int? limite,
  }) {
    final caminhoBase = inativos
        ? '$baseUrl/produto/inativos'
        : '$baseUrl/produto';

    if (somenteNumeros(busca)) {
      final codigo = busca.padLeft(14, '0');
      return Uri.parse('$caminhoBase/ean/$codigo');
    }

    final descricao = Uri.encodeComponent(busca);
    final uri = Uri.parse('$caminhoBase/descricao/$descricao');
    if (pagina == null || limite == null) {
      return uri;
    }

    return uri.replace(
      queryParameters: {
        'pagina': pagina.toString(),
        'limite': limite.toString(),
      },
    );
  }

  void mostrarProdutoNaoCadastrado({bool inativos = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.orange,
        content: Text(
          inativos
              ? 'Produto não encontrado nos inativos.'
              : 'Produto não cadastrado.',
        ),
      ),
    );
  }

  Future<void> tratarProdutoNaoEncontrado(String busca) async {
    if (!consultaInativosLiberada || !mounted) {
      mostrarProdutoNaoCadastrado();
      return;
    }

    final consultarInativos = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Produto não cadastrado'),
          content: const Text(
            'Deseja consultar este item nos produtos inativos?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Não'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: SessaoLoja.corPrimaria,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Buscar inativos'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (consultarInativos == true) {
      await buscarInativos(busca);
      return;
    }

    mostrarProdutoNaoCadastrado();
  }

  Future<void> buscarInativos(String textoBusca) async {
    final baseUrl = apiBaseUrl;
    final busca = textoBusca.trim();

    if (baseUrl == null || busca.isEmpty) {
      return;
    }

    try {
      final url = montarUrlBuscaProduto(baseUrl, busca, inativos: true);
      final response = await http.get(url);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final lista = extrairLista(data);

        if (lista.isNotEmpty) {
          await abrirProdutosInativos(
            lista.map((item) => Map<String, dynamic>.from(item)).toList(),
            busca,
          );
          return;
        }

        if (respostaProdutoUnicoValida(data)) {
          await abrirProdutosInativos([Map<String, dynamic>.from(data)], busca);
          return;
        }

        mostrarProdutoNaoCadastrado(inativos: true);
        return;
      }

      if (response.statusCode == 404) {
        mostrarProdutoNaoCadastrado(inativos: true);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Erro na API. Código HTTP: ${response.statusCode}'),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Erro de conexão. Verifique a API da loja.'),
        ),
      );
    }
  }

  Future<void> abrirProdutosInativos(
    List<Map<String, dynamic>> produtos,
    String busca,
  ) async {
    final ativou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ProdutosInativosPage(busca: busca, produtos: produtos),
      ),
    );

    if (!mounted) return;

    if (ativou == true) {
      buscar(busca);
    }
  }

  Future<void> buscar(String textoBusca) async {
    if (textoBusca.trim().isEmpty) return;

    final baseUrl = apiBaseUrl;

    if (baseUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text("Nenhuma API configurada para esta loja."),
        ),
      );
      return;
    }

    final busca = textoBusca.trim();

    try {
      final url = montarUrlBuscaProduto(
        baseUrl,
        busca,
        inativos: false,
        pagina: 1,
        limite: TelaListaProdutos.limitePagina,
      );

      final response = await http.get(url);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final lista = extrairLista(data);

        if (lista.isNotEmpty) {
          if (lista.length == 1) {
            abrirResultado(Map<String, dynamic>.from(lista.first));
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TelaListaProdutos(
                  busca: busca,
                  baseUrl: baseUrl,
                  produtos: lista
                      .take(TelaListaProdutos.limitePagina)
                      .map((item) => Map<String, dynamic>.from(item))
                      .toList(),
                  produtosExtrasIniciais: lista
                      .skip(TelaListaProdutos.limitePagina)
                      .map((item) => Map<String, dynamic>.from(item))
                      .toList(),
                  temMaisInicial:
                      !somenteNumeros(busca) &&
                      lista.length >= TelaListaProdutos.limitePagina,
                  onSelecionar: (produtoSelecionado) {
                    abrirResultado(produtoSelecionado);
                  },
                ),
              ),
            );
          }
          return;
        }

        if (data is Map && data["error"] != null) {
          await tratarProdutoNaoEncontrado(busca);
          return;
        }

        if (respostaProdutoUnicoValida(data)) {
          abrirResultado(Map<String, dynamic>.from(data));
          return;
        }

        await tratarProdutoNaoEncontrado(busca);
      } else {
        final produtoNaoCadastrado = response.statusCode == 404;

        if (produtoNaoCadastrado) {
          await tratarProdutoNaoEncontrado(busca);
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text("Erro na API. Código HTTP: ${response.statusCode}"),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            "Erro de conexão. Verifique internet, servidor ou IP da API.",
          ),
        ),
      );
    }
  }

  void abrirScanner() {
    removerOverlay();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScannerPage(
          onDetect: (codigo) {
            codigo = codigo.padLeft(14, '0');

            _controller.text = codigo;
            buscar(codigo);
          },
        ),
      ),
    );
  }

  Widget logoLoja() {
    final logoUrl = SessaoLoja.logoUrl?.trim() ?? '';

    Widget logoFallback() {
      return SizedBox(
        height: 120,
        child: Icon(
          Icons.storefront_rounded,
          size: 72,
          color: SessaoLoja.corPrimaria.withValues(alpha: 0.35),
        ),
      );
    }

    if (logoUrl.isEmpty) {
      return logoFallback();
    }

    return Image.network(
      logoUrl,
      height: 120,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) {
        return logoFallback();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final nomeLoja = SessaoLoja.mercadoNome ?? 'Loja';

    return Scaffold(
      appBar: AppBar(
        title: Text('Consulta - $nomeLoja'),
        backgroundColor: SessaoLoja.corPrimaria,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              logoLoja(),
              const SizedBox(height: 20),
              const Text(
                "Buscar Produto",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              CompositedTransformTarget(
                link: _layerLink,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.text,
                  onChanged: aoDigitar,
                  onTap: () {
                    if (_controller.text.trim().isEmpty) {
                      mostrarOverlayHistorico();
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: "Código ou descrição do produto",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => buscar(_controller.text),
                      child: const Text("Buscar"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: abrirScanner,
                      child: const Text("Scan"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: limpar,
                child: const Text("Limpar"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TelaListaProdutos extends StatefulWidget {
  static const int limitePagina = 30;

  final String busca;
  final String baseUrl;
  final List<Map<String, dynamic>> produtos;
  final List<Map<String, dynamic>> produtosExtrasIniciais;
  final bool temMaisInicial;
  final Function(Map<String, dynamic>) onSelecionar;

  const TelaListaProdutos({
    super.key,
    required this.busca,
    required this.baseUrl,
    required this.produtos,
    this.produtosExtrasIniciais = const [],
    required this.temMaisInicial,
    required this.onSelecionar,
  });

  @override
  State<TelaListaProdutos> createState() => _TelaListaProdutosState();
}

class _TelaListaProdutosState extends State<TelaListaProdutos> {
  final scrollController = ScrollController();

  late List<Map<String, dynamic>> produtos;
  late List<Map<String, dynamic>> pendentesLocais;
  late bool temMais;
  int paginaAtual = 1;
  bool carregandoMais = false;

  @override
  void initState() {
    super.initState();
    produtos = List<Map<String, dynamic>>.from(widget.produtos);
    pendentesLocais = List<Map<String, dynamic>>.from(
      widget.produtosExtrasIniciais,
    );
    temMais = widget.temMaisInicial;
    scrollController.addListener(verificarFimLista);
  }

  @override
  void dispose() {
    scrollController.removeListener(verificarFimLista);
    scrollController.dispose();
    super.dispose();
  }

  String texto(dynamic valor) {
    return valor?.toString().trim() ?? '';
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
    return texto(preco).isEmpty ? '0' : texto(preco);
  }

  String formatarEstoque(dynamic valor) {
    final bruto = texto(valor);
    if (bruto.isEmpty) return '-';

    final numero = double.tryParse(bruto.replaceAll(',', '.'));
    if (numero == null) return bruto;

    if (numero == numero.roundToDouble()) {
      return numero.toInt().toString();
    }

    return numero
        .toStringAsFixed(3)
        .replaceAll('.', ',')
        .replaceFirst(RegExp(r',?0+$'), '');
  }

  String estoqueProduto(Map<String, dynamic> produto) {
    for (final campo in [
      'estoque_atual',
      'estoque',
      'quantidade',
      'saldo_estoque',
      'qtd_estoque',
      'saldo',
      'estoque_total_app',
    ]) {
      if (produto[campo] != null && texto(produto[campo]).isNotEmpty) {
        return formatarEstoque(produto[campo]);
      }
    }

    return '-';
  }

  List<Map<String, dynamic>> extrairProdutos(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (data is Map) {
      for (final campo in ['produtos', 'data', 'resultado', 'results']) {
        if (data[campo] is List) {
          return List<Map<String, dynamic>>.from(data[campo]);
        }
      }
    }

    return [];
  }

  void verificarFimLista() {
    if (!scrollController.hasClients || carregandoMais || !temMais) return;

    final posicao = scrollController.position;
    if (posicao.pixels >= posicao.maxScrollExtent - 260) {
      carregarMais();
    }
  }

  Future<void> carregarMais() async {
    if (carregandoMais || !temMais) return;

    setState(() => carregandoMais = true);

    try {
      if (pendentesLocais.isNotEmpty) {
        final lote = pendentesLocais
            .take(TelaListaProdutos.limitePagina)
            .toList();
        pendentesLocais = pendentesLocais
            .skip(TelaListaProdutos.limitePagina)
            .toList();

        setState(() {
          produtos.addAll(lote);
          temMais = pendentesLocais.isNotEmpty || temMais;
          carregandoMais = false;
        });
        return;
      }

      final proximaPagina = paginaAtual + 1;
      final descricao = Uri.encodeComponent(widget.busca);
      final url = Uri.parse('${widget.baseUrl}/produto/descricao/$descricao')
          .replace(
            queryParameters: {
              'pagina': proximaPagina.toString(),
              'limite': TelaListaProdutos.limitePagina.toString(),
            },
          );

      final resposta = await http.get(url).timeout(const Duration(seconds: 20));
      if (!mounted) return;

      if (resposta.statusCode < 200 || resposta.statusCode >= 300) {
        setState(() {
          temMais = false;
          carregandoMais = false;
        });
        return;
      }

      final novos = extrairProdutos(jsonDecode(resposta.body));
      final eansAtuais = produtos.map(eanProduto).toSet();
      final novosSemDuplicar = novos.where((produto) {
        final ean = eanProduto(produto);
        return ean.isEmpty || !eansAtuais.contains(ean);
      }).toList();

      setState(() {
        paginaAtual = proximaPagina;
        produtos.addAll(novosSemDuplicar);
        temMais =
            novos.length >= TelaListaProdutos.limitePagina &&
            novosSemDuplicar.isNotEmpty;
        carregandoMais = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        temMais = false;
        carregandoMais = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Produtos encontrados"),
        centerTitle: true,
      ),
      body: ListView.builder(
        controller: scrollController,
        itemCount: produtos.length + (carregandoMais || temMais ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= produtos.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: carregandoMais
                    ? const CircularProgressIndicator()
                    : TextButton.icon(
                        onPressed: carregarMais,
                        icon: const Icon(Icons.expand_more),
                        label: const Text('Carregar mais 30'),
                      ),
              ),
            );
          }

          final produto = Map<String, dynamic>.from(produtos[index]);
          final ean = eanProduto(produto);
          final preco = precoProduto(produto);
          final estoque = estoqueProduto(produto);

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              title: Text(
                nomeProduto(produto),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                "EAN: ${ean.isEmpty ? '-' : ean}\n"
                "Estoque: $estoque | Preco: R\$ $preco",
              ),
              isThreeLine: true,
              onTap: () {
                widget.onSelecionar(produto);
              },
            ),
          );
        },
      ),
    );
  }
}

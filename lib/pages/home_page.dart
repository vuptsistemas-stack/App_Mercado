import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../controllers/carrinho_controller.dart';
import '../models/produto.dart';
import '../services/api_service.dart';
import '../services/imagem_service.dart';
import '../services/categoria_imagem_service.dart';
import '../services/loja_funcionamento_service.dart';
import '../services/ofertas_service.dart';
import '../services/sessao_mercado_cliente.dart' as sessao;
import 'carrinho_page.dart';
import 'categorias_page.dart';
import 'produtos_categoria_page.dart';
import '../services/app_tema_service.dart';

class HomePage extends StatefulWidget {
  final VoidCallback? abrirCategorias;
  final void Function(String categoria)? abrirCategoria;
  final VoidCallback? abrirConta;

  const HomePage({
    super.key,
    this.abrirCategorias,
    this.abrirCategoria,
    this.abrirConta,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController buscaController = TextEditingController();
  final PageController bannerController = PageController();
  final ScrollController scrollController = ScrollController();

  List<Produto> produtos = [];
  List<OfertaProdutoHome> superOfertas = [];
  List<OfertaProdutoHome> ofertas = [];
  List<String> categorias = [];

  final Map<String, Future<String?>> _cacheImagemProduto = {};
  final Map<String, String?> _imagensCategorias = {};

  String? categoriaFiltroSelecionada;

  bool carregando = false;
  bool carregandoOfertas = false;
  bool carregandoMais = false;
  bool temMais = true;

  int paginaProdutos = 1;
  final int limiteProdutos = 30;

  String mensagem = 'Carregando produtos...';

  String enderecoEntrega = 'Carregando endereço...';

  bool exibirEstoque = true;
  bool bloquearVendaSemEstoque = true;

  int bannerAtual = 0;
  Timer? bannerTimer;

  static const Color vermelho = Color(0xFFE30613);
  static const Color fundo = Color(0xFFF5F5F5);

  @override
  void initState() {
    super.initState();
    carregarProdutosIniciais();
    carregarOfertas();
    carregarCategorias();
    carregarEnderecoCliente();
    carregarConfiguracoesLoja();
    iniciarBannerAutomatico();

    scrollController.addListener(() {
      if (scrollController.position.pixels >=
              scrollController.position.maxScrollExtent - 220 &&
          !carregando &&
          !carregandoMais &&
          temMais) {
        carregarMaisProdutos();
      }
    });
  }

  @override
  void dispose() {
    bannerTimer?.cancel();
    bannerController.dispose();
    scrollController.dispose();
    buscaController.dispose();
    _cacheImagemProduto.clear();
    _imagensCategorias.clear();
    super.dispose();
  }

  int get quantidadePaginasSuperOfertas {
    return superOfertas.length;
  }

  void iniciarBannerAutomatico() {
    bannerTimer?.cancel();

    final totalPaginas = quantidadePaginasSuperOfertas;

    if (totalPaginas <= 1) {
      return;
    }

    bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !bannerController.hasClients) return;

      final proximo = bannerAtual >= totalPaginas - 1 ? 0 : bannerAtual + 1;

      bannerController.animateToPage(
        proximo,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> carregarProdutosIniciais() async {
    setState(() {
      categoriaFiltroSelecionada = null;
      paginaProdutos = 1;
      temMais = true;
      carregando = true;
      mensagem = '';
      produtos = [];
    });

    try {
      final resultados = await Future.wait([
        ApiService.listarProdutosIniciais(
          pagina: paginaProdutos,
          limite: limiteProdutos,
        ),
        ApiService.listarProdutosMaisVendidosNoApp(limite: 50),
      ]);

      final produtosCatalogoRetorno = resultados[0];
      final produtosCatalogo = produtosCatalogoRetorno
          .take(limiteProdutos)
          .toList();
      final produtosMaisVendidos = resultados[1];
      final listaProdutos = ApiService.removerProdutosDuplicados(
        combinarProdutosSemDuplicar(produtosMaisVendidos, produtosCatalogo),
      );

      if (!mounted) return;

      setState(() {
        produtos = listaProdutos;
        temMais = produtosCatalogoRetorno.length > limiteProdutos;
        mensagem = listaProdutos.isEmpty ? 'Nenhum produto encontrado' : '';
      });

      debugPrint(
        'APP_MERCADO HOME: carregou ${listaProdutos.length} produto(s) '
        'com ${produtosMaisVendidos.length} mais vendido(s) no topo',
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        produtos = [];
        temMais = false;
        mensagem = 'Erro ao carregar produtos';
      });
    } finally {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });
    }
  }

  List<Produto> combinarProdutosSemDuplicar(
    List<Produto> produtosPrioritarios,
    List<Produto> produtosComplementares,
  ) {
    final resultado = <Produto>[];
    final chaves = <String>{};

    void adicionar(Produto produto) {
      final chave = chaveProdutoLista(produto);

      if (chave.isEmpty || chaves.contains(chave)) {
        return;
      }

      chaves.add(chave);
      resultado.add(produto);
    }

    for (final produto in produtosPrioritarios) {
      adicionar(produto);
    }

    for (final produto in produtosComplementares) {
      adicionar(produto);
    }

    return resultado;
  }

  List<Produto> produtosNovosSemDuplicar(
    List<Produto> produtosAtuais,
    List<Produto> produtosNovos,
  ) {
    final chavesAtuais = produtosAtuais
        .map(chaveProdutoLista)
        .where((chave) => chave.isNotEmpty)
        .toSet();

    final resultado = <Produto>[];

    for (final produto in produtosNovos) {
      final chave = chaveProdutoLista(produto);

      if (chave.isEmpty || chavesAtuais.contains(chave)) {
        continue;
      }

      chavesAtuais.add(chave);
      resultado.add(produto);
    }

    return resultado;
  }

  String chaveProdutoLista(Produto produto) {
    final ean = produto.ean
        .replaceAll(RegExp(r'[^0-9]'), '')
        .replaceFirst(RegExp(r'^0+'), '');

    if (ean.isNotEmpty) {
      return 'ean:$ean';
    }

    final nome = produto.nome
        .trim()
        .toUpperCase()
        .replaceAll('Á', 'A')
        .replaceAll('À', 'A')
        .replaceAll('Â', 'A')
        .replaceAll('Ã', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Ê', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ô', 'O')
        .replaceAll('Õ', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('Ç', 'C')
        .replaceAll(RegExp(r'\s+'), ' ');

    if (nome.isNotEmpty) {
      return 'nome:$nome';
    }

    if (produto.produtoId > 0) {
      return 'id:${produto.produtoId}';
    }

    return '';
  }

  Future<void> carregarOfertas() async {
    if (!mounted) {
      return;
    }

    if (sessao.SessaoMercadoCliente.fonteProdutos == 'BANCO_LOJA') {
      debugPrint(
        'APP_MERCADO HOME: ofertas desativadas no modo BANCO_LOJA para evitar produtos fora da produtos_app.',
      );
      setState(() {
        superOfertas = [];
        ofertas = [];
        carregandoOfertas = false;
      });
      return;
    }

    setState(() {
      carregandoOfertas = true;
    });

    try {
      final resultados = await Future.wait([
        OfertasService.listarOfertasAtivas(
          limite: 12,
          tipoOferta: 'SUPER_OFERTA',
        ),
        OfertasService.listarOfertasAtivas(limite: 12, tipoOferta: 'OFERTA'),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        superOfertas = resultados[0];
        ofertas = resultados[1];
        bannerAtual = 0;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        if (bannerController.hasClients) {
          bannerController.jumpToPage(0);
        }

        iniciarBannerAutomatico();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        superOfertas = [];
        ofertas = [];
        bannerAtual = 0;
      });

      bannerTimer?.cancel();
    } finally {
      if (!mounted) {
        return;
      }

      setState(() {
        carregandoOfertas = false;
      });
    }
  }

  Future<void> carregarMaisProdutos() async {
    if (carregando || carregandoMais || !temMais) {
      return;
    }

    setState(() {
      carregandoMais = true;
    });

    final proximaPagina = paginaProdutos + 1;

    try {
      final buscaAtual = buscaController.text.trim();

      final resultadoRetorno = categoriaFiltroSelecionada == null
          ? await ApiService.listarProdutosIniciais(
              pagina: proximaPagina,
              limite: limiteProdutos,
              busca: buscaAtual,
            )
          : await ApiService.listarProdutosPorCategoria(
              categoria: categoriaFiltroSelecionada!,
              pagina: proximaPagina,
              limite: limiteProdutos,
              busca: buscaAtual,
            );
      final resultado = resultadoRetorno.take(limiteProdutos).toList();

      if (!mounted) return;

      setState(() {
        paginaProdutos = proximaPagina;
        produtos.addAll(produtosNovosSemDuplicar(produtos, resultado));
        temMais = resultadoRetorno.length > limiteProdutos;
      });
    } catch (_) {
      if (!mounted) return;
      debugPrint('HOME ERRO AO CARREGAR MAIS PRODUTOS');
    } finally {
      if (!mounted) return;

      setState(() {
        carregandoMais = false;
      });
    }
  }

  Future<void> carregarCategorias() async {
    try {
      final resultado = await ApiService.listarCategorias();

      if (!mounted) return;

      final categoriasCarregadas = resultado;
      Map<String, String?> imagensCarregadas = {};

      try {
        imagensCarregadas =
            await CategoriaImagemService.buscarImagensCategorias(
              categoriasCarregadas,
            );
      } catch (_) {}

      if (!mounted) return;

      setState(() {
        categorias = categoriasCarregadas;
        _imagensCategorias
          ..clear()
          ..addAll(imagensCarregadas);
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        categorias = [];
        _imagensCategorias.clear();
      });
    }
  }

  String montarEnderecoCliente(Map<String, dynamic> cliente) {
    final endereco = cliente['endereco']?.toString().trim() ?? '';
    final numero = cliente['numero']?.toString().trim() ?? '';
    final bairro = cliente['bairro']?.toString().trim() ?? '';
    final cidade = cliente['cidade']?.toString().trim() ?? '';

    final partes = <String>[];

    if (endereco.isNotEmpty) {
      partes.add(numero.isEmpty ? endereco : '$endereco, $numero');
    }

    if (bairro.isNotEmpty) {
      partes.add(bairro);
    }

    if (cidade.isNotEmpty) {
      partes.add(cidade);
    }

    if (partes.isEmpty) {
      return 'Endereço não cadastrado';
    }

    return partes.join(' - ');
  }

  Future<void> carregarConfiguracoesLoja() async {
    try {
      final configuracoes = await LojaFuncionamentoService.buscarConfiguracoes(
        forcarAtualizacao: true,
      );

      if (!mounted) {
        return;
      }

      context.read<CarrinhoController>().atualizarBloqueioVendaSemEstoque(
        configuracoes.bloquearVendaSemEstoque,
      );

      setState(() {
        exibirEstoque = configuracoes.exibirEstoque;
        bloquearVendaSemEstoque = configuracoes.bloquearVendaSemEstoque;
      });
    } catch (_) {}
  }

  Future<void> carregarEnderecoCliente() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;

      if (user == null) {
        if (!mounted) return;

        setState(() {
          enderecoEntrega = 'Endereço não cadastrado';
        });

        return;
      }

      final resposta = await Supabase.instance.client
          .from('clientes')
          .select('endereco, numero, bairro, cidade, referencia')
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .eq('user_id', user.id)
          .maybeSingle();

      if (!mounted) return;

      if (resposta == null) {
        setState(() {
          enderecoEntrega = 'Endereço não cadastrado';
        });

        return;
      }

      final cliente = Map<String, dynamic>.from(resposta);

      setState(() {
        enderecoEntrega = montarEnderecoCliente(cliente);
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        enderecoEntrega = 'Endereço não cadastrado';
      });
    }
  }

  Future<void> buscarProdutos() async {
    final busca = buscaController.text.trim();

    setState(() {
      categoriaFiltroSelecionada = null;
      paginaProdutos = 1;
      temMais = true;
      carregando = true;
      mensagem = '';
      produtos = [];
    });

    try {
      final resultadoRetorno = await ApiService.listarProdutosIniciais(
        pagina: paginaProdutos,
        limite: limiteProdutos,
        busca: busca,
      );
      final resultado = resultadoRetorno.take(limiteProdutos).toList();

      if (!mounted) return;

      setState(() {
        final resultadoSemDuplicar = ApiService.removerProdutosDuplicados(
          resultado,
        );
        produtos = resultadoSemDuplicar;
        temMais = resultadoRetorno.length > limiteProdutos;
        mensagem = resultadoSemDuplicar.isEmpty
            ? 'Nenhum produto encontrado'
            : '';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        produtos = [];
        temMais = false;
        mensagem = 'Erro ao buscar produtos';
      });
    } finally {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });
    }
  }

  Future<void> abrirPaginaPesquisa() async {
    FocusScope.of(context).unfocus();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PesquisaProdutosPage(
          corPrimaria: corPrimariaAtual,
          corFundo: corFundoAtual,
          exibirEstoque: exibirEstoque,
          bloquearVendaSemEstoque: bloquearVendaSemEstoque,
          buscaInicial: buscaController.text.trim(),
        ),
      ),
    );

    buscaController.clear();
  }

  Color corHex(String valor, Color padrao) {
    var texto = valor.trim();

    if (texto.isEmpty) {
      return padrao;
    }

    if (texto.startsWith('#')) {
      texto = texto.substring(1);
    }

    if (texto.length == 6) {
      texto = 'FF$texto';
    }

    final numero = int.tryParse(texto, radix: 16);

    if (numero == null) {
      return padrao;
    }

    return Color(numero);
  }

  Color get corPrimariaAtual {
    return corHex(sessao.SessaoMercadoCliente.clienteCorPrimaria, vermelho);
  }

  Color get corSecundariaAtual {
    return corHex(
      sessao.SessaoMercadoCliente.clienteCorSecundaria,
      const Color(0xFFC90010),
    );
  }

  Color get corFundoAtual {
    return corHex(sessao.SessaoMercadoCliente.clienteCorFundo, fundo);
  }

  Color get corDestaqueBannerAtual {
    final hsl = HSLColor.fromColor(corPrimariaAtual);
    final saturacao = (hsl.saturation + 0.24).clamp(0.58, 0.98).toDouble();
    final luminosidade = corPrimariaAtual.computeLuminance() > 0.42
        ? 0.36
        : 0.58;

    return hsl
        .withHue((hsl.hue + 42) % 360)
        .withSaturation(saturacao)
        .withLightness(luminosidade)
        .toColor();
  }

  Future<String?> buscarImagemProdutoComCache(Produto produto) {
    final chave = produto.ean.trim().isNotEmpty
        ? produto.ean.trim()
        : produto.nome.trim().toUpperCase();

    return _cacheImagemProduto.putIfAbsent(
      chave,
      () => ImagemService.buscarImagemProduto(
        ean: produto.ean,
        nomeProduto: produto.nome,
      ),
    );
  }

  Widget carregandoImagemCategoria() {
    return Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: corPrimariaAtual,
        ),
      ),
    );
  }

  Widget iconeCategoriaFallback() {
    return Icon(Icons.category_rounded, color: corPrimariaAtual, size: 34);
  }

  Widget imagemCategoriaNetwork({required String imagemUrl}) {
    return CachedNetworkImage(
      imageUrl: imagemUrl,
      fit: BoxFit.contain,
      placeholder: (context, url) => carregandoImagemCategoria(),
      errorWidget: (context, url, error) => iconeCategoriaFallback(),
    );
  }

  Future<void> filtrarPorCategoria(String categoria) async {
    setState(() {
      categoriaFiltroSelecionada = categoria;
      buscaController.clear();
      paginaProdutos = 1;
      temMais = true;
      carregando = true;
      mensagem = '';
      produtos = [];
    });

    try {
      final resultadoRetorno = await ApiService.listarProdutosPorCategoria(
        categoria: categoria,
        pagina: paginaProdutos,
        limite: limiteProdutos,
        busca: '',
      );
      final resultado = resultadoRetorno.take(limiteProdutos).toList();

      if (!mounted) return;

      setState(() {
        final resultadoSemDuplicar = ApiService.removerProdutosDuplicados(
          resultado,
        );
        produtos = resultadoSemDuplicar;
        temMais = resultadoRetorno.length > limiteProdutos;
        mensagem = resultadoSemDuplicar.isEmpty
            ? 'Nenhum produto encontrado em $categoria'
            : '';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        produtos = [];
        temMais = false;
        mensagem = 'Erro ao carregar produtos de $categoria';
      });

      debugPrint('HOME ERRO AO FILTRAR CATEGORIA $categoria: $e');
    } finally {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });
    }
  }

  String formatarMoeda(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  Widget imagemProduto(Produto produto) {
    return FutureBuilder<String?>(
      future: buscarImagemProdutoComCache(produto),
      builder: (context, snapshot) {
        final imagemUrl = snapshot.data;

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        if (imagemUrl == null || imagemUrl.isEmpty) {
          return Icon(Icons.shopping_basket, size: 34, color: corPrimariaAtual);
        }

        return Padding(
          padding: const EdgeInsets.all(6),
          child: CachedNetworkImage(
            imageUrl: imagemUrl,
            fit: BoxFit.contain,
            placeholder: (context, url) => const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (context, url, error) =>
                Icon(Icons.shopping_basket, size: 34, color: corPrimariaAtual),
          ),
        );
      },
    );
  }

  Widget bannerPromocional({
    required String titulo,
    required String subtitulo,
    required String botao,
    required Widget imagem,
    bool mostrarPorcentagem = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Depois vamos abrir a tela de ofertas')),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: corPrimariaAtual.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: corPrimariaAtual.withValues(alpha: 0.24),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTemaService.primaria.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              flex: 9,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: corPrimariaAtual,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    subtitulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 11,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 11),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: corPrimariaAtual,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      botao,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 12,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: imagem,
                    ),
                  ),
                  if (mostrarPorcentagem)
                    Positioned(
                      right: -2,
                      top: 0,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: corPrimariaAtual,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '%',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 31,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget carrosselBanners() {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 2.35,
          child: PageView(
            controller: bannerController,
            onPageChanged: (index) {
              setState(() {
                bannerAtual = index;
              });
            },
            children: [
              bannerPromocional(
                titulo: 'Economize mais\nno seu supermercado!',
                subtitulo: 'Ofertas imperdíveis\npara encher seu carrinho.',
                botao: 'Ver ofertas',
                mostrarPorcentagem: true,
                imagem: Image.asset(
                  'assets/images/banner_ofertas.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.shopping_basket,
                      size: 64,
                      color: corPrimariaAtual,
                    );
                  },
                ),
              ),
              bannerPromocional(
                titulo: 'Compre pelo app\ncom praticidade!',
                subtitulo: 'Escolha seus produtos\ne monte seu carrinho.',
                botao: 'Começar',
                imagem: Icon(
                  Icons.phone_android,
                  size: 86,
                  color: corPrimariaAtual,
                ),
              ),
              bannerPromocional(
                titulo: 'Entrega facilitada\npara você!',
                subtitulo: 'Receba em casa\nou retire no mercado.',
                botao: 'Conferir',
                imagem: Icon(
                  Icons.local_shipping,
                  size: 92,
                  color: corPrimariaAtual,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: bannerAtual == index ? 10 : 7,
              height: bannerAtual == index ? 10 : 7,
              decoration: BoxDecoration(
                color: bannerAtual == index
                    ? corPrimariaAtual
                    : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget itemCategoria({
    required String categoria,
    required VoidCallback onTap,
  }) {
    final chave = CategoriaImagemService.normalizarCategoria(categoria);
    final imagemUrl = (_imagensCategorias[chave] ?? '').trim();

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 84,
        height: 84,
        padding: const EdgeInsets.fromLTRB(7, 7, 7, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: categoriaFiltroSelecionada == categoria
                ? corPrimariaAtual
                : AppTemaService.primaria.withValues(alpha: 0.16),
            width: categoriaFiltroSelecionada == categoria ? 1.8 : 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTemaService.primaria.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Expanded(
              child: imagemUrl.isEmpty
                  ? iconeCategoriaFallback()
                  : imagemCategoriaNetwork(imagemUrl: imagemUrl),
            ),
            const SizedBox(height: 5),
            Text(
              categoria.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: corPrimariaAtual,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget categoriasHorizontais() {
    if (categorias.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 94,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: categorias.length,
        itemBuilder: (context, index) {
          final categoria = categorias[index];

          return Padding(
            padding: const EdgeInsets.only(right: 9),
            child: itemCategoria(
              categoria: categoria,
              onTap: () {
                filtrarPorCategoria(categoria);
              },
            ),
          );
        },
      ),
    );
  }

  bool produtoSemEstoque(Produto produto) {
    return bloquearVendaSemEstoque && produto.estoque <= 0;
  }

  Widget avisoSemEstoque() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Sem estoque',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.black54,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Future<void> tentarAdicionarProduto(
    CarrinhoController carrinho,
    Produto produto,
  ) async {
    await LojaFuncionamentoService.aplicarConfiguracoesNoCarrinho(context);

    if (!mounted) {
      return;
    }

    if (carrinho.bloquearVendaSemEstoque &&
        !carrinho.podeAdicionarProduto(produto)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Produto sem estoque disponível'),
          backgroundColor: corPrimariaAtual,
        ),
      );
      return;
    }

    final podeAdicionar =
        await LojaFuncionamentoService.podeAdicionarAoCarrinho(context);

    if (!podeAdicionar || !mounted) {
      return;
    }

    carrinho.adicionarProduto(produto);
  }

  Widget botaoAcaoProduto({
    required IconData icon,
    required VoidCallback? onTap,
    Color? backgroundColor,
    Color iconColor = Colors.white,
    double size = 22,
    double iconSize = 16,
  }) {
    final desabilitado = onTap == null;
    final corFundoBotao = desabilitado
        ? Colors.grey.shade300
        : backgroundColor ?? corPrimariaAtual;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: corFundoBotao, shape: BoxShape.circle),
        child: Icon(
          icon,
          color: desabilitado ? Colors.white : iconColor,
          size: iconSize,
        ),
      ),
    );
  }

  Widget controlesProduto(Produto produto) {
    return Consumer<CarrinhoController>(
      builder: (context, carrinho, child) {
        final quantidade = carrinho.quantidadeProduto(produto);

        return SizedBox(
          height: 30,
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (quantidade > 0) ...[
                  botaoAcaoProduto(
                    icon: Icons.remove,
                    onTap: () {
                      carrinho.diminuirQuantidade(produto);
                    },
                    backgroundColor: corPrimariaAtual.withValues(alpha: 0.10),
                    iconColor: corPrimariaAtual,
                    size: 26,
                    iconSize: 18,
                  ),
                  const SizedBox(width: 2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 13),
                    child: Text(
                      carrinho.textoQuantidadeProduto(produto),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                ],
                if (produtoSemEstoque(produto))
                  avisoSemEstoque()
                else
                  botaoAcaoProduto(
                    icon: Icons.add,
                    onTap: () {
                      tentarAdicionarProduto(carrinho, produto);
                    },
                    size: 27,
                    iconSize: 20,
                  ),
                const SizedBox(width: 6),
                botaoAcaoProduto(
                  icon: Icons.shopping_cart,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CarrinhoPage()),
                    );
                  },
                  backgroundColor: Colors.white,
                  iconColor: corPrimariaAtual,
                  size: 27,
                  iconSize: 20,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void mostrarZoomProduto(Produto produto) {
    final carrinhoDialog = context.read<CarrinhoController>();

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateZoom) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 24,
              ),
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 330,
                  maxHeight: 390,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: AppTemaService.primaria.withValues(alpha: 0.16),
                    width: 1.6,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTemaService.primaria.withValues(alpha: 0.08),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 8, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              produto.nome,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF1F2937),
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                        child: FutureBuilder<String?>(
                          future: buscarImagemProdutoComCache(produto),
                          builder: (context, snapshot) {
                            final imagemUrl = snapshot.data;

                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const SizedBox(
                                height: 130,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }

                            if (imagemUrl == null || imagemUrl.isEmpty) {
                              return SizedBox(
                                height: 130,
                                child: Center(
                                  child: Icon(
                                    Icons.shopping_basket,
                                    size: 64,
                                    color: corPrimariaAtual,
                                  ),
                                ),
                              );
                            }

                            return InteractiveViewer(
                              minScale: 1,
                              maxScale: 2.5,
                              child: CachedNetworkImage(
                                imageUrl: imagemUrl,
                                fit: BoxFit.contain,
                                placeholder: (context, url) => const SizedBox(
                                  height: 130,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                                errorWidget: (context, url, error) => SizedBox(
                                  height: 130,
                                  child: Center(
                                    child: Icon(
                                      Icons.shopping_basket,
                                      size: 64,
                                      color: corPrimariaAtual,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  produto.precoRotulo,
                                  style: TextStyle(
                                    color: corPrimariaAtual,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const Text(
                                'Pinça para ampliar',
                                style: TextStyle(
                                  color: Colors.black45,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          if (produto.ean.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.06),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.qr_code_2_rounded,
                                    color: corPrimariaAtual,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 7),
                                  const Text(
                                    'EAN:',
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      produto.ean,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF1F2937),
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: corPrimariaAtual.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: corPrimariaAtual.withValues(alpha: 0.16),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    produtoSemEstoque(produto)
                                        ? 'Produto sem estoque'
                                        : 'Adicionar no carrinho',
                                    style: const TextStyle(
                                      color: Color(0xFF1F2937),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (carrinhoDialog.quantidadeProduto(
                                          produto,
                                        ) >
                                        0) ...[
                                      botaoAcaoProduto(
                                        icon: Icons.remove,
                                        onTap: () {
                                          carrinhoDialog.diminuirQuantidade(
                                            produto,
                                          );
                                          setStateZoom(() {});
                                        },
                                        backgroundColor: corPrimariaAtual
                                            .withValues(alpha: 0.10),
                                        iconColor: corPrimariaAtual,
                                        size: 30,
                                        iconSize: 19,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        carrinhoDialog.textoQuantidadeProduto(
                                          produto,
                                        ),
                                        style: const TextStyle(
                                          color: Color(0xFF1F2937),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    produtoSemEstoque(produto)
                                        ? avisoSemEstoque()
                                        : botaoAcaoProduto(
                                            icon: Icons.add,
                                            onTap: () async {
                                              await tentarAdicionarProduto(
                                                carrinhoDialog,
                                                produto,
                                              );
                                              if (mounted) {
                                                setStateZoom(() {});
                                              }
                                            },
                                            size: 32,
                                            iconSize: 22,
                                          ),
                                    const SizedBox(width: 8),
                                    botaoAcaoProduto(
                                      icon: Icons.shopping_cart,
                                      onTap: () {
                                        Navigator.pop(context);

                                        Navigator.push(
                                          this.context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const CarrinhoPage(),
                                          ),
                                        );
                                      },
                                      backgroundColor: Colors.white,
                                      iconColor: corPrimariaAtual,
                                      size: 32,
                                      iconSize: 21,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget produtoCard(Produto produto) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTemaService.primaria.withValues(alpha: 0.16),
          width: 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTemaService.primaria.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Color(0xFFF8F8F8),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                  ),
                  onTap: () => mostrarZoomProduto(produto),
                  child: imagemProduto(produto),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 8,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(5, 5, 5, 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    produto.nome,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 10.5,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (exibirEstoque) ...[
                    Text(
                      'Estoque: ${produto.estoque}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFF4B5563),
                        fontSize: 9.4,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ] else
                    const SizedBox(height: 4),
                  Text(
                    produto.precoRotulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: corPrimariaAtual,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  if (produto.ehKg) ...[
                    const SizedBox(height: 2),
                    Text(
                      produto.pesoVariavel ? 'Peso variável' : '100g em 100g',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 8.8,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  controlesProduto(produto),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget ofertaCard(OfertaProdutoHome oferta) {
    return SizedBox.expand(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: produtoCard(oferta.produto)),
          if (oferta.usaPrecoApp)
            Positioned(
              top: 7,
              left: 7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade700,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Text(
                  'PREÇO APP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8.8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget imagemProdutoSuperOferta(Produto produto) {
    return FutureBuilder<String?>(
      future: buscarImagemProdutoComCache(produto),
      builder: (context, snapshot) {
        final imagemUrl = snapshot.data;

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              color: corPrimariaAtual,
              strokeWidth: 2,
            ),
          );
        }

        if (imagemUrl == null || imagemUrl.isEmpty) {
          return Icon(Icons.shopping_basket, size: 76, color: corPrimariaAtual);
        }

        return CachedNetworkImage(
          imageUrl: imagemUrl,
          fit: BoxFit.contain,
          placeholder: (context, url) => Center(
            child: CircularProgressIndicator(
              color: corPrimariaAtual,
              strokeWidth: 2,
            ),
          ),
          errorWidget: (context, url, error) =>
              Icon(Icons.shopping_basket, size: 76, color: corPrimariaAtual),
        );
      },
    );
  }

  Widget botaoAproveitarSuperOferta(Produto produto) {
    return Consumer<CarrinhoController>(
      builder: (context, carrinho, child) {
        final quantidade = carrinho.quantidadeProduto(produto);

        return SizedBox(
          height: 30,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (quantidade > 0) ...[
                  botaoAcaoProduto(
                    icon: Icons.remove,
                    onTap: () {
                      carrinho.diminuirQuantidade(produto);
                    },
                    backgroundColor: Colors.white,
                    iconColor: corPrimariaAtual,
                    size: 24,
                    iconSize: 15,
                  ),
                  const SizedBox(width: 6),
                  Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      carrinho.textoQuantidadeProduto(produto),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (!produtoSemEstoque(produto))
                    botaoAcaoProduto(
                      icon: Icons.add,
                      onTap: () {
                        tentarAdicionarProduto(carrinho, produto);
                      },
                      backgroundColor: Colors.white,
                      iconColor: corPrimariaAtual,
                      size: 24,
                      iconSize: 15,
                    ),
                ] else if (produtoSemEstoque(produto))
                  Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Sem estoque',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10.8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                else
                  InkWell(
                    onTap: () {
                      tentarAdicionarProduto(carrinho, produto);
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.14),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shopping_cart,
                            color: corPrimariaAtual,
                            size: 15,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Aproveitar',
                            style: TextStyle(
                              color: corPrimariaAtual,
                              fontSize: 11.2,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget superOfertaBanner(OfertaProdutoHome oferta) {
    final produto = oferta.produto;
    final mostrarPrecoDe =
        oferta.usaPrecoApp &&
        oferta.precoApiReferencia != null &&
        oferta.precoApiReferencia! > 0;
    final precoDeTexto = mostrarPrecoDe
        ? formatarMoeda(oferta.precoApiReferencia!)
        : null;

    Widget tituloOfertaGrande({
      required String texto,
      required Color cor,
      required double tamanho,
    }) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          texto,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: cor,
            fontSize: tamanho,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w900,
            height: 0.94,
            letterSpacing: -0.9,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.34),
                offset: const Offset(0, 2),
                blurRadius: 5,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: corPrimariaAtual.withValues(alpha: 0.22),
          width: 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: corPrimariaAtual.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largura = constraints.maxWidth;
          final altura = (largura * 0.52).clamp(184.0, 198.0).toDouble();

          final tituloSuper = (largura * 0.052).clamp(17.0, 23.0).toDouble();
          final tituloOferta = (largura * 0.064).clamp(20.0, 28.0).toDouble();
          final descricaoSize = (largura * 0.024).clamp(8.2, 9.6).toDouble();
          final nomeSize = (largura * 0.036).clamp(11.8, 14.4).toDouble();
          final estoqueSize = (largura * 0.026).clamp(8.8, 10.4).toDouble();
          final precoSize = (largura * 0.096).clamp(32.0, 40.0).toDouble();
          final raioIcone = (largura * 0.145).clamp(48.0, 62.0).toDouble();
          final imagemLargura = (largura * 0.285).clamp(84.0, 110.0).toDouble();
          final tamanhoSeloTempo = (largura * 0.152)
              .clamp(50.0, 62.0)
              .toDouble();
          final leftWidth = largura * 0.56;

          return SizedBox(
            height: altura,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _SuperOfertaBannerPainter(
                        corPrimaria: corPrimariaAtual,
                        corSecundaria: corSecundariaAtual,
                        corDestaque: corDestaqueBannerAtual,
                      ),
                    ),
                  ),

                  Positioned(
                    left: -22,
                    top: -26,
                    child: Container(
                      width: largura * 0.54,
                      height: altura * 1.35,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                  ),

                  Positioned(
                    left: 10,
                    top: 12,
                    width: leftWidth,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Transform.rotate(
                              angle: -0.18,
                              child: Container(
                                width: raioIcone,
                                height: raioIcone,
                                decoration: BoxDecoration(
                                  color: corDestaqueBannerAtual,
                                  borderRadius: BorderRadius.circular(15),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.18,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.flash_on_rounded,
                                  color: corPrimariaAtual,
                                  size: raioIcone * 0.78,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    height: tituloSuper + 2,
                                    width: double.infinity,
                                    child: tituloOfertaGrande(
                                      texto: 'SUPER',
                                      cor: Colors.white,
                                      tamanho: tituloSuper,
                                    ),
                                  ),
                                  SizedBox(
                                    height: tituloOferta + 2,
                                    width: double.infinity,
                                    child: tituloOfertaGrande(
                                      texto: 'OFERTA',
                                      cor: corDestaqueBannerAtual,
                                      tamanho: tituloOferta,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.97),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 12,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Flexible(
                                  child: Text(
                                    produto.nome.toUpperCase(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: const Color(0xFF111827),
                                      fontSize: nomeSize,
                                      height: 1.02,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                if (exibirEstoque) ...[
                                  const SizedBox(height: 1),
                                  Text(
                                    'Estoque: ${produto.estoque}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: const Color(0xFF6B7280),
                                      fontSize: estoqueSize,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                    ),
                                  ),
                                ],
                                if (precoDeTexto != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'De $precoDeTexto',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: const Color(0xFF6B7280),
                                      fontSize: estoqueSize,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 1),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Por',
                                      style: TextStyle(
                                        color: corPrimariaAtual,
                                        fontSize: estoqueSize + 1.2,
                                        fontWeight: FontWeight.w900,
                                        height: 1,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          produto.precoRotulo,
                                          maxLines: 1,
                                          style: TextStyle(
                                            color: corPrimariaAtual,
                                            fontSize: precoSize,
                                            height: 0.94,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -0.8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: leftWidth - 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.44),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Produto em destaque com preço imperdível!',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  color: corDestaqueBannerAtual,
                                  fontSize: descricaoSize,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w900,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Positioned(
                    right: largura * 0.11,
                    top: 22,
                    width: imagemLargura,
                    height: altura * 0.68,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: imagemProdutoSuperOferta(produto),
                    ),
                  ),

                  Positioned(
                    right: 10,
                    top: 10,
                    child: Container(
                      width: tamanhoSeloTempo,
                      height: tamanhoSeloTempo,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            corSecundariaAtual.withValues(alpha: 0.95),
                            corPrimariaAtual.withValues(alpha: 0.95),
                          ],
                        ),
                        border: Border.all(
                          color: corDestaqueBannerAtual,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.timer_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'OFERTA\nPOR TEMPO\nLIMITADO!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9.2,
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w900,
                                height: 0.96,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    offset: const Offset(0, 1),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    right: 14,
                    bottom: 10,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: largura * 0.46),
                      child: botaoAproveitarSuperOferta(produto),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget carrosselSuperOfertasHome() {
    if (carregandoOfertas && superOfertas.isEmpty) {
      return Container(
        height: 198,
        margin: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: corPrimariaAtual.withValues(alpha: 0.10)),
        ),
        child: Center(
          child: CircularProgressIndicator(
            color: corPrimariaAtual,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    if (superOfertas.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 198,
          child: PageView.builder(
            controller: bannerController,
            itemCount: superOfertas.length,
            onPageChanged: (index) {
              setState(() {
                bannerAtual = index;
              });
            },
            itemBuilder: (context, index) {
              return superOfertaBanner(superOfertas[index]);
            },
          ),
        ),
        if (superOfertas.length > 1) ...[
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(superOfertas.length, (index) {
              final ativo = bannerAtual == index;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: ativo ? 8 : 6,
                height: ativo ? 8 : 6,
                decoration: BoxDecoration(
                  color: ativo ? corPrimariaAtual : Colors.grey.shade300,
                  shape: BoxShape.circle,
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  Widget secaoOfertasHome() {
    if (carregandoOfertas && ofertas.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          secaoTitulo('Ofertas da loja'),
          SizedBox(
            height: 56,
            child: Center(
              child: CircularProgressIndicator(
                color: corPrimariaAtual,
                strokeWidth: 2.5,
              ),
            ),
          ),
        ],
      );
    }

    if (ofertas.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        secaoTitulo(
          'Ofertas da loja',
          acao: carregandoOfertas ? null : 'Atualizar',
          onTapAcao: carregandoOfertas ? null : carregarOfertas,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: GridView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: ofertas.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 7,
              crossAxisSpacing: 10,
              childAspectRatio: 0.62,
            ),
            itemBuilder: (context, index) {
              return ofertaCard(ofertas[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget secaoTitulo(String titulo, {String? acao, VoidCallback? onTapAcao}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              titulo,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          if (acao != null)
            InkWell(
              onTap: onTapAcao,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    acao,
                    style: TextStyle(
                      color: corPrimariaAtual,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(Icons.chevron_right, color: corPrimariaAtual, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget enderecoTopo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_outlined, color: Colors.white, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Entregar em',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  enderecoEntrega,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final carrinho = context.watch<CarrinhoController>();

    return Scaffold(
      backgroundColor: corFundoAtual,
      body: Column(
        children: [
          HomeHeaderOpcao2(
            logoUrl: sessao.SessaoMercadoCliente.logoUrl,
            nomeMercado: sessao.SessaoMercadoCliente.mercadoNome,
            enderecoEntrega: enderecoEntrega,
            quantidadeCarrinho: carrinho.quantidadeTotal,
            corPrimaria: corPrimariaAtual,
            corSecundaria: corSecundariaAtual,
            corFundo: corFundoAtual,
            buscaController: buscaController,
            onBuscaSubmitted: abrirPaginaPesquisa,
            onBuscaChanged: (_) {},
            onBuscaTap: abrirPaginaPesquisa,
            onScannerTap: abrirPaginaPesquisa,
            onCarrinhoTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CarrinhoPage()),
              );
            },
            onContaTap: () {
              if (widget.abrirConta != null) {
                widget.abrirConta!();
                return;
              }

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Depois vamos ligar esse botão à tela de conta',
                  ),
                ),
              );
            },
            onEnderecoTap: carregarEnderecoCliente,
          ),
          Expanded(
            child: carregando
                ? const Center(child: CircularProgressIndicator())
                : CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          children: [
                            const SizedBox(height: 8),
                            carrosselSuperOfertasHome(),
                            const SizedBox(height: 4),
                            secaoOfertasHome(),
                            const SizedBox(height: 6),
                            secaoTitulo('Categorias'),
                            categoriasHorizontais(),
                            const SizedBox(height: 4),
                            secaoTitulo(
                              categoriaFiltroSelecionada == null
                                  ? 'Produtos para você'
                                  : 'Produtos de $categoriaFiltroSelecionada',
                              acao: categoriaFiltroSelecionada == null
                                  ? 'Ver todos'
                                  : 'Limpar filtro',
                              onTapAcao: carregarProdutosIniciais,
                            ),
                          ],
                        ),
                      ),
                      if (produtos.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 30,
                                vertical: 20,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.search_off_rounded,
                                    color: corPrimariaAtual.withValues(
                                      alpha: 0.45,
                                    ),
                                    size: 48,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    mensagem,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (categoriaFiltroSelecionada != null) ...[
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      height: 44,
                                      child: OutlinedButton.icon(
                                        onPressed: carregarProdutosIniciais,
                                        icon: Icon(
                                          Icons.close_rounded,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Limpar filtro',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: corPrimariaAtual,
                                          side: BorderSide(
                                            color: corPrimariaAtual,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                          sliver: SliverGrid(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final produto = produtos[index];
                              return produtoCard(produto);
                            }, childCount: produtos.length),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  mainAxisSpacing: 7,
                                  crossAxisSpacing: 10,
                                  childAspectRatio: 0.62,
                                ),
                          ),
                        ),

                      if (carregandoMais)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: corPrimariaAtual,
                                strokeWidth: 2.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class PesquisaProdutosPage extends StatefulWidget {
  final Color corPrimaria;
  final Color corFundo;
  final bool exibirEstoque;
  final bool bloquearVendaSemEstoque;
  final String buscaInicial;

  const PesquisaProdutosPage({
    super.key,
    required this.corPrimaria,
    required this.corFundo,
    required this.exibirEstoque,
    required this.bloquearVendaSemEstoque,
    this.buscaInicial = '',
  });

  @override
  State<PesquisaProdutosPage> createState() => _PesquisaProdutosPageState();
}

class _PesquisaProdutosPageState extends State<PesquisaProdutosPage> {
  final TextEditingController buscaController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final Map<String, Future<String?>> _cacheImagemProduto = {};

  List<Produto> produtos = [];
  bool carregando = false;
  bool carregandoMais = false;
  bool temMais = false;
  int pagina = 1;
  final int limite = 30;
  String mensagem = 'Digite para buscar produtos';

  @override
  void initState() {
    super.initState();

    buscaController.text = widget.buscaInicial;

    scrollController.addListener(() {
      if (scrollController.position.pixels >=
              scrollController.position.maxScrollExtent - 200 &&
          !carregando &&
          !carregandoMais &&
          temMais) {
        carregarMaisProdutos();
      }
    });

    if (widget.buscaInicial.trim().isNotEmpty) {
      buscarProdutos();
    }
  }

  @override
  void dispose() {
    scrollController.dispose();
    buscaController.dispose();
    _cacheImagemProduto.clear();
    super.dispose();
  }

  Future<String?> buscarImagemProdutoComCache(Produto produto) {
    final chave = produto.ean.trim().isNotEmpty
        ? produto.ean.trim()
        : produto.nome.trim().toUpperCase();

    return _cacheImagemProduto.putIfAbsent(
      chave,
      () => ImagemService.buscarImagemProduto(
        ean: produto.ean,
        nomeProduto: produto.nome,
      ),
    );
  }

  Future<void> buscarProdutos() async {
    final busca = buscaController.text.trim();

    if (busca.isEmpty) {
      setState(() {
        produtos = [];
        pagina = 1;
        temMais = false;
        mensagem = 'Digite para buscar produtos';
      });
      return;
    }

    setState(() {
      carregando = true;
      carregandoMais = false;
      pagina = 1;
      temMais = true;
      mensagem = '';
      produtos = [];
    });

    try {
      final resultadoRetorno = await ApiService.listarProdutosIniciais(
        pagina: pagina,
        limite: limite,
        busca: busca,
      );
      final resultado = resultadoRetorno.take(limite).toList();

      if (!mounted) return;

      setState(() {
        final resultadoSemDuplicar = ApiService.removerProdutosDuplicados(
          resultado,
        );
        produtos = resultadoSemDuplicar;
        temMais = resultadoRetorno.length > limite;
        mensagem = resultadoSemDuplicar.isEmpty
            ? 'Nenhum produto encontrado'
            : '';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        produtos = [];
        temMais = false;
        mensagem = 'Erro ao buscar produtos';
      });
    } finally {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });
    }
  }

  Future<void> carregarMaisProdutos() async {
    final busca = buscaController.text.trim();

    if (busca.isEmpty || carregando || carregandoMais || !temMais) {
      return;
    }

    setState(() {
      carregandoMais = true;
    });

    final proximaPagina = pagina + 1;

    try {
      final resultadoRetorno = await ApiService.listarProdutosIniciais(
        pagina: proximaPagina,
        limite: limite,
        busca: busca,
      );
      final resultado = resultadoRetorno.take(limite).toList();

      if (!mounted) return;

      setState(() {
        pagina = proximaPagina;
        produtos = ApiService.removerProdutosDuplicados([
          ...produtos,
          ...resultado,
        ]);
        temMais = resultadoRetorno.length > limite;
      });
    } catch (_) {
      if (!mounted) return;
    } finally {
      if (!mounted) return;

      setState(() {
        carregandoMais = false;
      });
    }
  }

  String formatarMoeda(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  bool produtoSemEstoque(Produto produto) {
    return widget.bloquearVendaSemEstoque && produto.estoque <= 0;
  }

  Future<void> tentarAdicionarProduto(
    CarrinhoController carrinho,
    Produto produto,
  ) async {
    await LojaFuncionamentoService.aplicarConfiguracoesNoCarrinho(context);

    if (!mounted) {
      return;
    }

    if (carrinho.bloquearVendaSemEstoque &&
        !carrinho.podeAdicionarProduto(produto)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Produto sem estoque disponível'),
          backgroundColor: widget.corPrimaria,
        ),
      );
      return;
    }

    final podeAdicionar =
        await LojaFuncionamentoService.podeAdicionarAoCarrinho(context);

    if (!podeAdicionar || !mounted) {
      return;
    }

    carrinho.adicionarProduto(produto);
  }

  Widget imagemProduto(Produto produto) {
    return FutureBuilder<String?>(
      future: buscarImagemProdutoComCache(produto),
      builder: (context, snapshot) {
        final imagemUrl = snapshot.data;

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        if (imagemUrl == null || imagemUrl.isEmpty) {
          return Icon(
            Icons.shopping_basket,
            size: 34,
            color: widget.corPrimaria,
          );
        }

        return Padding(
          padding: const EdgeInsets.all(6),
          child: CachedNetworkImage(
            imageUrl: imagemUrl,
            fit: BoxFit.contain,
            placeholder: (context, url) => const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (context, url, error) => Icon(
              Icons.shopping_basket,
              size: 34,
              color: widget.corPrimaria,
            ),
          ),
        );
      },
    );
  }

  Widget botaoCircular({
    required IconData icon,
    required VoidCallback? onTap,
    Color? backgroundColor,
    Color iconColor = Colors.white,
  }) {
    final desabilitado = onTap == null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: desabilitado
              ? Colors.grey.shade300
              : backgroundColor ?? widget.corPrimaria,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: desabilitado ? Colors.white : iconColor,
          size: 20,
        ),
      ),
    );
  }

  Widget controlesProduto(Produto produto) {
    return Consumer<CarrinhoController>(
      builder: (context, carrinho, child) {
        final quantidade = carrinho.quantidadeProduto(produto);
        final semEstoque = produtoSemEstoque(produto);

        return SizedBox(
          height: 30,
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (quantidade > 0) ...[
                  botaoCircular(
                    icon: Icons.remove,
                    backgroundColor: widget.corPrimaria.withValues(alpha: 0.10),
                    iconColor: widget.corPrimaria,
                    onTap: () {
                      carrinho.diminuirQuantidade(produto);
                    },
                  ),
                  const SizedBox(width: 2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 13),
                    child: Text(
                      carrinho.textoQuantidadeProduto(produto),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                ],
                if (semEstoque)
                  Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Sem estoque',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                else
                  botaoCircular(
                    icon: Icons.add,
                    onTap: () {
                      tentarAdicionarProduto(carrinho, produto);
                    },
                  ),
                const SizedBox(width: 6),
                botaoCircular(
                  icon: Icons.shopping_cart,
                  backgroundColor: Colors.white,
                  iconColor: widget.corPrimaria,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CarrinhoPage()),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void mostrarZoomProduto(Produto produto) {
    final carrinhoDialog = context.read<CarrinhoController>();

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateZoom) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 24,
              ),
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 330,
                  maxHeight: 390,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: AppTemaService.primaria.withValues(alpha: 0.16),
                    width: 1.6,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTemaService.primaria.withValues(alpha: 0.08),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 8, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              produto.nome,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF1F2937),
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                        child: FutureBuilder<String?>(
                          future: buscarImagemProdutoComCache(produto),
                          builder: (context, snapshot) {
                            final imagemUrl = snapshot.data;

                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const SizedBox(
                                height: 130,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }

                            if (imagemUrl == null || imagemUrl.isEmpty) {
                              return SizedBox(
                                height: 130,
                                child: Center(
                                  child: Icon(
                                    Icons.shopping_basket,
                                    size: 64,
                                    color: widget.corPrimaria,
                                  ),
                                ),
                              );
                            }

                            return InteractiveViewer(
                              minScale: 1,
                              maxScale: 2.5,
                              child: CachedNetworkImage(
                                imageUrl: imagemUrl,
                                fit: BoxFit.contain,
                                placeholder: (context, url) => const SizedBox(
                                  height: 130,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                                errorWidget: (context, url, error) => SizedBox(
                                  height: 130,
                                  child: Center(
                                    child: Icon(
                                      Icons.shopping_basket,
                                      size: 64,
                                      color: widget.corPrimaria,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  produto.precoRotulo,
                                  style: TextStyle(
                                    color: widget.corPrimaria,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const Text(
                                'Pinça para ampliar',
                                style: TextStyle(
                                  color: Colors.black45,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          if (produto.ean.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.06),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.qr_code_2_rounded,
                                    color: widget.corPrimaria,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 7),
                                  const Text(
                                    'EAN:',
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      produto.ean,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF1F2937),
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: widget.corPrimaria.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: widget.corPrimaria.withValues(
                                  alpha: 0.16,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    produtoSemEstoque(produto)
                                        ? 'Produto sem estoque'
                                        : 'Adicionar no carrinho',
                                    style: const TextStyle(
                                      color: Color(0xFF1F2937),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (carrinhoDialog.quantidadeProduto(
                                          produto,
                                        ) >
                                        0) ...[
                                      botaoCircular(
                                        icon: Icons.remove,
                                        onTap: () {
                                          carrinhoDialog.diminuirQuantidade(
                                            produto,
                                          );
                                          setStateZoom(() {});
                                        },
                                        backgroundColor: widget.corPrimaria
                                            .withValues(alpha: 0.10),
                                        iconColor: widget.corPrimaria,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        carrinhoDialog.textoQuantidadeProduto(
                                          produto,
                                        ),
                                        style: const TextStyle(
                                          color: Color(0xFF1F2937),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    produtoSemEstoque(produto)
                                        ? Container(
                                            height: 30,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade200,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: const Text(
                                              'Sem estoque',
                                              style: TextStyle(
                                                color: Colors.black54,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          )
                                        : botaoCircular(
                                            icon: Icons.add,
                                            onTap: () async {
                                              await tentarAdicionarProduto(
                                                carrinhoDialog,
                                                produto,
                                              );
                                              if (mounted) {
                                                setStateZoom(() {});
                                              }
                                            },
                                          ),
                                    const SizedBox(width: 8),
                                    botaoCircular(
                                      icon: Icons.shopping_cart,
                                      onTap: () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const CarrinhoPage(),
                                          ),
                                        );
                                      },
                                      backgroundColor: Colors.white,
                                      iconColor: widget.corPrimaria,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget produtoPesquisaCard(Produto produto) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTemaService.primaria.withValues(alpha: 0.16),
          width: 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTemaService.primaria.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFFF8F8F8),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                  ),
                  onTap: () => mostrarZoomProduto(produto),
                  child: imagemProduto(produto),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 8,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(5, 5, 5, 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    produto.nome,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 10.5,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (widget.exibirEstoque) ...[
                    Text(
                      'Estoque: ${produto.estoque}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF4B5563),
                        fontSize: 9.4,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ] else
                    const SizedBox(height: 4),
                  Text(
                    produto.precoRotulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.corPrimaria,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  if (produto.ehKg) ...[
                    const SizedBox(height: 2),
                    Text(
                      produto.pesoVariavel ? 'Peso variável' : '100g em 100g',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 8.8,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  controlesProduto(produto),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget barraPesquisa() {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTemaService.primaria.withValues(alpha: 0.16),
          width: 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTemaService.primaria.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: buscaController,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => buscarProdutos(),
        decoration: InputDecoration(
          hintText: 'Buscar produtos, marcas ou EAN...',
          prefixIcon: Icon(
            Icons.search_rounded,
            color: widget.corPrimaria,
            size: 28,
          ),
          suffixIcon: IconButton(
            onPressed: buscarProdutos,
            icon: Icon(Icons.arrow_forward_rounded, color: widget.corPrimaria),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.corFundo,
      appBar: AppBar(
        title: const Text('Buscar produtos'),
        backgroundColor: widget.corPrimaria,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: barraPesquisa(),
          ),
          Expanded(
            child: carregando
                ? Center(
                    child: CircularProgressIndicator(color: widget.corPrimaria),
                  )
                : produtos.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Text(
                        mensagem,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                : GridView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                    itemCount: produtos.length + (carregandoMais ? 1 : 0),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 7,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.62,
                        ),
                    itemBuilder: (context, index) {
                      if (index >= produtos.length) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      return produtoPesquisaCard(produtos[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SuperOfertaBannerPainter extends CustomPainter {
  final Color corPrimaria;
  final Color corSecundaria;
  final Color corDestaque;

  _SuperOfertaBannerPainter({
    required this.corPrimaria,
    required this.corSecundaria,
    required this.corDestaque,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fundo = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          corPrimaria.withValues(alpha: 0.98),
          corSecundaria.withValues(alpha: 0.96),
          corPrimaria.withValues(alpha: 0.88),
        ],
        stops: const [0.0, 0.56, 1.0],
      ).createShader(Offset.zero & size);

    canvas.drawRect(Offset.zero & size, fundo);

    final brilhoCentral = Paint()
      ..shader =
          RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.20),
              Colors.white.withValues(alpha: 0.00),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.52, size.height * 0.34),
              radius: size.width * 0.38,
            ),
          );

    canvas.drawCircle(
      Offset(size.width * 0.52, size.height * 0.34),
      size.width * 0.38,
      brilhoCentral,
    );

    final faixaEscura = Path()
      ..moveTo(0, size.height * 0.76)
      ..lineTo(size.width * 0.56, size.height * 0.53)
      ..lineTo(size.width, size.height * 0.64)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      faixaEscura,
      Paint()..color = Colors.black.withValues(alpha: 0.08),
    );

    final faixaClara = Path()
      ..moveTo(size.width * 0.18, 0)
      ..lineTo(size.width * 0.66, 0)
      ..lineTo(size.width * 0.42, size.height)
      ..lineTo(size.width * 0.02, size.height)
      ..close();

    canvas.drawPath(
      faixaClara,
      Paint()..color = Colors.white.withValues(alpha: 0.06),
    );

    final raio = Paint()
      ..color = corDestaque.withValues(alpha: 0.56)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 8; i++) {
      final y = size.height * (0.18 + (i * 0.075));
      final x1 = size.width * (0.08 + (i.isEven ? 0.02 : 0.0));
      final x2 = x1 + size.width * 0.08;
      canvas.drawLine(Offset(x1, y), Offset(x2, y - 4), raio);
    }

    final pontos = Paint()
      ..color = corDestaque.withValues(alpha: 0.42)
      ..style = PaintingStyle.fill;

    for (var linha = 0; linha < 3; linha++) {
      for (var coluna = 0; coluna < 3; coluna++) {
        canvas.drawCircle(
          Offset(
            size.width * 0.91 + coluna * 11,
            size.height * 0.18 + linha * 11,
          ),
          2.0,
          pontos,
        );
      }
    }

    canvas.drawCircle(
      Offset(size.width * 0.84, size.height * 0.50),
      size.height * 0.34,
      Paint()..color = Colors.white.withValues(alpha: 0.08),
    );

    canvas.drawCircle(
      Offset(size.width * 0.84, size.height * 0.50),
      size.height * 0.25,
      Paint()
        ..color = corDestaque.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final destaque = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.43,
          size.height * 0.10,
          size.width * 0.36,
          size.height * 0.62,
        ),
        const Radius.circular(18),
      ),
      destaque,
    );

    final linhasRapidas = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(size.width * 0.15, size.height * 0.12),
      Offset(size.width * 0.24, size.height * 0.08),
      linhasRapidas,
    );

    canvas.drawLine(
      Offset(size.width * 0.78, size.height * 0.82),
      Offset(size.width * 0.92, size.height * 0.78),
      linhasRapidas,
    );
  }

  @override
  bool shouldRepaint(covariant _SuperOfertaBannerPainter oldDelegate) {
    return oldDelegate.corPrimaria != corPrimaria ||
        oldDelegate.corSecundaria != corSecundaria ||
        oldDelegate.corDestaque != corDestaque;
  }
}

class HomeHeaderOpcao2 extends StatelessWidget {
  final String logoUrl;
  final String nomeMercado;
  final String enderecoEntrega;
  final int quantidadeCarrinho;

  final Color corPrimaria;
  final Color corSecundaria;
  final Color corFundo;

  final TextEditingController buscaController;
  final ValueChanged<String>? onBuscaChanged;
  final VoidCallback? onBuscaSubmitted;
  final VoidCallback? onBuscaTap;
  final VoidCallback? onScannerTap;
  final VoidCallback? onCarrinhoTap;
  final VoidCallback? onContaTap;
  final VoidCallback? onEnderecoTap;

  const HomeHeaderOpcao2({
    super.key,
    required this.logoUrl,
    required this.nomeMercado,
    required this.enderecoEntrega,
    required this.quantidadeCarrinho,
    required this.corPrimaria,
    required this.corSecundaria,
    required this.corFundo,
    required this.buscaController,
    this.onBuscaChanged,
    this.onBuscaSubmitted,
    this.onBuscaTap,
    this.onScannerTap,
    this.onCarrinhoTap,
    this.onContaTap,
    this.onEnderecoTap,
  });

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.of(context).size.width;
    final safeTop = MediaQuery.of(context).padding.top;

    // Topo azul começa no limite superior da tela.
    // O safeTop protege logo/botões da barra de status.
    // A altura menor sobe o campo de pesquisa e remove espaço vazio.
    final alturaTopo = safeTop + (largura < 370 ? 170.0 : 180.0);

    return Container(
      color: Colors.white,
      child: SizedBox(
        height: alturaTopo + 18,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: alturaTopo,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(34),
                  bottomRight: Radius.circular(34),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(34),
                  bottomRight: Radius.circular(34),
                ),
                child: CustomPaint(
                  painter: _HomeHeaderFundoPainter(
                    corPrimaria: corPrimaria,
                    corSecundaria: corSecundaria,
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, safeTop + 6, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _linhaLogoAcoes(),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(child: _textoBoasVindas()),
                            const SizedBox(width: 10),
                            Expanded(child: _cardEndereco()),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(left: 20, right: 20, bottom: 0, child: _barraPesquisa()),
          ],
        ),
      ),
    );
  }

  Widget _linhaLogoAcoes() {
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _LogoMercadoHeader(
              logoUrl: logoUrl,
              nomeMercado: nomeMercado,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _BotaoCircularHeader(
          icon: Icons.person_outline_rounded,
          quantidade: 0,
          corPrimaria: corPrimaria,
          onTap: onContaTap,
        ),
        const SizedBox(width: 8),
        _BotaoCircularHeader(
          icon: Icons.shopping_cart_outlined,
          quantidade: quantidadeCarrinho,
          corPrimaria: corPrimaria,
          onTap: onCarrinhoTap,
        ),
      ],
    );
  }

  Widget _textoBoasVindas() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'O que deseja comprar hoje?',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            height: 1.12,
          ),
        ),
      ],
    );
  }

  Widget _cardEndereco() {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onEnderecoTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
          ),
          child: Row(
            children: [
              Container(
                width: 31,
                height: 31,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  color: corPrimaria,
                  size: 19,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: enderecoEntrega.trim().isEmpty
                    ? const Text(
                        'Escolha o endereço',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFF1F2937),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Entrega em:',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            enderecoEntrega,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.2,
                              fontWeight: FontWeight.w800,
                              height: 1.08,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white,
                size: 23,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barraPesquisa() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppTemaService.primaria.withValues(alpha: 0.16),
          width: 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTemaService.primaria.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: buscaController,
        readOnly: true,
        onTap: onBuscaTap,
        onChanged: onBuscaChanged,
        onSubmitted: (_) => onBuscaSubmitted?.call(),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Buscar produtos, marcas ou EAN...',
          hintStyle: TextStyle(
            color: Color(0xFF8A8F98),
            fontSize: 14.2,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(Icons.search_rounded, color: corPrimaria, size: 27),
          suffixIcon: IconButton(
            onPressed: onScannerTap,
            icon: Icon(
              Icons.qr_code_scanner_rounded,
              color: corPrimaria,
              size: 24,
            ),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }
}

class _LogoMercadoHeader extends StatelessWidget {
  final String logoUrl;
  final String nomeMercado;

  const _LogoMercadoHeader({required this.logoUrl, required this.nomeMercado});

  @override
  Widget build(BuildContext context) {
    if (logoUrl.trim().isNotEmpty) {
      return Container(
        width: 138,
        height: 66,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTemaService.primaria.withValues(alpha: 0.16),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTemaService.primaria.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            logoUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _textoLogo(),
          ),
        ),
      );
    }

    return _textoLogo();
  }

  Widget _textoLogo() {
    return Text(
      nomeMercado.trim().isEmpty ? 'Mercado' : nomeMercado,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFF1F2937),
        fontSize: 22,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _BotaoCircularHeader extends StatelessWidget {
  final IconData icon;
  final int quantidade;
  final Color corPrimaria;
  final VoidCallback? onTap;

  const _BotaoCircularHeader({
    required this.icon,
    required this.quantidade,
    required this.corPrimaria,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final qtd = quantidade < 0 ? 0 : quantidade;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(23),
      child: SizedBox(
        width: 46,
        height: 46,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            if (qtd > 0)
              Positioned(
                top: -2,
                right: -1,
                child: Container(
                  height: 20,
                  constraints: const BoxConstraints(minWidth: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFC107),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      qtd > 99 ? '99+' : '$qtd',
                      style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HomeHeaderFundoPainter extends CustomPainter {
  final Color corPrimaria;
  final Color corSecundaria;

  _HomeHeaderFundoPainter({
    required this.corPrimaria,
    required this.corSecundaria,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Fundo chapado: usa apenas a cor principal configurada,
    // sem degradê, sem transparência e sem mistura com branco/cinza.
    canvas.drawRect(
      rect,
      Paint()
        ..color = corPrimaria
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _HomeHeaderFundoPainter oldDelegate) {
    return oldDelegate.corPrimaria != corPrimaria ||
        oldDelegate.corSecundaria != corSecundaria;
  }
}

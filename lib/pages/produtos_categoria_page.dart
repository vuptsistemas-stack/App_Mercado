import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/carrinho_controller.dart';
import '../models/produto.dart';
import '../services/api_service.dart';
import '../services/sessao_mercado_cliente.dart' as sessao;
import '../services/app_tema_service.dart';
import '../services/imagem_service.dart';
import '../services/loja_funcionamento_service.dart';
import 'carrinho_page.dart';

class ProdutosCategoriaPage extends StatefulWidget {
  final String categoria;
  final bool mostrarAppBar;
  final bool mostrarBusca;
  final String buscaProduto;
  final VoidCallback? onVoltar;

  const ProdutosCategoriaPage({
    super.key,
    required this.categoria,
    this.mostrarAppBar = true,
    this.mostrarBusca = true,
    this.buscaProduto = '',
    this.onVoltar,
  });

  @override
  State<ProdutosCategoriaPage> createState() => _ProdutosCategoriaPageState();
}

class _ProdutosCategoriaPageState extends State<ProdutosCategoriaPage> {
  static const Color vermelho = Color(0xFFE30613);
  static const Color fundo = Color(0xFFF5F5F5);

  Color get corPrimaria => AppTemaService.primaria;
  Color get corSecundaria => AppTemaService.secundaria;
  Color get corFundo => AppTemaService.fundo;

  final ScrollController scrollController = ScrollController();
  final TextEditingController buscaController = TextEditingController();

  Timer? debounceBusca;

  List<Produto> produtos = [];
  List<Produto> produtosFiltrados = [];
  List<String> subcategorias = [];

  final Map<String, Future<String?>> _cacheImagemProduto = {};

  String subcategoriaSelecionada = 'Todos';
  String buscaAtual = '';

  bool carregando = false;
  bool carregandoMais = false;
  bool temMais = true;

  bool exibirEstoque = true;
  bool bloquearVendaSemEstoque = true;

  int pagina = 1;
  final int limite = 30;

  @override
  void initState() {
    super.initState();

    buscaAtual = widget.buscaProduto.trim();
    if (buscaAtual.isNotEmpty) {
      buscaController.text = buscaAtual;
    }

    carregarSubcategorias();
    carregarProdutos();
    carregarConfiguracoesLoja();

    scrollController.addListener(() {
      if (scrollController.position.pixels >=
              scrollController.position.maxScrollExtent - 200 &&
          !carregandoMais &&
          !carregando &&
          temMais) {
        carregarMaisProdutos();
      }
    });
  }

  @override
  void didUpdateWidget(covariant ProdutosCategoriaPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final novaBusca = widget.buscaProduto.trim();

    if (novaBusca != buscaAtual) {
      buscaAtual = novaBusca;
      buscaController.text = novaBusca;
      carregarProdutos();
    }
  }

  @override
  void dispose() {
    debounceBusca?.cancel();
    scrollController.dispose();
    buscaController.dispose();
    _cacheImagemProduto.clear();
    super.dispose();
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

  Future<void> carregarSubcategorias() async {
    if (widget.categoria.toUpperCase() == 'TODOS') {
      setState(() {
        subcategorias = [];
      });
      return;
    }

    try {
      final resultado = await ApiService.listarSubcategoriasPorCategoria(
        widget.categoria,
      );

      if (!mounted) return;

      setState(() {
        subcategorias = resultado;
      });
    } catch (e) {
      debugPrint('Erro ao carregar subcategorias: $e');
    }
  }

  Future<void> carregarProdutos() async {
    setState(() {
      carregando = true;
      pagina = 1;
      temMais = true;
      produtos = [];
      produtosFiltrados = [];
    });

    try {
      final resultadoRetorno = widget.categoria.toUpperCase() == 'TODOS'
          ? await ApiService.listarProdutosIniciais(
              pagina: pagina,
              limite: limite,
              busca: buscaAtual,
            )
          : subcategoriaSelecionada == 'Todos'
          ? await ApiService.listarProdutosPorCategoria(
              categoria: widget.categoria,
              pagina: pagina,
              limite: limite,
              busca: buscaAtual,
            )
          : await ApiService.listarProdutosPorSubcategoria(
              subcategoria: subcategoriaSelecionada,
              pagina: pagina,
              limite: limite,
              busca: buscaAtual,
            );
      final resultado = resultadoRetorno.take(limite).toList();

      if (!mounted) return;

      setState(() {
        final resultadoSemDuplicar = ApiService.removerProdutosDuplicados(
          resultado,
        );
        produtos = resultadoSemDuplicar;
        produtosFiltrados = resultadoSemDuplicar;
        carregando = false;

        temMais = resultadoRetorno.length > limite;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar produtos: $e'),
          backgroundColor: corPrimaria,
        ),
      );
    }
  }

  Future<void> carregarMaisProdutos() async {
    if (carregandoMais || carregando || !temMais) {
      return;
    }

    setState(() {
      carregandoMais = true;
    });

    pagina++;

    try {
      final resultadoRetorno = widget.categoria.toUpperCase() == 'TODOS'
          ? await ApiService.listarProdutosIniciais(
              pagina: pagina,
              limite: limite,
              busca: buscaAtual,
            )
          : subcategoriaSelecionada == 'Todos'
          ? await ApiService.listarProdutosPorCategoria(
              categoria: widget.categoria,
              pagina: pagina,
              limite: limite,
              busca: buscaAtual,
            )
          : await ApiService.listarProdutosPorSubcategoria(
              subcategoria: subcategoriaSelecionada,
              pagina: pagina,
              limite: limite,
              busca: buscaAtual,
            );
      final resultado = resultadoRetorno.take(limite).toList();

      if (!mounted) return;

      setState(() {
        produtos = ApiService.removerProdutosDuplicados([
          ...produtos,
          ...resultado,
        ]);
        produtosFiltrados = produtos;
        carregandoMais = false;
        temMais = resultadoRetorno.length > limite;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        carregandoMais = false;
        pagina--;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar mais produtos: $e'),
          backgroundColor: corPrimaria,
        ),
      );
    }
  }

  void filtrarProdutos(String texto) {
    debounceBusca?.cancel();

    debounceBusca = Timer(const Duration(milliseconds: 500), () {
      buscaAtual = texto.trim();
      carregarProdutos();
    });

    setState(() {});
  }

  void limparBusca() {
    debounceBusca?.cancel();

    buscaController.clear();
    buscaAtual = '';
    carregarProdutos();
  }

  String formatarMoeda(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String normalizarTexto(String texto) {
    return texto
        .toUpperCase()
        .replaceAll('Á', 'A')
        .replaceAll('À', 'A')
        .replaceAll('Â', 'A')
        .replaceAll('Ã', 'A')
        .replaceAll('Ä', 'A')
        .replaceAll('É', 'E')
        .replaceAll('È', 'E')
        .replaceAll('Ê', 'E')
        .replaceAll('Ë', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ì', 'I')
        .replaceAll('Î', 'I')
        .replaceAll('Ï', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ò', 'O')
        .replaceAll('Ô', 'O')
        .replaceAll('Õ', 'O')
        .replaceAll('Ö', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('Ù', 'U')
        .replaceAll('Û', 'U')
        .replaceAll('Ü', 'U')
        .replaceAll('Ç', 'C');
  }

  IconData iconeSubcategoria(String nome) {
    final texto = normalizarTexto(nome);

    if (texto.contains('ACOUGUE') ||
        texto.contains('CARNE') ||
        texto.contains('FRANGO') ||
        texto.contains('PEIXE') ||
        texto.contains('LINGUICA')) {
      return Icons.set_meal;
    }

    if (texto.contains('BAZAR') ||
        texto.contains('UTILIDADE') ||
        texto.contains('DESCARTAVEL') ||
        texto.contains('PAPELARIA')) {
      return Icons.shopping_bag;
    }

    if (texto.contains('BEBIDA') ||
        texto.contains('REFRIGERANTE') ||
        texto.contains('SUCO') ||
        texto.contains('AGUA') ||
        texto.contains('CERVEJA')) {
      return Icons.local_drink;
    }

    if (texto.contains('BISCOITO') ||
        texto.contains('BOLACHA') ||
        texto.contains('SNACK') ||
        texto.contains('SALGADINHO')) {
      return Icons.cookie;
    }

    if (texto.contains('PADARIA') ||
        texto.contains('PAO') ||
        texto.contains('BOLO') ||
        texto.contains('TORRADA')) {
      return Icons.bakery_dining;
    }

    if (texto.contains('HORTI') ||
        texto.contains('FRUTA') ||
        texto.contains('VERDURA') ||
        texto.contains('LEGUME') ||
        texto.contains('SALADA')) {
      return Icons.eco;
    }

    if (texto.contains('LIMPEZA') ||
        texto.contains('DETERGENTE') ||
        texto.contains('SABAO') ||
        texto.contains('DESINFETANTE')) {
      return Icons.cleaning_services;
    }

    if (texto.contains('HIGIENE') ||
        texto.contains('PERFUMARIA') ||
        texto.contains('SABONETE') ||
        texto.contains('SHAMPOO') ||
        texto.contains('CREME')) {
      return Icons.soap;
    }

    if (texto.contains('PET') ||
        texto.contains('RACAO') ||
        texto.contains('CAO') ||
        texto.contains('GATO')) {
      return Icons.pets;
    }

    if (texto.contains('CONGELADO') ||
        texto.contains('SORVETE') ||
        texto.contains('GELO')) {
      return Icons.ac_unit;
    }

    if (texto.contains('LEITE') ||
        texto.contains('LATICINIO') ||
        texto.contains('QUEIJO') ||
        texto.contains('IOGURTE')) {
      return Icons.egg_alt;
    }

    if (texto.contains('DOCE') ||
        texto.contains('CHOCOLATE') ||
        texto.contains('BOMBOM') ||
        texto.contains('BALAS')) {
      return Icons.cake;
    }

    if (texto.contains('ARROZ') ||
        texto.contains('FEIJAO') ||
        texto.contains('CEREAL') ||
        texto.contains('GRAOS') ||
        texto.contains('FARINHA')) {
      return Icons.rice_bowl;
    }

    if (texto.contains('MASSA') ||
        texto.contains('MACARRAO') ||
        texto.contains('MOLHO')) {
      return Icons.dinner_dining;
    }

    if (texto.contains('OLEO') ||
        texto.contains('AZEITE') ||
        texto.contains('TEMPERO') ||
        texto.contains('CONDIMENTO')) {
      return Icons.spa;
    }

    if (texto.contains('ENLATADO') ||
        texto.contains('CONSERVA') ||
        texto.contains('MILHO') ||
        texto.contains('ERVILHA')) {
      return Icons.inventory_2;
    }

    return Icons.shopping_basket;
  }

  Color corSubcategoria(String nome) {
    final texto = normalizarTexto(nome);

    if (texto.contains('ACOUGUE') ||
        texto.contains('CARNE') ||
        texto.contains('FRANGO') ||
        texto.contains('PEIXE')) {
      return const Color(0xFFE53935);
    }

    if (texto.contains('BAZAR') ||
        texto.contains('UTILIDADE') ||
        texto.contains('DESCARTAVEL')) {
      return const Color(0xFF8E24AA);
    }

    if (texto.contains('BEBIDA') ||
        texto.contains('REFRIGERANTE') ||
        texto.contains('SUCO') ||
        texto.contains('AGUA')) {
      return const Color(0xFF1E88E5);
    }

    if (texto.contains('BISCOITO') ||
        texto.contains('BOLACHA') ||
        texto.contains('SNACK') ||
        texto.contains('SALGADINHO')) {
      return const Color(0xFFFF8F00);
    }

    if (texto.contains('PADARIA') ||
        texto.contains('PAO') ||
        texto.contains('BOLO')) {
      return const Color(0xFFD84315);
    }

    if (texto.contains('HORTI') ||
        texto.contains('FRUTA') ||
        texto.contains('VERDURA') ||
        texto.contains('LEGUME')) {
      return const Color(0xFF43A047);
    }

    if (texto.contains('LIMPEZA') ||
        texto.contains('DETERGENTE') ||
        texto.contains('DESINFETANTE')) {
      return const Color(0xFF00897B);
    }

    if (texto.contains('HIGIENE') ||
        texto.contains('PERFUMARIA') ||
        texto.contains('SABONETE')) {
      return const Color(0xFF5E35B1);
    }

    if (texto.contains('PET') ||
        texto.contains('RACAO') ||
        texto.contains('CAO') ||
        texto.contains('GATO')) {
      return const Color(0xFF6D4C41);
    }

    if (texto.contains('CONGELADO') ||
        texto.contains('SORVETE') ||
        texto.contains('GELO')) {
      return const Color(0xFF039BE5);
    }

    if (texto.contains('LEITE') ||
        texto.contains('LATICINIO') ||
        texto.contains('QUEIJO') ||
        texto.contains('IOGURTE')) {
      return const Color(0xFFF9A825);
    }

    if (texto.contains('DOCE') ||
        texto.contains('CHOCOLATE') ||
        texto.contains('BOMBOM') ||
        texto.contains('BALAS')) {
      return const Color(0xFFD81B60);
    }

    if (texto.contains('ARROZ') ||
        texto.contains('FEIJAO') ||
        texto.contains('CEREAL') ||
        texto.contains('GRAOS') ||
        texto.contains('FARINHA')) {
      return const Color(0xFF7CB342);
    }

    if (texto.contains('MASSA') ||
        texto.contains('MACARRAO') ||
        texto.contains('MOLHO')) {
      return const Color(0xFFFB8C00);
    }

    if (texto.contains('OLEO') ||
        texto.contains('AZEITE') ||
        texto.contains('TEMPERO') ||
        texto.contains('CONDIMENTO')) {
      return const Color(0xFF9E9D24);
    }

    if (texto.contains('ENLATADO') || texto.contains('CONSERVA')) {
      return const Color(0xFF546E7A);
    }

    return const Color(0xFFE30613);
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

  Widget imagemProduto(Produto produto) {
    return FutureBuilder<String?>(
      future: buscarImagemProdutoComCache(produto),
      builder: (context, snapshot) {
        final imagemUrl = snapshot.data;

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        if (imagemUrl == null || imagemUrl.isEmpty) {
          return Icon(Icons.shopping_basket, size: 58, color: corPrimaria);
        }

        return Padding(
          padding: const EdgeInsets.all(10),
          child: CachedNetworkImage(
            imageUrl: imagemUrl,
            fit: BoxFit.contain,
            placeholder: (context, url) => const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (context, url, error) =>
                Icon(Icons.shopping_basket, size: 58, color: corPrimaria),
          ),
        );
      },
    );
  }

  Widget campoBusca() {
    return Container(
      color: corPrimaria,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: Container(
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
        child: TextField(
          controller: buscaController,
          onChanged: filtrarProdutos,
          decoration: InputDecoration(
            hintText: widget.categoria.toUpperCase() == 'TODOS'
                ? 'Buscar produto'
                : 'Buscar produto em ${widget.categoria}',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: buscaController.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: limparBusca,
                  ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget listaSubcategorias() {
    if (subcategorias.isEmpty) {
      return const SizedBox.shrink();
    }

    final lista = ['Todos', ...subcategorias];

    return Container(
      height: 48,
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: lista.length,
        itemBuilder: (context, index) {
          final nome = lista[index];
          final selecionado = nome == subcategoriaSelecionada;

          return InkWell(
            onTap: () {
              setState(() {
                subcategoriaSelecionada = nome;

                if (widget.mostrarBusca) {
                  buscaController.clear();
                  buscaAtual = '';
                }
              });

              carregarProdutos();
            },
            child: Container(
              margin: const EdgeInsets.only(right: 18),
              padding: const EdgeInsets.only(top: 9),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    nome,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selecionado ? Colors.black : Colors.black54,
                      fontSize: 15,
                      fontWeight: selecionado
                          ? FontWeight.w900
                          : FontWeight.w500,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 7),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: selecionado ? 42 : 0,
                    height: 3,
                    decoration: BoxDecoration(
                      color: selecionado ? corPrimaria : Colors.transparent,
                      borderRadius: BorderRadius.circular(99),
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
          backgroundColor: corPrimaria,
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
    double size = 27,
    double iconSize = 20,
  }) {
    final desabilitado = onTap == null;
    final corFundoBotao = desabilitado
        ? Colors.grey.shade300
        : backgroundColor ?? corPrimaria;

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

  Widget controleCarrinho(Produto produto) {
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
                    backgroundColor: corPrimaria.withValues(alpha: 0.10),
                    iconColor: corPrimaria,
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
                  iconColor: corPrimaria,
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
      barrierColor: Colors.black.withValues(alpha: 0.70),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateZoom) {
            final quantidade = carrinhoDialog.quantidadeProduto(produto);

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 26,
                vertical: 26,
              ),
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 330,
                  maxHeight: 430,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
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
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                height: 1.1,
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
                                height: 150,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }

                            if (imagemUrl == null || imagemUrl.isEmpty) {
                              return SizedBox(
                                height: 150,
                                child: Center(
                                  child: Icon(
                                    Icons.shopping_basket,
                                    size: 64,
                                    color: corPrimaria,
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
                                  height: 150,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                                errorWidget: (context, url, error) => SizedBox(
                                  height: 150,
                                  child: Center(
                                    child: Icon(
                                      Icons.shopping_basket,
                                      size: 64,
                                      color: corPrimaria,
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
                                    color: corPrimaria,
                                    fontSize: 19,
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
                                    color: corPrimaria,
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
                          const SizedBox(height: 9),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: corPrimaria.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: corPrimaria.withValues(alpha: 0.16),
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
                                if (quantidade > 0) ...[
                                  botaoAcaoProduto(
                                    icon: Icons.remove,
                                    onTap: () {
                                      carrinhoDialog.diminuirQuantidade(
                                        produto,
                                      );
                                      setStateZoom(() {});
                                    },
                                    backgroundColor: corPrimaria.withValues(
                                      alpha: 0.10,
                                    ),
                                    iconColor: corPrimaria,
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
                                        builder: (_) => const CarrinhoPage(),
                                      ),
                                    );
                                  },
                                  backgroundColor: Colors.white,
                                  iconColor: corPrimaria,
                                  size: 32,
                                  iconSize: 21,
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
                color: const Color(0xFFF8F8F8),
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
                      color: corPrimaria,
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
                  controleCarrinho(produto),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget? appBarCategoria(BuildContext context) {
    if (!widget.mostrarAppBar) {
      return null;
    }

    final carrinho = context.watch<CarrinhoController>();

    return AppBar(
      title: Text(widget.categoria),
      leading: widget.onVoltar != null
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: widget.onVoltar,
            )
          : null,
      backgroundColor: corPrimaria,
      foregroundColor: Colors.white,
      actions: [
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.shopping_cart_outlined),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CarrinhoPage()),
                );
              },
            ),
            if (carrinho.quantidadeTotal > 0)
              Positioned(
                right: 6,
                top: 6,
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: Colors.white,
                  child: Text(
                    carrinho.quantidadeTotal.toString(),
                    style: TextStyle(
                      color: corPrimaria,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final buscando = buscaAtual.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: corFundo,
      appBar: appBarCategoria(context),
      body: Column(
        children: [
          if (widget.mostrarBusca) campoBusca(),
          listaSubcategorias(),
          Expanded(
            child: carregando
                ? const Center(child: CircularProgressIndicator())
                : produtosFiltrados.isEmpty
                ? Center(
                    child: Text(
                      buscando
                          ? 'Nenhum produto encontrado para "${buscaAtual.trim()}"'
                          : 'Nenhum produto encontrado',
                    ),
                  )
                : GridView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                    itemCount:
                        produtosFiltrados.length + (carregandoMais ? 1 : 0),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 7,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.62,
                        ),
                    itemBuilder: (context, index) {
                      if (index >= produtosFiltrados.length) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final produto = produtosFiltrados[index];
                      return produtoCard(produto);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

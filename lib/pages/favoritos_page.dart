import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/carrinho_controller.dart';
import '../models/produto.dart';
import '../services/app_tema_service.dart';
import '../services/favoritos_service.dart';
import '../services/imagem_service.dart';
import '../widgets/imagem_produto_network.dart';

class FavoritosPage extends StatefulWidget {
  final VoidCallback? onVoltarInicio;
  final VoidCallback? onAbrirCarrinho;

  const FavoritosPage({super.key, this.onVoltarInicio, this.onAbrirCarrinho});

  @override
  State<FavoritosPage> createState() => _FavoritosPageState();
}

class _FavoritosPageState extends State<FavoritosPage> {
  bool carregando = true;
  List<Produto> produtos = [];
  final Map<String, Future<String?>> _cacheImagemProduto = {};

  @override
  void initState() {
    super.initState();
    carregarFavoritos();
  }

  Future<void> carregarFavoritos() async {
    setState(() => carregando = true);
    try {
      await FavoritosService.instance.carregar(forcar: true);
      final favoritos = await FavoritosService.instance.listar();
      final encontrados = <Produto>[];
      for (final favorito in favoritos) {
        final produto = await FavoritosService.instance.produtoAtual(favorito);
        if (produto != null && produto.nome.trim().isNotEmpty) {
          encontrados.add(produto);
        }
      }
      if (mounted) {
        setState(() => produtos = encontrados);
      }
    } catch (_) {
      if (mounted) setState(() => produtos = []);
    } finally {
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> removerFavorito(Produto produto) async {
    await FavoritosService.instance.alternar(produto);
    if (mounted) {
      setState(
        () =>
            produtos.removeWhere((item) => item.produtoId == produto.produtoId),
      );
    }
  }

  void adicionarQuantidade(Produto produto) {
    final carrinho = context.read<CarrinhoController>();
    if (!carrinho.adicionarQuantidade(produto, 1)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produto indisponível no momento.')),
      );
    }
  }

  Future<String?> buscarImagemProdutoComCache(Produto produto) {
    final imagemProdutoApp = produto.produtoAppId.trim().isNotEmpty
        ? produto.imagemUrl.trim()
        : '';
    final chaveBase = produto.ean.trim().isNotEmpty
        ? produto.ean.trim()
        : produto.nome.trim().toUpperCase();
    final chave = imagemProdutoApp.isEmpty
        ? chaveBase
        : '$chaveBase|app:${produto.produtoAppId.trim()}|img:$imagemProdutoApp';

    return _cacheImagemProduto.putIfAbsent(
      chave,
      () => ImagemService.buscarImagemProduto(
        ean: produto.ean,
        nomeProduto: produto.nome,
        imagemUrlCadastroProdutoApp: imagemProdutoApp,
      ),
    );
  }

  Widget cardFavorito(Produto produto) {
    return Consumer<CarrinhoController>(
      builder: (context, carrinho, _) {
        final quantidade = carrinho.quantidadeProduto(produto);
        final semEstoque =
            carrinho.bloquearVendaSemEstoque && produto.estoque <= 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.all(12),
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 58,
                height: 58,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTemaService.primaria.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: FutureBuilder<String?>(
                  future: buscarImagemProdutoComCache(produto),
                  builder: (context, snapshot) {
                    final imagemUrl = snapshot.data?.trim() ?? '';
                    final carregandoImagem =
                        snapshot.connectionState == ConnectionState.waiting;
                    final fallback = Icon(
                      Icons.shopping_basket_outlined,
                      size: 36,
                      color: AppTemaService.primaria,
                    );

                    if (carregandoImagem) {
                      return Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTemaService.primaria,
                          ),
                        ),
                      );
                    }
                    if (imagemUrl.isEmpty) return fallback;

                    return ImagemProdutoNetwork(
                      imagemUrl: imagemUrl,
                      ean: produto.ean,
                      nomeProduto: produto.nome,
                      imagemUrlCadastroProdutoApp:
                          produto.produtoAppId.trim().isNotEmpty
                          ? produto.imagemUrl
                          : '',
                      fit: BoxFit.contain,
                      placeholder: const SizedBox.shrink(),
                      fallback: fallback,
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      produto.nome,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF424242),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      quantidade > 0
                          ? '${carrinho.textoQuantidadeProduto(produto)} no carrinho'
                          : 'Favorito',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      produto.precoRotulo,
                      style: TextStyle(
                        color: AppTemaService.primaria,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    if (semEstoque) ...[
                      const SizedBox(height: 4),
                      const Text(
                        'Indisponível',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _botaoQuantidade(
                        icone: Icons.remove_circle,
                        descricao: 'Diminuir quantidade',
                        cor: Colors.red,
                        onPressed: quantidade <= 0
                            ? null
                            : () => carrinho.diminuirQuantidade(produto),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          quantidade > 0
                              ? carrinho.textoQuantidadeProduto(produto)
                              : '0',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      _botaoQuantidade(
                        icone: Icons.add_circle,
                        descricao: 'Adicionar ao carrinho',
                        cor: Colors.green,
                        onPressed: semEstoque
                            ? null
                            : () => adicionarQuantidade(produto),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () => removerFavorito(produto),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppTemaService.primaria.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.favorite,
                        color: Colors.red,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _botaoQuantidade({
    required IconData icone,
    required String descricao,
    required Color cor,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: descricao,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Icon(
          icone,
          color: onPressed == null ? Colors.grey.shade300 : cor,
          size: 26,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cacheImagemProduto.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTemaService.fundo,
      appBar: AppBar(
        title: const Text('Favoritos'),
        leading: widget.onVoltarInicio == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onVoltarInicio,
              ),
        backgroundColor: AppTemaService.primaria,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Atualizar favoritos',
            onPressed: carregarFavoritos,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: carregando
          ? Center(
              child: CircularProgressIndicator(color: AppTemaService.primaria),
            )
          : produtos.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nenhum produto favoritado ainda.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: carregarFavoritos,
              child: ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: produtos.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final produto = produtos[index];
                  return cardFavorito(produto);
                },
              ),
            ),
    );
  }
}

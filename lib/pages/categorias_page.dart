import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/app_tema_service.dart';
import '../services/categoria_imagem_service.dart';
import 'produtos_categoria_page.dart';

class CategoriasPage extends StatefulWidget {
  final VoidCallback? onVoltarInicio;

  const CategoriasPage({super.key, this.onVoltarInicio});

  @override
  State<CategoriasPage> createState() => _CategoriasPageState();
}

class _CategoriasPageState extends State<CategoriasPage> {
  static const Color vermelho = Color(0xFFE30613);
  static const Color fundo = Color(0xFFF5F5F5);

  Color get corPrimaria => AppTemaService.primaria;
  Color get corFundo => AppTemaService.fundo;

  final TextEditingController buscaProdutoController = TextEditingController();
  Timer? debounceBuscaProduto;

  String buscaProdutoAtual = '';

  List<String> categorias = [];
  List<String> categoriasFiltradas = [];

  bool carregando = true;
  String? categoriaSelecionada;

  @override
  void initState() {
    super.initState();
    carregarCategorias();
  }

  @override
  void dispose() {
    debounceBuscaProduto?.cancel();
    buscaProdutoController.dispose();
    super.dispose();
  }

  Future<void> carregarCategorias() async {
    try {
      final resultado = await ApiService.listarCategorias();

      if (!mounted) return;

      await CategoriaImagemService.buscarImagensCategorias(resultado);

      if (!mounted) return;

      setState(() {
        categorias = resultado;
        categoriasFiltradas = resultado;
        categoriaSelecionada = 'Todos';
        carregando = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        categorias = [];
        categoriasFiltradas = [];
        categoriaSelecionada = null;
        carregando = false;
      });
    }
  }

  void filtrarProdutos(String texto) {
    debounceBuscaProduto?.cancel();

    debounceBuscaProduto = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;

      setState(() {
        buscaProdutoAtual = texto.trim();
      });
    });

    setState(() {});
  }

  void limparBuscaProduto() {
    debounceBuscaProduto?.cancel();

    setState(() {
      buscaProdutoController.clear();
      buscaProdutoAtual = '';
    });
  }

  void selecionarCategoria(String categoria) {
    if (categoriaSelecionada == categoria) {
      return;
    }

    setState(() {
      categoriaSelecionada = categoria;
    });
  }

  IconData iconeCategoria(String categoria) {
    final c = categoria.toUpperCase();

    if (c == 'TODOS') return Icons.grid_view_rounded;
    if (c.contains('HORT')) return Icons.eco;
    if (c.contains('BEBIDA')) return Icons.local_drink;
    if (c.contains('LATIC')) return Icons.local_cafe;
    if (c.contains('PADARIA')) return Icons.bakery_dining;
    if (c.contains('CARNE') || c.contains('ACOUGUE') || c.contains('AÇOUGUE')) {
      return Icons.set_meal;
    }
    if (c.contains('CEREAIS')) return Icons.rice_bowl;
    if (c.contains('MERCEARIA')) return Icons.shopping_bag;
    if (c.contains('CONGEL') || c.contains('SORVETE')) return Icons.ac_unit;
    if (c.contains('LIMPEZA')) return Icons.cleaning_services;
    if (c.contains('HIGIENE') || c.contains('PERFUMARIA')) return Icons.soap;
    if (c.contains('PET')) return Icons.pets;
    if (c.contains('BISCOITO') || c.contains('BOLACHA')) return Icons.cookie;
    if (c.contains('BAZAR')) return Icons.shopping_bag;
    if (c.contains('BOMBON')) return Icons.cake;

    return Icons.shopping_basket;
  }

  Color corIconeCategoria(String categoria) {
    final c = categoria.toUpperCase();

    if (c == 'TODOS') return corPrimaria;
    if (c.contains('HORT')) return Colors.green;
    if (c.contains('BEBIDA')) return Colors.blue;
    if (c.contains('LATIC')) return Colors.blueAccent;
    if (c.contains('PADARIA')) return Colors.orange;
    if (c.contains('CARNE') || c.contains('ACOUGUE') || c.contains('AÇOUGUE')) {
      return Colors.red;
    }
    if (c.contains('CONGEL') || c.contains('SORVETE')) return Colors.lightBlue;
    if (c.contains('LIMPEZA')) return Colors.teal;
    if (c.contains('HIGIENE') || c.contains('PERFUMARIA')) return Colors.purple;
    if (c.contains('PET')) return Colors.brown;
    if (c.contains('BISCOITO') || c.contains('BOLACHA')) return Colors.orange;
    if (c.contains('BAZAR')) return Colors.deepPurple;
    if (c.contains('BOMBON')) return Colors.pink;

    return corPrimaria;
  }

  Widget categoriaHorizontal(String categoria) {
    final selecionada = categoriaSelecionada == categoria;
    final cor = corIconeCategoria(categoria);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => selecionarCategoria(categoria),
      child: Container(
        width: 82,
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 68,
              height: 68,
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selecionada
                      ? corPrimaria
                      : AppTemaService.primaria.withValues(alpha: 0.16),
                  width: selecionada ? 2.6 : 1.6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTemaService.primaria.withValues(alpha: 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: categoria.toUpperCase() == 'TODOS'
                  ? Icon(
                      Icons.grid_view_rounded,
                      color: selecionada ? corPrimaria : Colors.grey,
                      size: 34,
                    )
                  : FutureBuilder<String?>(
                      future: CategoriaImagemService.buscarImagemCategoria(
                        categoria,
                      ),
                      builder: (context, snapshot) {
                        final imagemUrl = snapshot.data;

                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            imagemUrl == null) {
                          return Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cor,
                              ),
                            ),
                          );
                        }

                        if (imagemUrl == null || imagemUrl.trim().isEmpty) {
                          return Icon(
                            iconeCategoria(categoria),
                            color: cor,
                            size: 30,
                          );
                        }

                        return CachedNetworkImage(
                          imageUrl: imagemUrl,
                          fit: BoxFit.contain,
                          placeholder: (context, url) => Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cor,
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Icon(
                            iconeCategoria(categoria),
                            color: cor,
                            size: 30,
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 5),
            Text(
              categoria,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selecionada ? Colors.black : Colors.black54,
                fontSize: 11.2,
                fontWeight: selecionada ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget campoBuscaProduto() {
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
          controller: buscaProdutoController,
          onChanged: filtrarProdutos,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Buscar produto',
            prefixIcon: Icon(Icons.search, color: corPrimaria),
            suffixIcon: buscaProdutoController.text.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.close, color: corPrimaria),
                    onPressed: limparBuscaProduto,
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

  Widget listaCategoriasHorizontal() {
    if (carregando) {
      return SizedBox(
        height: 96,
        child: Center(child: CircularProgressIndicator(color: corPrimaria)),
      );
    }

    if (categorias.isEmpty) {
      return const SizedBox(
        height: 96,
        child: Center(
          child: Text(
            'Nenhuma categoria encontrada',
            style: TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    final lista = ['Todos', ...categorias];

    return SizedBox(
      height: 96,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 4),
        itemCount: lista.length,
        itemBuilder: (context, index) {
          final categoria = lista[index];
          return categoriaHorizontal(categoria);
        },
      ),
    );
  }

  Widget areaProdutos() {
    final categoria = categoriaSelecionada;

    if (categoria == null) {
      return const Expanded(
        child: Center(
          child: Text(
            'Selecione uma categoria',
            style: TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Expanded(
      child: ProdutosCategoriaPage(
        key: ValueKey('$categoria|$buscaProdutoAtual'),
        categoria: categoria,
        mostrarAppBar: false,
        mostrarBusca: false,
        buscaProduto: buscaProdutoAtual,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: corFundo,
      appBar: AppBar(
        title: const Text('Categorias'),
        leading: widget.onVoltarInicio != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onVoltarInicio,
              )
            : null,
        backgroundColor: corPrimaria,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          campoBuscaProduto(),
          listaCategoriasHorizontal(),
          Container(height: 1, color: Colors.black.withOpacity(0.08)),
          areaProdutos(),
        ],
      ),
    );
  }
}

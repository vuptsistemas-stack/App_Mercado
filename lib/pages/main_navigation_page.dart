import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../controllers/carrinho_controller.dart';
import '../services/app_tema_service.dart';
import '../services/lista_compras_service.dart';
import '../services/loja_funcionamento_service.dart';
import '../services/monitor_status_pedidos_cliente_service.dart';

import 'home_page.dart';
import 'categorias_page.dart';
import 'carrinho_page.dart';
import 'pedidos_page.dart';
import 'conta_page.dart';
import 'produtos_categoria_page.dart';
import 'finalizar_pedido_page.dart';
import 'mais_page.dart';

class MainNavigationPage extends StatefulWidget {
  final int indexInicial;

  const MainNavigationPage({super.key, this.indexInicial = 0});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  final GlobalKey<CarrinhoPageState> carrinhoPageKey =
      GlobalKey<CarrinhoPageState>();

  late int indexSelecionado;
  String? categoriaSelecionada;

  bool exibindoFinalizarPedido = false;
  bool exibindoConta = false;
  bool exibirBotaoFinalizarCompra = false;

  @override
  void initState() {
    super.initState();
    indexSelecionado = widget.indexInicial;
    MonitorStatusPedidosClienteService.instance.iniciar();
    carregarConfiguracaoBotaoFinalizarCompra();
  }

  Future<void> carregarConfiguracaoBotaoFinalizarCompra() async {
    final configuracoes = await LojaFuncionamentoService.buscarConfiguracoes(
      forcarAtualizacao: true,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      exibirBotaoFinalizarCompra =
          configuracoes.exibirBotaoFinalizarCompra;
    });
  }

  @override
  void dispose() {
    MonitorStatusPedidosClienteService.instance.parar();
    super.dispose();
  }

  void voltarParaInicio() {
    setState(() {
      exibindoFinalizarPedido = false;
      exibindoConta = false;
      categoriaSelecionada = null;
      indexSelecionado = 0;
    });
  }

  void abrirCategoria(String categoria) {
    setState(() {
      exibindoFinalizarPedido = false;
      exibindoConta = false;
      categoriaSelecionada = categoria;
      indexSelecionado = 0;
    });
  }

  void abrirCategorias() {
    setState(() {
      exibindoFinalizarPedido = false;
      exibindoConta = false;
      categoriaSelecionada = null;
      indexSelecionado = 1;
    });
  }

  void abrirFinalizarPedido() {
    setState(() {
      categoriaSelecionada = null;
      exibindoConta = false;
      exibindoFinalizarPedido = true;
      indexSelecionado = 2;
    });
  }

  void iniciarFinalizacaoRapida() {
    setState(() {
      categoriaSelecionada = null;
      exibindoConta = false;
      exibindoFinalizarPedido = false;
      indexSelecionado = 2;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      carrinhoPageKey.currentState?.iniciarFinalizacao();
    });
  }

  void voltarParaCarrinho() {
    setState(() {
      exibindoFinalizarPedido = false;
      exibindoConta = false;
      categoriaSelecionada = null;
      indexSelecionado = 2;
    });
  }

  void abrirAbaPedidos() {
    setState(() {
      exibindoFinalizarPedido = false;
      exibindoConta = false;
      categoriaSelecionada = null;
      indexSelecionado = 3;
    });
  }

  void abrirConta() {
    setState(() {
      exibindoFinalizarPedido = false;
      exibindoConta = true;
      categoriaSelecionada = null;
      indexSelecionado = 0;
    });
  }

  void trocarAba(int index) {
    setState(() {
      exibindoFinalizarPedido = false;
      exibindoConta = false;
      categoriaSelecionada = null;
      indexSelecionado = index;
    });
  }

  void tratarBotaoVoltar() {
    if (exibindoConta) {
      setState(() {
        exibindoConta = false;
        exibindoFinalizarPedido = false;
        exibindoConta = false;
        categoriaSelecionada = null;
        indexSelecionado = 0;
      });
      return;
    }

    if (categoriaSelecionada != null) {
      setState(() {
        categoriaSelecionada = null;
        exibindoFinalizarPedido = false;
        exibindoConta = false;
        indexSelecionado = 0;
      });
      return;
    }

    if (exibindoFinalizarPedido) {
      setState(() {
        exibindoFinalizarPedido = false;
        exibindoConta = false;
        categoriaSelecionada = null;
        indexSelecionado = 2;
      });
      return;
    }

    if (indexSelecionado != 0) {
      setState(() {
        exibindoFinalizarPedido = false;
        exibindoConta = false;
        categoriaSelecionada = null;
        indexSelecionado = 0;
      });
      return;
    }

    SystemNavigator.pop();
  }

  Widget carrinhoIcone({required bool ativo, required int quantidade}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(ativo ? Icons.shopping_cart : Icons.shopping_cart_outlined),
        if (quantidade > 0)
          Positioned(
            right: -8,
            top: -6,
            child: Container(
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              decoration: BoxDecoration(
                color: AppTemaService.primaria,
                shape: BoxShape.circle,
              ),
              child: Text(
                quantidade > 99 ? '99+' : quantidade.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final paginas = [
      categoriaSelecionada == null
          ? HomePage(
              abrirCategorias: abrirCategorias,
              abrirCategoria: abrirCategoria,
              abrirConta: abrirConta,
            )
          : ProdutosCategoriaPage(
              categoria: categoriaSelecionada!,
              mostrarAppBar: true,
              onVoltar: tratarBotaoVoltar,
            ),
      CategoriasPage(onVoltarInicio: voltarParaInicio),
      exibindoFinalizarPedido
          ? FinalizarPedidoPage(
              onVoltar: voltarParaCarrinho,
              onPedidoFinalizado: abrirAbaPedidos,
            )
          : CarrinhoPage(
              key: carrinhoPageKey,
              onFinalizarPedido: abrirFinalizarPedido,
              onVoltarInicio: voltarParaInicio,
            ),
      PedidosPage(onVoltarInicio: voltarParaInicio),
      ListasComprasPage(
        onAbrirCarrinho: () => trocarAba(2),
        onVoltarInicio: voltarParaInicio,
      ),
      MaisPage(onVoltarInicio: voltarParaInicio),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        tratarBotaoVoltar();
      },
      child: Consumer<CarrinhoController>(
        builder: (context, carrinho, child) {
          final mostrarAtalhoFinalizacao =
              exibirBotaoFinalizarCompra &&
              carrinho.quantidadeTotal > 0 &&
              !exibindoConta &&
              !exibindoFinalizarPedido &&
              (indexSelecionado == 0 || indexSelecionado == 1);

          return Scaffold(
            body: exibindoConta
                ? ContaPage(onVoltar: tratarBotaoVoltar)
                : paginas[indexSelecionado],
            bottomNavigationBar: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (mostrarAtalhoFinalizacao)
                    Container(
                      width: double.infinity,
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
                      child: SizedBox(
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: iniciarFinalizacaoRapida,
                          icon: const Icon(Icons.shopping_cart_checkout),
                          label: const Text('Finalizar compra'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTemaService.primaria,
                            foregroundColor: Colors.white,
                            elevation: 2,
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  SizedBox(
                    height: 58,
                    child: MediaQuery.removePadding(
                      context: context,
                      removeBottom: true,
                      child: BottomNavigationBar(
                    currentIndex: indexSelecionado,
                    onTap: trocarAba,
                    type: BottomNavigationBarType.fixed,
                    selectedItemColor: AppTemaService.primaria,
                    unselectedItemColor: const Color(0xFF5F6670),
                    selectedFontSize: 11.5,
                    unselectedFontSize: 11,
                    iconSize: 27,
                    elevation: 8,
                    items: [
                      const BottomNavigationBarItem(
                        icon: Icon(Icons.home_outlined),
                        activeIcon: Icon(Icons.home),
                        label: 'Início',
                      ),
                      const BottomNavigationBarItem(
                        icon: Icon(Icons.grid_view_outlined),
                        activeIcon: Icon(Icons.grid_view),
                        label: 'Categorias',
                      ),
                      BottomNavigationBarItem(
                        icon: carrinhoIcone(
                          ativo: false,
                          quantidade: carrinho.quantidadeTotal,
                        ),
                        activeIcon: carrinhoIcone(
                          ativo: true,
                          quantidade: carrinho.quantidadeTotal,
                        ),
                        label: 'Carrinho',
                      ),
                      const BottomNavigationBarItem(
                        icon: Icon(Icons.receipt_long_outlined),
                        activeIcon: Icon(Icons.receipt_long),
                        label: 'Pedidos',
                      ),
                      const BottomNavigationBarItem(
                        icon: Icon(Icons.playlist_add_outlined),
                        activeIcon: Icon(Icons.playlist_add_check_rounded),
                        label: 'Listas',
                      ),
                      const BottomNavigationBarItem(
                        icon: Icon(Icons.more_horiz),
                        activeIcon: Icon(Icons.more_rounded),
                        label: 'Mais',
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
      ),
    );
  }
}

class ListasComprasPage extends StatefulWidget {
  final VoidCallback? onAbrirCarrinho;
  final VoidCallback? onVoltarInicio;

  const ListasComprasPage({
    super.key,
    this.onAbrirCarrinho,
    this.onVoltarInicio,
  });

  @override
  State<ListasComprasPage> createState() => _ListasComprasPageState();
}

class _ListasComprasPageState extends State<ListasComprasPage> {
  bool carregando = true;
  List<ListaComprasSalva> listas = [];

  Color get vermelho => AppTemaService.primaria;

  @override
  void initState() {
    super.initState();
    carregarListas();
  }

  Future<void> carregarListas() async {
    final resultado = await ListaComprasService.listarListas();

    if (!mounted) {
      return;
    }

    setState(() {
      listas = resultado;
      carregando = false;
    });
  }

  String formatarMoeda(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String formatarData(DateTime data) {
    final local = data.toLocal();
    final dia = local.day.toString().padLeft(2, '0');
    final mes = local.month.toString().padLeft(2, '0');
    final ano = local.year.toString();
    final hora = local.hour.toString().padLeft(2, '0');
    final minuto = local.minute.toString().padLeft(2, '0');

    return '$dia/$mes/$ano às $hora:$minuto';
  }

  Future<void> adicionarListaAoCarrinho(ListaComprasSalva lista) async {
    final carrinho = context.read<CarrinhoController>();

    for (final item in lista.itens) {
      final quantidadeAtual = carrinho.quantidadeProduto(item.produto);

      final novaQuantidade = quantidadeAtual + item.quantidade;

      carrinho.definirQuantidade(
        produto: item.produto,
        quantidade: novaQuantidade.toInt(),
      );
    }

    await carrinho.atualizarProdutosCarrinho();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: vermelho,
        content: Text(
          'Itens da lista "${lista.nome}" adicionados ao carrinho.',
        ),
        action: SnackBarAction(
          label: 'Ver carrinho',
          textColor: Colors.white,
          onPressed: () {
            widget.onAbrirCarrinho?.call();
          },
        ),
      ),
    );
  }

  Future<void> confirmarExcluirLista(ListaComprasSalva lista) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Excluir lista'),
          content: Text(
            'Deseja excluir a lista "${lista.nome}" deste celular?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                'Excluir',
                style: TextStyle(color: vermelho, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );

    if (confirmou != true) {
      return;
    }

    await ListaComprasService.excluirLista(lista.id);
    await carregarListas();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: vermelho,
        content: const Text('Lista excluída.'),
      ),
    );
  }

  Widget estadoVazio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 94,
              height: 94,
              decoration: BoxDecoration(
                color: vermelho.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.playlist_add_check_rounded,
                color: vermelho,
                size: 46,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Listas de compras',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF1F2937),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Monte um carrinho e toque em “Salvar como lista de compras”. As listas ficam salvas apenas neste celular.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black54,
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget itemListaPreview(ListaComprasItem item) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shopping_bag_outlined, color: vermelho, size: 16),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '${item.produto.nome} • ${item.produto.textoQuantidadeCurto(item.quantidade)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF4B5563),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget cardLista(ListaComprasSalva lista) {
    final preview = lista.itens.take(3).toList();
    final restantes = lista.itens.length - preview.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      padding: const EdgeInsets.all(14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: vermelho.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(Icons.list_alt_rounded, color: vermelho, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lista.nome,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${lista.quantidadeItens} item(ns) • criada em ${formatarData(lista.criadoEm)}',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Excluir lista',
                onPressed: () => confirmarExcluirLista(lista),
                icon: Icon(Icons.delete_outline_rounded, color: vermelho),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: AppTemaService.fundo,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in preview) itemListaPreview(item),
                if (restantes > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '+ $restantes outro(s) produto(s)',
                    style: TextStyle(
                      color: vermelho,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Estimado: ${formatarMoeda(lista.valorEstimado)}',
                  style: TextStyle(
                    color: vermelho,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => adicionarListaAoCarrinho(lista),
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                label: const Text(
                  'Adicionar',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: vermelho,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
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
      backgroundColor: AppTemaService.fundo,
      appBar: AppBar(
        title: const Text('Listas de compras'),
        leading: widget.onVoltarInicio != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onVoltarInicio,
              )
            : null,
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Atualizar listas',
            onPressed: carregarListas,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: carregando
          ? Center(child: CircularProgressIndicator(color: vermelho))
          : listas.isEmpty
          ? estadoVazio()
          : RefreshIndicator(
              color: vermelho,
              onRefresh: carregarListas,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(0, 14, 0, 14),
                itemCount: listas.length,
                itemBuilder: (context, index) {
                  return cardLista(listas[index]);
                },
              ),
            ),
    );
  }
}

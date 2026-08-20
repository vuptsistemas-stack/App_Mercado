import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../controllers/carrinho_controller.dart';
import '../models/produto.dart';
import '../services/imagem_service.dart';
import '../services/loja_funcionamento_service.dart';
import '../services/app_tema_service.dart';
import '../services/lista_compras_service.dart';
import 'finalizar_pedido_page.dart';
import '../services/sessao_mercado_cliente.dart' as sessao;

class CarrinhoPage extends StatefulWidget {
  final VoidCallback? onFinalizarPedido;
  final VoidCallback? onVoltarInicio;

  const CarrinhoPage({super.key, this.onFinalizarPedido, this.onVoltarInicio});

  @override
  State<CarrinhoPage> createState() => CarrinhoPageState();
}

class CarrinhoPageState extends State<CarrinhoPage> {
  bool atualizouAoAbrir = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      atualizarCarrinhoAoAbrir();
    });
  }

  Future<void> atualizarCarrinhoAoAbrir() async {
    if (atualizouAoAbrir || !mounted) {
      return;
    }

    atualizouAoAbrir = true;

    final carrinho = context.read<CarrinhoController>();

    if (carrinho.itens.isEmpty) {
      return;
    }

    final totalAtualizados = await carrinho.atualizarProdutosCarrinho();

    if (!mounted || totalAtualizados <= 0) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Carrinho atualizado com os preços atuais'),
        backgroundColor: AppTemaService.primaria,
      ),
    );
  }

  Future<void> atualizarCarrinhoManual(BuildContext context) async {
    final carrinho = context.read<CarrinhoController>();

    if (carrinho.itens.isEmpty) {
      return;
    }

    final totalAtualizados = await carrinho.atualizarProdutosCarrinho();

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          totalAtualizados > 0
              ? 'Carrinho atualizado com os preços atuais'
              : 'Carrinho já está atualizado',
        ),
        backgroundColor: AppTemaService.primaria,
      ),
    );
  }

  Future<void> salvarCarrinhoComoLista(BuildContext context) async {
    final carrinho = context.read<CarrinhoController>();

    if (carrinho.itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Adicione produtos no carrinho antes de salvar uma lista.',
          ),
          backgroundColor: AppTemaService.primaria,
        ),
      );
      return;
    }

    var nomeDigitado = '';

    final nome = await showDialog<String>(
      context: context,
      useSafeArea: true,
      builder: (dialogContext) {
        final tamanhoTela = MediaQuery.of(dialogContext).size;
        final teclado = MediaQuery.of(dialogContext).viewInsets.bottom;

        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + teclado),
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 420,
                  maxHeight: tamanhoTela.height * 0.82,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    color: Colors.white,
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                            color: AppTemaService.primaria,
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.playlist_add_check_rounded,
                                    color: Colors.white,
                                    size: 25,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Salvar lista de compras',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Dê um nome para essa lista. Ela ficará salva somente neste celular.',
                                  style: TextStyle(
                                    color: Color(0xFF374151),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                TextField(
                                  autofocus: false,
                                  textInputAction: TextInputAction.done,
                                  onChanged: (valor) {
                                    nomeDigitado = valor;
                                  },
                                  onSubmitted: (valor) {
                                    FocusManager.instance.primaryFocus
                                        ?.unfocus();
                                    Navigator.of(dialogContext).pop(valor);
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'Nome da lista',
                                    hintText: 'Ex: Compra do mês',
                                    prefixIcon: const Icon(
                                      Icons.edit_note_rounded,
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey.shade100,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: AppTemaService.primaria,
                                        width: 1.4,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () {
                                      FocusManager.instance.primaryFocus
                                          ?.unfocus();
                                      Navigator.of(dialogContext).pop();
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTemaService.primaria,
                                      side: BorderSide(
                                        color: AppTemaService.primaria
                                            .withValues(alpha: 0.35),
                                      ),
                                      minimumSize: const Size(0, 48),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                    ),
                                    child: const Text(
                                      'Cancelar',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      FocusManager.instance.primaryFocus
                                          ?.unfocus();
                                      Navigator.of(
                                        dialogContext,
                                      ).pop(nomeDigitado);
                                    },
                                    icon: const Icon(Icons.save_alt_rounded),
                                    label: const Text(
                                      'Salvar',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTemaService.primaria,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      minimumSize: const Size(0, 48),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
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
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    final nomeFinal = (nome ?? '').trim();
    if (nomeFinal.isEmpty) {
      return;
    }

    await ListaComprasService.salvarListaDoCarrinho(
      nome: nomeFinal,
      itensCarrinho: carrinho.itens,
    );

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Lista "$nomeFinal" salva neste celular.'),
        backgroundColor: AppTemaService.primaria,
      ),
    );
  }

  String formatarMoeda(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  double numeroConfiguracao(dynamic valor) {
    if (valor == null) {
      return 0;
    }

    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor.toString().replaceAll(',', '.').trim()) ?? 0;
  }

  Future<double> buscarPedidoMinimoLoja() async {
    try {
      final resposta = await Supabase.instance.client
          .from('loja_configuracoes')
          .select('pedido_minimo')
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .limit(1)
          .maybeSingle();

      return numeroConfiguracao(resposta?['pedido_minimo']);
    } catch (_) {
      return 0;
    }
  }

  Future<bool> validarPedidoMinimoCarrinho(
    BuildContext context,
    double subtotalProdutos,
  ) async {
    final pedidoMinimo = await buscarPedidoMinimoLoja();

    if (pedidoMinimo <= 0 || subtotalProdutos >= pedidoMinimo) {
      return true;
    }

    if (!context.mounted) {
      return false;
    }

    final faltante = pedidoMinimo - subtotalProdutos;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Pedido mínimo de ${formatarMoeda(pedidoMinimo)}. Faltam ${formatarMoeda(faltante)} em produtos para finalizar.',
        ),
        backgroundColor: AppTemaService.primaria,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );

    return false;
  }

  String formatarPeso(double kg) {
    if (kg <= 0) {
      return '0g';
    }

    if (kg < 1) {
      final gramas = (kg * 1000).round();
      return '${gramas}g';
    }

    var texto = kg.toStringAsFixed(3).replaceAll('.', ',');

    while (texto.endsWith('0')) {
      texto = texto.substring(0, texto.length - 1);
    }

    if (texto.endsWith(',')) {
      texto = texto.substring(0, texto.length - 1);
    }

    return '${texto}kg';
  }

  void confirmarRemocao(BuildContext context, dynamic produto) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  decoration: BoxDecoration(color: AppTemaService.primaria),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Remover item',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Deseja remover este produto do carrinho?',
                        style: TextStyle(
                          color: Color(0xFF374151),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTemaService.primaria.withValues(
                            alpha: 0.06,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTemaService.primaria.withValues(
                              alpha: 0.16,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.shopping_bag_outlined,
                              color: AppTemaService.primaria,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                produto.nome,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF1F2937),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w900,
                                  height: 1.15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTemaService.primaria,
                            side: BorderSide(
                              color: AppTemaService.primaria.withValues(
                                alpha: 0.35,
                              ),
                            ),
                            minimumSize: const Size(0, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          child: const Text(
                            'Cancelar',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            context.read<CarrinhoController>().removerProduto(
                              produto,
                            );
                            Navigator.of(dialogContext).pop();
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text(
                            'Remover',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTemaService.primaria,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: const Size(0, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
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
      },
    );
  }

  Future<void> abrirFinalizarPedido(BuildContext context) async {
    final carrinho = context.read<CarrinhoController>();

    await carrinho.atualizarProdutosCarrinho();

    if (!context.mounted) {
      return;
    }

    final itensComProblema = carrinho.itensComProblemaEstoque;

    if (itensComProblema.isNotEmpty) {
      mostrarAlertaEstoque(context, itensComProblema);
      return;
    }

    final pedidoMinimoOk = await validarPedidoMinimoCarrinho(
      context,
      carrinho.valorTotal,
    );

    if (!context.mounted || !pedidoMinimoOk) {
      return;
    }

    final podeContinuar =
        await LojaFuncionamentoService.podeAdicionarAoCarrinho(
          context,
          forcarAtualizacao: true,
        );

    if (!podeContinuar) {
      return;
    }

    final itensPesoVariavel = carrinho.itens
        .where((item) => item.pesoVariavel)
        .toList();

    if (itensPesoVariavel.isNotEmpty) {
      final continuar = await mostrarAvisoPesoVariavel(
        context,
        itensPesoVariavel,
      );

      if (!context.mounted || !continuar) {
        return;
      }
    }

    if (widget.onFinalizarPedido != null) {
      widget.onFinalizarPedido!();
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FinalizarPedidoPage()),
    );
  }

  Future<void> iniciarFinalizacao() async {
    if (!mounted) {
      return;
    }

    await abrirFinalizarPedido(context);
  }

  Future<bool> mostrarAvisoPesoVariavel(
    BuildContext context,
    List<dynamic> itensPesoVariavel,
  ) async {
    final resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final itensPreview = itensPesoVariavel.take(3).toList();
        final itensRestantes = itensPesoVariavel.length - itensPreview.length;

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  decoration: BoxDecoration(color: AppTemaService.primaria),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.scale_outlined,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Valor estimado',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Seu carrinho possui produto vendido por peso variável.',
                        style: TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'O total do pedido pode sofrer alteração, pois alguns produtos são vendidos em pacote fechado e o peso real será conferido pelo mercado.',
                        style: TextStyle(
                          color: Color(0xFF4B5563),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTemaService.primaria.withValues(
                            alpha: 0.06,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppTemaService.primaria.withValues(
                              alpha: 0.16,
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            for (final item in itensPreview)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.inventory_2_outlined,
                                      color: AppTemaService.primaria,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${item.produto.nome} • ${item.textoQuantidadeCurto} • peso estimado ${formatarPeso(item.pesoEstimadoKg)}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF1F2937),
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          height: 1.18,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (itensRestantes > 0)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '+ $itensRestantes item(ns) de peso variável',
                                  style: TextStyle(
                                    color: AppTemaService.primaria,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text(
                            'Entendi e quero continuar',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTemaService.primaria,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: const Size(0, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: Text(
                            'Voltar ao carrinho',
                            style: TextStyle(
                              color: AppTemaService.primaria,
                              fontWeight: FontWeight.w900,
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
      },
    );

    return resultado == true;
  }

  String textoProblemaEstoque(dynamic item) {
    final estoque = item.produto.estoque;

    if (estoque <= 0) {
      return 'Sem estoque';
    }

    if (item.produto.ehKg) {
      final pesoCarrinho = item.pesoEstimadoKg as double;

      if (pesoCarrinho > estoque + 0.0001) {
        return 'Estoque disponível: ${formatarPeso(estoque)} | No carrinho: ${formatarPeso(pesoCarrinho)}';
      }

      return '';
    }

    if (item.quantidade > estoque) {
      return 'Estoque disponível: ${estoque.toStringAsFixed(0)} | No carrinho: ${item.quantidade}';
    }

    return '';
  }

  void mostrarAlertaEstoque(
    BuildContext context,
    List<dynamic> itensComProblema,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  decoration: BoxDecoration(color: AppTemaService.primaria),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.inventory_2_outlined,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Atenção ao estoque',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Não é possível finalizar o pedido enquanto houver produto sem estoque ou com quantidade maior que a disponível.',
                          style: TextStyle(
                            color: Color(0xFF374151),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Remova o item ou ajuste a quantidade para continuar.',
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: itensComProblema.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = itensComProblema[index];

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTemaService.primaria.withValues(
                                  alpha: 0.06,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppTemaService.primaria.withValues(
                                    alpha: 0.16,
                                  ),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: AppTemaService.primaria,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.produto.nome,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF1F2937),
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w900,
                                            height: 1.15,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          textoProblemaEstoque(item),
                                          style: TextStyle(
                                            color: AppTemaService.primaria,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.check_circle),
                      label: const Text(
                        'Entendi',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTemaService.primaria,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
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

  Widget avisoProblemaEstoque(dynamic item) {
    final texto = textoProblemaEstoque(item);

    if (texto.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(
        texto,
        style: TextStyle(
          color: AppTemaService.primaria,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Future<void> tentarAumentarQuantidade(
    BuildContext context,
    Produto produto,
  ) async {
    final carrinho = context.read<CarrinhoController>();
    if (produto.estoque <= 0 || !carrinho.podeAdicionarProduto(produto)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Produto sem estoque disponível'),
          backgroundColor: AppTemaService.primaria,
        ),
      );
      return;
    }

    final podeAdicionar =
        await LojaFuncionamentoService.podeAdicionarAoCarrinho(context);

    if (!podeAdicionar) {
      return;
    }

    if (!context.mounted) {
      return;
    }

    carrinho.aumentarQuantidade(produto);
  }

  Widget imagemCarrinho(Produto produto) {
    return FutureBuilder<String?>(
      future: ImagemService.buscarImagemProduto(
        ean: produto.ean,
        nomeProduto: produto.nome,
        imagemUrlCadastroProdutoApp: produto.produtoAppId.trim().isNotEmpty
            ? produto.imagemUrl
            : '',
      ),
      builder: (context, snapshot) {
        final imagemUrl = snapshot.data;

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
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
            color: AppTemaService.primaria,
            size: 32,
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: imagemUrl,
            fit: BoxFit.contain,
            placeholder: (context, url) => Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (context, url, error) => Icon(
              Icons.shopping_basket,
              color: AppTemaService.primaria,
              size: 32,
            ),
          ),
        );
      },
    );
  }

  Widget botaoQuantidade({
    required IconData icon,
    required Color cor,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Icon(
        icon,
        color: onTap == null ? Colors.grey.shade300 : cor,
        size: 26,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final carrinho = context.watch<CarrinhoController>();

    return Scaffold(
      backgroundColor: AppTemaService.fundo,
      appBar: AppBar(
        title: Text('Meu Carrinho'),
        leading: widget.onVoltarInicio != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onVoltarInicio,
              )
            : null,
        backgroundColor: AppTemaService.primaria,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Salvar como lista de compras',
            onPressed: carrinho.itens.isEmpty
                ? null
                : () => salvarCarrinhoComoLista(context),
            icon: Icon(Icons.playlist_add_check_rounded),
          ),
          IconButton(
            tooltip: 'Atualizar preços',
            onPressed: carrinho.atualizandoProdutos
                ? null
                : () => atualizarCarrinhoManual(context),
            icon: Icon(Icons.refresh),
          ),
        ],
      ),
      body: carrinho.itens.isEmpty
          ? Center(
              child: Text(
                'Seu carrinho está vazio',
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
            )
          : Column(
              children: [
                if (carrinho.atualizandoProdutos)
                  LinearProgressIndicator(
                    minHeight: 3,
                    color: AppTemaService.primaria,
                    backgroundColor: AppTemaService.primaria.withValues(
                      alpha: 0.12,
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    color: AppTemaService.primaria,
                    onRefresh: () => atualizarCarrinhoManual(context),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      itemCount: carrinho.itens.length,
                      itemBuilder: (context, index) {
                        final item = carrinho.itens[index];
                        final produto = item.produto;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: AppTemaService.primaria.withValues(
                                alpha: 0.16,
                              ),
                              width: 1.6,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTemaService.primaria.withValues(
                                  alpha: 0.08,
                                ),
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
                                  color: AppTemaService.primaria.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: imagemCarrinho(produto),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      produto.nome,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Color(0xFF424242),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        height: 1.2,
                                      ),
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      item.textoPrecoQuantidade,
                                      style: TextStyle(
                                        color: Colors.black54,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (produto.ehKg &&
                                        produto.pesoVariavel) ...[
                                      SizedBox(height: 3),
                                      Text(
                                        'Valor estimado pelo peso médio',
                                        style: TextStyle(
                                          color: Colors.black45,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                    SizedBox(height: 4),
                                    Text(
                                      'Total: ${formatarMoeda(item.total)}',
                                      style: TextStyle(
                                        color: AppTemaService.primaria,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    avisoProblemaEstoque(item),
                                  ],
                                ),
                              ),
                              SizedBox(width: 8),
                              Column(
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      botaoQuantidade(
                                        icon: Icons.remove_circle,
                                        cor: Colors.red,
                                        onTap: item.quantidade <= 1
                                            ? null
                                            : () {
                                                context
                                                    .read<CarrinhoController>()
                                                    .diminuirQuantidade(
                                                      produto,
                                                    );
                                              },
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        child: Text(
                                          item.textoQuantidadeCurto,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      botaoQuantidade(
                                        icon: Icons.add_circle,
                                        cor: Colors.green,
                                        onTap: () {
                                          tentarAumentarQuantidade(
                                            context,
                                            produto,
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 10),
                                  InkWell(
                                    onTap: () {
                                      confirmarRemocao(context, produto);
                                    },
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: AppTemaService.primaria
                                            .withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Icon(
                                        Icons.delete_outline,
                                        color: AppTemaService.primaria,
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
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(22),
                      topRight: Radius.circular(22),
                    ),
                    border: Border.all(
                      color: AppTemaService.primaria.withValues(alpha: 0.16),
                      width: 1.6,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTemaService.primaria.withValues(alpha: 0.08),
                        blurRadius: 14,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total do pedido',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              formatarMoeda(carrinho.valorTotal),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppTemaService.primaria,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton.icon(
                            icon: Icon(Icons.playlist_add_check_rounded),
                            label: Text(
                              'Salvar como lista de compras',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTemaService.primaria,
                              side: BorderSide(
                                color: AppTemaService.primaria.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            onPressed: carrinho.atualizandoProdutos
                                ? null
                                : () => salvarCarrinhoComoLista(context),
                          ),
                        ),
                        SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.check_circle),
                            label: Text(
                              carrinho.atualizandoProdutos
                                  ? 'Atualizando Carrinho...'
                                  : 'Finalizar Pedido',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTemaService.primaria,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            onPressed: carrinho.atualizandoProdutos
                                ? null
                                : () => abrirFinalizarPedido(context),
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
}

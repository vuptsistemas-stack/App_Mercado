import 'dart:io';

import 'package:excel/excel.dart' as ex;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/central_service.dart';
import '../../services/lista_compras_service.dart';
import '../../services/sessao_loja.dart';

class ListaComprasPage extends StatefulWidget {
  const ListaComprasPage({super.key});

  @override
  State<ListaComprasPage> createState() => _ListaComprasPageState();
}

class _ListaComprasPageState extends State<ListaComprasPage> {
  final service = ListaComprasService();

  Map<String, dynamic>? listaAtiva;
  List<Map<String, dynamic>> itens = [];
  bool carregando = true;
  bool exportando = false;
  bool criandoLista = false;
  String? itemCarregandoId;
  String? erroCarregamento;

  Color get cor => SessaoLoja.corPrimaria;
  Color get fundo => SessaoLoja.corFundo;

  @override
  void initState() {
    super.initState();
    carregar();
  }

  String texto(dynamic valor, {String fallback = ''}) {
    final convertido = valor?.toString().trim() ?? '';
    return convertido.isEmpty || convertido.toLowerCase() == 'null'
        ? fallback
        : convertido;
  }

  double numero(dynamic valor) {
    if (valor is num) return valor.toDouble();
    var convertido = texto(valor).replaceAll('R\$', '').replaceAll(' ', '');
    if (convertido.contains(',')) {
      convertido = convertido.replaceAll('.', '').replaceAll(',', '.');
    }
    return double.tryParse(convertido) ?? 0;
  }

  String quantidade(dynamic valor) {
    final numeroValor = numero(valor);
    if (numeroValor == numeroValor.roundToDouble()) {
      return numeroValor.toInt().toString();
    }
    return numeroValor
        .toStringAsFixed(3)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  String moeda(dynamic valor) {
    return 'R\$ ${numero(valor).toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String dataBr(dynamic valor) {
    final data = DateTime.tryParse(texto(valor));
    if (data == null) return '-';
    final local = data.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  bool itemPronto(Map<String, dynamic> item) {
    return texto(item['fornecedor_selecionado']).isNotEmpty &&
        numero(item['quantidade_pedida']) > 0;
  }

  int get totalProntos => itens.where(itemPronto).length;
  bool get todosProntos => itens.isNotEmpty && totalProntos == itens.length;

  Future<void> carregar() async {
    if (mounted) {
      setState(() {
        carregando = true;
        erroCarregamento = null;
      });
    }

    try {
      final lista = await service.carregarListaAtiva();
      final listaId = texto(lista?['id']);
      final novosItens = listaId.isEmpty
          ? <Map<String, dynamic>>[]
          : await service.carregarItens(listaId);
      if (!mounted) return;
      setState(() {
        listaAtiva = lista;
        itens = novosItens;
        carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        carregando = false;
        erroCarregamento = CentralService.mensagemErroUsuario(e);
      });
    }
  }

  void mensagem(String mensagem, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? Colors.red.shade700 : cor,
      ),
    );
  }

  Future<void> criarNovaLista() async {
    if (criandoLista) return;

    setState(() => criandoLista = true);
    try {
      final resposta = await service.criarLista();
      await carregar();
      mensagem(
        resposta['criada'] == true
            ? 'Nova lista de compras criada.'
            : 'Já existe uma lista de compras ativa.',
      );
    } catch (e) {
      mensagem(
        'Erro ao criar lista: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    } finally {
      if (mounted) setState(() => criandoLista = false);
    }
  }

  List<Map<String, dynamic>> comprasDoResumo(Map<String, dynamic> resumo) {
    final compras = resumo['compras_recentes'];
    if (compras is! List) return [];
    return compras
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .take(2)
        .toList();
  }

  List<Map<String, dynamic>> opcoesFornecedores(
    List<Map<String, dynamic>> compras,
  ) {
    final nomes = <String>{};
    final resultado = <Map<String, dynamic>>[];
    for (final compra in compras) {
      final fornecedor = texto(compra['fornecedor']);
      final chave = fornecedor.toLowerCase();
      if (fornecedor.isEmpty || nomes.contains(chave)) continue;
      nomes.add(chave);
      resultado.add(compra);
    }
    return resultado;
  }

  Future<void> abrirItem(Map<String, dynamic> item) async {
    final itemId = texto(item['id']);
    final ean = texto(item['ean']);
    if (itemId.isEmpty || ean.isEmpty || itemCarregandoId != null) return;

    setState(() => itemCarregandoId = itemId);
    try {
      final resumo = await service.buscarResumoProduto(ean);
      if (!mounted) return;
      final configuracao = await mostrarConfiguracao(item, resumo);
      if (configuracao == null) return;

      await service.configurarItem(
        itemId: itemId,
        fornecedor: configuracao.fornecedor,
        precoReferencia: configuracao.precoReferencia,
        quantidadePedida: configuracao.quantidade,
        estoqueAtual: configuracao.estoqueAtual,
        vendas30Dias: configuracao.vendas30Dias,
        comprasRecentes: configuracao.compras,
      );
      await carregar();
      mensagem('Item preparado para compra.');
    } catch (e) {
      mensagem(
        'Nao foi possivel abrir o item: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    } finally {
      if (mounted) setState(() => itemCarregandoId = null);
    }
  }

  Future<_ConfiguracaoCompra?> mostrarConfiguracao(
    Map<String, dynamic> item,
    Map<String, dynamic> resumo,
  ) async {
    final compras = comprasDoResumo(resumo);
    final opcoes = opcoesFornecedores(compras);
    final estoque = numero(resumo['estoque_atual']);
    final vendas = numero(resumo['qtd_vendida_30_dias']);
    final quantidadeInicial = numero(item['quantidade_pedida']);
    final controller = TextEditingController(
      text: quantidadeInicial > 0 ? quantidade(quantidadeInicial) : '',
    );
    var fornecedorSelecionado = texto(item['fornecedor_selecionado']);
    if (!opcoes.any(
      (opcao) =>
          texto(opcao['fornecedor']).toLowerCase() ==
          fornecedorSelecionado.toLowerCase(),
    )) {
      fornecedorSelecionado = '';
    }

    final resultado = await showModalBottomSheet<_ConfiguracaoCompra>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final compraSelecionada = opcoes
                .cast<Map<String, dynamic>?>()
                .firstWhere(
                  (opcao) =>
                      texto(opcao?['fornecedor']).toLowerCase() ==
                      fornecedorSelecionado.toLowerCase(),
                  orElse: () => null,
                );
            final quantidadeDigitada = numero(controller.text);
            final podeSalvar =
                fornecedorSelecionado.isNotEmpty && quantidadeDigitada > 0;

            return SafeArea(
              top: false,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.92,
                ),
                padding: EdgeInsets.fromLTRB(
                  18,
                  10,
                  18,
                  18 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              texto(item['nome_produto'], fallback: 'Produto'),
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF172033),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Fechar',
                            onPressed: () => Navigator.pop(modalContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      Text(
                        'EAN ${texto(item['ean'], fallback: '-')}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _MetricaCompra(
                              titulo: 'Estoque atual',
                              valor: quantidade(estoque),
                              icone: Icons.inventory_2_outlined,
                              cor: cor,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _MetricaCompra(
                              titulo: 'Vendido em 30 dias',
                              valor: quantidade(vendas),
                              icone: Icons.trending_up,
                              cor: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Duas ultimas compras',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF172033),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (compras.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.25),
                            ),
                          ),
                          child: const Text(
                            'Nenhuma compra anterior encontrada para este produto.',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        )
                      else
                        ...compras.map(
                          (compra) => Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F8FB),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        texto(
                                          compra['fornecedor'],
                                          fallback:
                                              'Fornecedor nao identificado',
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${dataBr(compra['data_compra'])}  |  Qtd. ${quantidade(compra['quantidade'])}',
                                        style: const TextStyle(
                                          color: Colors.black54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  moeda(compra['preco_custo']),
                                  style: TextStyle(
                                    color: cor,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      const Text(
                        'Fornecedor escolhido',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF172033),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...opcoes.map((opcao) {
                        final fornecedor = texto(opcao['fornecedor']);
                        final selecionado =
                            fornecedor.toLowerCase() ==
                            fornecedorSelecionado.toLowerCase();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Material(
                            color: selecionado
                                ? cor.withValues(alpha: 0.08)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => setModalState(
                                () => fornecedorSelecionado = fornecedor,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: selecionado
                                        ? cor
                                        : const Color(0xFFD1D5DB),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      selecionado
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off,
                                      color: selecionado ? cor : Colors.black45,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        fornecedor,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      moeda(opcao['preco_custo']),
                                      style: TextStyle(
                                        color: cor,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 10),
                      TextField(
                        controller: controller,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setModalState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Quantidade a pedir',
                          prefixIcon: Icon(Icons.add_shopping_cart),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: podeSalvar
                              ? () => Navigator.pop(
                                  modalContext,
                                  _ConfiguracaoCompra(
                                    fornecedor: fornecedorSelecionado,
                                    precoReferencia: numero(
                                      compraSelecionada?['preco_custo'],
                                    ),
                                    quantidade: quantidadeDigitada,
                                    estoqueAtual: estoque,
                                    vendas30Dias: vendas,
                                    compras: compras,
                                  ),
                                )
                              : null,
                          icon: const Icon(Icons.check),
                          label: const Text('Salvar item'),
                          style: FilledButton.styleFrom(
                            backgroundColor: cor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    controller.dispose();
    return resultado;
  }

  Future<void> removerItem(Map<String, dynamic> item) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover item?'),
        content: Text(texto(item['nome_produto'], fallback: 'Este produto')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;
    try {
      await service.removerItem(texto(item['id']));
      await carregar();
      mensagem('Item removido da lista.');
    } catch (e) {
      mensagem(CentralService.mensagemErroUsuario(e), erro: true);
    }
  }

  List<ex.CellValue> linhaExcel(List<dynamic> valores) {
    return valores.map<ex.CellValue>((valor) {
      if (valor is int) return ex.IntCellValue(valor);
      if (valor is num) return ex.DoubleCellValue(valor.toDouble());
      return ex.TextCellValue(texto(valor));
    }).toList();
  }

  String nomeAba(String fornecedor, Set<String> usados) {
    var base = fornecedor.replaceAll(RegExp(r'[\\/*?:\[\]]'), ' ').trim();
    base = base.replaceAll(RegExp(r'\s+'), ' ');
    if (base.isEmpty) base = 'Fornecedor';
    if (base.length > 31) base = base.substring(0, 31).trim();
    var candidato = base;
    var contador = 2;
    while (usados.contains(candidato.toLowerCase())) {
      final sufixo = ' $contador';
      final limite = 31 - sufixo.length;
      candidato =
          '${base.substring(0, base.length > limite ? limite : base.length).trim()}$sufixo';
      contador++;
    }
    usados.add(candidato.toLowerCase());
    return candidato;
  }

  Map<String, dynamic>? compraHistorico(Map<String, dynamic> item, int indice) {
    final compras = item['compras_recentes'];
    if (compras is! List ||
        compras.length <= indice ||
        compras[indice] is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(compras[indice] as Map);
  }

  Future<void> exportarExcel() async {
    final listaId = texto(listaAtiva?['id']);
    if (!todosProntos || listaId.isEmpty || exportando) return;
    setState(() => exportando = true);

    try {
      final excel = ex.Excel.createExcel();
      final resumo = excel['Resumo'];
      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

      const cabecalho = [
        'Fornecedor',
        'Produto',
        'EAN',
        'Unidade',
        'Estoque atual',
        'Vendido 30 dias',
        'Quantidade pedida',
        'Preco referencia',
        'Total estimado',
        'Compra anterior 1',
        'Compra anterior 2',
      ];
      resumo.appendRow(linhaExcel(cabecalho));

      final porFornecedor = <String, List<Map<String, dynamic>>>{};
      for (final item in itens) {
        final fornecedor = texto(item['fornecedor_selecionado']);
        porFornecedor.putIfAbsent(fornecedor, () => []).add(item);
        final compra1 = compraHistorico(item, 0);
        final compra2 = compraHistorico(item, 1);
        final preco = numero(item['preco_referencia']);
        final pedido = numero(item['quantidade_pedida']);
        resumo.appendRow(
          linhaExcel([
            fornecedor,
            item['nome_produto'],
            item['ean'],
            item['unidade'],
            numero(item['estoque_snapshot']),
            numero(item['vendas_30_dias_snapshot']),
            pedido,
            preco,
            pedido * preco,
            compra1 == null
                ? ''
                : '${texto(compra1['fornecedor'])} | ${dataBr(compra1['data_compra'])} | ${moeda(compra1['preco_custo'])}',
            compra2 == null
                ? ''
                : '${texto(compra2['fornecedor'])} | ${dataBr(compra2['data_compra'])} | ${moeda(compra2['preco_custo'])}',
          ]),
        );
      }

      final abasUsadas = <String>{'resumo'};
      for (final entrada in porFornecedor.entries) {
        final aba = excel[nomeAba(entrada.key, abasUsadas)];
        aba.appendRow(
          linhaExcel([
            'Produto',
            'EAN',
            'Unidade',
            'Estoque atual',
            'Vendido 30 dias',
            'Quantidade pedida',
            'Preco referencia',
            'Total estimado',
          ]),
        );
        for (final item in entrada.value) {
          final preco = numero(item['preco_referencia']);
          final pedido = numero(item['quantidade_pedida']);
          aba.appendRow(
            linhaExcel([
              item['nome_produto'],
              item['ean'],
              item['unidade'],
              numero(item['estoque_snapshot']),
              numero(item['vendas_30_dias_snapshot']),
              pedido,
              preco,
              pedido * preco,
            ]),
          );
        }
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Nao foi possivel gerar o Excel.');
      final dir = await getTemporaryDirectory();
      final agora = DateTime.now();
      final nomeArquivo =
          'lista_compras_${SessaoLoja.mercadoCodigoObrigatorio}_${agora.year}${agora.month.toString().padLeft(2, '0')}${agora.day.toString().padLeft(2, '0')}_${agora.hour.toString().padLeft(2, '0')}${agora.minute.toString().padLeft(2, '0')}.xlsx';
      final arquivo = File('${dir.path}/$nomeArquivo');
      await arquivo.writeAsBytes(bytes);
      await service.registrarExportacao(
        listaId: listaId,
        arquivoNome: nomeArquivo,
      );

      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          text: 'Lista de compras - ${SessaoLoja.mercadoNome ?? 'Loja'}',
          files: [XFile(arquivo.path)],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );

      if (!mounted) return;
      final finalizar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Finalizar lista?'),
          content: const Text(
            'Ao finalizar, a proxima inclusao criara uma nova lista de compras.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Continuar editando'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Finalizar'),
            ),
          ],
        ),
      );
      if (finalizar == true) {
        await service.finalizarLista(listaId);
        await carregar();
        mensagem('Lista finalizada.');
      } else {
        await carregar();
      }
    } catch (e) {
      mensagem(
        'Erro ao gerar Excel: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    } finally {
      if (mounted) setState(() => exportando = false);
    }
  }

  Widget estadoSemLista() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.playlist_add,
              size: 70,
              color: cor.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 14),
            const Text(
              'Nenhuma lista ativa',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF172033),
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Crie uma lista para começar a organizar suas compras.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: criandoLista ? null : criarNovaLista,
              icon: criandoLista
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.playlist_add),
              label: Text(
                criandoLista ? 'Criando lista...' : 'Criar nova lista',
              ),
              style: FilledButton.styleFrom(backgroundColor: cor),
            ),
          ],
        ),
      ),
    );
  }

  Widget estadoListaSemItens() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 64,
              color: cor.withValues(alpha: 0.65),
            ),
            const SizedBox(height: 14),
            const Text(
              'Lista criada',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w900,
                color: Color(0xFF172033),
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Esta lista ainda não possui itens.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget cabecalhoLista() {
    final progresso = itens.isEmpty ? 0.0 : totalProntos / itens.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.shopping_cart_checkout, color: cor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${itens.length} ${itens.length == 1 ? 'item' : 'itens'}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '$totalProntos de ${itens.length} preparados',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progresso,
              minHeight: 7,
              backgroundColor: cor.withValues(alpha: 0.10),
              valueColor: AlwaysStoppedAnimation(cor),
            ),
          ),
        ],
      ),
    );
  }

  Widget itemLista(Map<String, dynamic> item) {
    final pronto = itemPronto(item);
    final carregandoItem = itemCarregandoId == texto(item['id']);
    final compras = [
      compraHistorico(item, 0),
      compraHistorico(item, 1),
    ].whereType<Map<String, dynamic>>().toList();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: carregandoItem ? null : () => abrirItem(item),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: pronto
                  ? Colors.green.withValues(alpha: 0.34)
                  : const Color(0xFFE5E7EB),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: pronto
                      ? Colors.green.withValues(alpha: 0.10)
                      : cor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: carregandoItem
                    ? Padding(
                        padding: const EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cor,
                        ),
                      )
                    : Icon(
                        pronto ? Icons.check : Icons.inventory_2_outlined,
                        color: pronto ? Colors.green.shade700 : cor,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      texto(item['nome_produto'], fallback: 'Produto'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF172033),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pronto
                          ? '${texto(item['fornecedor_selecionado'])}  |  Pedir ${quantidade(item['quantidade_pedida'])}'
                          : 'Selecionar fornecedor e quantidade',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: pronto ? Colors.green.shade800 : Colors.black54,
                        fontSize: 12.5,
                        fontWeight: pronto ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (compras.isEmpty)
                      const Text(
                        'Toque para consultar as ultimas compras',
                        style: TextStyle(color: Colors.black45, fontSize: 11.5),
                      )
                    else
                      ...compras.asMap().entries.map((entrada) {
                        final compra = entrada.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '${entrada.key + 1}a compra: ${texto(compra['fornecedor'], fallback: 'Fornecedor')}  |  ${moeda(compra['preco_custo'])}  |  ${dataBr(compra['data_compra'])}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF4B5563),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }),
                    if (pronto) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Estoque ${quantidade(item['estoque_snapshot'])}  |  30 dias ${quantidade(item['vendas_30_dias_snapshot'])}  |  ${moeda(item['preco_referencia'])}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black45,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remover',
                onPressed: () => removerItem(item),
                icon: const Icon(Icons.delete_outline),
                color: Colors.red.shade600,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fundo,
      appBar: AppBar(
        title: const Text(
          'Lista de compras',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        backgroundColor: cor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: carregando ? null : carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: carregando
          ? Center(child: CircularProgressIndicator(color: cor))
          : erroCarregamento != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 58,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      erroCarregamento!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: carregar,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            )
          : listaAtiva == null
          ? estadoSemLista()
          : Column(
              children: [
                cabecalhoLista(),
                Expanded(
                  child: itens.isEmpty
                      ? estadoListaSemItens()
                      : RefreshIndicator(
                          onRefresh: carregar,
                          color: cor,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 116),
                            itemCount: itens.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 9),
                            itemBuilder: (_, index) => itemLista(itens[index]),
                          ),
                        ),
                ),
              ],
            ),
      bottomNavigationBar: listaAtiva != null && itens.isNotEmpty
          ? SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                ),
                child: FilledButton.icon(
                  onPressed: todosProntos && !exportando ? exportarExcel : null,
                  icon: exportando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.table_view_outlined),
                  label: Text(
                    exportando
                        ? 'Gerando planilha...'
                        : todosProntos
                        ? 'Gerar Excel por fornecedor'
                        : 'Prepare todos os itens ($totalProntos/${itens.length})',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: cor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _ConfiguracaoCompra {
  final String fornecedor;
  final double precoReferencia;
  final double quantidade;
  final double estoqueAtual;
  final double vendas30Dias;
  final List<Map<String, dynamic>> compras;

  const _ConfiguracaoCompra({
    required this.fornecedor,
    required this.precoReferencia,
    required this.quantidade,
    required this.estoqueAtual,
    required this.vendas30Dias,
    required this.compras,
  });
}

class _MetricaCompra extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icone;
  final Color cor;

  const _MetricaCompra({
    required this.titulo,
    required this.valor,
    required this.icone,
    required this.cor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 20, color: cor),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: cor,
            ),
          ),
          Text(
            titulo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

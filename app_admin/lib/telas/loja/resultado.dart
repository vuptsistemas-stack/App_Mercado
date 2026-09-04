import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/central_service.dart';
import '../../services/preferencias_interface_service.dart';
import '../../services/sessao_loja.dart';
import 'produto_imagem_page.dart';
import 'scanner.dart';

class TelaResultado extends StatefulWidget {
  final dynamic produto;

  const TelaResultado({super.key, required this.produto});

  @override
  State<TelaResultado> createState() => _TelaResultadoState();
}

class _TelaResultadoState extends State<TelaResultado> {
  final centralService = CentralService();

  late Map<String, dynamic> produto;

  late DateTime dataInicio;
  late DateTime dataFim;

  int periodoSelecionado = 30;
  bool carregandoPeriodo = false;
  bool carregandoEstoqueDetalhado = false;
  bool alterandoPreco = false;
  LayoutConsultaItem layoutConsultaItem = LayoutConsultaItem.compacto;

  Color get corPrimaria => SessaoLoja.corPrimaria;
  Color get corSecundaria => SessaoLoja.corSecundaria;
  bool get mostrarEstoqueDetalhado =>
      SessaoLoja.estoqueDetalhadoAtivo && SessaoLoja.temApiConfigurada;
  bool get podeAlterarPreco =>
      SessaoLoja.alterarPrecoConsultaAtivo &&
      SessaoLoja.temApiConfigurada &&
      (!SessaoLoja.logadoNaLoja ||
          SessaoLoja.usuarioAdminLoja ||
          SessaoLoja.temPermissao('alterar_preco'));

  @override
  void initState() {
    super.initState();
    produto = Map<String, dynamic>.from(widget.produto);
    aplicarPeriodo(30);
    carregarLayoutConsultaItem();
  }

  Future<void> carregarLayoutConsultaItem() async {
    final layout =
        await PreferenciasInterfaceService.carregarLayoutConsultaItem();

    if (!mounted) return;

    setState(() {
      layoutConsultaItem = layout;
    });
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

  void aplicarPeriodo(int dias) {
    setState(() {
      periodoSelecionado = dias;
      dataFim = DateTime.now();
      dataInicio = dataFim.subtract(Duration(days: dias));
    });

    buscarQuantidadeVendida();
  }

  String dataApi(DateTime data) {
    return "${data.year}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}";
  }

  String dataBr(DateTime data) {
    return "${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}";
  }

  String dataBrApi(dynamic valor) {
    if (valor == null) return "-";

    try {
      final data = DateTime.parse(valor.toString());
      return dataBr(data);
    } catch (e) {
      return valor.toString();
    }
  }

  Future<void> buscarQuantidadeVendida() async {
    final baseUrl = apiBaseUrl;
    final ean = produto['ean_principal'];

    if (ean == null) return;

    if (baseUrl == null) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text("Nenhuma API configurada para esta loja."),
        ),
      );
      return;
    }

    setState(() {
      carregandoPeriodo = true;
      produto.remove('qtd_comprada_periodo');
      produto.remove('historico_compras');
    });

    try {
      final url = Uri.parse(
        "$baseUrl/produto/ean/$ean/quantidade-vendida"
        "?inicio=${dataApi(dataInicio)}"
        "&fim=${dataApi(dataFim)}",
      );

      final response = await http.get(url);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          produto.addAll(Map<String, dynamic>.from(data));
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Erro ao consultar quantidade vendida. HTTP: ${response.statusCode}",
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Erro de conexão ao consultar período"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          carregandoPeriodo = false;
        });
      }
    }
  }

  Future<void> selecionarPeriodo() async {
    final inicio = await showDatePicker(
      context: context,
      initialDate: dataInicio,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (inicio == null) return;

    if (!mounted) return;

    final fim = await showDatePicker(
      context: context,
      initialDate: dataFim,
      firstDate: inicio,
      lastDate: DateTime.now(),
    );

    if (fim == null) return;

    setState(() {
      periodoSelecionado = 0;
      dataInicio = inicio;
      dataFim = fim;
    });

    buscarQuantidadeVendida();
  }

  Future<void> escanearNovoProduto() async {
    final codigo = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerPage(
          onDetect: (codigo) {
            Navigator.pop(context, codigo);
          },
        ),
      ),
    );

    if (codigo != null && codigo.isNotEmpty) {
      if (!mounted) return;
      Navigator.pop(context, codigo);
    }
  }

  Future<void> abrirImagemProduto() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => ProdutoImagemPage(produto: produto)),
    );
  }

  Future<void> alterarPrecoProduto() async {
    if (alterandoPreco) return;

    final mercadoId = SessaoLoja.mercadoId?.trim();

    if (mercadoId == null || mercadoId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loja atual nao identificada.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!podeAlterarPreco) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alteracao de preco nao liberada para este usuario.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    var precoDigitado =
        precoVendaAtual()?.toStringAsFixed(2).replaceAll('.', ',') ?? '';

    final novoPrecoTexto = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Alterar preco'),
          content: TextFormField(
            initialValue: precoDigitado,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (valor) => precoDigitado = valor,
            onFieldSubmitted: (valor) {
              FocusScope.of(dialogContext).unfocus();
              Navigator.pop(dialogContext, valor.trim());
            },
            decoration: const InputDecoration(
              labelText: 'Novo preco de venda',
              prefixIcon: Icon(Icons.price_change_outlined),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusScope.of(dialogContext).unfocus();
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                FocusScope.of(dialogContext).unfocus();
                Navigator.pop(dialogContext, precoDigitado.trim());
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );

    if (novoPrecoTexto == null || novoPrecoTexto.trim().isEmpty) return;

    final novoPreco = numeroDecimal(novoPrecoTexto);

    if (novoPreco == null || novoPreco <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe um preco valido.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => alterandoPreco = true);

    try {
      await centralService.alterarPrecoProdutoApi(
        mercadoId: mercadoId,
        mercadoCodigo: SessaoLoja.mercadoCodigo,
        produto: {
          'produto_id': texto(produto['produto_id'], fallback: ''),
          'ean': eanProduto(),
          'codigo_barras': texto(produto['codigo_barras'], fallback: ''),
          'nome_produto': texto(produto['nome_produto'], fallback: ''),
        },
        preco: novoPreco,
      );

      if (!mounted) return;

      final precoTexto = novoPreco.toStringAsFixed(2);

      setState(() {
        produto['preco_venda'] = precoTexto;
        produto['preco'] = precoTexto;
        produto['valor_venda'] = precoTexto;
        produto['preco_atual'] = precoTexto;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Preco alterado na API da loja.'),
          backgroundColor: corPrimaria,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao alterar preco: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => alterandoPreco = false);
      }
    }
  }

  String valorTotalVendido() {
    return "${produto['qtd_vendida_periodo'] ?? produto['total_vendido'] ?? produto['quantidade_vendida'] ?? produto['quantidade'] ?? 0}";
  }

  double quantidadeVendidaPeriodo() {
    return numeroDecimal(
          produto['qtd_vendida_periodo'] ??
              produto['total_vendido'] ??
              produto['quantidade_vendida'] ??
              produto['quantidade'],
        ) ??
        0;
  }

  double estoqueAtual() {
    return numeroDecimal(produto['estoque_atual']) ?? 0;
  }

  double quantidadeSugeridaCompra() {
    final necessidade = quantidadeVendidaPeriodo() - estoqueAtual();
    return necessidade > 0 ? necessidade : 0;
  }

  int diasDoPeriodo() {
    final dias = dataFim.difference(dataInicio).inDays;
    return dias > 0 ? dias : 1;
  }

  Widget sugestaoCompra() {
    final vendido = quantidadeVendidaPeriodo();
    final estoque = estoqueAtual();
    final sugestao = quantidadeSugeridaCompra();
    final unidade = texto(produto['sigla_saida'], fallback: 'UN');
    final precisaComprar = sugestao > 0;
    final semHistorico = vendido <= 0;
    final cor = precisaComprar
        ? const Color(0xFFD97706)
        : const Color(0xFF15803D);

    final mensagem = semHistorico
        ? 'Não houve venda no período selecionado. Não é necessário comprar com base neste histórico.'
        : precisaComprar
        ? 'Sugestão: comprar ${quantidade(sugestao)} $unidade para cobrir outro período semelhante de ${diasDoPeriodo()} dias.'
        : 'O estoque atual cobre outro período semelhante de ${diasDoPeriodo()} dias. Não precisa comprar.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        border: Border.all(color: cor.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              precisaComprar
                  ? Icons.add_shopping_cart_rounded
                  : Icons.inventory_outlined,
              color: cor,
              size: 21,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sugestão de compra',
                  style: TextStyle(
                    color: cor,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  carregandoPeriodo ? 'Calculando pelo período...' : mensagem,
                  style: const TextStyle(
                    color: Color(0xFF374151),
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!carregandoPeriodo && !semHistorico) ...[
                  const SizedBox(height: 5),
                  Text(
                    'Vendido: ${quantidade(vendido)} $unidade  •  Estoque: ${quantidade(estoque)} $unidade',
                    style: TextStyle(
                      color: cor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String valorTotalComprado() {
    final qtdCompradaPeriodo =
        numeroDecimal(produto['qtd_comprada_periodo']) ?? 0;

    if (qtdCompradaPeriodo > 0) {
      return quantidade(qtdCompradaPeriodo);
    }

    final totalUltimaCompra = numeroDecimal(produto['total_comprado']) ?? 0;

    if (totalUltimaCompra > 0) {
      return quantidade(totalUltimaCompra);
    }

    final qteEmb = numeroDecimal(produto['qte_emb']) ?? 1;
    final qtdUltimaCompra = numeroDecimal(produto['qtd_ultima_compra']) ?? 0;

    if (qteEmb <= 1) {
      return quantidade(qtdUltimaCompra);
    }

    return quantidade(qteEmb * qtdUltimaCompra);
  }

  List<Map<String, dynamic>> historicoCompras() {
    final historico = produto['historico_compras'];

    if (historico is! List) {
      return const [];
    }

    return historico
        .whereType<Map>()
        .map((compra) => Map<String, dynamic>.from(compra))
        .toList();
  }

  String valorMonetario(dynamic valor) {
    final numero = numeroDecimal(valor);

    if (numero == null) {
      return '-';
    }

    return 'R\$ ${numero.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  Widget historicoComprasTabela() {
    final compras = historicoCompras();

    if (carregandoPeriodo) {
      return Container(
        width: double.infinity,
        height: 92,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: corPrimaria.withValues(alpha: 0.18)),
        ),
        child: CircularProgressIndicator(strokeWidth: 2, color: corPrimaria),
      );
    }

    if (compras.isEmpty) {
      return caixa(
        children: [
          linha(
            'Fornecedor',
            texto(produto['fornecedor']),
            icone: Icons.local_shipping_outlined,
          ),
          const Divider(height: 1),
          linha(
            'Última compra',
            dataBrApi(produto['data_ultima_compra']),
            icone: Icons.calendar_today_outlined,
          ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: corPrimaria.withValues(alpha: 0.22)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: corPrimaria,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: const Text(
                'HISTÓRICO DE COMPRAS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Container(
              color: corPrimaria.withValues(alpha: 0.90),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: const Row(
                children: [
                  Expanded(
                    child: Text(
                      'ÚLT. COMPRA',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    'PREÇO',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            for (var indice = 0; indice < compras.length; indice++) ...[
              Container(
                color: corPrimaria.withValues(alpha: 0.10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Text(
                  texto(
                    compras[indice]['fornecedor'] ??
                        compras[indice]['historico'] ??
                        produto['fornecedor'],
                  ).toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF172033),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        dataBrApi(compras[indice]['data_compra']),
                        style: const TextStyle(
                          color: Color(0xFF1F2937),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      valorMonetario(compras[indice]['preco_custo']),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Color(0xFF172033),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              if (indice < compras.length - 1)
                Divider(height: 1, color: corPrimaria.withValues(alpha: 0.12)),
            ],
          ],
        ),
      ),
    );
  }

  String texto(dynamic valor, {String fallback = '-'}) {
    final convertido = valor?.toString().trim() ?? '';

    return convertido.isEmpty || convertido.toLowerCase() == 'null'
        ? fallback
        : convertido;
  }

  double? numeroDecimal(dynamic valor) {
    var convertido = texto(
      valor,
      fallback: '',
    ).replaceAll('R\$', '').replaceAll(' ', '').trim();

    if (convertido.isEmpty) {
      return null;
    }

    if (convertido.contains(',')) {
      convertido = convertido.replaceAll('.', '').replaceAll(',', '.');
    }

    return double.tryParse(convertido);
  }

  double? precoVendaAtual() {
    return numeroDecimal(
      produto['preco_venda'] ??
          produto['preco'] ??
          produto['valor_venda'] ??
          produto['preco_atual'],
    );
  }

  String eanProduto() {
    return texto(
      produto['ean_principal'] ??
          produto['ean'] ??
          produto['codigo_barras'] ??
          produto['codigo'],
      fallback: '',
    );
  }

  String quantidade(dynamic valor) {
    final numero = double.tryParse(
      valor?.toString().replaceAll(',', '.').trim() ?? '',
    );

    if (numero == null) {
      return texto(valor, fallback: '0');
    }

    if (numero == numero.roundToDouble()) {
      return numero.toInt().toString();
    }

    var convertido = numero.toStringAsFixed(3).replaceAll('.', ',');

    while (convertido.endsWith('0')) {
      convertido = convertido.substring(0, convertido.length - 1);
    }

    if (convertido.endsWith(',')) {
      convertido = convertido.substring(0, convertido.length - 1);
    }

    return convertido;
  }

  bool booleanoDinamico(dynamic valor, {bool padrao = true}) {
    if (valor == true) return true;
    if (valor == false) return false;
    if (valor is num) return valor == 1;

    final texto = valor?.toString().trim().toLowerCase() ?? '';

    if (texto == 'true' || texto == '1' || texto == 'sim' || texto == 's') {
      return true;
    }

    if (texto == 'false' ||
        texto == '0' ||
        texto == 'nao' ||
        texto == 'nÃ£o' ||
        texto == 'n') {
      return false;
    }

    return padrao;
  }

  bool localConsideradoNoApp(Map<String, dynamic> local) {
    return booleanoDinamico(local['considerado_no_app'], padrao: true);
  }

  Future<void> consultarEstoqueDetalhado() async {
    final baseUrl = apiBaseUrl;
    final ean = eanProduto();

    if (ean.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Produto sem EAN para consultar estoque detalhado.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (baseUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma API configurada para esta loja.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      carregandoEstoqueDetalhado = true;
    });

    try {
      final url = Uri.parse(
        '$baseUrl/produto/ean/${Uri.encodeComponent(ean)}/estoque-locais',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 20));

      if (!mounted) return;

      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao consultar estoque detalhado. HTTP: ${response.statusCode}',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final data = jsonDecode(response.body);

      if (data is! Map) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Resposta inválida ao consultar estoque detalhado.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      exibirEstoqueDetalhado(Map<String, dynamic>.from(data));
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro de conexão ao consultar estoque detalhado.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          carregandoEstoqueDetalhado = false;
        });
      }
    }
  }

  void exibirEstoqueDetalhado(Map<String, dynamic> data) {
    final locais = data['locais'] is List
        ? List<Map<String, dynamic>>.from(
            (data['locais'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .where(localConsideradoNoApp),
          )
        : <Map<String, dynamic>>[];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.36,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: SafeArea(
                top: false,
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: corPrimaria.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.inventory_2_outlined,
                            color: corPrimaria,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Estoque detalhado',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF172033),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                texto(data['nome_produto']),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        metricaEstoqueDetalhado(
                          titulo: 'Considerado no app',
                          valor: quantidade(data['estoque_total_app']),
                          icone: Icons.mobile_friendly_outlined,
                          cor: const Color(0xFF059669),
                        ),
                        const SizedBox(width: 8),
                        metricaEstoqueDetalhado(
                          titulo: 'Total geral',
                          valor: quantidade(data['estoque_total_geral']),
                          icone: Icons.warehouse_outlined,
                          cor: corPrimaria,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (locais.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'Nenhum local de estoque considerado no app foi retornado pela API.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54),
                          ),
                        ),
                      )
                    else
                      ...locais.map(cardLocalEstoque),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget metricaEstoqueDetalhado({
    required String titulo,
    required String valor,
    required IconData icone,
    required Color cor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(cor.withValues(alpha: 0.08), Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cor.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Icon(icone, color: cor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    valor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF172033),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    titulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      height: 1.05,
                      color: Colors.black54,
                      fontWeight: FontWeight.w700,
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

  Widget cardLocalEstoque(Map<String, dynamic> local) {
    const corStatus = Color(0xFF059669);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: corStatus.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: corStatus.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.store_outlined, color: corStatus, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  texto(local['nome_local_estoque'], fallback: 'Local'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF172033),
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Considerado no app',
                  style: TextStyle(
                    fontSize: 11,
                    color: corStatus,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            quantidade(local['quantidade']),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF172033),
            ),
          ),
        ],
      ),
    );
  }

  String valorMargem() {
    if (produto['margem_lucro1'] == null) return "-";

    final margem = double.tryParse(produto['margem_lucro1'].toString());

    if (margem == null) return "-";

    return "${margem.toStringAsFixed(2).replaceAll('.', ',')}%";
  }

  Widget linha(String titulo, String valor, {required IconData icone}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: corPrimaria.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icone, size: 17, color: corPrimaria),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 86,
            child: Text(
              titulo,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  valor,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFF1F2937),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget caixa({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: corPrimaria.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget metrica({
    required String titulo,
    required String valor,
    required IconData icone,
    Color? cor,
    bool carregando = false,
    bool compacto = true,
  }) {
    final destaque = cor ?? corPrimaria;

    return Container(
      width: double.infinity,
      height: compacto ? 78 : 88,
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 3 : 10,
        vertical: compacto ? 6 : 9,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(destaque.withValues(alpha: 0.07), Colors.white),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: destaque.withValues(alpha: 0.28)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: compacto ? 25 : 30,
            height: compacto ? 25 : 30,
            decoration: BoxDecoration(
              color: destaque.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icone, color: destaque, size: compacto ? 15 : 18),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: compacto ? 15 : 18,
            child: carregando
                ? Center(
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: destaque,
                      ),
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      valor,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: compacto ? 11 : 14,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF172033),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: compacto ? 11 : 14,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                titulo,
                maxLines: 1,
                style: TextStyle(
                  fontSize: compacto ? 8.5 : 10.5,
                  color: Colors.black54,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget tituloSecao(String titulo, {String? subtitulo}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: Color(0xFF172033),
          ),
        ),
        if (subtitulo != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitulo,
            style: const TextStyle(fontSize: 11.5, color: Colors.black54),
          ),
        ],
      ],
    );
  }

  Widget botaoPeriodo(int dias) {
    final selecionado = periodoSelecionado == dias;

    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: selecionado
              ? corPrimaria
              : corPrimaria.withValues(alpha: 0.06),
          foregroundColor: selecionado ? Colors.white : corPrimaria,
          side: BorderSide(color: corPrimaria.withValues(alpha: 0.45)),
          padding: const EdgeInsets.symmetric(vertical: 9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: () => aplicarPeriodo(dias),
        child: Text(
          "$dias dias",
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget painelMetricas(dynamic estoque) {
    final metricasRaioX = [
      metrica(
        titulo: layoutConsultaItem == LayoutConsultaItem.compacto
            ? 'Compra'
            : 'Preço de compra',
        valor: "R\$ ${produto['custo_liquido'] ?? 0}",
        icone: Icons.shopping_cart_checkout,
        compacto: layoutConsultaItem == LayoutConsultaItem.compacto,
      ),
      metrica(
        titulo: layoutConsultaItem == LayoutConsultaItem.compacto
            ? 'Venda'
            : 'Preço de venda',
        valor: "R\$ ${produto['preco_venda'] ?? 0}",
        icone: Icons.sell_outlined,
        cor: const Color(0xFF059669),
        compacto: layoutConsultaItem == LayoutConsultaItem.compacto,
      ),
      metrica(
        titulo: 'Margem',
        valor: valorMargem(),
        icone: Icons.percent,
        cor: const Color(0xFFF59E0B),
        compacto: layoutConsultaItem == LayoutConsultaItem.compacto,
      ),
    ];
    final metricasPeriodo = [
      metrica(
        titulo: layoutConsultaItem == LayoutConsultaItem.compacto
            ? 'Estoque'
            : 'Estoque atual',
        valor: '$estoque',
        icone: Icons.inventory_2_outlined,
        cor: const Color(0xFF0F766E),
        compacto: layoutConsultaItem == LayoutConsultaItem.compacto,
      ),
      metrica(
        titulo: layoutConsultaItem == LayoutConsultaItem.compacto
            ? 'Comprado'
            : 'Total comprado',
        valor: valorTotalComprado(),
        icone: Icons.move_to_inbox_outlined,
        carregando: carregandoPeriodo,
        compacto: layoutConsultaItem == LayoutConsultaItem.compacto,
      ),
      metrica(
        titulo: layoutConsultaItem == LayoutConsultaItem.compacto
            ? 'Vendido'
            : 'Total vendido',
        valor: valorTotalVendido(),
        icone: Icons.bar_chart_rounded,
        cor: const Color(0xFF059669),
        carregando: carregandoPeriodo,
        compacto: layoutConsultaItem == LayoutConsultaItem.compacto,
      ),
    ];

    final cabecalhos = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: tituloSecao(
            layoutConsultaItem == LayoutConsultaItem.compacto
                ? 'Raio-X'
                : 'Raio-X do produto',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: tituloSecao(
            layoutConsultaItem == LayoutConsultaItem.compacto
                ? 'Mov. período'
                : 'Movimentação no período',
            subtitulo: '${dataBr(dataInicio)} até ${dataBr(dataFim)}',
          ),
        ),
      ],
    );

    if (layoutConsultaItem == LayoutConsultaItem.compacto) {
      return Column(
        children: [
          cabecalhos,
          const SizedBox(height: 8),
          Row(
            children: [
              for (var indice = 0; indice < metricasRaioX.length; indice++) ...[
                Expanded(child: metricasRaioX[indice]),
                if (indice < metricasRaioX.length - 1) const SizedBox(width: 3),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Container(
                  width: 1.5,
                  height: 66,
                  color: corPrimaria.withValues(alpha: 0.28),
                ),
              ),
              for (
                var indice = 0;
                indice < metricasPeriodo.length;
                indice++
              ) ...[
                Expanded(child: metricasPeriodo[indice]),
                if (indice < metricasPeriodo.length - 1)
                  const SizedBox(width: 3),
              ],
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tituloSecao('Raio-X do produto'),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var indice = 0; indice < metricasRaioX.length; indice++) ...[
              Expanded(child: metricasRaioX[indice]),
              if (indice < metricasRaioX.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 12),
        tituloSecao(
          'Movimentação no período',
          subtitulo: '${dataBr(dataInicio)} até ${dataBr(dataFim)}',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var indice = 0; indice < metricasPeriodo.length; indice++) ...[
              Expanded(child: metricasPeriodo[indice]),
              if (indice < metricasPeriodo.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final estoque = produto['estoque_atual'] ?? 0;
    final nomeLoja = SessaoLoja.mercadoNome ?? 'Loja';

    return Scaffold(
      backgroundColor: SessaoLoja.corFundo,
      appBar: AppBar(
        title: const Text(
          "Consultar Item",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        backgroundColor: corPrimaria,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [corPrimaria, corSecundaria],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: corPrimaria.withValues(alpha: 0.20),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.query_stats,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${produto['nome_produto'] ?? 'Produto'}",
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              height: 1.15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            "EAN ${produto['ean_principal'] ?? '-'} • $nomeLoja",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              painelMetricas(estoque),
              const SizedBox(height: 10),
              sugestaoCompra(),
              if (mostrarEstoqueDetalhado) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: carregandoEstoqueDetalhado
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.inventory_2_outlined, size: 19),
                    label: const Text(
                      'Estoque detalhado',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: corPrimaria,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: corPrimaria.withValues(
                        alpha: 0.70,
                      ),
                      disabledForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                    onPressed: carregandoEstoqueDetalhado
                        ? null
                        : consultarEstoqueDetalhado,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  botaoPeriodo(15),
                  const SizedBox(width: 8),
                  botaoPeriodo(30),
                  const SizedBox(width: 8),
                  botaoPeriodo(45),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_month_outlined, size: 19),
                  label: const Text("Escolher outro período"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: corPrimaria,
                    side: BorderSide(
                      color: corPrimaria.withValues(alpha: 0.45),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  onPressed: selecionarPeriodo,
                ),
              ),
              const SizedBox(height: 14),
              historicoComprasTabela(),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text(
                    "Escanear novo produto",
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: corPrimaria,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: escanearNovoProduto,
                ),
              ),
              const SizedBox(height: 10),
              if (podeAlterarPreco)
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.image_search_outlined),
                        label: const Text(
                          "Carregar imagem",
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: corPrimaria,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onPressed: abrirImagemProduto,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        icon: alterandoPreco
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.price_change_outlined),
                        label: Text(
                          alterandoPreco ? "Alterando..." : "Alterar preço",
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: corPrimaria,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onPressed: alterandoPreco ? null : alterarPrecoProduto,
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.image_search_outlined),
                    label: const Text(
                      "Carregar imagem",
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: corPrimaria,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: abrirImagemProduto,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

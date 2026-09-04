import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart' as ex;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/central_service.dart';
import '../../../services/sessao_loja.dart';

class EstoqueAuditoriaPage extends StatefulWidget {
  const EstoqueAuditoriaPage({super.key});

  @override
  State<EstoqueAuditoriaPage> createState() => _EstoqueAuditoriaPageState();
}

class _EstoqueAuditoriaPageState extends State<EstoqueAuditoriaPage> {
  final buscaController = TextEditingController();
  final scrollController = ScrollController();

  bool carregando = false;
  bool carregandoCustos = false;
  bool exportando = false;
  String? erro;
  String modoConsulta = 'tudo';
  String filtroTipo = 'TODOS';
  DateTime? dataInicio;
  DateTime? dataFim;
  List<Map<String, dynamic>> registros = [];

  static Color get cor => SessaoLoja.corPrimaria;
  static Color get fundo => SessaoLoja.corFundo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        consultarTudo();
      }
    });
  }

  @override
  void dispose() {
    buscaController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  String texto(dynamic valor, {String fallback = '-'}) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? fallback : texto;
  }

  double numero(dynamic valor) {
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  double numeroApi(dynamic valor) {
    if (valor == null) return 0;
    if (valor is num) return valor.toDouble();

    var textoValor = valor.toString().trim();
    if (textoValor.isEmpty) return 0;

    textoValor = textoValor.replaceAll('R\$', '').trim();
    if (textoValor.contains(',')) {
      textoValor = textoValor.replaceAll('.', '').replaceAll(',', '.');
    }

    return double.tryParse(textoValor) ?? 0;
  }

  String moeda(dynamic valor) {
    final n = numero(valor);
    return 'R\$ ${n.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String quantidade(dynamic valor) {
    final n = numero(valor);
    if (n == n.roundToDouble()) {
      return n.toStringAsFixed(0);
    }
    return n.toStringAsFixed(3).replaceAll('.', ',');
  }

  String dataHora(dynamic valor) {
    final data = DateTime.tryParse(valor?.toString() ?? '')?.toLocal();
    if (data == null) return '-';

    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final ano = data.year.toString();
    final hora = data.hour.toString().padLeft(2, '0');
    final minuto = data.minute.toString().padLeft(2, '0');
    return '$dia/$mes/$ano $hora:$minuto';
  }

  String dataIso(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final ano = data.year.toString().padLeft(4, '0');
    return '$ano-$mes-$dia';
  }

  String dataCurta(DateTime? data, String vazio) {
    if (data == null) return vazio;
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final ano = data.year.toString();
    return '$dia/$mes/$ano';
  }

  Future<void> escolherData({required bool inicio}) async {
    final agora = DateTime.now();
    final atual = inicio ? dataInicio : dataFim;
    final escolhida = await showDatePicker(
      context: context,
      initialDate: atual ?? agora,
      firstDate: DateTime(2020),
      lastDate: DateTime(agora.year + 1, 12, 31),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: cor),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (escolhida == null || !mounted) return;

    setState(() {
      if (inicio) {
        dataInicio = escolhida;
        if (dataFim != null && dataFim!.isBefore(escolhida)) {
          dataFim = escolhida;
        }
      } else {
        dataFim = escolhida;
        if (dataInicio != null && dataInicio!.isAfter(escolhida)) {
          dataInicio = escolhida;
        }
      }
    });
  }

  String limparBuscaSql(String valor) {
    return valor
        .trim()
        .replaceAll('%', '')
        .replaceAll(',', ' ')
        .replaceAll('(', ' ')
        .replaceAll(')', ' ');
  }

  String nomeTipo(Map<String, dynamic> item) {
    final tipo = texto(item['tipo_movimentacao']).toUpperCase();
    if (tipo == 'ENTRADA') return 'Entrada';
    if (tipo == 'CORRECAO') return 'Correção';
    if (tipo == 'CONSUMO_INTERNO') return 'Consumo interno';
    if (tipo == 'BAIXA_AVARIA') return 'Baixa avaria';
    if (tipo == 'BAIXA_VALIDADE') return 'Baixa validade';
    return tipo;
  }

  Color corTipo(Map<String, dynamic> item) {
    final tipo = texto(item['tipo_movimentacao']).toUpperCase();
    if (tipo == 'ENTRADA') return Colors.green;
    if (tipo == 'CORRECAO') return Colors.orange;
    if (tipo == 'CONSUMO_INTERNO') return Colors.deepPurple;
    if (tipo == 'BAIXA_AVARIA') return Colors.deepOrange;
    if (tipo == 'BAIXA_VALIDADE') return Colors.red;
    return Colors.blueGrey;
  }

  String localTexto(Map<String, dynamic> item) {
    final nome = texto(item['nome_local_estoque'], fallback: '');
    if (nome.isNotEmpty) return nome;

    final id = texto(
      item['local_estoqueid'] ?? item['local_estoque_id'],
      fallback: '',
    );
    return id.isEmpty ? 'Sem local detalhado' : 'Local $id';
  }

  String tipoMovimento(Map<String, dynamic> item) {
    return texto(item['tipo_movimentacao']).toUpperCase();
  }

  String apiBaseUrl() {
    final api = SessaoLoja.apiBaseUrl?.trim() ?? '';
    return api.replaceAll(RegExp(r'/+$'), '');
  }

  bool itemFiltroAtual(Map<String, dynamic> item) {
    return filtroTipo == 'TODOS' || tipoMovimento(item) == filtroTipo;
  }

  String nomeFiltroSelecionado() {
    if (filtroTipo == 'ENTRADA') return 'Entradas';
    if (filtroTipo == 'CORRECAO') return 'Correcoes';
    if (filtroTipo == 'CONSUMO_INTERNO') return 'Consumo';
    if (filtroTipo == 'BAIXA_AVARIA') return 'Avarias';
    if (filtroTipo == 'BAIXA_VALIDADE') return 'Validade';
    return 'Todos os registros';
  }

  List<Map<String, dynamic>> get registrosFiltrados {
    if (filtroTipo == 'TODOS') return registros;
    return registros
        .where((item) => tipoMovimento(item) == filtroTipo)
        .toList();
  }

  int totalPorTipo(String tipo) {
    if (tipo == 'TODOS') return registros.length;
    return registros.where((item) => tipoMovimento(item) == tipo).length;
  }

  Future<void> selecionarFiltro(String tipo) async {
    setState(() => filtroTipo = filtroTipo == tipo ? 'TODOS' : tipo);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) return;
      scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });

    await carregarCustosFiltroSelecionado();
  }

  double custoUnitario(Map<String, dynamic> item) {
    for (final campo in [
      'preco_custo',
      'preco_compra',
      'custo_liquido',
      'custo',
      'valor_custo',
      'custo_unitario',
    ]) {
      final valor = numero(item[campo]);
      if (valor > 0) return valor;
    }
    return 0;
  }

  bool itemTemCusto(Map<String, dynamic> item) {
    return custoUnitario(item) > 0;
  }

  String chaveCacheCusto(Map<String, dynamic> item) {
    final ean = texto(item['ean_principal'], fallback: '');
    if (ean.isNotEmpty) return 'ean:$ean';

    final produtoId = texto(item['produto_id'], fallback: '');
    if (produtoId.isNotEmpty) return 'id:$produtoId';

    return '';
  }

  List<Map<String, dynamic>> extrairProdutosApi(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (data is Map) {
      if (data['produtos'] is List) {
        return List<Map<String, dynamic>>.from(data['produtos']);
      }

      if (data['produto'] is Map) {
        return [Map<String, dynamic>.from(data['produto'])];
      }

      if (data['produto_id'] != null || data['ean'] != null) {
        return [Map<String, dynamic>.from(data)];
      }
    }

    return [];
  }

  double custoProdutoApi(Map<String, dynamic> produto) {
    for (final campo in [
      'preco_custo',
      'preco_compra',
      'custo_liquido',
      'custo',
      'valor_custo',
      'custo_unitario',
    ]) {
      final valor = numeroApi(produto[campo]);
      if (valor > 0) return valor;
    }
    return 0;
  }

  String fornecedorProdutoApi(Map<String, dynamic> produto) {
    for (final campo in [
      'fornecedor',
      'nome_fornecedor',
      'razao_social_fornecedor',
      'fornecedor_nome',
      'ultimo_fornecedor',
      'fornecedor_ultima_compra',
    ]) {
      final valor = texto(produto[campo], fallback: '');
      if (valor.isNotEmpty) return valor;
    }
    return '';
  }

  String fornecedorMovimento(Map<String, dynamic> item) {
    for (final campo in [
      'fornecedor',
      'nome_fornecedor',
      'razao_social_fornecedor',
      'fornecedor_nome',
      'ultimo_fornecedor',
      'fornecedor_ultima_compra',
    ]) {
      final valor = texto(item[campo], fallback: '');
      if (valor.isNotEmpty) return valor;
    }
    return '-';
  }

  bool itemTemFornecedor(Map<String, dynamic> item) {
    return fornecedorMovimento(item) != '-';
  }

  Map<String, dynamic>? escolherProdutoApi(
    List<Map<String, dynamic>> produtos,
    Map<String, dynamic> auditoria,
  ) {
    if (produtos.isEmpty) return null;

    final eanAuditoria = texto(auditoria['ean_principal'], fallback: '');
    final produtoIdAuditoria = texto(auditoria['produto_id'], fallback: '');

    for (final produto in produtos) {
      final eanProduto = texto(
        produto['ean_principal'] ?? produto['ean'] ?? produto['codigo_barras'],
        fallback: '',
      );

      if (eanAuditoria.isNotEmpty && eanProduto == eanAuditoria) {
        return produto;
      }
    }

    for (final produto in produtos) {
      final produtoId = texto(
        produto['produto_id'] ?? produto['id'] ?? produto['codigo_produto'],
        fallback: '',
      );

      if (produtoIdAuditoria.isNotEmpty && produtoId == produtoIdAuditoria) {
        return produto;
      }
    }

    return produtos.first;
  }

  Future<Map<String, dynamic>> buscarDadosProdutoNaApi(
    Map<String, dynamic> item,
  ) async {
    final api = apiBaseUrl();

    if (api.isEmpty) {
      return const {};
    }

    final ean = texto(item['ean_principal'], fallback: '');
    final produtoId = texto(item['produto_id'], fallback: '');
    final urls = <Uri>[];

    if (ean.isNotEmpty) {
      urls.add(Uri.parse('$api/produto/ean/${Uri.encodeComponent(ean)}'));
    }

    if (produtoId.isNotEmpty) {
      urls.add(
        Uri.parse(
          '$api/produto',
        ).replace(queryParameters: {'busca': produtoId}),
      );
    }

    for (final url in urls) {
      try {
        final resposta = await http
            .get(url)
            .timeout(const Duration(seconds: 8));

        if (resposta.statusCode == 404) {
          continue;
        }

        if (resposta.statusCode < 200 || resposta.statusCode >= 300) {
          continue;
        }

        final produtos = extrairProdutosApi(jsonDecode(resposta.body));
        final produto = escolherProdutoApi(produtos, item);
        if (produto == null) continue;

        final custo = custoProdutoApi(produto);
        final fornecedor = fornecedorProdutoApi(produto);
        if (custo > 0 || fornecedor.isNotEmpty) {
          return {'custo': custo, 'fornecedor': fornecedor};
        }
      } catch (_) {
        continue;
      }
    }

    return const {};
  }

  Future<void> carregarCustosFiltroSelecionado() async {
    if (carregandoCustos || registros.isEmpty) {
      return;
    }

    final indices = <int>[];

    for (var i = 0; i < registros.length; i++) {
      final item = registros[i];
      if (itemFiltroAtual(item) &&
          (!itemTemCusto(item) || !itemTemFornecedor(item))) {
        indices.add(i);
      }
    }

    if (indices.isEmpty) {
      return;
    }

    setState(() => carregandoCustos = true);

    final atualizados = registros
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final cache = <String, Map<String, dynamic>>{};

    for (final index in indices) {
      final item = atualizados[index];
      final chave = chaveCacheCusto(item);

      if (chave.isEmpty) {
        continue;
      }

      final dados = cache.containsKey(chave)
          ? cache[chave]!
          : await buscarDadosProdutoNaApi(item);

      cache[chave] = dados;

      final custo = numeroApi(dados['custo']);
      if (custo > 0) {
        item['preco_custo'] = custo;
        item['custo_unitario'] = custo;
      }

      final fornecedor = texto(dados['fornecedor'], fallback: '');
      if (fornecedor.isNotEmpty) {
        item['fornecedor'] = fornecedor;
        item['nome_fornecedor'] = fornecedor;
      }
    }

    if (!mounted) return;

    setState(() {
      registros = atualizados;
      carregandoCustos = false;
    });
  }

  double valorCustoMovimento(Map<String, dynamic> item) {
    final custo = custoUnitario(item);
    if (custo <= 0) return 0;
    return custo * numero(item['quantidade_alterada']).abs();
  }

  double totalCustoFiltrado() {
    return registrosFiltrados.fold<double>(
      0,
      (total, item) => total + valorCustoMovimento(item),
    );
  }

  int registrosSemCusto() {
    return registrosFiltrados
        .where(
          (item) =>
              numero(item['quantidade_alterada']).abs() > 0 &&
              custoUnitario(item) <= 0,
        )
        .length;
  }

  Widget resumoFiltroSelecionado() {
    if (registros.isEmpty) {
      return const SizedBox.shrink();
    }

    final lista = registrosFiltrados;
    final totalCusto = totalCustoFiltrado();
    final semCusto = registrosSemCusto();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cor.withValues(alpha: 0.18)),
            ),
            child: Icon(Icons.calculate_outlined, color: cor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nomeFiltroSelecionado(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  carregandoCustos
                      ? 'Buscando preco de custo...'
                      : '${lista.length} registros filtrados',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
                if (semCusto > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                    '$semCusto registros sem preco de custo',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                moeda(totalCusto),
                style: TextStyle(
                  color: cor,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Custo filtrado',
                style: TextStyle(color: Colors.black54, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> consultarTudo() async {
    await consultar(tudo: true);
  }

  Future<void> consultarItem() async {
    final busca = buscaController.text.trim();

    if (busca.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o item, EAN ou codigo do produto'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await consultar(tudo: false);
  }

  Future<void> consultar({required bool tudo}) async {
    final mercadoId = SessaoLoja.mercadoId?.trim() ?? '';

    if (mercadoId.isEmpty) {
      setState(() {
        erro = 'Loja nao identificada para consultar auditoria.';
        registros = [];
      });
      return;
    }

    setState(() {
      carregando = true;
      erro = null;
      modoConsulta = tudo ? 'tudo' : 'item';
      filtroTipo = 'TODOS';
    });

    try {
      SessaoLoja.sincronizarSessaoAtual();
      await SessaoLoja.renovarSessaoLojaSePossivel();

      final lojaAccessToken =
          SessaoLoja.supabaseLoja?.auth.currentSession?.accessToken ??
          SessaoLoja.lojaAccessToken;

      final resposta = await Supabase.instance.client.functions.invoke(
        'listar-estoque-auditoria',
        body: {
          'mercado_id': mercadoId,
          'mercado_codigo': SessaoLoja.mercadoCodigo,
          'loja_access_token': lojaAccessToken,
          if (!tudo) 'busca': limparBuscaSql(buscaController.text),
          if (dataInicio != null) 'data_inicio': dataIso(dataInicio!),
          if (dataFim != null) 'data_fim': dataIso(dataFim!),
        },
      );

      final data = resposta.data;

      if (data is Map && data['erro'] != null) {
        throw Exception(data['erro'].toString());
      }

      final lista = data is Map && data['registros'] is List
          ? List<Map<String, dynamic>>.from(data['registros'])
          : <Map<String, dynamic>>[];

      if (!mounted) return;

      setState(() {
        registros = lista;
        carregando = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        erro = CentralService.mensagemErroUsuario(e);
        registros = [];
        carregando = false;
      });
    }
  }

  Future<void> exportarExcel() async {
    if (registrosFiltrados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao ha dados para exportar'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => exportando = true);

    try {
      await carregarCustosFiltroSelecionado();
      final listaExportacao = registrosFiltrados;

      final excel = ex.Excel.createExcel();
      const nomeAba = 'Auditoria';
      final sheet = excel[nomeAba];

      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      final colunas = [
        'Data',
        'Tipo',
        'Produto',
        'Fornecedor',
        'EAN',
        'Produto ID',
        'Local',
        'Estoque anterior',
        'Quantidade informada',
        'Alteracao',
        'Estoque novo',
        'Unidade',
        'Usuario',
        'Email',
        'Perfil',
        'Observacao',
        'Preco custo',
        'Valor custo',
      ];

      sheet.appendRow(colunas.map((item) => ex.TextCellValue(item)).toList());

      for (final item in listaExportacao) {
        sheet.appendRow([
          ex.TextCellValue(dataHora(item['criado_em'])),
          ex.TextCellValue(nomeTipo(item)),
          ex.TextCellValue(texto(item['nome_produto'])),
          ex.TextCellValue(fornecedorMovimento(item)),
          ex.TextCellValue(texto(item['ean_principal'])),
          ex.TextCellValue(texto(item['produto_id'])),
          ex.TextCellValue(localTexto(item)),
          ex.TextCellValue(quantidade(item['estoque_anterior'])),
          ex.TextCellValue(quantidade(item['quantidade_informada'])),
          ex.TextCellValue(quantidade(item['quantidade_alterada'])),
          ex.TextCellValue(quantidade(item['estoque_novo'])),
          ex.TextCellValue(texto(item['unidade'])),
          ex.TextCellValue(texto(item['usuario_nome'])),
          ex.TextCellValue(texto(item['usuario_email'])),
          ex.TextCellValue(texto(item['usuario_perfil'])),
          ex.TextCellValue(texto(item['observacao'], fallback: '')),
          ex.TextCellValue(moeda(custoUnitario(item))),
          ex.TextCellValue(moeda(valorCustoMovimento(item))),
        ]);
      }

      final bytes = excel.encode();
      if (bytes == null) {
        throw Exception('Nao foi possivel gerar o Excel.');
      }

      final dir = await getTemporaryDirectory();
      final filtroArquivo = nomeFiltroSelecionado()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      final nomeArquivo =
          'auditoria_estoque_${filtroArquivo}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final arquivo = File('${dir.path}/$nomeArquivo');
      await arquivo.writeAsBytes(bytes);

      await SharePlus.instance.share(
        ShareParams(
          text: 'Auditoria de estoque - ${nomeFiltroSelecionado()}',
          files: [XFile(arquivo.path)],
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao exportar auditoria: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => exportando = false);
      }
    }
  }

  Widget resumo() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: cardResumo(
                titulo: 'Registros',
                valor: totalPorTipo('TODOS').toString(),
                icone: Icons.receipt_long,
                tipoFiltro: 'TODOS',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: cardResumo(
                titulo: 'Entradas',
                valor: totalPorTipo('ENTRADA').toString(),
                icone: Icons.add_box,
                tipoFiltro: 'ENTRADA',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: cardResumo(
                titulo: 'Correções',
                valor: totalPorTipo('CORRECAO').toString(),
                icone: Icons.edit_note,
                tipoFiltro: 'CORRECAO',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: cardResumo(
                titulo: 'Consumo',
                valor: totalPorTipo('CONSUMO_INTERNO').toString(),
                icone: Icons.remove_circle_outline,
                tipoFiltro: 'CONSUMO_INTERNO',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: cardResumo(
                titulo: 'Avarias',
                valor: totalPorTipo('BAIXA_AVARIA').toString(),
                icone: Icons.broken_image_outlined,
                tipoFiltro: 'BAIXA_AVARIA',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: cardResumo(
                titulo: 'Validade',
                valor: totalPorTipo('BAIXA_VALIDADE').toString(),
                icone: Icons.event_busy_outlined,
                tipoFiltro: 'BAIXA_VALIDADE',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget botaoData({
    required String textoBotao,
    required DateTime? data,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.calendar_month_outlined, size: 17),
      label: Text(
        dataCurta(data, textoBotao),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: cor,
        side: BorderSide(color: cor.withValues(alpha: 0.55)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
    );
  }

  Widget botaoLimparPeriodo() {
    final temPeriodo = dataInicio != null || dataFim != null;
    return IconButton(
      tooltip: 'Limpar período',
      onPressed: !temPeriodo || carregando
          ? null
          : () {
              setState(() {
                dataInicio = null;
                dataFim = null;
              });
              consultar(tudo: modoConsulta == 'tudo');
            },
      icon: const Icon(Icons.clear),
      color: cor,
    );
  }

  Widget cardResumo({
    required String titulo,
    required String valor,
    required IconData icone,
    required String tipoFiltro,
  }) {
    final selecionado = filtroTipo == tipoFiltro;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: carregando ? null : () => selecionarFiltro(tipoFiltro),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selecionado ? cor.withValues(alpha: 0.10) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selecionado ? cor : cor.withValues(alpha: 0.22),
            width: selecionado ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, color: cor, size: 20),
            const SizedBox(height: 8),
            Text(
              valor,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: selecionado ? cor : Colors.black54,
                fontWeight: selecionado ? FontWeight.w800 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget filtros() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withValues(alpha: 0.20)),
      ),
      child: Column(
        children: [
          TextField(
            controller: buscaController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => consultarItem(),
            decoration: InputDecoration(
              labelText: 'Consultar pelo item',
              hintText: 'Nome, EAN ou produto_id',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: buscaController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      onPressed: carregando
                          ? null
                          : () {
                              setState(() => buscaController.clear());
                              consultarTudo();
                            },
                      icon: const Icon(Icons.close),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: botaoData(
                  textoBotao: 'Data inicial',
                  data: dataInicio,
                  onPressed: carregando
                      ? null
                      : () => escolherData(inicio: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: botaoData(
                  textoBotao: 'Data final',
                  data: dataFim,
                  onPressed: carregando
                      ? null
                      : () => escolherData(inicio: false),
                ),
              ),
              botaoLimparPeriodo(),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: carregando ? null : consultarItem,
                  icon: const Icon(Icons.manage_search),
                  label: const Text('Consultar item'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: carregando ? null : consultarTudo,
                  icon: const Icon(Icons.list_alt),
                  label: const Text('Consultar tudo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cor,
                    side: BorderSide(color: cor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget cardAuditoria(Map<String, dynamic> item) {
    final tipoCor = corTipo(item);
    final alteracao = numero(item['quantidade_alterada']);
    final unidade = texto(item['unidade'], fallback: '');
    final sinal = alteracao > 0 ? '+' : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tipoCor.withValues(alpha: 0.30), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 5),
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
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: tipoCor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  nomeTipo(item),
                  style: TextStyle(
                    color: tipoCor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                dataHora(item['criado_em']),
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            texto(item['nome_produto']),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'EAN: ${texto(item['ean_principal'])} | ID: ${texto(item['produto_id'])}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip(
                Icons.inventory_2_outlined,
                'Antes: ${quantidade(item['estoque_anterior'])} $unidade',
              ),
              chip(
                Icons.compare_arrows,
                'Alteracao: $sinal${quantidade(item['quantidade_alterada'])} $unidade',
              ),
              chip(
                Icons.check_circle_outline,
                'Depois: ${quantidade(item['estoque_novo'])} $unidade',
              ),
              chip(Icons.warehouse_outlined, localTexto(item)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.person_outline, size: 16, color: Colors.black54),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${texto(item['usuario_nome'])} | ${texto(item['usuario_email'])}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black87, fontSize: 12),
                ),
              ),
            ],
          ),
          if (texto(item['observacao'], fallback: '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Obs: ${texto(item['observacao'])}',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget chip(IconData icone, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: Colors.black54),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget listaRegistros() {
    final lista = registrosFiltrados;

    if (carregando) {
      return Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(child: CircularProgressIndicator(color: cor)),
      );
    }

    if (erro != null) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
        ),
        child: Text(
          erro!,
          style: const TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    if (registros.isEmpty) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: const Text('Nenhuma alteracao de estoque encontrada.'),
      );
    }

    if (lista.isEmpty) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Text(
          'Nenhum registro encontrado para ${nomeFiltroSelecionado().toLowerCase()}.',
        ),
      );
    }

    return Column(children: lista.map(cardAuditoria).toList());
  }

  @override
  Widget build(BuildContext context) {
    final tituloConsulta = modoConsulta == 'tudo'
        ? 'Ultimas alteracoes'
        : 'Resultado da consulta';

    return Scaffold(
      backgroundColor: fundo,
      appBar: AppBar(
        backgroundColor: cor,
        foregroundColor: Colors.white,
        title: const Text('Auditoria'),
        actions: [
          IconButton(
            tooltip: 'Exportar relatorio',
            onPressed: exportando || carregando ? null : exportarExcel,
            icon: exportando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: cor,
        onRefresh: () => consultar(tudo: modoConsulta == 'tudo'),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Alteracoes de estoque',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Consulte entradas, correções, consumo interno e baixas realizadas no app_preco.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            resumo(),
            const SizedBox(height: 14),
            filtros(),
            const SizedBox(height: 18),
            resumoFiltroSelecionado(),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    tituloConsulta,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${registrosFiltrados.length} registros',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
            listaRegistros(),
          ],
        ),
      ),
    );
  }
}

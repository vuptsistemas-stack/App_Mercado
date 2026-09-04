import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart' as ex;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/central_service.dart';
import '../../services/notificacao_pedidos_service.dart';
import '../../services/sessao_loja.dart';
import 'scanner.dart';

class AcoesValidadePage extends StatefulWidget {
  const AcoesValidadePage({super.key});

  @override
  State<AcoesValidadePage> createState() => _AcoesValidadePageState();
}

class _AcoesValidadePageState extends State<AcoesValidadePage> {
  final centralService = CentralService();

  final buscaController = TextEditingController();
  final precoPromocionalController = TextEditingController();
  final quantidadeController = TextEditingController();
  final dataValidadeController = TextEditingController();

  Timer? debounceBusca;

  bool carregando = true;
  bool buscandoProdutos = false;
  bool salvando = false;
  bool monitorando = false;
  bool exportandoRelatorio = false;

  String? erro;
  String? erroCarregamento;
  String filtroAcoes = 'ativas';

  List<Map<String, dynamic>> produtos = [];
  List<Map<String, dynamic>> acoes = [];
  List<Map<String, dynamic>> alertas = [];

  Map<String, dynamic>? produtoSelecionado;

  Color get corPrimaria => SessaoLoja.corPrimaria;
  Color get corSecundaria => SessaoLoja.corSecundaria;
  Color get corFundo => SessaoLoja.corFundo;

  String? get mercadoIdAtual {
    final id = SessaoLoja.mercadoId?.trim();
    return id == null || id.isEmpty ? null : id;
  }

  String? get apiBaseUrl {
    final url = SessaoLoja.apiBaseUrl?.trim();
    if (url == null || url.isEmpty) return null;
    return url.replaceAll(RegExp(r'/+$'), '');
  }

  bool mensagemIndicaSessaoExpirada(String mensagem) {
    final texto = mensagem.toLowerCase();

    return texto.contains('sessão expir') ||
        texto.contains('sessao expir') ||
        texto.contains('jwt expired') ||
        texto.contains('pgrst303');
  }

  @override
  void initState() {
    super.initState();
    carregarAcoes();
  }

  @override
  void dispose() {
    debounceBusca?.cancel();
    buscaController.dispose();
    precoPromocionalController.dispose();
    quantidadeController.dispose();
    dataValidadeController.dispose();
    super.dispose();
  }

  String texto(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? '-' : texto;
  }

  String somenteNumeros(String valor) {
    return valor.replaceAll(RegExp(r'\D'), '');
  }

  String normalizarEan(String valor) {
    final numeros = somenteNumeros(valor);
    if (numeros.isEmpty) return '';
    return numeros.length < 14 ? numeros.padLeft(14, '0') : numeros;
  }

  double? numero(dynamic valor) {
    if (valor == null) return null;
    if (valor is num) return valor.toDouble();

    final textoValor = valor
        .toString()
        .trim()
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll('.', '')
        .replaceAll(',', '.');

    if (textoValor.isEmpty) return null;
    return double.tryParse(textoValor);
  }

  String moeda(dynamic valor) {
    final numeroValor = numero(valor);
    if (numeroValor == null) return 'R\$ 0,00';
    return 'R\$ ${numeroValor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String quantidadeTexto(dynamic valor) {
    final numeroValor = numero(valor) ?? 0;
    if (numeroValor == numeroValor.roundToDouble()) {
      return numeroValor.toInt().toString();
    }
    return numeroValor.toStringAsFixed(3).replaceAll('.', ',');
  }

  String dataCurta(dynamic valor) {
    final textoData = valor?.toString() ?? '';
    if (textoData.length >= 10) return textoData.substring(0, 10);
    return textoData.isEmpty ? '-' : textoData;
  }

  bool acaoEstaAtiva(Map<String, dynamic> acao) {
    final status = acao['status']?.toString().trim().toUpperCase() ?? '';
    return acao['ativo'] == true && (status.isEmpty || status == 'ATIVA');
  }

  List<Map<String, dynamic>> get acoesFiltradas {
    return acoes.where((acao) {
      final ativa = acaoEstaAtiva(acao);
      return filtroAcoes == 'ativas' ? ativa : !ativa;
    }).toList();
  }

  int get totalAcoesAtivas => acoes.where(acaoEstaAtiva).length;

  int get totalAcoesInativas => acoes.length - totalAcoesAtivas;

  String statusTextoAcao(Map<String, dynamic> acao) {
    final status = acao['status']?.toString().toUpperCase() ?? 'ATIVA';
    if (status == 'ENCERRADA_VENDA') return 'vendida';
    if (status == 'ENCERRADA_VALIDADE') return 'validade';
    if (status == 'CANCELADA') return 'cancelada';
    if (acaoEstaAtiva(acao)) return 'ativa';
    return 'inativa';
  }

  String dataHoraTexto(dynamic valor) {
    final raw = valor?.toString().trim() ?? '';
    if (raw.isEmpty) return '-';

    final data = DateTime.tryParse(raw);
    if (data == null) return raw.length >= 16 ? raw.substring(0, 16) : raw;

    final local = data.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String dataArquivo() {
    final agora = DateTime.now();
    return '${agora.year}'
        '${agora.month.toString().padLeft(2, '0')}'
        '${agora.day.toString().padLeft(2, '0')}_'
        '${agora.hour.toString().padLeft(2, '0')}'
        '${agora.minute.toString().padLeft(2, '0')}';
  }

  String nomeArquivoSeguro(String valor) {
    final limpo = valor
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return limpo.isEmpty ? 'loja' : limpo;
  }

  String tituloFiltroRelatorio() {
    return filtroAcoes == 'ativas' ? 'Acoes ativas' : 'Acoes inativas';
  }

  String campoProduto(Map<String, dynamic> produto, List<String> nomes) {
    for (final nome in nomes) {
      final valor = produto[nome];
      if (valor != null && valor.toString().trim().isNotEmpty) {
        return valor.toString().trim();
      }
    }
    return '';
  }

  String nomeProduto(Map<String, dynamic> produto) {
    final nome = campoProduto(produto, [
      'nome_produto',
      'descricao',
      'nome',
      'produto',
    ]);
    return nome.isEmpty ? 'Produto' : nome;
  }

  String eanProduto(Map<String, dynamic> produto) {
    final ean = campoProduto(produto, [
      'ean_principal',
      'ean',
      'codigo_barras',
      'codigo',
      'cod_barras',
    ]);
    return ean.isEmpty ? '' : normalizarEan(ean);
  }

  String? produtoId(Map<String, dynamic> produto) {
    final id = campoProduto(produto, [
      'produto_id',
      'id',
      'codigo_produto',
      'cod_produto',
    ]);
    return id.isEmpty ? null : id;
  }

  double? precoProduto(Map<String, dynamic> produto) {
    for (final campo in [
      'preco_venda',
      'preco',
      'valor',
      'valor_venda',
      'preco_unitario',
    ]) {
      final valor = numero(produto[campo]);
      if (valor != null) return valor;
    }
    return null;
  }

  double? precoCustoProduto(Map<String, dynamic> produto) {
    for (final campo in [
      'preco_custo',
      'preco_compra',
      'custo_liquido',
      'custo',
      'valor_custo',
      'custo_unitario',
    ]) {
      final valor = numero(produto[campo]);
      if (valor != null) return valor;
    }
    return null;
  }

  double estoqueProduto(Map<String, dynamic> produto) {
    for (final campo in [
      'estoque_atual',
      'estoque',
      'quantidade',
      'saldo_estoque',
      'qtd_estoque',
      'saldo',
    ]) {
      final valor = numero(produto[campo]);
      if (valor != null) return valor;
    }
    return 0;
  }

  String mensagemEstoqueIndisponivel(double estoque) {
    if (estoque < 0) {
      return 'Produto encontrado, mas está com estoque negativo. Corrija o estoque antes de criar a ação.';
    }

    return 'Produto encontrado, mas está sem estoque disponível para criar ação.';
  }

  List<Map<String, dynamic>> extrairProdutos(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (data is Map) {
      if (data['erro'] != null) throw Exception(data['erro'].toString());

      for (final campo in ['produtos', 'data', 'resultado', 'results']) {
        if (data[campo] is List) {
          return List<Map<String, dynamic>>.from(data[campo]);
        }
      }

      if (data['produto'] is Map) {
        return [Map<String, dynamic>.from(data['produto'])];
      }

      if (data['produto_id'] != null ||
          data['ean_principal'] != null ||
          data['nome_produto'] != null) {
        return [Map<String, dynamic>.from(data)];
      }
    }

    return [];
  }

  bool buscaSomenteNumeros(String valor) {
    final busca = valor.trim();
    return busca.isNotEmpty && RegExp(r'^[0-9]+$').hasMatch(busca);
  }

  Future<List<Map<String, dynamic>>> buscarNaApi(String busca) async {
    final api = apiBaseUrl;
    if (api == null) {
      throw Exception('API da loja nao configurada.');
    }

    final textoBusca = busca.trim();
    if (textoBusca.isEmpty) return [];

    final Uri url;

    if (buscaSomenteNumeros(textoBusca)) {
      url = Uri.parse('$api/produto/ean/${normalizarEan(textoBusca)}');
    } else {
      final descricao = Uri.encodeComponent(textoBusca);
      url = Uri.parse('$api/produto/descricao/$descricao');
    }

    final resposta = await http.get(url).timeout(const Duration(seconds: 20));

    if (resposta.statusCode == 404) return [];
    if (resposta.statusCode != 200) {
      throw Exception('Erro na API. Codigo HTTP: ${resposta.statusCode}');
    }

    return extrairProdutos(jsonDecode(resposta.body));
  }

  Future<Map<String, dynamic>?> buscarProdutoAtualPorEan(String ean) async {
    final resultado = await buscarNaApi(ean);
    return resultado.isEmpty ? null : resultado.first;
  }

  void agendarBusca(String valor) {
    debounceBusca?.cancel();

    final busca = valor.trim();
    if (busca.isEmpty) {
      setState(() {
        produtos = [];
        produtoSelecionado = null;
        erro = null;
        buscandoProdutos = false;
      });
      return;
    }

    if (buscaSomenteNumeros(busca) || busca.length < 3) {
      setState(() {
        produtos = [];
        erro = null;
        buscandoProdutos = false;
      });
      return;
    }

    debounceBusca = Timer(
      const Duration(milliseconds: 500),
      () => buscarProdutos(busca, sugestao: true),
    );
  }

  Future<void> buscarProdutos(String busca, {bool sugestao = false}) async {
    final textoBusca = busca.trim();
    if (textoBusca.isEmpty) return;

    if (!sugestao) {
      FocusScope.of(context).unfocus();
    }

    setState(() {
      buscandoProdutos = true;
      erro = null;
      produtos = [];
      if (!sugestao) produtoSelecionado = null;
    });

    try {
      final resultado = await buscarNaApi(textoBusca);
      if (!mounted) return;

      if (resultado.length == 1 && !sugestao) {
        selecionarProduto(resultado.first);
        setState(() => buscandoProdutos = false);
        return;
      }

      setState(() {
        produtos = resultado;
        buscandoProdutos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        erro = CentralService.mensagemErroUsuario(e);
        buscandoProdutos = false;
      });
    }
  }

  Future<void> abrirScanner() async {
    debounceBusca?.cancel();

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerPage(
          onDetect: (codigo) {
            final ean = normalizarEan(codigo);
            buscaController.text = ean;
            buscarProdutos(ean);
          },
        ),
      ),
    );
  }

  Future<void> carregarAcoes({bool monitorarDepois = true}) async {
    final mercadoId = mercadoIdAtual;
    if (mercadoId == null) {
      setState(() {
        carregando = false;
        erroCarregamento = 'Nao foi possivel identificar a loja atual.';
      });
      return;
    }

    setState(() {
      carregando = true;
      erro = null;
      erroCarregamento = null;
    });

    try {
      await SessaoLoja.renovarSessaoLojaSePossivel();

      final resposta = await centralService.listarAcoesValidade(
        mercadoId: mercadoId,
      );

      if (!mounted) return;

      setState(() {
        acoes = resposta['acoes'] as List<Map<String, dynamic>>;
        alertas = resposta['alertas'] as List<Map<String, dynamic>>;
        erroCarregamento = null;
        carregando = false;
      });

      if (monitorarDepois) {
        await monitorarAcoes(silencioso: true);
      }
    } catch (e) {
      if (!mounted) return;
      final mensagem = CentralService.mensagemErroUsuario(e);

      setState(() {
        erroCarregamento = mensagemIndicaSessaoExpirada(mensagem)
            ? null
            : mensagem;
        carregando = false;
      });
    }
  }

  void selecionarProduto(Map<String, dynamic> produto) {
    final preco = precoProduto(produto);
    final estoque = estoqueProduto(produto);

    setState(() {
      produtoSelecionado = produto;
      produtos = [];
      buscaController.text = nomeProduto(produto);
      precoPromocionalController.clear();
      quantidadeController.text = estoque > 0
          ? quantidadeTexto(estoque).replaceAll(',', '.')
          : '';
    });

    if (preco == null || preco <= 0) {
      mostrarMensagem('Produto selecionado, mas sem preco na API.', erro: true);
    }

    if (estoque <= 0) {
      mostrarMensagem(mensagemEstoqueIndisponivel(estoque), erro: true);
    }
  }

  Future<void> escolherDataValidade() async {
    final hoje = DateTime.now();
    final dataInicial =
        DateTime.tryParse(dataValidadeController.text.trim()) ?? hoje;

    final data = await showDatePicker(
      context: context,
      initialDate: dataInicial.isBefore(hoje) ? hoje : dataInicial,
      firstDate: DateTime(hoje.year - 1),
      lastDate: DateTime(hoje.year + 3),
    );

    if (data == null) return;

    dataValidadeController.text =
        '${data.year.toString().padLeft(4, '0')}-'
        '${data.month.toString().padLeft(2, '0')}-'
        '${data.day.toString().padLeft(2, '0')}';
  }

  Future<void> salvarAcao() async {
    final mercadoId = mercadoIdAtual;
    final produto = produtoSelecionado;

    if (mercadoId == null) {
      mostrarMensagem('Loja atual nao identificada.', erro: true);
      return;
    }

    if (produto == null) {
      mostrarMensagem('Selecione um produto primeiro.', erro: true);
      return;
    }

    final ean = eanProduto(produto);
    final precoOriginal = precoProduto(produto);
    final precoPromocional = numero(precoPromocionalController.text);
    final quantidade = numero(quantidadeController.text);
    final estoqueAtual = estoqueProduto(produto);
    final dataValidade = dataValidadeController.text.trim();

    if (ean.isEmpty) {
      mostrarMensagem('Produto sem EAN/codigo de barras.', erro: true);
      return;
    }

    if (precoOriginal == null || precoOriginal <= 0) {
      mostrarMensagem('Preco original nao encontrado na API.', erro: true);
      return;
    }

    if (precoPromocional == null || precoPromocional <= 0) {
      mostrarMensagem('Informe o preco promocional.', erro: true);
      return;
    }

    if (precoPromocional >= precoOriginal) {
      mostrarMensagem(
        'O preco promocional precisa ser menor que o preco atual.',
        erro: true,
      );
      return;
    }

    if (estoqueAtual <= 0) {
      mostrarMensagem(mensagemEstoqueIndisponivel(estoqueAtual), erro: true);
      return;
    }

    if (quantidade == null || quantidade <= 0) {
      mostrarMensagem('Informe a quantidade proxima da validade.', erro: true);
      return;
    }

    if (quantidade > estoqueAtual) {
      mostrarMensagem(
        'A quantidade da acao nao pode ser maior que o estoque atual.',
        erro: true,
      );
      return;
    }

    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dataValidade)) {
      mostrarMensagem('Informe a validade no formato AAAA-MM-DD.', erro: true);
      return;
    }

    setState(() => salvando = true);

    try {
      await centralService.salvarAcaoValidade(
        mercadoId: mercadoId,
        acaoValidade: {
          'produto_id': produtoId(produto),
          'ean': ean,
          'nome_produto': nomeProduto(produto),
          'preco_original': precoOriginal,
          'preco_promocional': precoPromocional,
          'estoque_inicial': estoqueAtual,
          'quantidade_promocional': quantidade,
          'data_validade': dataValidade,
        },
      );

      if (!mounted) return;

      mostrarMensagem('Acao de validade criada e preco promocional aplicado.');
      limparFormulario();
      await carregarAcoes(monitorarDepois: false);
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(
        'Erro ao salvar acao: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    } finally {
      if (mounted) setState(() => salvando = false);
    }
  }

  Future<void> monitorarAcoes({bool silencioso = false}) async {
    final mercadoId = mercadoIdAtual;
    if (mercadoId == null || monitorando) return;

    final ativas = acoes.where((acao) {
      return acao['ativo'] == true &&
          acao['status']?.toString().toUpperCase() == 'ATIVA';
    }).toList();

    if (ativas.isEmpty) {
      if (!silencioso) {
        mostrarMensagem('Nenhuma acao ativa para monitorar.');
      }
      return;
    }

    setState(() => monitorando = true);

    try {
      final estoques = <Map<String, dynamic>>[];

      for (final acao in ativas) {
        final ean = acao['ean']?.toString() ?? '';
        if (ean.isEmpty) continue;

        final produtoAtual = await buscarProdutoAtualPorEan(ean);
        final estoqueAtual = produtoAtual == null
            ? numero(acao['estoque_atual_ultima'])
            : estoqueProduto(produtoAtual);

        if (estoqueAtual == null) continue;

        estoques.add({
          'acao_id': acao['id'],
          'ean': ean,
          'estoque_atual': estoqueAtual,
        });
      }

      final resposta = await centralService.monitorarAcoesValidade(
        mercadoId: mercadoId,
        estoques: estoques,
      );

      final encerradas = resposta['encerradas'] as List<Map<String, dynamic>>;

      for (final encerrada in encerradas) {
        final mensagem =
            encerrada['alerta_mensagem']?.toString() ??
            'Acao de validade encerrada.';

        await NotificacaoPedidosService.instance.alertaValidade(
          titulo: 'Alerta de validade',
          mensagem: mensagem,
        );
      }

      if (!mounted) return;

      if (encerradas.isNotEmpty) {
        mostrarMensagem('${encerradas.length} acao(oes) encerrada(s).');
      } else if (!silencioso) {
        mostrarMensagem('Monitoramento atualizado.');
      }

      await carregarAcoes(monitorarDepois: false);
    } catch (e) {
      if (!mounted) return;
      if (!silencioso) {
        mostrarMensagem(
          'Erro ao monitorar: ${CentralService.mensagemErroUsuario(e)}',
          erro: true,
        );
      }
    } finally {
      if (mounted) setState(() => monitorando = false);
    }
  }

  Future<void> encerrarManual(Map<String, dynamic> acao) async {
    final mercadoId = mercadoIdAtual;
    if (mercadoId == null) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Encerrar acao'),
        content: Text(
          'Deseja encerrar a acao de "${texto(acao['nome_produto'])}" e voltar ao preco normal?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Encerrar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      final produtoAtual = await buscarProdutoAtualPorEan(texto(acao['ean']));
      final estoqueAtual = produtoAtual == null
          ? numero(acao['estoque_atual_ultima']) ?? 0
          : estoqueProduto(produtoAtual);

      await centralService.encerrarAcaoValidade(
        mercadoId: mercadoId,
        acaoId: texto(acao['id']),
        motivo: 'CANCELADA',
        estoqueAtual: estoqueAtual,
      );

      if (!mounted) return;
      mostrarMensagem('Acao encerrada.');
      await carregarAcoes(monitorarDepois: false);
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(
        'Erro ao encerrar acao: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    }
  }

  Future<void> marcarAlertaLido(Map<String, dynamic> alerta) async {
    final mercadoId = mercadoIdAtual;
    if (mercadoId == null) return;

    try {
      await centralService.marcarAlertaAcaoValidadeLido(
        mercadoId: mercadoId,
        alertaId: alerta['id']?.toString(),
        acaoId: alerta['acao_id']?.toString(),
      );
      await carregarAcoes(monitorarDepois: false);
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(
        'Erro ao marcar alerta: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    }
  }

  void limparFormulario() {
    debounceBusca?.cancel();
    setState(() {
      buscaController.clear();
      precoPromocionalController.clear();
      quantidadeController.clear();
      dataValidadeController.clear();
      produtoSelecionado = null;
      produtos = [];
      erro = null;
    });
  }

  void mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? Colors.red : Colors.green,
      ),
    );
  }

  List<Map<String, dynamic>> listaRelatorioAtual() {
    return List<Map<String, dynamic>>.from(acoesFiltradas);
  }

  List<ex.TextCellValue> linhaExcel(List<String> valores) {
    return valores.map(ex.TextCellValue.new).toList();
  }

  Future<void> baixarRelatorioAcoes() async {
    final lista = listaRelatorioAtual();
    if (lista.isEmpty) {
      mostrarMensagem(
        'Nenhuma acao no filtro atual para gerar relatorio.',
        erro: true,
      );
      return;
    }

    setState(() => exportandoRelatorio = true);

    try {
      final excel = ex.Excel.createExcel();
      final sheet = excel['Acoes de validade'];
      excel.setDefaultSheet('Acoes de validade');

      sheet.appendRow(
        linhaExcel([
          'Status',
          'Produto',
          'EAN',
          'Preco original',
          'Preco promocional',
          'Quantidade promocional',
          'Vendido estimado',
          'Estoque inicial',
          'Estoque atual',
          'Data de validade',
          'Criado em',
          'Atualizado em',
          'Alerta',
        ]),
      );

      for (final acao in lista) {
        sheet.appendRow(
          linhaExcel([
            statusTextoAcao(acao),
            texto(acao['nome_produto']),
            texto(acao['ean']),
            moeda(acao['preco_original']),
            moeda(acao['preco_promocional']),
            quantidadeTexto(acao['quantidade_promocional']),
            quantidadeTexto(acao['quantidade_vendida_estimada']),
            quantidadeTexto(acao['estoque_inicial']),
            quantidadeTexto(acao['estoque_atual_ultima']),
            dataCurta(acao['data_validade']),
            dataHoraTexto(acao['criado_em']),
            dataHoraTexto(acao['atualizado_em']),
            texto(acao['alerta_mensagem']),
          ]),
        );
      }

      final bytes = excel.encode();
      if (bytes == null) {
        throw Exception('Nao foi possivel gerar o Excel.');
      }

      final dir = await getTemporaryDirectory();
      final loja = nomeArquivoSeguro(
        SessaoLoja.mercadoCodigo ?? SessaoLoja.mercadoNome ?? 'loja',
      );
      final filtro = filtroAcoes == 'ativas' ? 'ativas' : 'inativas';
      final arquivo = File(
        '${dir.path}/acoes_validade_${loja}_${filtro}_${dataArquivo()}.xlsx',
      );
      await arquivo.writeAsBytes(bytes);

      await SharePlus.instance.share(
        ShareParams(
          text: 'Relatorio de acoes de validade',
          files: [XFile(arquivo.path)],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(
        'Erro ao gerar relatorio: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    } finally {
      if (mounted) setState(() => exportandoRelatorio = false);
    }
  }

  Future<void> visualizarRelatorioAcoes() async {
    final lista = listaRelatorioAtual();
    if (lista.isEmpty) {
      mostrarMensagem(
        'Nenhuma acao no filtro atual para visualizar.',
        erro: true,
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (context, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: ListView.separated(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
                itemCount: lista.length + 1,
                separatorBuilder: (_, index) =>
                    index == 0 ? const SizedBox(height: 10) : const Divider(),
                itemBuilder: (_, index) {
                  if (index == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 46,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                tituloFiltroRelatorio(),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(
                              '${lista.length} registro(s)',
                              style: TextStyle(
                                color: corPrimaria,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Loja: ${SessaoLoja.mercadoNome ?? SessaoLoja.mercadoCodigo ?? '-'}',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    );
                  }

                  return itemRelatorioAcao(lista[index - 1]);
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget itemRelatorioAcao(Map<String, dynamic> acao) {
    final ativa = acaoEstaAtiva(acao);
    final status = statusTextoAcao(acao);
    final corStatus = ativa ? Colors.green : Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  texto(acao['nome_produto']),
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: corStatus.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: corStatus.shade700,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'EAN: ${texto(acao['ean'])} | Validade: ${dataCurta(acao['data_validade'])}',
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            '${moeda(acao['preco_original'])} -> ${moeda(acao['preco_promocional'])}',
            style: TextStyle(color: corPrimaria, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Qtd: ${quantidadeTexto(acao['quantidade_promocional'])} | Vendido: ${quantidadeTexto(acao['quantidade_vendida_estimada'])} | Estoque: ${quantidadeTexto(acao['estoque_atual_ultima'])}',
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          if ((acao['alerta_mensagem']?.toString().isNotEmpty ?? false)) ...[
            const SizedBox(height: 6),
            Text(
              acao['alerta_mensagem'].toString(),
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  BoxDecoration caixaBranca() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }

  Widget topo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [corPrimaria, corSecundaria],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white,
            child: Icon(Icons.timer_outlined, color: corPrimaria, size: 32),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Acoes de validade',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Desconto temporario com monitoramento por estoque e data.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget cardAlertas() {
    if (alertas.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
              SizedBox(width: 8),
              Text(
                'Alertas pendentes',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF92400E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...alertas.map((alerta) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      alerta['mensagem']?.toString() ?? '',
                      style: const TextStyle(color: Color(0xFF78350F)),
                    ),
                  ),
                  TextButton(
                    onPressed: () => marcarAlertaLido(alerta),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget campoBusca() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: caixaBranca(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Criar nova acao',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: buscaController,
            onChanged: agendarBusca,
            onSubmitted: (valor) => buscarProdutos(valor),
            decoration: InputDecoration(
              labelText: 'Buscar produto por nome ou EAN',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: buscandoProdutos
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Scanner',
                          icon: const Icon(Icons.qr_code_scanner),
                          color: corPrimaria,
                          onPressed: abrirScanner,
                        ),
                        IconButton(
                          tooltip: 'Buscar',
                          icon: const Icon(Icons.arrow_forward),
                          onPressed: () => buscarProdutos(buscaController.text),
                        ),
                      ],
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          if (erro != null) ...[
            const SizedBox(height: 8),
            Text(erro!, style: const TextStyle(color: Colors.red)),
          ],
          if (produtos.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 260),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: produtos.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final produto = produtos[index];
                  return ListTile(
                    title: Text(
                      nomeProduto(produto),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'EAN: ${eanProduto(produto)} | Estoque: ${quantidadeTexto(estoqueProduto(produto))} | ${moeda(precoProduto(produto))}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => selecionarProduto(produto),
                  );
                },
              ),
            ),
          ],
          if (produtoSelecionado != null) ...[
            const SizedBox(height: 14),
            formularioAcao(),
          ],
        ],
      ),
    );
  }

  Widget formularioAcao() {
    final produto = produtoSelecionado!;
    final precoOriginal = precoProduto(produto) ?? 0;
    final precoCusto = precoCustoProduto(produto);
    final estoqueAtual = estoqueProduto(produto);
    final quantidade = numero(quantidadeController.text) ?? 0;
    final estoqueDisponivel = estoqueAtual > 0;
    final estoqueAlvo = estoqueDisponivel
        ? (estoqueAtual - quantidade).clamp(0, estoqueAtual)
        : estoqueAtual;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nomeProduto(produto),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text('EAN: ${eanProduto(produto)}'),
          const SizedBox(height: 10),
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: chipInfo(
                      'Preço venda',
                      moeda(precoOriginal),
                      Icons.sell,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: chipInfo(
                      'Preço custo',
                      precoCusto == null ? '-' : moeda(precoCusto),
                      Icons.payments_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: chipInfo(
                      'Estoque atual',
                      quantidadeTexto(estoqueAtual),
                      Icons.inventory_2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: chipInfo(
                      'Encerra em',
                      quantidadeTexto(estoqueAlvo),
                      Icons.flag_outlined,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (!estoqueDisponivel) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                mensagemEstoqueIndisponivel(estoqueAtual),
                style: TextStyle(
                  color: Colors.orange.shade900,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: precoPromocionalController,
            enabled: estoqueDisponivel && !salvando,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
            ],
            decoration: InputDecoration(
              labelText: 'Preco promocional',
              prefixIcon: const Icon(Icons.price_change_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: quantidadeController,
            enabled: estoqueDisponivel && !salvando,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
            ],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Quantidade proxima da validade',
              prefixIcon: const Icon(Icons.production_quantity_limits),
              helperText:
                  'Quando essa quantidade sair do estoque, a acao encerra.',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: dataValidadeController,
            enabled: estoqueDisponivel && !salvando,
            readOnly: true,
            onTap: estoqueDisponivel ? escolherDataValidade : null,
            decoration: InputDecoration(
              labelText: 'Data de validade',
              hintText: 'AAAA-MM-DD',
              prefixIcon: const Icon(Icons.event_busy_outlined),
              suffixIcon: IconButton(
                icon: const Icon(Icons.calendar_today),
                onPressed: estoqueDisponivel ? escolherDataValidade : null,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: salvando ? null : limparFormulario,
                  icon: const Icon(Icons.close),
                  label: const Text('Limpar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: salvando || !estoqueDisponivel ? null : salvarAcao,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: corPrimaria,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: salvando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Criar acao'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget chipInfo(String titulo, String valor, IconData icone) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: corPrimaria.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: corPrimaria.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 18, color: corPrimaria),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
              Text(valor, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget botaoFiltroAcoes({
    required String filtro,
    required String titulo,
    required int total,
    required IconData icone,
  }) {
    final selecionado = filtroAcoes == filtro;
    final cor = filtro == 'ativas' ? Colors.green : Colors.orange;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => filtroAcoes = filtro),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: selecionado ? cor.withValues(alpha: 0.12) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selecionado
                  ? cor.withValues(alpha: 0.70)
                  : Colors.black.withValues(alpha: 0.10),
              width: selecionado ? 1.3 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icone, size: 18, color: selecionado ? cor : Colors.black45),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '$titulo ($total)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selecionado ? cor.shade700 : Colors.black54,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget listaAcoes() {
    final lista = acoesFiltradas;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: caixaBranca(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Acoes cadastradas',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Monitorar agora',
                onPressed: monitorando ? null : () => monitorarAcoes(),
                icon: monitorando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              botaoFiltroAcoes(
                filtro: 'ativas',
                titulo: 'Ativas',
                total: totalAcoesAtivas,
                icone: Icons.play_circle_outline,
              ),
              const SizedBox(width: 8),
              botaoFiltroAcoes(
                filtro: 'inativas',
                titulo: 'Inativas',
                total: totalAcoesInativas,
                icone: Icons.history_toggle_off,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: carregando || lista.isEmpty
                      ? null
                      : visualizarRelatorioAcoes,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Visualizar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: corPrimaria,
                    side: BorderSide(color: corPrimaria.withValues(alpha: 0.7)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: carregando || lista.isEmpty || exportandoRelatorio
                      ? null
                      : baixarRelatorioAcoes,
                  icon: exportandoRelatorio
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Baixar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: corPrimaria,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (carregando)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (erroCarregamento != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                erroCarregamento!,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else if (acoes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: Text(
                  'Nenhuma acao de validade cadastrada.',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            )
          else if (lista.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: Text(
                  filtroAcoes == 'ativas'
                      ? 'Nenhuma acao ativa no momento.'
                      : 'Nenhuma acao inativa encontrada.',
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
            )
          else
            ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: lista.length,
              separatorBuilder: (_, _) => const Divider(height: 18),
              itemBuilder: (_, index) => itemAcao(lista[index]),
            ),
        ],
      ),
    );
  }

  Widget itemAcao(Map<String, dynamic> acao) {
    final ativa = acaoEstaAtiva(acao);
    final vendida = numero(acao['quantidade_vendida_estimada']) ?? 0;
    final alvo = numero(acao['quantidade_promocional']) ?? 0;
    final progresso = alvo <= 0 ? 0.0 : (vendida / alvo).clamp(0.0, 1.0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: ativa ? () => encerrarManual(acao) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: ativa
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.grey.withValues(alpha: 0.16),
                child: Icon(
                  ativa ? Icons.timer_outlined : Icons.check_circle_outline,
                  color: ativa ? Colors.green.shade700 : Colors.grey,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            texto(acao['nome_produto']),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        statusChip(acao),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'EAN: ${texto(acao['ean'])} | Validade: ${dataCurta(acao['data_validade'])}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${moeda(acao['preco_original'])} -> ${moeda(acao['preco_promocional'])}',
                      style: TextStyle(
                        color: corPrimaria,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 7,
                        value: progresso,
                        backgroundColor: Colors.black.withValues(alpha: 0.08),
                        color: ativa ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Vendido estimado: ${quantidadeTexto(vendida)} de ${quantidadeTexto(alvo)} | Estoque atual: ${quantidadeTexto(acao['estoque_atual_ultima'])}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                    if ((acao['alerta_mensagem']?.toString().isNotEmpty ??
                        false)) ...[
                      const SizedBox(height: 6),
                      Text(
                        acao['alerta_mensagem'].toString(),
                        style: const TextStyle(
                          color: Color(0xFF92400E),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (ativa)
                PopupMenuButton<String>(
                  onSelected: (_) => encerrarManual(acao),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'encerrar',
                      child: Text('Encerrar agora'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget statusChip(Map<String, dynamic> acao) {
    final status = acao['status']?.toString().toUpperCase() ?? 'ATIVA';
    final ativa = status == 'ATIVA' && acao['ativo'] == true;
    final cor = ativa
        ? Colors.green
        : status == 'ENCERRADA_VALIDADE'
        ? Colors.orange
        : Colors.grey;
    final textoStatus = statusTextoAcao(acao);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        textoStatus,
        style: TextStyle(
          color: cor.shade700,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lojaConectada = mercadoIdAtual != null;

    return Scaffold(
      backgroundColor: corFundo,
      appBar: AppBar(
        title: const Text('Acoes de validade'),
        backgroundColor: corPrimaria,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: !lojaConectada
            ? const Center(child: Text('Loja atual nao identificada.'))
            : RefreshIndicator(
                onRefresh: () => carregarAcoes(),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    topo(),
                    const SizedBox(height: 14),
                    cardAlertas(),
                    if (alertas.isNotEmpty) const SizedBox(height: 14),
                    campoBusca(),
                    const SizedBox(height: 14),
                    listaAcoes(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/central_service.dart';
import '../../services/etiqueta_balanca_service.dart';
import '../../services/sessao_loja.dart';
import 'scanner.dart';

class ConferenciaNotasPage extends StatefulWidget {
  const ConferenciaNotasPage({super.key});

  @override
  State<ConferenciaNotasPage> createState() => _ConferenciaNotasPageState();
}

class _ConferenciaNotasPageState extends State<ConferenciaNotasPage> {
  final centralService = CentralService();
  final buscaController = TextEditingController();

  bool carregando = false;
  String erro = '';
  List<Map<String, dynamic>> notas = [];
  bool tokenConferenciaCarregado = false;
  String tokenConferencia = '';
  bool exibindoConferidas = false;

  Color get corPrimaria => SessaoLoja.corPrimaria;
  Color get corFundo => SessaoLoja.corFundo;

  @override
  void dispose() {
    buscaController.dispose();
    super.dispose();
  }

  String baseUrlConferencia() {
    final api = SessaoLoja.apiBaseUrl?.trim();

    if (api == null || api.isEmpty) {
      throw Exception('API da loja nao configurada.');
    }

    try {
      final uri = Uri.parse(api.replaceAll(RegExp(r'/+$'), ''));

      if (uri.hasScheme && uri.host.isNotEmpty) {
        return uri
            .replace(port: 35000)
            .toString()
            .replaceAll(RegExp(r'/+$'), '');
      }
    } catch (_) {}

    return api.replaceAll(RegExp(r'/+$'), '').replaceFirst(':34000', ':35000');
  }

  Map<String, String> jsonHeaders() {
    final headers = <String, String>{'Content-Type': 'application/json'};

    if (tokenConferencia.trim().isNotEmpty) {
      headers['x-api-key'] = tokenConferencia.trim();
    }

    return headers;
  }

  dynamic decodeResposta(http.Response resposta) {
    if (resposta.body.trim().isEmpty) return {};
    return jsonDecode(resposta.body);
  }

  bool respostaSucesso(http.Response resposta) {
    return resposta.statusCode >= 200 && resposta.statusCode < 300;
  }

  String mensagemErro(dynamic data, http.Response resposta) {
    if (data is Map && data['erro'] != null) {
      return data['erro'].toString();
    }
    if (data is Map && data['mensagem'] != null) {
      return data['mensagem'].toString();
    }
    return 'Erro HTTP ${resposta.statusCode}';
  }

  String texto(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? '-' : texto;
  }

  String chaveNormalizada(dynamic valor) {
    return valor?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '';
  }

  bool possuiValor(dynamic valor) {
    final valorTexto = valor?.toString().trim() ?? '';
    return valorTexto.isNotEmpty && valorTexto != '-';
  }

  String numeroNota(Map<String, dynamic> nota) {
    if (possuiValor(nota['numero_nota'])) {
      return texto(nota['numero_nota']);
    }

    final chave = chaveNormalizada(nota['chave_nfe']);
    if (chave.length != 44) return '-';
    return (int.tryParse(chave.substring(25, 34)) ?? 0).toString();
  }

  String serieNota(Map<String, dynamic> nota) {
    if (possuiValor(nota['serie'])) {
      return texto(nota['serie']);
    }

    final chave = chaveNormalizada(nota['chave_nfe']);
    if (chave.length != 44) return '-';
    return (int.tryParse(chave.substring(22, 25)) ?? 0).toString();
  }

  dynamic cienciaNota(Map<String, dynamic> nota) {
    if (possuiValor(nota['ciencia_nota'])) {
      return nota['ciencia_nota'];
    }

    return texto(nota['status_manifestacao']).toUpperCase() == 'CIENCIA'
        ? 'S'
        : null;
  }

  String dataCurta(dynamic valor) {
    final textoData = valor?.toString() ?? '';
    if (textoData.length >= 10) {
      return textoData.substring(0, 10).split('-').reversed.join('/');
    }
    return textoData.isEmpty ? '-' : textoData;
  }

  String moeda(dynamic valor) {
    final numero = double.tryParse(valor?.toString() ?? '');
    if (numero == null) return 'R\$ 0,00';
    return 'R\$ ${numero.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String simNao(dynamic valor) {
    final textoStatus = texto(valor).toUpperCase();
    if (textoStatus == 'S') return 'Sim';
    if (textoStatus == 'N') return 'Nao';
    return texto(valor);
  }

  Future<void> carregarTokenConferenciaSeNecessario() async {
    if (tokenConferenciaCarregado) return;

    tokenConferenciaCarregado = true;

    final mercadoId = SessaoLoja.mercadoId?.trim();
    if (mercadoId == null || mercadoId.isEmpty) return;

    try {
      final conexao = await centralService.buscarConexaoMercado(mercadoId);
      final token = conexao['estoque_update_token']?.toString().trim() ?? '';

      if (token.isNotEmpty) {
        tokenConferencia = token;
      }
    } catch (_) {
      tokenConferencia = '';
    }
  }

  Future<void> listarNotasDiamante() async {
    if (!mounted) return;

    setState(() {
      carregando = true;
      erro = '';
    });

    try {
      await carregarTokenConferenciaSeNecessario();

      final uri = Uri.parse('${baseUrlConferencia()}/notas-diamante').replace(
        queryParameters: {
          'limite': '100',
          'aceito': 'n',
          if (buscaController.text.trim().isNotEmpty)
            'busca': buscaController.text.trim(),
        },
      );

      final resposta = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = decodeResposta(resposta);

      if (!respostaSucesso(resposta)) {
        throw Exception(mensagemErro(data, resposta));
      }

      final lista = data is Map && data['notas'] is List
          ? List<Map<String, dynamic>>.from(data['notas'])
          : <Map<String, dynamic>>[];

      if (!mounted) return;
      setState(() {
        notas = lista;
        exibindoConferidas = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => erro = CentralService.mensagemErroUsuario(e));
    } finally {
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<List<Map<String, dynamic>>> buscarNotasConferidasPorStatus(
    String status,
  ) async {
    final uri = Uri.parse('${baseUrlConferencia()}/notas-entrada').replace(
      queryParameters: {
        'limite': '100',
        'status': status,
        if (buscaController.text.trim().isNotEmpty)
          'busca': buscaController.text.trim(),
      },
    );

    final resposta = await http.get(uri).timeout(const Duration(seconds: 30));
    final data = decodeResposta(resposta);

    if (!respostaSucesso(resposta)) {
      throw Exception(mensagemErro(data, resposta));
    }

    return data is Map && data['notas'] is List
        ? List<Map<String, dynamic>>.from(data['notas'])
        : <Map<String, dynamic>>[];
  }

  Future<void> listarNotasConferidas() async {
    if (!mounted) return;

    setState(() {
      carregando = true;
      erro = '';
    });

    try {
      await carregarTokenConferenciaSeNecessario();

      final todas = <Map<String, dynamic>>[];
      for (final status in ['CONCLUIDA', 'DIVERGENTE']) {
        todas.addAll(await buscarNotasConferidasPorStatus(status));
      }

      final porChave = <String, Map<String, dynamic>>{};
      for (final nota in todas) {
        final chave = chaveNormalizada(nota['chave_nfe']);
        if (chave.length != 44) continue;
        porChave[chave] = nota;
      }

      final lista = porChave.values.toList()
        ..sort((a, b) {
          final dataA = (a['atualizado_em'] ?? a['data_emissao'] ?? '')
              .toString();
          final dataB = (b['atualizado_em'] ?? b['data_emissao'] ?? '')
              .toString();
          return dataB.compareTo(dataA);
        });

      if (!mounted) return;
      setState(() {
        notas = lista;
        exibindoConferidas = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => erro = CentralService.mensagemErroUsuario(e));
    } finally {
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> buscarNotasAtual() {
    return exibindoConferidas ? listarNotasConferidas() : listarNotasDiamante();
  }

  Future<void> abrirNota(Map<String, dynamic> nota) async {
    await carregarTokenConferenciaSeNecessario();

    if (!mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ConferenciaNotaDetalhePage(
          notaInicial: nota,
          baseUrl: baseUrlConferencia(),
          headers: jsonHeaders(),
        ),
      ),
    );
  }

  Widget chip(String titulo, dynamic valor, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cor.withValues(alpha: 0.22)),
      ),
      child: Text(
        '$titulo: ${simNao(valor)}',
        style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget notaCard(Map<String, dynamic> nota) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => abrirNota(nota),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: corPrimaria.withValues(alpha: 0.16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.055),
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
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: corPrimaria.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.receipt_long, color: corPrimaria),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        texto(nota['nome_emitente']),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'NF ${numeroNota(nota)} | Serie ${serieNota(nota)}',
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFF6B7280)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (nota['status_conferencia'] != null)
                  chip('Status', nota['status_conferencia'], Colors.green),
                if (possuiValor(nota['nota_lancada']))
                  chip('Lancada', nota['nota_lancada'], Colors.blueGrey),
                if (possuiValor(cienciaNota(nota)))
                  chip('Ciencia', cienciaNota(nota), Colors.indigo),
                if (possuiValor(nota['aceito']))
                  chip('Aceita', nota['aceito'], Colors.orange),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Emissao: ${dataCurta(nota['data_emissao'])}',
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  moeda(nota['valor_total']),
                  style: TextStyle(
                    color: corPrimaria,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: corFundo,
      appBar: AppBar(
        title: const Text('Conferencia NF-e'),
        backgroundColor: corPrimaria,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: corPrimaria,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: corPrimaria.withValues(alpha: 0.20),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.fact_check_outlined,
                    color: Colors.white,
                    size: 34,
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Conferencia de entrada',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Liste as notas pendentes do Diamante e confira os itens na entrega.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  TextField(
                    controller: buscaController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => buscarNotasAtual(),
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.search, color: corPrimaria),
                      hintText: 'Fornecedor, numero ou chave da NF-e',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: carregando ? null : listarNotasDiamante,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: corPrimaria,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: carregando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.list_alt),
                      label: Text(
                        carregando ? 'Buscando...' : 'Listar notas do Diamante',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: carregando ? null : listarNotasConferidas,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: corPrimaria,
                        side: BorderSide(color: corPrimaria),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.history),
                      label: const Text(
                        'Notas conferidas',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (erro.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ErroBox(erro: erro),
            ],
            const SizedBox(height: 16),
            if (!carregando && notas.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  exibindoConferidas
                      ? 'Nenhuma nota conferida encontrada.'
                      : 'Clique em Listar notas do Diamante para pendentes ou em Notas conferidas para reabrir notas finalizadas.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF6B7280)),
                ),
              )
            else
              ...notas.map(notaCard),
          ],
        ),
      ),
    );
  }
}

class ConferenciaNotaDetalhePage extends StatefulWidget {
  final Map<String, dynamic> notaInicial;
  final String baseUrl;
  final Map<String, String> headers;

  const ConferenciaNotaDetalhePage({
    super.key,
    required this.notaInicial,
    required this.baseUrl,
    required this.headers,
  });

  @override
  State<ConferenciaNotaDetalhePage> createState() =>
      _ConferenciaNotaDetalhePageState();
}

class _ConferenciaNotaDetalhePageState
    extends State<ConferenciaNotaDetalhePage> {
  Map<String, dynamic> nota = {};
  List<Map<String, dynamic>> itens = [];
  bool carregandoItens = true;
  bool dandoCiencia = false;
  bool buscandoSefaz = false;
  String erro = '';

  Color get corPrimaria => SessaoLoja.corPrimaria;
  Color get corFundo => SessaoLoja.corFundo;

  @override
  void initState() {
    super.initState();
    nota = Map<String, dynamic>.from(widget.notaInicial);
    carregarItensSalvos();
  }

  dynamic decodeResposta(http.Response resposta) {
    if (resposta.body.trim().isEmpty) return {};
    return jsonDecode(resposta.body);
  }

  bool respostaSucesso(http.Response resposta) {
    return resposta.statusCode >= 200 && resposta.statusCode < 300;
  }

  String texto(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? '-' : texto;
  }

  String mensagemErro(dynamic data, http.Response resposta) {
    if (data is Map && data['erro'] != null) {
      final partes = <String>[data['erro'].toString()];
      final liberadoEm = data['liberado_em'] ?? data['proxima_tentativa_em'];
      final liberado = dataHora(liberadoEm);
      final motivoSefaz = data['ultimo_xmotivo']?.toString().trim();

      if (liberado != null && liberado.isAfter(DateTime.now())) {
        partes.add('Tente novamente apos ${horaCurta(liberado)}.');
      }

      if (motivoSefaz != null && motivoSefaz.isNotEmpty) {
        partes.add('Retorno SEFAZ: $motivoSefaz');
      }

      return partes.join('\n');
    }
    if (data is Map && data['mensagem'] != null) {
      return data['mensagem'].toString();
    }
    return 'Erro HTTP ${resposta.statusCode}';
  }

  DateTime? dataHora(dynamic valor) {
    final textoData = valor?.toString().trim() ?? '';
    if (textoData.isEmpty) return null;

    final data = DateTime.tryParse(textoData);
    return data?.toLocal();
  }

  String horaCurta(DateTime data) {
    final hora = data.hour.toString().padLeft(2, '0');
    final minuto = data.minute.toString().padLeft(2, '0');
    return '$hora:$minuto';
  }

  bool get notaFinalizada {
    final status = texto(nota['status_conferencia']).toUpperCase();
    return status == 'CONCLUIDA' || status == 'DIVERGENTE';
  }

  String textoBotaoBuscaSefaz() {
    if (buscandoSefaz) return 'Buscando itens...';
    if (notaFinalizada && itens.isNotEmpty) return 'Conferencia finalizada';
    return itens.isEmpty ? 'Buscar itens na SEFAZ' : 'Abrir conferencia';
  }

  String quantidade(dynamic valor) {
    final numero = double.tryParse(valor?.toString() ?? '') ?? 0;
    if (numero == numero.roundToDouble()) return numero.toStringAsFixed(0);
    return numero.toStringAsFixed(3).replaceAll('.', ',');
  }

  String somenteNumeros(dynamic valor) {
    return valor?.toString().replaceAll(RegExp(r'\D'), '') ?? '';
  }

  bool eanIgual(dynamic a, dynamic b) {
    final codigoA = somenteNumeros(a);
    final codigoB = somenteNumeros(b);
    if (codigoA.isEmpty || codigoB.isEmpty) return false;

    final semZerosA = codigoA.replaceFirst(RegExp(r'^0+'), '');
    final semZerosB = codigoB.replaceFirst(RegExp(r'^0+'), '');
    return (semZerosA.isEmpty ? codigoA : semZerosA) ==
        (semZerosB.isEmpty ? codigoB : semZerosB);
  }

  bool eanNotaIgualReal(Map<String, dynamic> item) {
    return eanIgual(item['ean_nota'], item['ean_real']) ||
        eanIgual(item['ean_tributavel'], item['ean_real']);
  }

  bool itemDivergente(Map<String, dynamic> item) {
    final status = texto(item['status_conferencia']).toUpperCase();
    final pendente =
        double.tryParse(item['quantidade_pendente']?.toString() ?? '') ?? 0;
    if (status == 'MAPEADO_MISTO' || status == 'MISTO') return true;
    if (eanNotaIgualReal(item)) return false;
    return status == 'DIVERGENTE' || pendente < 0;
  }

  bool itemSemMapeamento(Map<String, dynamic> item) {
    final produtoId = item['produto_id_diamante'];
    final status = texto(item['status_conferencia']).toUpperCase();
    if (eanNotaIgualReal(item)) return false;
    if (status == 'CONFERIDO') return false;
    return produtoId == null &&
        status != 'DIVERGENTE' &&
        status != 'MAPEADO_MISTO';
  }

  bool itemTemBipe(Map<String, dynamic> item) {
    return quantidadeInformadaItem(item) > 0;
  }

  double quantidadeInformadaItem(Map<String, dynamic> item) {
    for (final campo in [
      'quantidade_bipada_total',
      'quantidade_conferida',
      'quantidade_bipada',
      'quantidade_informada',
    ]) {
      final valor = double.tryParse(item[campo]?.toString() ?? '');
      if (valor != null && valor > 0) return valor;
    }

    return 0;
  }

  bool itemConferido(Map<String, dynamic> item) {
    final status = texto(item['status_conferencia']).toUpperCase();
    return status == 'CONFERIDO' || itemTemBipe(item);
  }

  bool itemMisto(Map<String, dynamic> item) {
    final status = texto(item['status_conferencia']).toUpperCase();
    return status == 'MAPEADO_MISTO' || item['caixa_mista'] is Map;
  }

  String statusVisual(Map<String, dynamic> item) {
    if (itemMisto(item)) return 'Caixa mista';
    if (itemDivergente(item)) return 'Divergente';
    if (itemConferido(item)) return 'Conferido';
    if (itemSemMapeamento(item)) return 'Associar codigo';
    return 'Pendente';
  }

  List<Map<String, dynamic>> itensMistos(Map<String, dynamic> item) {
    final caixa = item['caixa_mista'];
    if (caixa is! Map || caixa['itens'] is! List) return [];
    return List<Map<String, dynamic>>.from(caixa['itens'] as List);
  }

  Future<void> carregarItensSalvos() async {
    setState(() {
      carregandoItens = true;
      erro = '';
    });

    try {
      final chave = texto(nota['chave_nfe']);
      final resposta = await http
          .get(Uri.parse('${widget.baseUrl}/notas-entrada/$chave/itens'))
          .timeout(const Duration(seconds: 20));

      if (resposta.statusCode == 404) {
        if (!mounted) return;
        setState(() => itens = []);
        return;
      }

      final data = decodeResposta(resposta);
      if (!respostaSucesso(resposta)) {
        throw Exception(mensagemErro(data, resposta));
      }

      if (!mounted) return;
      setState(() {
        nota = data is Map && data['nota'] is Map
            ? Map<String, dynamic>.from(data['nota'])
            : nota;
        itens = data is Map && data['itens'] is List
            ? List<Map<String, dynamic>>.from(data['itens'])
            : [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => erro = CentralService.mensagemErroUsuario(e));
    } finally {
      if (mounted) setState(() => carregandoItens = false);
    }
  }

  Future<void> darCiencia() async {
    setState(() {
      dandoCiencia = true;
      erro = '';
    });

    try {
      final chave = texto(nota['chave_nfe']);
      final resposta = await http
          .post(
            Uri.parse('${widget.baseUrl}/notas-entrada/$chave/ciencia'),
            headers: widget.headers,
            body: jsonEncode({}),
          )
          .timeout(const Duration(seconds: 40));
      final data = decodeResposta(resposta);

      if (!respostaSucesso(resposta)) {
        throw Exception(mensagemErro(data, resposta));
      }

      if (!mounted) return;
      setState(() {
        nota['status_manifestacao'] = 'CIENCIA';
        nota['ciencia_nota'] = 'S';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ciencia registrada para esta nota.'),
          backgroundColor: Colors.green,
        ),
      );

      await carregarItensSalvos();
    } catch (e) {
      if (!mounted) return;
      setState(() => erro = CentralService.mensagemErroUsuario(e));
    } finally {
      if (mounted) setState(() => dandoCiencia = false);
    }
  }

  Future<void> buscarItensSefazEConferir() async {
    setState(() {
      buscandoSefaz = true;
      erro = '';
    });

    try {
      final chave = texto(nota['chave_nfe']);

      if (itens.isEmpty) {
        final resposta = await http
            .post(
              Uri.parse(
                '${widget.baseUrl}/notas-diamante/$chave/buscar-itens-sefaz',
              ),
              headers: widget.headers,
              body: jsonEncode({}),
            )
            .timeout(const Duration(seconds: 180));
        final data = decodeResposta(resposta);

        if (!respostaSucesso(resposta)) {
          throw Exception(mensagemErro(data, resposta));
        }
      }

      final respostaConferencia = await http
          .post(
            Uri.parse('${widget.baseUrl}/notas-entrada/$chave/conferencias'),
            headers: widget.headers,
            body: jsonEncode({
              'usuario_login':
                  SessaoLoja.usuarioLogin ?? SessaoLoja.usuarioNome,
            }),
          )
          .timeout(const Duration(seconds: 30));
      final dataConferencia = decodeResposta(respostaConferencia);

      if (!respostaSucesso(respostaConferencia)) {
        throw Exception(mensagemErro(dataConferencia, respostaConferencia));
      }

      final conferencia = dataConferencia is Map
          ? Map<String, dynamic>.from(
              dataConferencia['conferencia'] ??
                  dataConferencia['dados'] ??
                  dataConferencia,
            )
          : <String, dynamic>{};
      final conferenciaId = conferencia['id']?.toString() ?? '';

      if (conferenciaId.isEmpty) {
        throw Exception('A API nao retornou o id da conferencia.');
      }

      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ConferenciaBipagemPage(
            baseUrl: widget.baseUrl,
            headers: widget.headers,
            conferenciaId: conferenciaId,
          ),
        ),
      );

      if (mounted) carregarItensSalvos();
    } catch (e) {
      if (!mounted) return;
      setState(() => erro = CentralService.mensagemErroUsuario(e));
    } finally {
      if (mounted) setState(() => buscandoSefaz = false);
    }
  }

  Widget itemPreview(Map<String, dynamic> item) {
    final divergente = itemDivergente(item);
    final semMapeamento = itemSemMapeamento(item);
    final misto = itemMisto(item);
    final conferido = itemConferido(item);
    final codigoOk = conferido;
    final internos = itensMistos(item);
    final cor = divergente || semMapeamento
        ? Colors.red
        : codigoOk
        ? Colors.green
        : corPrimaria;
    final fundoCard = divergente || semMapeamento
        ? const Color(0xFFFFE0E0)
        : codigoOk
        ? const Color(0xFFE4FBEA)
        : Colors.white;
    final corBorda = divergente || semMapeamento
        ? Colors.red.withValues(alpha: 0.70)
        : codigoOk
        ? Colors.green.withValues(alpha: 0.55)
        : cor.withValues(alpha: 0.38);
    final quantidadeBipada = quantidadeInformadaItem(item);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fundoCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: corBorda, width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  texto(item['descricao']),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                misto
                    ? Icons.inventory_2_outlined
                    : divergente
                    ? Icons.warning_amber_rounded
                    : semMapeamento
                    ? Icons.link_off
                    : conferido
                    ? Icons.check_circle_outline
                    : Icons.touch_app_outlined,
                color: cor,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            'Nota/Caixa: ${texto(item['ean_nota'])} | Item: ${texto(item['ean_real'])}',
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Qtd nota: ${quantidade(item['quantidade_comercial'])} ${texto(item['unidade_comercial'])}',
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          ),
          if (quantidadeBipada > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Qtd informada: ${quantidade(quantidadeBipada)}',
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cor.withValues(alpha: 0.34)),
            ),
            child: Text(
              statusVisual(item),
              style: TextStyle(
                color: cor,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
          if (internos.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Itens internos da caixa',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...internos.map(
                    (interno) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '${texto(interno['ean_real'])} - qtd ${quantidade(interno['quantidade'])}',
                        style: const TextStyle(
                          color: Color(0xFF7F1D1D),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chave = texto(nota['chave_nfe']);
    final cienciaRegistrada =
        texto(nota['status_manifestacao']).toUpperCase() == 'CIENCIA' ||
        texto(nota['ciencia_nota']).toUpperCase() == 'S';

    return Scaffold(
      backgroundColor: corFundo,
      appBar: AppBar(
        title: const Text('Nota de entrada'),
        backgroundColor: corPrimaria,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    texto(nota['nome_emitente']),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'NF ${texto(nota['numero_nota'])} | Serie ${texto(nota['serie'])}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    chave,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: dandoCiencia || cienciaRegistrada
                    ? null
                    : darCiencia,
                style: OutlinedButton.styleFrom(
                  foregroundColor: corPrimaria,
                  side: BorderSide(color: corPrimaria),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: dandoCiencia
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: corPrimaria,
                        ),
                      )
                    : Icon(
                        cienciaRegistrada
                            ? Icons.verified_outlined
                            : Icons.fact_check_outlined,
                      ),
                label: Text(
                  dandoCiencia
                      ? 'Registrando ciencia...'
                      : cienciaRegistrada
                      ? 'Ciencia registrada'
                      : 'Dar ciencia na nota',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: buscandoSefaz || notaFinalizada
                    ? null
                    : buscarItensSefazEConferir,
                style: ElevatedButton.styleFrom(
                  backgroundColor: corPrimaria,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: buscandoSefaz
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.cloud_download_outlined),
                label: Text(
                  textoBotaoBuscaSefaz(),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            if (erro.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ErroBox(erro: erro),
            ],
            const SizedBox(height: 16),
            Text(
              itens.isEmpty
                  ? 'Itens ainda nao carregados'
                  : 'Itens encontrados',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 10),
            if (carregandoItens)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (itens.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Ao clicar em Buscar itens na SEFAZ, o XML sera consultado e a tela de conferencia sera aberta.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF6B7280)),
                ),
              )
            else
              ...itens.map(itemPreview),
          ],
        ),
      ),
    );
  }
}

class _AssociarItemDialog extends StatefulWidget {
  const _AssociarItemDialog({
    required this.descricao,
    required this.corPrimaria,
    required this.quantidadeInicial,
  });

  final String descricao;
  final Color corPrimaria;
  final String quantidadeInicial;

  @override
  State<_AssociarItemDialog> createState() => _AssociarItemDialogState();
}

class _AssociarItemDialogState extends State<_AssociarItemDialog> {
  final eanController = TextEditingController();
  final fatorController = TextEditingController(text: '1');
  final eanMistoController = TextEditingController();
  final quantidadeMistaController = TextEditingController(text: '1');
  final eanFocus = FocusNode();
  final fatorFocus = FocusNode();
  final eanMistoFocus = FocusNode();
  final quantidadeMistaFocus = FocusNode();

  bool caixaMista = false;
  String erro = '';
  final itensMistos = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    if (widget.quantidadeInicial.trim().isNotEmpty) {
      fatorController.text = widget.quantidadeInicial;
    }
  }

  @override
  void dispose() {
    eanFocus.dispose();
    fatorFocus.dispose();
    eanMistoFocus.dispose();
    quantidadeMistaFocus.dispose();
    eanController.dispose();
    fatorController.dispose();
    eanMistoController.dispose();
    quantidadeMistaController.dispose();
    super.dispose();
  }

  String somenteNumeros(String valor) {
    return valor.replaceAll(RegExp(r'\D'), '');
  }

  String normalizarEan(String valor) {
    final numeros = somenteNumeros(valor);
    if (numeros.isEmpty) return '';
    if (numeros.length < 14) return numeros.padLeft(14, '0');
    return numeros;
  }

  double numeroQuantidade(String valor) {
    return double.tryParse(valor.trim().replaceAll(',', '.')) ?? 0;
  }

  String quantidadeTexto(dynamic valor) {
    final numero = valor is num
        ? valor.toDouble()
        : double.tryParse(valor?.toString() ?? '') ?? 0;
    if (numero == numero.roundToDouble()) return numero.toStringAsFixed(0);
    return numero.toStringAsFixed(3).replaceAll('.', ',');
  }

  void fechar([Map<String, dynamic>? resultado]) {
    FocusScope.of(context).unfocus();
    Navigator.pop(context, resultado);
  }

  Future<void> scanearItemMisto() async {
    FocusScope.of(context).unfocus();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerPage(
          onDetect: (codigo) {
            if (!mounted) return;
            setState(() {
              eanMistoController.text = codigo.trim();
              erro = '';
            });
          },
        ),
      ),
    );
  }

  Future<void> scanearProdutoUnico() async {
    FocusScope.of(context).unfocus();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerPage(
          onDetect: (codigo) {
            if (!mounted) return;
            setState(() {
              eanController.text = codigo.trim();
              erro = '';
            });
          },
        ),
      ),
    );
  }

  void adicionarItemMisto() {
    final ean = normalizarEan(eanMistoController.text);
    final quantidade = numeroQuantidade(quantidadeMistaController.text);

    if (ean.isEmpty) {
      setState(() => erro = 'Informe ou escaneie o EAN do item interno.');
      return;
    }

    if (quantidade <= 0) {
      setState(() => erro = 'Informe a quantidade deste item dentro da caixa.');
      return;
    }

    final existente = itensMistos.indexWhere((item) => item['ean_real'] == ean);

    setState(() {
      if (existente >= 0) {
        itensMistos[existente]['quantidade'] =
            (itensMistos[existente]['quantidade'] as double) + quantidade;
      } else {
        itensMistos.add({'ean_real': ean, 'quantidade': quantidade});
      }

      eanMistoController.clear();
      quantidadeMistaController.text = '1';
      erro = '';
    });
  }

  void salvar() {
    if (caixaMista) {
      if (itensMistos.isEmpty) {
        setState(() => erro = 'Adicione ao menos um item interno da caixa.');
        return;
      }

      fechar({'tipo_associacao': 'MISTA', 'itens_mistos': itensMistos});
      return;
    }

    final ean = normalizarEan(eanController.text);
    final quantidade = numeroQuantidade(fatorController.text);

    if (ean.isEmpty) {
      setState(() => erro = 'Informe o EAN real do produto.');
      return;
    }

    if (quantidade <= 0) {
      setState(() => erro = 'Informe uma quantidade maior que zero.');
      return;
    }

    fechar({
      'tipo_associacao': 'UNICO',
      'ean_real': ean,
      'fator_conversao': '1',
      'quantidade': quantidade.toString(),
    });
  }

  Widget modoBotao({
    required bool selecionado,
    required IconData icone,
    required String titulo,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: selecionado
                ? widget.corPrimaria.withValues(alpha: 0.10)
                : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selecionado ? widget.corPrimaria : const Color(0xFFE5E7EB),
              width: selecionado ? 1.4 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icone,
                color: selecionado ? widget.corPrimaria : Colors.grey,
              ),
              const SizedBox(height: 6),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selecionado
                      ? widget.corPrimaria
                      : const Color(0xFF374151),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget camposProdutoUnico() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: eanController,
                focusNode: eanFocus,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'EAN do item recebido',
                  helperText: 'Informe ou escaneie o codigo recebido.',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Escanear codigo recebido',
              onPressed: scanearProdutoUnico,
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: fatorController,
          focusNode: fatorFocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Quantidade recebida',
            helperText: 'Substitui a quantidade informada anteriormente.',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget camposCaixaMista() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: eanMistoController,
                focusNode: eanMistoFocus,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'EAN do item interno',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Escanear item interno',
              onPressed: scanearItemMisto,
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: quantidadeMistaController,
                focusNode: quantidadeMistaFocus,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Quantidade',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: adicionarItemMisto,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (itensMistos.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: const Text(
              'Adicione os EANs e quantidades que existem dentro desta caixa.',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
            ),
          )
        else
          ...itensMistos.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: widget.corPrimaria.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.corPrimaria.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item['ean_real']} | ${quantidadeTexto(item['quantidade'])} un',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      setState(() => itensMistos.removeAt(index));
                    },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Associar item'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.descricao,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  modoBotao(
                    selecionado: !caixaMista,
                    icone: Icons.inventory_2_outlined,
                    titulo: 'Produto unico',
                    onTap: () => setState(() {
                      caixaMista = false;
                      erro = '';
                    }),
                  ),
                  const SizedBox(width: 8),
                  modoBotao(
                    selecionado: caixaMista,
                    icone: Icons.category_outlined,
                    titulo: 'Caixa mista',
                    onTap: () => setState(() {
                      caixaMista = true;
                      erro = '';
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (caixaMista) camposCaixaMista() else camposProdutoUnico(),
              if (erro.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  erro,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: fechar, child: const Text('Cancelar')),
        ElevatedButton(onPressed: salvar, child: const Text('Salvar')),
      ],
    );
  }
}

class _QuantidadeBipeDialog extends StatefulWidget {
  final String ean;
  final Color corPrimaria;

  const _QuantidadeBipeDialog({required this.ean, required this.corPrimaria});

  @override
  State<_QuantidadeBipeDialog> createState() => _QuantidadeBipeDialogState();
}

class _QuantidadeBipeDialogState extends State<_QuantidadeBipeDialog> {
  final quantidadeController = TextEditingController(text: '1');
  final quantidadeFocus = FocusNode();
  String erro = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      quantidadeFocus.requestFocus();
      quantidadeController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: quantidadeController.text.length,
      );
    });
  }

  @override
  void dispose() {
    quantidadeController.dispose();
    quantidadeFocus.dispose();
    super.dispose();
  }

  double quantidade() {
    return double.tryParse(
          quantidadeController.text.trim().replaceAll(',', '.'),
        ) ??
        0;
  }

  void confirmar() {
    final valor = quantidade();
    if (valor <= 0) {
      setState(() => erro = 'Informe uma quantidade maior que zero.');
      return;
    }

    Navigator.pop(context, valor);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quantidade recebida'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EAN ${widget.ean}',
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: quantidadeController,
            focusNode: quantidadeFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => confirmar(),
            decoration: const InputDecoration(
              labelText: 'Quantidade',
              border: OutlineInputBorder(),
            ),
          ),
          if (erro.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              erro,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: confirmar,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.corPrimaria,
            foregroundColor: Colors.white,
          ),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

class ConferenciaBipagemPage extends StatefulWidget {
  final String baseUrl;
  final Map<String, String> headers;
  final String conferenciaId;

  const ConferenciaBipagemPage({
    super.key,
    required this.baseUrl,
    required this.headers,
    required this.conferenciaId,
  });

  @override
  State<ConferenciaBipagemPage> createState() => _ConferenciaBipagemPageState();
}

class _ConferenciaBipagemPageState extends State<ConferenciaBipagemPage> {
  final codigoController = TextEditingController();

  Map<String, dynamic> conferencia = {};
  List<Map<String, dynamic>> itens = [];
  final Map<String, int> ordemProcessados = {};
  int proximaOrdemProcessado = 0;
  bool carregando = true;
  bool bipando = false;
  bool finalizando = false;
  String erro = '';
  ConfiguracaoEtiquetaBalanca? configuracaoEtiquetaBalanca;

  Color get corPrimaria => SessaoLoja.corPrimaria;
  Color get corFundo => SessaoLoja.corFundo;

  @override
  void initState() {
    super.initState();
    carregarConfiguracaoEtiquetaBalanca();
    carregar();
  }

  @override
  void dispose() {
    codigoController.dispose();
    super.dispose();
  }

  dynamic decodeResposta(http.Response resposta) {
    if (resposta.body.trim().isEmpty) return {};
    return jsonDecode(resposta.body);
  }

  bool respostaSucesso(http.Response resposta) {
    return resposta.statusCode >= 200 && resposta.statusCode < 300;
  }

  String texto(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? '-' : texto;
  }

  String mensagemErro(dynamic data, http.Response resposta) {
    if (data is Map && data['erro'] != null) {
      return data['erro'].toString();
    }
    if (data is Map && data['mensagem'] != null) {
      return data['mensagem'].toString();
    }
    return 'Erro HTTP ${resposta.statusCode}';
  }

  String quantidade(dynamic valor) {
    final numero = double.tryParse(valor?.toString() ?? '') ?? 0;
    if (numero == numero.roundToDouble()) return numero.toStringAsFixed(0);
    return numero.toStringAsFixed(3).replaceAll('.', ',');
  }

  String somenteNumeros(dynamic valor) {
    return valor?.toString().replaceAll(RegExp(r'\D'), '') ?? '';
  }

  bool eanIgual(dynamic a, dynamic b) {
    final codigoA = somenteNumeros(a);
    final codigoB = somenteNumeros(b);
    if (codigoA.isEmpty || codigoB.isEmpty) return false;

    final semZerosA = codigoA.replaceFirst(RegExp(r'^0+'), '');
    final semZerosB = codigoB.replaceFirst(RegExp(r'^0+'), '');
    return (semZerosA.isEmpty ? codigoA : semZerosA) ==
        (semZerosB.isEmpty ? codigoB : semZerosB);
  }

  bool eanNotaIgualReal(Map<String, dynamic> item) {
    return eanIgual(item['ean_nota'], item['ean_real']) ||
        eanIgual(item['ean_tributavel'], item['ean_real']);
  }

  bool itemDivergente(Map<String, dynamic> item) {
    final status = texto(item['status_conferencia']).toUpperCase();
    final pendente =
        double.tryParse(item['quantidade_pendente']?.toString() ?? '') ?? 0;
    if (status == 'MAPEADO_MISTO' || status == 'MISTO') return true;
    if (eanNotaIgualReal(item)) return false;
    return status == 'DIVERGENTE' || pendente < 0;
  }

  bool itemSemMapeamento(Map<String, dynamic> item) {
    final produtoId = item['produto_id_diamante'];
    final status = texto(item['status_conferencia']).toUpperCase();
    if (eanNotaIgualReal(item)) return false;
    if (status == 'CONFERIDO') return false;
    return produtoId == null &&
        status != 'DIVERGENTE' &&
        status != 'MAPEADO_MISTO';
  }

  bool itemTemBipe(Map<String, dynamic> item) {
    return quantidadeInformadaItem(item) > 0;
  }

  double quantidadeInformadaItem(Map<String, dynamic> item) {
    for (final campo in [
      'quantidade_bipada_total',
      'quantidade_conferida',
      'quantidade_bipada',
      'quantidade_informada',
    ]) {
      final valor = double.tryParse(item[campo]?.toString() ?? '');
      if (valor != null && valor > 0) return valor;
    }

    return 0;
  }

  bool itemConferido(Map<String, dynamic> item) {
    final status = texto(item['status_conferencia']).toUpperCase();
    return status == 'CONFERIDO' || itemTemBipe(item);
  }

  String idItem(Map<String, dynamic> item) {
    return item['id']?.toString().trim() ?? '';
  }

  bool itemProcessado(Map<String, dynamic> item) {
    final id = idItem(item);
    final status = texto(item['status_conferencia']).toUpperCase();
    return (id.isNotEmpty && ordemProcessados.containsKey(id)) ||
        itemTemBipe(item) ||
        status == 'CONFERIDO' ||
        status == 'MAPEADO_MISTO' ||
        status == 'MISTO' ||
        status == 'DIVERGENTE';
  }

  void registrarOrdemProcessado(dynamic itemId) {
    final id = itemId?.toString().trim() ?? '';
    if (id.isEmpty || ordemProcessados.containsKey(id)) return;
    ordemProcessados[id] = proximaOrdemProcessado++;
  }

  DateTime dataAtualizacaoItem(Map<String, dynamic> item) {
    return DateTime.tryParse(item['atualizado_em']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  void sincronizarOrdemProcessados(List<Map<String, dynamic>> novosItens) {
    final processados =
        novosItens.where((item) {
          final status = texto(item['status_conferencia']).toUpperCase();
          return itemTemBipe(item) ||
              status == 'CONFERIDO' ||
              status == 'MAPEADO_MISTO' ||
              status == 'MISTO' ||
              status == 'DIVERGENTE';
        }).toList()..sort(
          (a, b) => dataAtualizacaoItem(a).compareTo(dataAtualizacaoItem(b)),
        );

    for (final item in processados) {
      registrarOrdemProcessado(idItem(item));
    }
  }

  bool itemMisto(Map<String, dynamic> item) {
    final status = texto(item['status_conferencia']).toUpperCase();
    return status == 'MAPEADO_MISTO' || item['caixa_mista'] is Map;
  }

  bool itemPodeAssociar(Map<String, dynamic> item) {
    final eanNota = item['ean_nota']?.toString().trim() ?? '';
    final eanTributavel = item['ean_tributavel']?.toString().trim() ?? '';
    return eanNota.isNotEmpty ||
        eanTributavel.isNotEmpty ||
        itemSemMapeamento(item) ||
        itemDivergente(item) ||
        itemMisto(item);
  }

  String statusVisual(Map<String, dynamic> item) {
    if (itemMisto(item)) return 'Caixa mista';
    if (itemDivergente(item)) return 'Divergente';
    if (itemConferido(item)) return 'Conferido';
    if (itemSemMapeamento(item)) return 'Associar codigo';
    return 'Pendente';
  }

  List<Map<String, dynamic>> itensMistos(Map<String, dynamic> item) {
    final caixa = item['caixa_mista'];
    if (caixa is! Map || caixa['itens'] is! List) return [];
    return List<Map<String, dynamic>>.from(caixa['itens'] as List);
  }

  List<Map<String, dynamic>> itensOrdenados() {
    final copia = [...itens];
    copia.sort((a, b) {
      final processadoA = itemProcessado(a);
      final processadoB = itemProcessado(b);
      if (processadoA != processadoB) return processadoA ? 1 : -1;

      if (processadoA && processadoB) {
        final ordemA = ordemProcessados[idItem(a)] ?? (1 << 30);
        final ordemB = ordemProcessados[idItem(b)] ?? (1 << 30);
        if (ordemA != ordemB) return ordemA.compareTo(ordemB);
      }

      final na = int.tryParse(a['numero_item']?.toString() ?? '') ?? 0;
      final nb = int.tryParse(b['numero_item']?.toString() ?? '') ?? 0;
      return na.compareTo(nb);
    });
    return copia;
  }

  Future<void> carregarConfiguracaoEtiquetaBalanca() async {
    final cliente = SessaoLoja.supabaseLoja;
    if (cliente == null || !SessaoLoja.lojaSelecionada) return;

    try {
      final dados = await cliente
          .from('loja_configuracoes')
          .select()
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
          .limit(1)
          .maybeSingle();

      if (!mounted || dados == null) return;
      setState(() {
        configuracaoEtiquetaBalanca = ConfiguracaoEtiquetaBalanca.fromMap(
          Map<String, dynamic>.from(dados),
        );
      });
    } catch (_) {
      // Mantém a bipagem comum disponível enquanto a migração não for aplicada.
      configuracaoEtiquetaBalanca = null;
    }
  }

  String apiProdutos() {
    final api = SessaoLoja.apiBaseUrl?.trim() ?? '';
    if (api.isEmpty) {
      throw Exception('API de produtos da loja não configurada.');
    }
    return api.endsWith('/') ? api.substring(0, api.length - 1) : api;
  }

  List<Map<String, dynamic>> extrairProdutos(dynamic data) {
    dynamic lista = data;
    if (data is Map) {
      lista =
          data['produtos'] ??
          data['data'] ??
          data['resultado'] ??
          data['results'];
      if (lista == null &&
          (data['produto_id'] != null || data['ean_principal'] != null)) {
        return [Map<String, dynamic>.from(data)];
      }
    }
    if (lista is! List) return [];
    return lista
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String removerZerosEsquerda(dynamic valor) {
    final numeros = somenteNumeros(valor);
    if (numeros.isEmpty) return '';
    final normalizado = numeros.replaceFirst(RegExp(r'^0+'), '');
    return normalizado.isEmpty ? '0' : normalizado;
  }

  String eanProduto(Map<String, dynamic> produto) {
    return somenteNumeros(
      produto['ean_principal'] ??
          produto['ean'] ??
          produto['codigo_barras'] ??
          produto['codigo'],
    );
  }

  double numeroProduto(dynamic valor) {
    if (valor is num) return valor.toDouble();
    var textoNumero = valor?.toString().trim() ?? '';
    if (textoNumero.contains(',') && textoNumero.contains('.')) {
      textoNumero = textoNumero.replaceAll('.', '').replaceAll(',', '.');
    } else {
      textoNumero = textoNumero.replaceAll(',', '.');
    }
    return double.tryParse(textoNumero) ?? 0;
  }

  Future<Map<String, dynamic>> buscarProdutoEtiqueta(
    String codigoProduto,
  ) async {
    final uri = Uri.parse(
      '${apiProdutos()}/produto',
    ).replace(queryParameters: {'busca': codigoProduto});
    final resposta = await http.get(uri).timeout(const Duration(seconds: 30));
    final data = decodeResposta(resposta);

    if (!respostaSucesso(resposta)) {
      throw Exception(mensagemErro(data, resposta));
    }

    final produtos = extrairProdutos(data);
    if (produtos.isEmpty) {
      throw Exception(
        'Produto ${removerZerosEsquerda(codigoProduto)} não encontrado na base da loja.',
      );
    }

    final codigoNormalizado = removerZerosEsquerda(codigoProduto);
    for (final produto in produtos) {
      final eanNormalizado = removerZerosEsquerda(eanProduto(produto));
      final idNormalizado = removerZerosEsquerda(produto['produto_id']);
      if (eanNormalizado == codigoNormalizado ||
          idNormalizado == codigoNormalizado) {
        return produto;
      }
    }

    if (produtos.length == 1) return produtos.first;
    throw Exception(
      'Mais de um produto foi retornado para o código $codigoProduto. Revise o formato da etiqueta.',
    );
  }

  bool unidadeQuilo(Map<String, dynamic> produto) {
    final unidade =
        (produto['sigla_saida'] ??
                produto['unidade'] ??
                produto['unidade_medida'] ??
                '')
            .toString()
            .trim()
            .toUpperCase();
    return ['KG', 'KGS', 'QUILO', 'QUILOGRAMA'].contains(unidade);
  }

  String nomeProdutoEtiqueta(Map<String, dynamic> produto) {
    final nome =
        (produto['nome_produto'] ??
                produto['descricao'] ??
                produto['produto'] ??
                'Produto')
            .toString()
            .trim();
    return nome.isEmpty ? 'Produto' : nome;
  }

  Future<bool> confirmarEtiquetaBalanca({
    required Map<String, dynamic> produto,
    required ResultadoEtiquetaBalanca etiqueta,
    required double precoKg,
    required double pesoKg,
    required double valorTotal,
  }) async {
    final moeda = valorTotal.toStringAsFixed(2).replaceAll('.', ',');
    final preco = precoKg.toStringAsFixed(2).replaceAll('.', ',');
    final peso = pesoKg.toStringAsFixed(3).replaceAll('.', ',');

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.scale_outlined),
                SizedBox(width: 10),
                Expanded(child: Text('Conferir etiqueta de balança')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nomeProdutoEtiqueta(produto),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                Text('EAN do produto: ${eanProduto(produto)}'),
                Text('Preço por KG: R\$ $preco'),
                Text('Peso calculado: $peso kg'),
                Text('Valor da etiqueta: R\$ $moeda'),
                const SizedBox(height: 10),
                Text(
                  'Etiqueta: ${etiqueta.codigoCompleto}',
                  style: const TextStyle(color: Color(0xFF6B7280)),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: corPrimaria),
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.check),
                label: const Text('Confirmar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> carregar() async {
    setState(() {
      carregando = true;
      erro = '';
    });

    try {
      final resposta = await http
          .get(
            Uri.parse(
              '${widget.baseUrl}/notas-entrada/conferencias/${widget.conferenciaId}',
            ),
          )
          .timeout(const Duration(seconds: 25));
      final data = decodeResposta(resposta);

      if (!respostaSucesso(resposta)) {
        throw Exception(mensagemErro(data, resposta));
      }

      final novosItens = data is Map && data['itens'] is List
          ? List<Map<String, dynamic>>.from(data['itens'])
          : <Map<String, dynamic>>[];
      sincronizarOrdemProcessados(novosItens);

      if (!mounted) return;
      setState(() {
        conferencia = data is Map && data['conferencia'] is Map
            ? Map<String, dynamic>.from(data['conferencia'])
            : {};
        itens = novosItens;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => erro = CentralService.mensagemErroUsuario(e));
    } finally {
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> bipar(String codigo) async {
    final ean = somenteNumeros(codigo);
    if (ean.isEmpty || bipando) return;

    final configuracao = configuracaoEtiquetaBalanca;
    if (configuracao != null && configuracao.pareceEtiqueta(ean)) {
      await biparEtiquetaBalanca(ean, configuracao);
      return;
    }

    final quantidade = await showDialog<double>(
      context: context,
      builder: (_) => _QuantidadeBipeDialog(ean: ean, corPrimaria: corPrimaria),
    );

    if (!mounted) return;
    if (quantidade == null || quantidade <= 0) return;

    await enviarBipagem(ean: ean, quantidade: quantidade);
  }

  Future<void> biparEtiquetaBalanca(
    String codigo,
    ConfiguracaoEtiquetaBalanca configuracao,
  ) async {
    setState(() {
      bipando = true;
      erro = '';
    });

    try {
      final etiqueta = EtiquetaBalancaService.interpretar(codigo, configuracao);
      final produto = await buscarProdutoEtiqueta(etiqueta.codigoProduto);

      if (!unidadeQuilo(produto)) {
        throw Exception(
          '${nomeProdutoEtiqueta(produto)} não está cadastrado com unidade KG.',
        );
      }

      final precoKg = numeroProduto(
        produto['preco_venda'] ?? produto['preco'] ?? produto['valor'],
      );
      if (precoKg <= 0) {
        throw Exception('O produto está sem preço por KG válido na API.');
      }

      final pesoCalculado = etiqueta.tipoValor == 'PESO'
          ? etiqueta.valorInterpretado
          : etiqueta.valorInterpretado / precoKg;
      final pesoKg = double.parse(pesoCalculado.toStringAsFixed(3));
      final valorTotal = etiqueta.tipoValor == 'PRECO'
          ? etiqueta.valorInterpretado
          : pesoKg * precoKg;

      if (pesoKg <= 0) {
        throw Exception('O peso calculado pela etiqueta é inválido.');
      }

      if (!mounted) return;
      setState(() => bipando = false);

      final confirmado = await confirmarEtiquetaBalanca(
        produto: produto,
        etiqueta: etiqueta,
        precoKg: precoKg,
        pesoKg: pesoKg,
        valorTotal: valorTotal,
      );
      if (!confirmado || !mounted) return;

      final eanReal = eanProduto(produto);
      if (eanReal.isEmpty) {
        throw Exception('O produto encontrado está sem EAN principal.');
      }

      await enviarBipagem(
        ean: eanReal,
        quantidade: pesoKg,
        dadosEtiqueta: {
          'codigo_etiqueta': etiqueta.codigoCompleto,
          'codigo_produto_etiqueta': etiqueta.codigoProduto,
          'tipo_valor_etiqueta': etiqueta.tipoValor,
          'valor_etiqueta': etiqueta.valorInterpretado,
          'preco_kg': precoKg,
          'peso_calculado_kg': pesoKg,
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => erro = CentralService.mensagemErroUsuario(e));
    } finally {
      if (mounted && bipando) setState(() => bipando = false);
    }
  }

  Future<void> enviarBipagem({
    required String ean,
    required double quantidade,
    Map<String, dynamic>? dadosEtiqueta,
  }) async {
    if (bipando) return;

    setState(() {
      bipando = true;
      erro = '';
    });

    try {
      final resposta = await http
          .post(
            Uri.parse(
              '${widget.baseUrl}/notas-entrada/conferencias/${widget.conferenciaId}/bipar',
            ),
            headers: widget.headers,
            body: jsonEncode({
              'ean': ean,
              'quantidade': quantidade,
              if (dadosEtiqueta != null) 'etiqueta_balanca': dadosEtiqueta,
            }),
          )
          .timeout(const Duration(seconds: 25));
      final data = decodeResposta(resposta);

      if (!respostaSucesso(resposta)) {
        throw Exception(mensagemErro(data, resposta));
      }

      if (data is Map && data['item'] is Map) {
        registrarOrdemProcessado((data['item'] as Map)['id']);
      }

      codigoController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            data is Map && data['mensagem'] != null
                ? data['mensagem'].toString()
                : 'Item conferido',
          ),
          backgroundColor: Colors.green,
        ),
      );
      await carregar();
    } catch (e) {
      if (!mounted) return;
      setState(() => erro = CentralService.mensagemErroUsuario(e));
    } finally {
      if (mounted) setState(() => bipando = false);
    }
  }

  Future<void> abrirScanner() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerPage(onDetect: (codigo) => bipar(codigo)),
      ),
    );
  }

  Future<void> associarItem(Map<String, dynamic> item) async {
    final quantidadeAtual =
        double.tryParse(item['quantidade_bipada_total']?.toString() ?? '') ?? 0;
    final dados = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AssociarItemDialog(
        descricao: texto(item['descricao']),
        corPrimaria: corPrimaria,
        quantidadeInicial: quantidadeAtual > 0
            ? quantidade(quantidadeAtual)
            : '1',
      ),
    );

    if (dados == null) return;

    final tipoAssociacao = dados['tipo_associacao']?.toString() ?? 'UNICO';

    try {
      final resposta = await http
          .post(
            Uri.parse(
              '${widget.baseUrl}/notas-entrada/itens/${item['id']}/de-para',
            ),
            headers: widget.headers,
            body: jsonEncode({
              'tipo_associacao': tipoAssociacao,
              'conferencia_id': widget.conferenciaId,
              if (tipoAssociacao == 'MISTA') ...{
                'ean_caixa': item['ean_nota'] ?? item['ean_tributavel'] ?? '',
                'descricao_caixa': item['descricao'] ?? '',
                'itens_mistos': dados['itens_mistos'] ?? [],
              } else ...{
                'ean_real': dados['ean_real'] ?? '',
                'fator_conversao': dados['fator_conversao'] ?? '1',
                'quantidade': dados['quantidade'] ?? '1',
              },
            }),
          )
          .timeout(const Duration(seconds: 25));
      final data = decodeResposta(resposta);

      if (!respostaSucesso(resposta)) {
        throw Exception(mensagemErro(data, resposta));
      }

      registrarOrdemProcessado(
        data is Map && data['item_id'] != null ? data['item_id'] : item['id'],
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Associacao salva'),
          backgroundColor: Colors.green,
        ),
      );
      await carregar();
    } catch (e) {
      if (!mounted) return;
      setState(() => erro = CentralService.mensagemErroUsuario(e));
    }
  }

  Future<void> finalizar() async {
    if (finalizando) return;

    setState(() {
      finalizando = true;
      erro = '';
    });

    try {
      final resposta = await http
          .post(
            Uri.parse(
              '${widget.baseUrl}/notas-entrada/conferencias/${widget.conferenciaId}/finalizar',
            ),
            headers: widget.headers,
            body: jsonEncode({}),
          )
          .timeout(const Duration(seconds: 25));
      final data = decodeResposta(resposta);

      if (!respostaSucesso(resposta)) {
        throw Exception(mensagemErro(data, resposta));
      }

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => erro = CentralService.mensagemErroUsuario(e));
    } finally {
      if (mounted) setState(() => finalizando = false);
    }
  }

  Widget resumo(String titulo, int valor, Color cor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cor.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              valor.toString(),
              style: TextStyle(
                color: cor,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            Text(
              titulo,
              style: TextStyle(
                color: cor,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget itemCard(Map<String, dynamic> item) {
    final divergente = itemDivergente(item);
    final semMapeamento = itemSemMapeamento(item);
    final misto = itemMisto(item);
    final conferido = itemConferido(item);
    final podeAssociar = itemPodeAssociar(item);
    final internos = itensMistos(item);
    final quantidadeBipada = quantidadeInformadaItem(item);
    final codigoOk = conferido;
    final cor = divergente || semMapeamento
        ? Colors.red
        : codigoOk
        ? Colors.green
        : corPrimaria;
    final fundoCard = divergente || semMapeamento
        ? const Color(0xFFFFE0E0)
        : codigoOk
        ? const Color(0xFFE4FBEA)
        : Colors.white;
    final corBorda = divergente || semMapeamento
        ? Colors.red.withValues(alpha: 0.70)
        : codigoOk
        ? Colors.green.withValues(alpha: 0.55)
        : cor.withValues(alpha: 0.38);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: podeAssociar ? () => associarItem(item) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: fundoCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: corBorda, width: 1.3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    texto(item['descricao']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  misto
                      ? Icons.inventory_2_outlined
                      : divergente
                      ? Icons.warning_amber_rounded
                      : semMapeamento
                      ? Icons.link_off
                      : conferido
                      ? Icons.check_circle_outline
                      : Icons.touch_app_outlined,
                  color: cor,
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              'Nota/Caixa: ${texto(item['ean_nota'])} | Item: ${texto(item['ean_real'])}',
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              'Qtd nota: ${quantidade(item['quantidade_comercial'])} ${texto(item['unidade_comercial'])}',
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
            ),
            if (quantidadeBipada > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Qtd informada: ${quantidade(quantidadeBipada)}',
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: cor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cor.withValues(alpha: 0.34)),
              ),
              child: Text(
                statusVisual(item),
                style: TextStyle(
                  color: cor,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            if (internos.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.30)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Itens internos da caixa',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...internos.map(
                      (interno) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          '${texto(interno['ean_real'])} - qtd ${quantidade(interno['quantidade'])}',
                          style: const TextStyle(
                            color: Color(0xFF7F1D1D),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (semMapeamento) ...[
              const SizedBox(height: 8),
              Text(
                'Toque para associar o codigo recebido ou registrar caixa mista.',
                style: TextStyle(
                  color: cor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = itens.length;
    final divergentes = itens.where(itemDivergente).length;
    final pendentes = itens.where((item) {
      final pendente =
          double.tryParse(item['quantidade_pendente']?.toString() ?? '') ?? 0;
      return pendente > 0;
    }).length;

    return Scaffold(
      backgroundColor: corFundo,
      appBar: AppBar(
        title: const Text('Conferir itens'),
        backgroundColor: corPrimaria,
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: carregando ? null : carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      resumo('Itens', total, corPrimaria),
                      const SizedBox(width: 8),
                      resumo('Pendentes', pendentes, Colors.orange),
                      const SizedBox(width: 8),
                      resumo('Diverg.', divergentes, Colors.red),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: codigoController,
                    textInputAction: TextInputAction.done,
                    keyboardType: TextInputType.number,
                    onSubmitted: bipar,
                    decoration: InputDecoration(
                      prefixIcon: Icon(
                        Icons.qr_code_scanner,
                        color: corPrimaria,
                      ),
                      hintText: 'EAN do item conferido',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: bipando
                              ? null
                              : () => bipar(codigoController.text),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: corPrimaria,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: bipando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: const Text('Conferir'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: bipando ? null : abrirScanner,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: corPrimaria,
                            side: BorderSide(color: corPrimaria),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Scanner'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (erro.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ErroBox(erro: erro),
            ],
            const SizedBox(height: 14),
            if (carregando)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              ...itensOrdenados().map(itemCard),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: finalizando ? null : finalizar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: finalizando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.flag_outlined),
                label: const Text(
                  'Finalizar conferencia',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErroBox extends StatelessWidget {
  final String erro;

  const _ErroBox({required this.erro});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Text(
        erro,
        style: TextStyle(
          color: Colors.red.shade700,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

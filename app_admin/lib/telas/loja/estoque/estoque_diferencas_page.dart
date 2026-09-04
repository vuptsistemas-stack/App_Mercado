import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../services/central_service.dart';
import 'package:http/http.dart' as http;

import '../../../services/sessao_loja.dart';

class EstoqueDiferencasPage extends StatefulWidget {
  const EstoqueDiferencasPage({super.key});

  @override
  State<EstoqueDiferencasPage> createState() => _EstoqueDiferencasPageState();
}

class _EstoqueDiferencasPageState extends State<EstoqueDiferencasPage> {
  bool carregando = false;
  bool somenteDivergentes = true;
  String tipoDivergenciaFiltro = 'TODOS';
  DateTime? dataVendaInicio;
  String? erro;
  int total = 0;
  List<Map<String, dynamic>> produtos = [];

  static Color get corPrimaria => SessaoLoja.corPrimaria;
  static Color get fundo => SessaoLoja.corFundo;

  String quantidade(dynamic valor) {
    final numero = valor is num
        ? valor.toDouble()
        : double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;

    if (numero == numero.truncateToDouble()) {
      return numero.toStringAsFixed(0);
    }

    return numero
        .toStringAsFixed(3)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  String data(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';

    if (texto.isEmpty) {
      return '-';
    }

    final data = DateTime.tryParse(texto);

    if (data == null) {
      return texto.split('T').first;
    }

    return '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/${data.year}';
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

  double numero(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  String texto(dynamic valor, {String fallback = ''}) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? fallback : texto;
  }

  String? apiBaseUrl() {
    final api = SessaoLoja.apiBaseUrl?.trim();

    if (api == null || api.isEmpty) {
      return null;
    }

    return api.replaceAll(RegExp(r'/+$'), '');
  }

  Future<void> escolherDataVendaInicio() async {
    final agora = DateTime.now();
    final escolhida = await showDatePicker(
      context: context,
      initialDate: dataVendaInicio ?? agora,
      firstDate: DateTime(2020),
      lastDate: DateTime(agora.year + 1, 12, 31),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: corPrimaria),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (escolhida == null || !mounted) return;

    setState(() => dataVendaInicio = escolhida);
    await analisar();
  }

  Future<void> limparDataVendaInicio() async {
    setState(() => dataVendaInicio = null);
    await analisar();
  }

  Future<void> alterarTipoFiltro(String tipo) async {
    if (tipoDivergenciaFiltro == tipo) return;

    setState(() => tipoDivergenciaFiltro = tipo);
    await analisar();
  }

  Future<void> analisar() async {
    final api = apiBaseUrl();

    if (api == null) {
      setState(() {
        erro = 'API da loja nao configurada.';
        produtos = [];
        total = 0;
      });
      return;
    }

    setState(() {
      carregando = true;
      erro = null;
    });

    try {
      final uri = Uri.parse('$api/estoque/analisar-divergencias').replace(
        queryParameters: {
          'pagina': '1',
          'limite': '1000',
          'somente_divergentes': somenteDivergentes ? 'true' : 'false',
          if (tipoDivergenciaFiltro != 'TODOS')
            'tipo_divergencia': tipoDivergenciaFiltro,
          if (dataVendaInicio != null)
            'data_venda_inicio': dataIso(dataVendaInicio!),
        },
      );

      final resposta = await http.get(uri).timeout(const Duration(seconds: 60));

      if (resposta.statusCode != 200) {
        final corpo = resposta.body.toLowerCase();

        if (resposta.statusCode == 404 &&
            corpo.contains('cannot get /estoque/analisar-divergencias')) {
          throw Exception(
            'A rota /estoque/analisar-divergencias ainda nao existe na API '
            'que esta rodando. Atualize o server.js da API e reinicie o PM2.',
          );
        }

        throw Exception('Erro ${resposta.statusCode}: ${resposta.body}');
      }

      final dados = jsonDecode(resposta.body);
      final lista = dados['produtos'] ?? dados['divergencias'] ?? [];

      if (!mounted) return;

      setState(() {
        produtos = List<Map<String, dynamic>>.from(lista);
        total =
            int.tryParse(dados['total']?.toString() ?? '') ?? produtos.length;
        carregando = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        erro =
            'Nao foi possivel analisar o estoque: ${CentralService.mensagemErroUsuario(e)}';
        produtos = [];
        total = 0;
        carregando = false;
      });
    }
  }

  Color corTipo(String tipo) {
    if (tipo == 'FALTA') {
      return Colors.red;
    }

    if (tipo == 'SOBRA') {
      return Colors.orange;
    }

    return Colors.green;
  }

  Widget resumoTopo() {
    final faltas = produtos
        .where((item) => texto(item['tipo_divergencia']) == 'FALTA')
        .length;
    final sobras = produtos
        .where((item) => texto(item['tipo_divergencia']) == 'SOBRA')
        .length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: corPrimaria.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: corPrimaria.withValues(alpha: 0.12),
                child: Icon(Icons.compare_arrows, color: corPrimaria),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Diferenças de estoque',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: indicador('Itens', total.toString(), corPrimaria),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: indicador('Faltas', faltas.toString(), Colors.red),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: indicador('Sobras', sobras.toString(), Colors.orange),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            value: somenteDivergentes,
            dense: true,
            contentPadding: EdgeInsets.zero,
            activeThumbColor: corPrimaria,
            title: const Text(
              'Mostrar apenas produtos com divergencia',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            onChanged: carregando
                ? null
                : (valor) {
                    setState(() => somenteDivergentes = valor);
                    analisar();
                  },
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: botaoTipoDivergencia(
                  texto: 'Todos',
                  tipo: 'TODOS',
                  cor: corPrimaria,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: botaoTipoDivergencia(
                  texto: 'Faltas',
                  tipo: 'FALTA',
                  cor: Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: botaoTipoDivergencia(
                  texto: 'Sobras',
                  tipo: 'SOBRA',
                  cor: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: carregando ? null : escolherDataVendaInicio,
                  icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: Text(
                    dataCurta(dataVendaInicio, 'Vendas desde ultima compra'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: corPrimaria,
                    side: BorderSide(
                      color: corPrimaria.withValues(alpha: 0.55),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              if (dataVendaInicio != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Usar ultima compra',
                  onPressed: carregando ? null : limparDataVendaInicio,
                  icon: const Icon(Icons.clear),
                  color: corPrimaria,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            dataVendaInicio == null
                ? 'Sem data manual: cada produto usa a data da ultima compra.'
                : 'Com data manual: vendas calculadas desde ${dataCurta(dataVendaInicio, '')}.',
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: carregando ? null : analisar,
              icon: carregando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.analytics_outlined),
              label: Text(carregando ? 'Analisando...' : 'Analisar estoque'),
              style: ElevatedButton.styleFrom(
                backgroundColor: corPrimaria,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget botaoTipoDivergencia({
    required String texto,
    required String tipo,
    required Color cor,
  }) {
    final selecionado = tipoDivergenciaFiltro == tipo;

    return OutlinedButton(
      onPressed: carregando ? null : () => alterarTipoFiltro(tipo),
      style: OutlinedButton.styleFrom(
        backgroundColor: selecionado ? cor : Colors.white,
        foregroundColor: selecionado ? Colors.white : cor,
        side: BorderSide(color: cor.withValues(alpha: 0.65)),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        texto,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }

  Widget indicador(String titulo, String valor, Color cor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(
              color: cor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget linhaValor(String titulo, String valor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black54, fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(
              valor,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget cardProduto(Map<String, dynamic> produto) {
    final tipo = texto(produto['tipo_divergencia'], fallback: 'OK');
    final cor = corTipo(tipo);
    final divergencia = numero(produto['divergencia']);
    final unidade = texto(produto['sigla_saida'], fallback: 'UN');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cor.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 12,
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      texto(produto['nome_produto'], fallback: 'Produto'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'EAN: ${texto(produto['ean_principal'], fallback: '-')}',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  tipo,
                  style: TextStyle(
                    color: cor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              linhaValor('Ultima compra', data(produto['data_ultima_compra'])),
              const SizedBox(width: 8),
              linhaValor(
                'Divergencia',
                '${quantidade(divergencia.abs())} $unidade',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              linhaValor('Comprado', quantidade(produto['total_comprado'])),
              const SizedBox(width: 8),
              linhaValor('Vendido', quantidade(produto['quantidade_vendida'])),
              const SizedBox(width: 8),
              linhaValor('Estoque', quantidade(produto['estoque_atual'])),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Vendido desde ${data(produto['periodo_venda_inicio'] ?? produto['data_ultima_compra'])} '
            'ate ${data(produto['periodo_venda_fim'] ?? DateTime.now())}',
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Vendido + estoque = ${quantidade(produto['saldo_calculado'])} $unidade',
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget listaResultados() {
    if (erro != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withValues(alpha: 0.18)),
        ),
        child: Text(
          erro!,
          style: const TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (carregando && produtos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (produtos.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: const Text(
          'Nenhuma divergencia encontrada.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
        ),
      );
    }

    return Column(children: produtos.map(cardProduto).toList());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => analisar());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fundo,
      appBar: AppBar(
        title: const Text('Diferenças de estoque'),
        backgroundColor: corPrimaria,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: carregando ? null : analisar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: analisar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            resumoTopo(),
            const SizedBox(height: 16),
            listaResultados(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

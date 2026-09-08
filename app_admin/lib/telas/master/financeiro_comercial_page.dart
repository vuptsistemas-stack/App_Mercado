import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/central_service.dart';
import '../../services/financeiro_master_service.dart';

const _vermelhoFinanceiro = Color(0xFFE30613);
const _fundoFinanceiro = Color(0xFFF5F7FA);

double _numero(dynamic valor) {
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor?.toString() ?? '') ?? 0;
}

String _moeda(dynamic valor) {
  final numero = _numero(valor);
  final partes = numero.toStringAsFixed(2).split('.');
  final inteiro = partes.first;
  final buffer = StringBuffer();
  for (var i = 0; i < inteiro.length; i++) {
    final restante = inteiro.length - i;
    buffer.write(inteiro[i]);
    if (restante > 1 && restante % 3 == 1) buffer.write('.');
  }
  return 'R\$ ${buffer.toString()},${partes.last}';
}

String _mesAno(DateTime data) {
  const meses = [
    'Janeiro',
    'Fevereiro',
    'Março',
    'Abril',
    'Maio',
    'Junho',
    'Julho',
    'Agosto',
    'Setembro',
    'Outubro',
    'Novembro',
    'Dezembro',
  ];
  return '${meses[data.month - 1]} ${data.year}';
}

DateTime _primeiroDiaMes(DateTime data) => DateTime(data.year, data.month);

DateTime _somarMes(DateTime data, int quantidade) =>
    DateTime(data.year, data.month + quantidade);

DateTime? _data(dynamic valor) {
  final texto = valor?.toString().trim() ?? '';
  return texto.isEmpty ? null : DateTime.tryParse(texto)?.toLocal();
}

String _dataBr(dynamic valor) {
  final data = valor is DateTime ? valor : _data(valor);
  if (data == null) return '-';
  return '${data.day.toString().padLeft(2, '0')}/'
      '${data.month.toString().padLeft(2, '0')}/${data.year}';
}

Color _corStatus(String status) {
  switch (status.toUpperCase()) {
    case 'PAGA':
    case 'ATIVO':
      return const Color(0xFF16803C);
    case 'VENCIDA':
    case 'CANCELADO':
    case 'CANCELADA':
      return const Color(0xFFC62828);
    case 'EMITIDA':
    case 'AGUARDANDO_EMISSAO':
      return const Color(0xFFB75D00);
    case 'NEGOCIADA':
      return const Color(0xFF6B4EFF);
    default:
      return const Color(0xFF52606D);
  }
}

class FinanceiroComercialPage extends StatefulWidget {
  const FinanceiroComercialPage({super.key});

  @override
  State<FinanceiroComercialPage> createState() =>
      _FinanceiroComercialPageState();
}

class _FinanceiroComercialPageState extends State<FinanceiroComercialPage>
    with SingleTickerProviderStateMixin {
  final FinanceiroMasterService service = FinanceiroMasterService();
  final buscaController = TextEditingController();

  late final TabController tabController;
  DateTime competencia = _primeiroDiaMes(DateTime.now());
  bool carregando = true;
  bool fechando = false;
  String? erro;
  Map<String, dynamic> dados = {};

  List<Map<String, dynamic>> get lojas => dados['lojas'] is List
      ? List<Map<String, dynamic>>.from(dados['lojas'])
      : [];

  List<Map<String, dynamic>> get modulos => dados['modulos'] is List
      ? List<Map<String, dynamic>>.from(dados['modulos'])
      : [];

  Map<String, dynamic> get totais =>
      dados['totais'] is Map ? Map<String, dynamic>.from(dados['totais']) : {};

  List<String> get avisosSincronizacao => dados['_avisos_sincronizacao'] is List
      ? List<String>.from(dados['_avisos_sincronizacao'])
      : const [];

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 3, vsync: this);
    buscaController.addListener(() => setState(() {}));
    carregar();
  }

  @override
  void dispose() {
    tabController.dispose();
    buscaController.dispose();
    super.dispose();
  }

  Future<void> carregar() async {
    setState(() {
      carregando = true;
      erro = null;
    });
    try {
      final resposta = await service.carregarDashboard(competencia);
      if (!mounted) return;
      setState(() {
        dados = resposta;
        carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        erro = CentralService.mensagemErroUsuario(e);
        carregando = false;
      });
    }
  }

  Future<void> fecharCompetencia() async {
    if (fechando) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Fechar competência'),
        content: Text(
          'Gerar cobranças definitivas de ${_mesAno(competencia)}? '
          'Os valores serão preservados como histórico.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => fechando = true);
    try {
      final resposta = await service.fecharCompetencia(competencia);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${resposta['quantidade'] ?? 0} cobrança(s) processada(s).',
          ),
          backgroundColor: Colors.green,
        ),
      );
      await carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(CentralService.mensagemErroUsuario(e)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => fechando = false);
    }
  }

  Future<void> abrirLoja(Map<String, dynamic> loja) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => FinanceiroLojaPage(
          mercadoId: loja['mercado_id'].toString(),
          mercadoNome: loja['mercado_nome']?.toString() ?? 'Loja',
          competencia: competencia,
        ),
      ),
    );
    await carregar();
  }

  List<Map<String, dynamic>> get lojasFiltradas {
    final busca = buscaController.text.trim().toLowerCase();
    if (busca.isEmpty) return lojas;
    return lojas.where((loja) {
      return [
        loja['mercado_nome'],
        loja['mercado_codigo'],
      ].any((valor) => valor?.toString().toLowerCase().contains(busca) == true);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundoFinanceiro,
      appBar: AppBar(
        title: const Text('Financeiro e comercial'),
        backgroundColor: _vermelhoFinanceiro,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: carregando ? null : carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Painel', icon: Icon(Icons.dashboard_outlined)),
            Tab(text: 'Módulos', icon: Icon(Icons.extension_outlined)),
            Tab(text: 'Simular', icon: Icon(Icons.calculate_outlined)),
          ],
        ),
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : erro != null
          ? _ErroFinanceiro(mensagem: erro!, tentarNovamente: carregar)
          : TabBarView(
              controller: tabController,
              children: [
                _painel(),
                _catalogoModulos(),
                _SimuladorFinanceiro(modulos: modulos),
              ],
            ),
    );
  }

  Widget _painel() {
    return RefreshIndicator(
      onRefresh: carregar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (avisosSincronizacao.isNotEmpty) ...[
            _AvisoSincronizacaoFinanceira(avisos: avisosSincronizacao),
            const SizedBox(height: 14),
          ],
          _seletorCompetencia(),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final largura = constraints.maxWidth;
              final colunas = largura >= 900
                  ? 4
                  : largura >= 560
                  ? 2
                  : 1;
              final larguraItem = (largura - ((colunas - 1) * 12)) / colunas;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _metrica(
                    larguraItem,
                    'GMV elegível',
                    _moeda(totais['gmv_elegivel']),
                    Icons.payments_outlined,
                    const Color(0xFF136F63),
                  ),
                  _metrica(
                    larguraItem,
                    'Receita estimada',
                    _moeda(totais['total_estimado']),
                    Icons.trending_up,
                    const Color(0xFF1565C0),
                  ),
                  _metrica(
                    larguraItem,
                    'Pedidos entregues',
                    '${totais['pedidos_elegiveis'] ?? 0}',
                    Icons.local_shipping_outlined,
                    const Color(0xFF6A1B9A),
                  ),
                  _metrica(
                    larguraItem,
                    'Em atraso',
                    '${totais['lojas_em_atraso'] ?? 0}',
                    Icons.warning_amber_outlined,
                    const Color(0xFFC62828),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          TextField(
            controller: buscaController,
            decoration: InputDecoration(
              hintText: 'Buscar loja',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: buscaController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar busca',
                      onPressed: buscaController.clear,
                      icon: const Icon(Icons.close),
                    ),
              filled: true,
              fillColor: Colors.white,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          if (lojasFiltradas.isEmpty)
            const _PainelVazio(
              icone: Icons.store_outlined,
              texto: 'Nenhuma loja encontrada.',
            )
          else
            ...lojasFiltradas.map(_cardLoja),
        ],
      ),
    );
  }

  Widget _seletorCompetencia() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final navegacao = Row(
            children: [
              IconButton(
                tooltip: 'Mês anterior',
                onPressed: () {
                  competencia = _somarMes(competencia, -1);
                  carregar();
                },
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  _mesAno(competencia),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Próximo mês',
                onPressed: () {
                  competencia = _somarMes(competencia, 1);
                  carregar();
                },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          );
          final fechar = FilledButton.icon(
            onPressed: fechando ? null : fecharCompetencia,
            icon: fechando
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_outline),
            label: const Text('Fechar competência'),
          );

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: constraints.maxWidth < 520
                ? Column(
                    children: [
                      navegacao,
                      const SizedBox(height: 6),
                      SizedBox(width: double.infinity, child: fechar),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: navegacao),
                      const SizedBox(width: 8),
                      fechar,
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _metrica(
    double largura,
    String titulo,
    String valor,
    IconData icone,
    Color cor,
  ) {
    return SizedBox(
      width: largura,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: cor.withValues(alpha: 0.12),
                child: Icon(icone, color: cor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        valor,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
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
    );
  }

  Widget _cardLoja(Map<String, dynamic> loja) {
    final status = loja['situacao_acesso']?.toString() ?? 'SEM_CONTRATO';
    final cor = _corStatus(status);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => abrirLoja(loja),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final identificacao = Row(
                children: [
                  CircleAvatar(
                    backgroundColor: cor.withValues(alpha: 0.12),
                    child: Icon(Icons.storefront, color: cor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loja['mercado_nome']?.toString() ?? 'Loja',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${loja['mercado_codigo'] ?? ''}  •  '
                          '${loja['pedidos_elegiveis'] ?? 0} pedidos',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final etiqueta = Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status.replaceAll('_', ' '),
                  style: TextStyle(
                    color: cor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              );

              if (constraints.maxWidth < 680) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    identificacao,
                    const Divider(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: _valorLegenda('Vendas', loja['gmv_elegivel']),
                        ),
                        Expanded(
                          child: _valorLegenda(
                            'Mensalidade',
                            loja['total_estimado'],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    etiqueta,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 4, child: identificacao),
                  Expanded(
                    flex: 3,
                    child: _valorLegenda('Vendas', loja['gmv_elegivel']),
                  ),
                  Expanded(
                    flex: 3,
                    child: _valorLegenda('Mensalidade', loja['total_estimado']),
                  ),
                  etiqueta,
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _valorLegenda(String legenda, dynamic valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          legenda,
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _moeda(valor),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _catalogoModulos() {
    final base = modulos
        .where((m) => m['incluido_plano_base'] == true)
        .toList();
    final adicionais = modulos
        .where((m) => m['incluido_plano_base'] != true)
        .toList();
    return RefreshIndicator(
      onRefresh: carregar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Catálogo de módulos',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          const Text(
            'O preço padrão pode ser alterado pelo master. Valores negociados por loja são configurados no contrato.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 18),
          _tituloGrupo('Incluídos no plano base', base.length),
          ...base.map(_itemModulo),
          const SizedBox(height: 16),
          _tituloGrupo('Módulos adicionais', adicionais.length),
          ...adicionais.map(_itemModulo),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _editarModulo(null),
            icon: const Icon(Icons.add),
            label: const Text('Novo módulo'),
          ),
        ],
      ),
    );
  }

  Widget _tituloGrupo(String titulo, int quantidade) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Text(
        '$titulo ($quantidade)',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _itemModulo(Map<String, dynamic> modulo) {
    final ativo = modulo['ativo'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        leading: Icon(
          ativo ? Icons.check_circle_outline : Icons.pause_circle_outline,
          color: ativo ? Colors.green : Colors.grey,
        ),
        title: Text(
          modulo['nome']?.toString() ?? 'Módulo',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(modulo['descricao']?.toString() ?? ''),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              modulo['incluido_plano_base'] == true
                  ? 'Incluso'
                  : '${_moeda(modulo['preco_padrao'])}/mês',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            IconButton(
              tooltip: 'Editar módulo',
              onPressed: () => _editarModulo(modulo),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editarModulo(Map<String, dynamic>? modulo) async {
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ModuloCatalogoDialog(modulo: modulo),
    );
    if (resultado == null) return;
    try {
      await service.salvarModuloCatalogo(
        id: modulo?['id']?.toString(),
        codigo: resultado['codigo'].toString(),
        nome: resultado['nome'].toString(),
        descricao: resultado['descricao'].toString(),
        precoPadrao: _numero(resultado['preco_padrao']),
        incluidoPlanoBase: resultado['incluido_plano_base'] == true,
        ativo: resultado['ativo'] == true,
      );
      await carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(CentralService.mensagemErroUsuario(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _SimuladorFinanceiro extends StatefulWidget {
  const _SimuladorFinanceiro({required this.modulos});

  final List<Map<String, dynamic>> modulos;

  @override
  State<_SimuladorFinanceiro> createState() => _SimuladorFinanceiroState();
}

class _SimuladorFinanceiroState extends State<_SimuladorFinanceiro> {
  final faturamentoController = TextEditingController(text: '15000,00');
  final diasAtivosController = TextEditingController(text: '30');
  final diasMesController = TextEditingController(text: '30');
  final implantacaoController = TextEditingController(text: '590,00');
  final Set<String> selecionados = {};

  @override
  void initState() {
    super.initState();
    for (final controller in [
      faturamentoController,
      diasAtivosController,
      diasMesController,
      implantacaoController,
    ]) {
      controller.addListener(_atualizar);
    }
  }

  @override
  void dispose() {
    faturamentoController.dispose();
    diasAtivosController.dispose();
    diasMesController.dispose();
    implantacaoController.dispose();
    super.dispose();
  }

  void _atualizar() => setState(() {});

  double _decimal(String texto) =>
      double.tryParse(texto.replaceAll('.', '').replaceAll(',', '.')) ?? 0;

  List<Map<String, dynamic>> get adicionais => widget.modulos
      .where((m) => m['incluido_plano_base'] != true && m['ativo'] == true)
      .toList();

  double get totalAdicionais => adicionais
      .where((m) => selecionados.contains(m['id']?.toString()))
      .fold(0, (total, m) => total + _numero(m['preco_padrao']));

  Map<String, double> get simulacao => FinanceiroMasterService.simularPlano(
    faturamento: _decimal(faturamentoController.text),
    diasAtivos: int.tryParse(diasAtivosController.text) ?? 0,
    diasNoMes: int.tryParse(diasMesController.text) ?? 30,
    adicionais: totalAdicionais,
    implantacao: _decimal(implantacaoController.text),
  );

  Future<void> compartilhar() async {
    final resultado = simulacao;
    final nomes = adicionais
        .where((m) => selecionados.contains(m['id']?.toString()))
        .map((m) => m['nome'])
        .join(', ');
    final texto =
        '''
Simulação comercial - Vupt Sistemas

Faturamento informado: ${_moeda(_decimal(faturamentoController.text))}
Mensalidade App Mercado: ${_moeda(resultado['mensalidade'])}
Módulos adicionais: ${_moeda(resultado['adicionais'])}${nomes.isEmpty ? '' : ' ($nomes)'}
Implantação: ${_moeda(resultado['implantacao'])}
Total inicial estimado: ${_moeda(resultado['total'])}

Período considerado: ${diasAtivosController.text} de ${diasMesController.text} dias.
Simulação sujeita à conferência e formalização comercial.
''';
    await SharePlus.instance.share(ShareParams(text: texto));
  }

  @override
  Widget build(BuildContext context) {
    final resultado = simulacao;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Simulador de plano',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        const Text(
          'Ferramenta interna do master para apresentação comercial. Não realiza contratação ou pagamento.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _campo(faturamentoController, 'Faturamento do mês', 'R\$'),
            _campo(diasAtivosController, 'Dias ativos', 'dias'),
            _campo(diasMesController, 'Dias no mês', 'dias'),
            _campo(implantacaoController, 'Taxa de implantação', 'R\$'),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Módulos adicionais',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (adicionais.isEmpty)
          const Text('Nenhum módulo adicional ativo.')
        else
          ...adicionais.map((modulo) {
            final id = modulo['id']?.toString() ?? '';
            return CheckboxListTile(
              value: selecionados.contains(id),
              contentPadding: EdgeInsets.zero,
              title: Text(modulo['nome']?.toString() ?? 'Módulo'),
              subtitle: Text('${_moeda(modulo['preco_padrao'])}/mês'),
              onChanged: (valor) {
                setState(() {
                  if (valor == true) {
                    selecionados.add(id);
                  } else {
                    selecionados.remove(id);
                  }
                });
              },
            );
          }),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black12),
          ),
          child: Column(
            children: [
              _linhaResultado(
                'Mensalidade App Mercado',
                resultado['mensalidade'],
              ),
              _linhaResultado('Módulos adicionais', resultado['adicionais']),
              _linhaResultado('Implantação', resultado['implantacao']),
              const Divider(height: 24),
              _linhaResultado(
                'Total inicial estimado',
                resultado['total'],
                destaque: true,
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Mensalidade cheia da faixa: ${_moeda(resultado['mensalidade_cheia'])}',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: compartilhar,
          icon: const Icon(Icons.share_outlined),
          label: const Text('Compartilhar simulação'),
        ),
      ],
    );
  }

  Widget _campo(TextEditingController controller, String label, String sufixo) {
    return SizedBox(
      width: 240,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: sufixo,
          filled: true,
          fillColor: Colors.white,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _linhaResultado(
    String titulo,
    dynamic valor, {
    bool destaque = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              titulo,
              style: TextStyle(
                fontWeight: destaque ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            _moeda(valor),
            style: TextStyle(
              fontSize: destaque ? 20 : 15,
              fontWeight: destaque ? FontWeight.w900 : FontWeight.w700,
              color: destaque ? _vermelhoFinanceiro : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuloCatalogoDialog extends StatefulWidget {
  const _ModuloCatalogoDialog({this.modulo});

  final Map<String, dynamic>? modulo;

  @override
  State<_ModuloCatalogoDialog> createState() => _ModuloCatalogoDialogState();
}

class _ModuloCatalogoDialogState extends State<_ModuloCatalogoDialog> {
  late final TextEditingController codigoController;
  late final TextEditingController nomeController;
  late final TextEditingController descricaoController;
  late final TextEditingController precoController;
  late bool incluido;
  late bool ativo;

  @override
  void initState() {
    super.initState();
    final modulo = widget.modulo ?? {};
    codigoController = TextEditingController(
      text: modulo['codigo']?.toString(),
    );
    nomeController = TextEditingController(text: modulo['nome']?.toString());
    descricaoController = TextEditingController(
      text: modulo['descricao']?.toString(),
    );
    precoController = TextEditingController(
      text: _numero(
        modulo['preco_padrao'],
      ).toStringAsFixed(2).replaceAll('.', ','),
    );
    incluido = modulo['incluido_plano_base'] == true;
    ativo = modulo.isEmpty || modulo['ativo'] == true;
  }

  @override
  void dispose() {
    codigoController.dispose();
    nomeController.dispose();
    descricaoController.dispose();
    precoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.modulo == null ? 'Novo módulo' : 'Editar módulo'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codigoController,
                enabled: widget.modulo == null,
                decoration: const InputDecoration(
                  labelText: 'Código',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nomeController,
                decoration: const InputDecoration(
                  labelText: 'Nome do módulo',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descricaoController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Descrição',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: precoController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Preço padrão mensal',
                  prefixText: 'R\$ ',
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: incluido,
                onChanged: (valor) => setState(() => incluido = valor),
                title: const Text('Incluído no plano base'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: ativo,
                onChanged: (valor) => setState(() => ativo = valor),
                title: const Text('Módulo ativo'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final codigo = codigoController.text.trim();
            final nome = nomeController.text.trim();
            if (codigo.isEmpty || nome.isEmpty) return;
            Navigator.pop(context, {
              'codigo': codigo,
              'nome': nome,
              'descricao': descricaoController.text.trim(),
              'preco_padrao':
                  double.tryParse(
                    precoController.text
                        .replaceAll('.', '')
                        .replaceAll(',', '.'),
                  ) ??
                  0,
              'incluido_plano_base': incluido,
              'ativo': ativo,
            });
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

class FinanceiroLojaPage extends StatefulWidget {
  const FinanceiroLojaPage({
    super.key,
    required this.mercadoId,
    required this.mercadoNome,
    required this.competencia,
  });

  final String mercadoId;
  final String mercadoNome;
  final DateTime competencia;

  @override
  State<FinanceiroLojaPage> createState() => _FinanceiroLojaPageState();
}

class _FinanceiroLojaPageState extends State<FinanceiroLojaPage> {
  final FinanceiroMasterService service = FinanceiroMasterService();
  bool carregando = true;
  bool processando = false;
  String? erro;
  Map<String, dynamic> dados = {};

  Map<String, dynamic> get resumo =>
      dados['resumo'] is Map ? Map<String, dynamic>.from(dados['resumo']) : {};

  Map<String, dynamic>? get contrato => dados['contrato'] is Map
      ? Map<String, dynamic>.from(dados['contrato'])
      : null;

  List<Map<String, dynamic>> get modulos => dados['modulos'] is List
      ? List<Map<String, dynamic>>.from(dados['modulos'])
      : [];

  List<Map<String, dynamic>> get cobrancas => dados['cobrancas'] is List
      ? List<Map<String, dynamic>>.from(dados['cobrancas'])
      : [];

  @override
  void initState() {
    super.initState();
    carregar();
  }

  Future<void> carregar() async {
    setState(() {
      carregando = true;
      erro = null;
    });
    try {
      final resposta = await service.carregarDetalheLoja(
        mercadoId: widget.mercadoId,
        competencia: widget.competencia,
      );
      if (!mounted) return;
      setState(() {
        dados = resposta;
        carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        erro = CentralService.mensagemErroUsuario(e);
        carregando = false;
      });
    }
  }

  void mensagem(String texto, {bool falha = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: falha ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundoFinanceiro,
      appBar: AppBar(
        title: Text(widget.mercadoNome),
        backgroundColor: _vermelhoFinanceiro,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: processando ? null : carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : erro != null
          ? _ErroFinanceiro(mensagem: erro!, tentarNovamente: carregar)
          : RefreshIndicator(
              onRefresh: carregar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _cabecalho(),
                  const SizedBox(height: 14),
                  _cardContrato(),
                  const SizedBox(height: 14),
                  _cardModulos(),
                  const SizedBox(height: 14),
                  _cardCobrancas(),
                  const SizedBox(height: 14),
                  _cardAcoesContrato(),
                  const SizedBox(height: 28),
                ],
              ),
            ),
    );
  }

  Widget _cabecalho() {
    final situacao = resumo['situacao_acesso']?.toString() ?? 'SEM_CONTRATO';
    final cor = _corStatus(situacao);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _mesAno(widget.competencia),
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.mercadoNome,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
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
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  situacao.replaceAll('_', ' '),
                  style: TextStyle(color: cor, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const Divider(height: 28),
          Wrap(
            spacing: 28,
            runSpacing: 12,
            children: [
              _resumoValor('GMV elegível', resumo['gmv_elegivel']),
              _resumoValor('Mensalidade base', resumo['mensalidade_base']),
              _resumoValor('Adicionais', resumo['modulos_adicionais']),
              _resumoValor('Implantação', resumo['implantacao']),
              _resumoValor(
                'Total estimado',
                resumo['total_estimado'],
                destaque: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${resumo['pedidos_elegiveis'] ?? 0} pedidos entregues  •  '
            'ticket médio ${_moeda(resumo['ticket_medio'])}  •  '
            '${resumo['dias_ativos'] ?? 0} dia(s) ativo(s)',
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _resumoValor(String titulo, dynamic valor, {bool destaque = false}) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _moeda(valor),
              style: TextStyle(
                fontSize: destaque ? 20 : 16,
                fontWeight: FontWeight.w800,
                color: destaque ? _vermelhoFinanceiro : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardContrato() {
    final atual = contrato;
    return _secao(
      titulo: 'Contrato e implantação',
      icone: Icons.description_outlined,
      acao: TextButton.icon(
        onPressed: processando ? null : _editarContrato,
        icon: const Icon(Icons.edit_outlined),
        label: Text(atual == null ? 'Configurar' : 'Editar'),
      ),
      corpo: atual == null
          ? const Text(
              'Contrato ainda não configurado. A loja não será incluída no fechamento até a ativação.',
              style: TextStyle(color: Colors.black54),
            )
          : Wrap(
              spacing: 30,
              runSpacing: 12,
              children: [
                _dado('Status', atual['status']),
                _dado('Início', _dataBr(atual['inicio_em'])),
                _dado('Vencimento', 'Dia ${atual['dia_vencimento'] ?? 10}'),
                _dado('Carência', '${atual['dias_carencia'] ?? 15} dias'),
                _dado(
                  'Implantação',
                  _moeda(atual['valor_implantacao_liquido']),
                ),
                _dado(
                  'Tipo ERP',
                  atual['tipo_implantacao']?.toString().replaceAll('_', ' ') ??
                      '-',
                ),
              ],
            ),
    );
  }

  Widget _cardModulos() {
    final adicionais = modulos
        .where((modulo) => modulo['incluido_plano_base'] != true)
        .toList();
    return _secao(
      titulo: 'Módulos adicionais',
      icone: Icons.extension_outlined,
      corpo: adicionais.isEmpty
          ? const Text('Nenhum módulo adicional cadastrado.')
          : Column(
              children: adicionais.map((modulo) {
                final ativo = modulo['contratado'] == true;
                final preco = ativo
                    ? modulo['preco_contratado']
                    : modulo['preco_padrao'];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    ativo ? Icons.check_circle : Icons.circle_outlined,
                    color: ativo ? Colors.green : Colors.grey,
                  ),
                  title: Text(modulo['nome']?.toString() ?? 'Módulo'),
                  subtitle: Text(
                    ativo
                        ? '${_moeda(preco)}/mês • desde ${_dataBr(modulo['vigencia_inicio'])}'
                        : 'Padrão: ${_moeda(preco)}/mês',
                  ),
                  trailing: IconButton(
                    tooltip: ativo ? 'Alterar contratação' : 'Contratar módulo',
                    onPressed: processando
                        ? null
                        : () => _editarModuloLoja(modulo),
                    icon: const Icon(Icons.tune),
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _cardCobrancas() {
    return _secao(
      titulo: 'Cobranças',
      icone: Icons.receipt_long_outlined,
      corpo: cobrancas.isEmpty
          ? const Text(
              'Nenhuma cobrança fechada para esta loja.',
              style: TextStyle(color: Colors.black54),
            )
          : Column(
              children: cobrancas.map((cobranca) {
                final status = cobranca['status']?.toString() ?? '';
                final cor = _corStatus(status);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: cor.withValues(alpha: 0.1),
                    child: Icon(Icons.payments_outlined, color: cor),
                  ),
                  title: Text(
                    '${cobranca['competencia_texto'] ?? cobranca['competencia']} • ${_moeda(cobranca['valor_total'])}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '$status • vence ${_dataBr(cobranca['vencimento_em'])}'
                    '${cobranca['referencia'] == null || cobranca['referencia'].toString().isEmpty ? '' : ' • ${cobranca['referencia']}'}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Atualizar cobrança',
                    onPressed: processando
                        ? null
                        : () => _editarCobranca(cobranca),
                    icon: const Icon(Icons.edit_note),
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _cardAcoesContrato() {
    final cancelado = contrato?['status'] == 'CANCELADO';
    return _secao(
      titulo: 'Ações do contrato',
      icone: Icons.admin_panel_settings_outlined,
      corpo: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              cancelado
                  ? 'A reativação só é liberada quando todas as cobranças pendentes estiverem pagas.'
                  : 'O cancelamento é imediato e será impedido enquanto houver pedidos em andamento.',
              style: const TextStyle(color: Colors.black54),
            ),
          ),
          if (cancelado)
            FilledButton.icon(
              onPressed: processando ? null : _reativar,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Reativar'),
            )
          else
            OutlinedButton.icon(
              onPressed: processando || contrato == null ? null : _cancelar,
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              icon: const Icon(Icons.block),
              label: const Text('Cancelar contrato'),
            ),
        ],
      ),
    );
  }

  Widget _secao({
    required String titulo,
    required IconData icone,
    required Widget corpo,
    Widget? acao,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, color: _vermelhoFinanceiro),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ?acao,
              ],
            ),
            const Divider(height: 24),
            corpo,
          ],
        ),
      ),
    );
  }

  Widget _dado(String titulo, dynamic valor) {
    return SizedBox(
      width: 155,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            valor?.toString() ?? '-',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Future<void> _editarContrato() async {
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ContratoDialog(contrato: contrato),
    );
    if (resultado == null) return;
    await _executar(() async {
      await service.salvarContrato(
        mercadoId: widget.mercadoId,
        inicio: resultado['inicio'] as DateTime,
        status: resultado['status'].toString(),
        tipoImplantacao: resultado['tipo_implantacao'].toString(),
        valorImplantacao: _numero(resultado['valor_implantacao']),
        descontoImplantacao: _numero(resultado['desconto_implantacao']),
        observacao: resultado['observacao'].toString(),
      );
    }, sucesso: 'Contrato atualizado.');
  }

  Future<void> _editarModuloLoja(Map<String, dynamic> modulo) async {
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ModuloLojaDialog(modulo: modulo),
    );
    if (resultado == null) return;
    await _executar(() async {
      await service.salvarModuloLoja(
        mercadoId: widget.mercadoId,
        moduloId: modulo['id'].toString(),
        ativo: resultado['ativo'] == true,
        precoMensal: _numero(resultado['preco']),
        vigenciaInicio: resultado['vigencia'] as DateTime,
        motivo: resultado['motivo'].toString(),
      );
    }, sucesso: 'Módulo atualizado.');
  }

  Future<void> _editarCobranca(Map<String, dynamic> cobranca) async {
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CobrancaDialog(cobranca: cobranca),
    );
    if (resultado == null) return;
    await _executar(() async {
      await service.atualizarCobranca(
        cobrancaId: cobranca['id'].toString(),
        status: resultado['status'].toString(),
        referencia: resultado['referencia'].toString(),
        pagoEm: resultado['pago_em'] as DateTime?,
        formaPagamento: resultado['forma_pagamento'].toString(),
        observacao: resultado['observacao'].toString(),
      );
    }, sucesso: 'Cobrança atualizada.');
  }

  Future<String?> _pedirMotivo(String titulo, String explicacao) async {
    final controller = TextEditingController();
    final resultado = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(titulo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(explicacao),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo obrigatório',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () {
              final texto = controller.text.trim();
              if (texto.isNotEmpty) Navigator.pop(context, texto);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return resultado;
  }

  Future<void> _cancelar() async {
    final motivo = await _pedirMotivo(
      'Cancelar contrato',
      'A loja perderá o acesso imediatamente. O sistema verificará se ainda existem pedidos em andamento.',
    );
    if (motivo == null) return;
    await _executar(() async {
      await service.cancelarLoja(mercadoId: widget.mercadoId, motivo: motivo);
    }, sucesso: 'Contrato cancelado e cobrança proporcional gerada.');
  }

  Future<void> _reativar() async {
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ReativarDialog(modulos: modulos),
    );
    if (resultado == null) return;
    await _executar(() async {
      await service.reativarLoja(
        mercadoId: widget.mercadoId,
        data: DateTime.now(),
        motivo: resultado['motivo'].toString(),
        modulosIds: List<String>.from(resultado['modulos_ids']),
      );
    }, sucesso: 'Contrato reativado.');
  }

  Future<void> _executar(
    Future<void> Function() acao, {
    required String sucesso,
  }) async {
    setState(() => processando = true);
    try {
      await acao();
      mensagem(sucesso);
      await carregar();
    } catch (e) {
      mensagem(CentralService.mensagemErroUsuario(e), falha: true);
    } finally {
      if (mounted) setState(() => processando = false);
    }
  }
}

class _ReativarDialog extends StatefulWidget {
  const _ReativarDialog({required this.modulos});

  final List<Map<String, dynamic>> modulos;

  @override
  State<_ReativarDialog> createState() => _ReativarDialogState();
}

class _ReativarDialogState extends State<_ReativarDialog> {
  final motivoController = TextEditingController();
  final Set<String> selecionados = {};

  List<Map<String, dynamic>> get adicionais => widget.modulos
      .where((modulo) => modulo['incluido_plano_base'] != true)
      .toList();

  @override
  void initState() {
    super.initState();
    selecionados.addAll(
      adicionais
          .where((modulo) => modulo['contratado'] == true)
          .map((modulo) => modulo['id'].toString()),
    );
  }

  @override
  void dispose() {
    motivoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reativar contrato'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'A reativação só será concluída sem cobranças pendentes. '
                'O plano base será liberado automaticamente.',
              ),
              if (adicionais.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'Módulos adicionais que voltarão ativos',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                ...adicionais.map((modulo) {
                  final id = modulo['id'].toString();
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: selecionados.contains(id),
                    title: Text(modulo['nome']?.toString() ?? 'Módulo'),
                    subtitle: Text(
                      '${_moeda(modulo['preco_contratado'] ?? modulo['preco_padrao'])}/mês',
                    ),
                    onChanged: (valor) {
                      setState(() {
                        if (valor == true) {
                          selecionados.add(id);
                        } else {
                          selecionados.remove(id);
                        }
                      });
                    },
                  );
                }),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: motivoController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Motivo obrigatório',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final motivo = motivoController.text.trim();
            if (motivo.isEmpty) return;
            Navigator.pop(context, {
              'motivo': motivo,
              'modulos_ids': selecionados.toList(),
            });
          },
          child: const Text('Reativar'),
        ),
      ],
    );
  }
}

class _ContratoDialog extends StatefulWidget {
  const _ContratoDialog({this.contrato});

  final Map<String, dynamic>? contrato;

  @override
  State<_ContratoDialog> createState() => _ContratoDialogState();
}

class _ContratoDialogState extends State<_ContratoDialog> {
  late DateTime inicio;
  late String status;
  late String tipo;
  late final TextEditingController valorController;
  late final TextEditingController descontoController;
  late final TextEditingController observacaoController;

  static const valoresPadrao = {
    'SEM_IMPLANTACAO': 0.0,
    'ERP_INTEGRADO': 590.0,
    'ERP_NOVO': 990.0,
    'SOB_ORCAMENTO': 0.0,
  };

  @override
  void initState() {
    super.initState();
    final contrato = widget.contrato ?? {};
    inicio = _data(contrato['inicio_em']) ?? DateTime.now();
    status = contrato['status']?.toString() ?? 'ATIVO';
    if (status == 'CANCELADO') status = 'ATIVO';
    tipo = contrato['tipo_implantacao']?.toString() ?? 'ERP_INTEGRADO';
    valorController = TextEditingController(
      text: _numero(
        contrato['valor_implantacao'] ?? valoresPadrao[tipo],
      ).toStringAsFixed(2).replaceAll('.', ','),
    );
    descontoController = TextEditingController(
      text: _numero(
        contrato['desconto_implantacao'],
      ).toStringAsFixed(2).replaceAll('.', ','),
    );
    observacaoController = TextEditingController(
      text: contrato['observacao']?.toString(),
    );
  }

  @override
  void dispose() {
    valorController.dispose();
    descontoController.dispose();
    observacaoController.dispose();
    super.dispose();
  }

  double decimal(String texto) =>
      double.tryParse(texto.replaceAll('.', '').replaceAll(',', '.')) ?? 0;

  Future<void> escolherData() async {
    final selecionada = await showDatePicker(
      context: context,
      initialDate: inicio,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selecionada != null) setState(() => inicio = selecionada);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Contrato da loja'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Início da cobrança'),
                subtitle: Text(_dataBr(inicio)),
                trailing: IconButton(
                  tooltip: 'Escolher data',
                  onPressed: escolherData,
                  icon: const Icon(Icons.calendar_month),
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'ATIVO', child: Text('Ativo')),
                  DropdownMenuItem(value: 'RASCUNHO', child: Text('Rascunho')),
                ],
                onChanged: (valor) => setState(() => status = valor ?? status),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: tipo,
                decoration: const InputDecoration(
                  labelText: 'Implantação / ERP',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'SEM_IMPLANTACAO',
                    child: Text('Sem taxa de implantação'),
                  ),
                  DropdownMenuItem(
                    value: 'ERP_INTEGRADO',
                    child: Text('ERP já integrado'),
                  ),
                  DropdownMenuItem(
                    value: 'ERP_NOVO',
                    child: Text('Novo ERP para a Vupt'),
                  ),
                  DropdownMenuItem(
                    value: 'SOB_ORCAMENTO',
                    child: Text('Sob orçamento'),
                  ),
                ],
                onChanged: (valor) {
                  if (valor == null) return;
                  setState(() {
                    tipo = valor;
                    valorController.text = (valoresPadrao[valor] ?? 0)
                        .toStringAsFixed(2)
                        .replaceAll('.', ',');
                  });
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: valorController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Valor da implantação',
                        prefixText: 'R\$ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: descontoController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Desconto',
                        prefixText: 'R\$ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: observacaoController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Observação / justificativa',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final valor = decimal(valorController.text);
            final desconto = decimal(descontoController.text);
            if (valor < 0 || desconto < 0 || desconto > valor) return;
            Navigator.pop(context, {
              'inicio': inicio,
              'status': status,
              'tipo_implantacao': tipo,
              'valor_implantacao': valor,
              'desconto_implantacao': desconto,
              'observacao': observacaoController.text.trim(),
            });
          },
          child: const Text('Salvar contrato'),
        ),
      ],
    );
  }
}

class _ModuloLojaDialog extends StatefulWidget {
  const _ModuloLojaDialog({required this.modulo});

  final Map<String, dynamic> modulo;

  @override
  State<_ModuloLojaDialog> createState() => _ModuloLojaDialogState();
}

class _ModuloLojaDialogState extends State<_ModuloLojaDialog> {
  late bool ativo;
  late DateTime vigencia;
  late final TextEditingController precoController;
  final motivoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    ativo = widget.modulo['contratado'] == true;
    vigencia = DateTime.now();
    precoController = TextEditingController(
      text: _numero(
        widget.modulo['preco_contratado'] ?? widget.modulo['preco_padrao'],
      ).toStringAsFixed(2).replaceAll('.', ','),
    );
  }

  @override
  void dispose() {
    precoController.dispose();
    motivoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.modulo['nome']?.toString() ?? 'Módulo'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: ativo,
              onChanged: (valor) => setState(() => ativo = valor),
              title: Text(
                ativo ? 'Módulo contratado' : 'Módulo não contratado',
              ),
            ),
            TextField(
              controller: precoController,
              enabled: ativo,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Preço mensal negociado',
                prefixText: 'R\$ ',
                border: OutlineInputBorder(),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Início da vigência'),
              subtitle: Text(_dataBr(vigencia)),
              trailing: IconButton(
                tooltip: 'Escolher data',
                onPressed: () async {
                  final data = await showDatePicker(
                    context: context,
                    initialDate: vigencia,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (data != null) setState(() => vigencia = data);
                },
                icon: const Icon(Icons.calendar_month),
              ),
            ),
            TextField(
              controller: motivoController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Motivo / condição negociada',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final motivo = motivoController.text.trim();
            if (motivo.isEmpty) return;
            Navigator.pop(context, {
              'ativo': ativo,
              'preco':
                  double.tryParse(
                    precoController.text
                        .replaceAll('.', '')
                        .replaceAll(',', '.'),
                  ) ??
                  0,
              'vigencia': vigencia,
              'motivo': motivo,
            });
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _CobrancaDialog extends StatefulWidget {
  const _CobrancaDialog({required this.cobranca});

  final Map<String, dynamic> cobranca;

  @override
  State<_CobrancaDialog> createState() => _CobrancaDialogState();
}

class _CobrancaDialogState extends State<_CobrancaDialog> {
  late String status;
  late DateTime? pagoEm;
  late final TextEditingController referenciaController;
  late final TextEditingController formaController;
  late final TextEditingController observacaoController;

  @override
  void initState() {
    super.initState();
    status = widget.cobranca['status']?.toString() ?? 'AGUARDANDO_EMISSAO';
    pagoEm = _data(widget.cobranca['pago_em']);
    referenciaController = TextEditingController(
      text: widget.cobranca['referencia']?.toString(),
    );
    formaController = TextEditingController(
      text: widget.cobranca['forma_pagamento']?.toString(),
    );
    observacaoController = TextEditingController(
      text: widget.cobranca['observacao']?.toString(),
    );
  }

  @override
  void dispose() {
    referenciaController.dispose();
    formaController.dispose();
    observacaoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const statuses = [
      'AGUARDANDO_EMISSAO',
      'EMITIDA',
      'PAGA',
      'VENCIDA',
      'NEGOCIADA',
      'CANCELADA',
    ];
    return AlertDialog(
      title: Text('Cobrança ${_moeda(widget.cobranca['valor_total'])}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: statuses.contains(status)
                    ? status
                    : statuses.first,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: statuses
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(item.replaceAll('_', ' ')),
                      ),
                    )
                    .toList(),
                onChanged: (valor) {
                  if (valor == null) return;
                  setState(() {
                    status = valor;
                    if (status == 'PAGA') pagoEm ??= DateTime.now();
                  });
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: referenciaController,
                decoration: const InputDecoration(
                  labelText: 'Nº da fatura / referência',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: formaController,
                decoration: const InputDecoration(
                  labelText: 'Forma de pagamento',
                  border: OutlineInputBorder(),
                ),
              ),
              if (status == 'PAGA')
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Data do pagamento'),
                  subtitle: Text(_dataBr(pagoEm)),
                  trailing: IconButton(
                    tooltip: 'Escolher data',
                    onPressed: () async {
                      final data = await showDatePicker(
                        context: context,
                        initialDate: pagoEm ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (data != null) setState(() => pagoEm = data);
                    },
                    icon: const Icon(Icons.calendar_month),
                  ),
                ),
              TextField(
                controller: observacaoController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Observação',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, {
              'status': status,
              'referencia': referenciaController.text.trim(),
              'forma_pagamento': formaController.text.trim(),
              'pago_em': status == 'PAGA' ? pagoEm ?? DateTime.now() : null,
              'observacao': observacaoController.text.trim(),
            });
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _AvisoSincronizacaoFinanceira extends StatelessWidget {
  const _AvisoSincronizacaoFinanceira({required this.avisos});

  final List<String> avisos;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF3E0),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.sync_problem, color: Color(0xFFB75D00)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Algumas lojas não puderam ser atualizadas agora:\n'
                '${avisos.join('\n')}',
                style: const TextStyle(color: Color(0xFF7A3E00)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErroFinanceiro extends StatelessWidget {
  const _ErroFinanceiro({
    required this.mensagem,
    required this.tentarNovamente,
  });

  final String mensagem;
  final VoidCallback tentarNovamente;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(mensagem, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: tentarNovamente,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PainelVazio extends StatelessWidget {
  const _PainelVazio({required this.icone, required this.texto});

  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(36),
      child: Column(
        children: [
          Icon(icone, size: 48, color: Colors.black26),
          const SizedBox(height: 10),
          Text(texto, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

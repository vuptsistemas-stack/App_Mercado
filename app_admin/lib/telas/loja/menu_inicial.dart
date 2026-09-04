import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/central_service.dart';
import '../../services/monitor_acoes_validade_service.dart';
import '../../services/monitor_pedidos_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/sessao_loja.dart';
import '../auth/login_central_page.dart';
import '../shared/usuarios_sistema_page.dart';

import 'estoque/estoque_page.dart';
import 'estoque/estoque_auditoria_page.dart';
import 'balanco_page.dart';
import 'conferencia_notas_page.dart';
import 'consulta_item_page.dart';
import 'home.dart';
import 'pedidos_mercado.dart';
import 'loja_configuracoes_page.dart';
import 'cupons_desconto_page.dart';
import 'ofertas_page.dart';
import 'jornal_promocoes_page.dart';
import 'acoes_validade_page.dart';
import 'produtos_peso_variavel_page.dart';
import 'produtos_app_page.dart';
import 'receitas_producao_page.dart';
import 'relatorios_page.dart';
import 'clientes_app_page.dart';

class MenuInicialPage extends StatefulWidget {
  const MenuInicialPage({super.key});

  @override
  State<MenuInicialPage> createState() => _MenuInicialPageState();
}

class _MenuInicialPageState extends State<MenuInicialPage>
    with WidgetsBindingObserver {
  static Color get vermelho => SessaoLoja.corPrimaria;
  static Color get fundo => SessaoLoja.corFundo;

  final CentralService centralService = CentralService();

  bool carregandoPermissoes = true;
  bool usuarioMasterCentral = false;
  bool mercadoBloqueado = false;
  bool bloqueioExecutado = false;
  bool monitorPedidosIniciado = false;
  bool monitorValidadeIniciado = false;
  bool testandoApi = false;
  bool apiConectada = false;
  bool alertaValidadePendente = false;
  bool verificandoAlertaValidade = false;
  bool atualizandoPermissoesRemotas = false;
  bool ativandoNotificacoesWeb = false;
  bool notificacoesWebAtivas = false;

  Timer? monitorPermissoesTimer;
  DateTime? ultimaAtualizacaoPermissoesRemotas;

  Set<String> permissoes = {};

  final Set<String> todasPermissoes = const {
    'pedidos',
    'consulta_preco',
    'consulta_item',
    'balanco',
    'conferencia_notas',
    'estoque',
    'estoque_entrada',
    'estoque_correcao',
    'estoque_baixa_avaria',
    'estoque_baixa_validade',
    'estoque_consumo_interno',
    'estoque_auditoria',
    'produtos_app',
    'receitas',
    'cupons',
    'ofertas',
    'jornal_promocoes',
    'clientes_app',
    'acoes_validade',
    'peso_variavel',
    'loja_configuracoes',
    'usuarios',
    'relatorios',
  };

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    iniciarMonitorPermissoes();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        await carregarPermissoesUsuario(forcarAtualizacaoRemota: true);
        await testarConexaoApi();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    monitorPermissoesTimer?.cancel();
    MonitorAcoesValidadeService.instance.parar();
    super.dispose();
  }

  void iniciarMonitorPermissoes() {
    monitorPermissoesTimer ??= Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(atualizarPermissoesRemotas(silencioso: true));
    });
  }

  Future<void> iniciarMonitorPedidos() async {
    if (monitorPedidosIniciado) {
      return;
    }

    try {
      await MonitorPedidosService.instance.iniciar(
        onNovoPedido: () async {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Novo pedido recebido'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 5),
            ),
          );
        },
      );

      monitorPedidosIniciado = true;
      if (kIsWeb && mounted) {
        setState(() {
          notificacoesWebAtivas = PushNotificationService.instance.pushAtivo;
        });
      }
    } catch (_) {
      // Não trava o menu caso o monitor não consiga iniciar.
    }
  }

  Future<void> ativarNotificacoesDoPwa() async {
    if (!kIsWeb || ativandoNotificacoesWeb) return;

    setState(() => ativandoNotificacoesWeb = true);

    final ativou = await PushNotificationService.instance.inicializarAdmin(
      solicitarPermissao: true,
    );

    if (!mounted) return;

    setState(() {
      ativandoNotificacoesWeb = false;
      notificacoesWebAtivas = ativou;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ativou
              ? 'Notificacoes ativadas neste dispositivo.'
              : 'Nao foi possivel ativar. No iPhone, abra o PWA instalado na Tela de Inicio e permita as notificacoes.',
        ),
        backgroundColor: ativou ? Colors.green : Colors.orange,
      ),
    );
  }

  Future<void> pararMonitorPedidos() async {
    try {
      await MonitorPedidosService.instance.parar();
    } catch (_) {}

    monitorPedidosIniciado = false;
  }

  Future<void> iniciarMonitorAcoesValidade() async {
    if (monitorValidadeIniciado) {
      await carregarAlertaValidadePainel();
      return;
    }

    if (!usuarioMasterCentral && !temPermissao('acoes_validade')) {
      await carregarAlertaValidadePainel();
      return;
    }

    try {
      await MonitorAcoesValidadeService.instance.iniciar(
        onAcoesEncerradas: carregarAlertaValidadePainel,
      );
      monitorValidadeIniciado = true;
      await carregarAlertaValidadePainel();
    } catch (_) {
      // Nao trava o menu caso o monitor nao consiga iniciar.
    }
  }

  Future<void> pararMonitorAcoesValidade() async {
    try {
      await MonitorAcoesValidadeService.instance.parar();
    } catch (_) {}

    monitorValidadeIniciado = false;
  }

  Future<void> carregarAlertaValidadePainel() async {
    if (verificandoAlertaValidade || !mounted) return;

    final podeVerValidade =
        usuarioMasterCentral || permissoes.contains('acoes_validade');
    final mercadoId = SessaoLoja.mercadoId?.trim();

    if (!podeVerValidade || mercadoId == null || mercadoId.isEmpty) {
      if (alertaValidadePendente && mounted) {
        setState(() => alertaValidadePendente = false);
      }
      return;
    }

    verificandoAlertaValidade = true;

    try {
      final dados = await centralService.listarAcoesValidade(
        mercadoId: mercadoId,
      );
      final alertas = dados['alertas'] as List<Map<String, dynamic>>;
      final temAlerta = alertas.isNotEmpty;

      if (!mounted) return;

      if (alertaValidadePendente != temAlerta) {
        setState(() => alertaValidadePendente = temAlerta);
      }
    } catch (_) {
      // O painel continua funcionando mesmo se a consulta de alerta falhar.
    } finally {
      verificandoAlertaValidade = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!carregandoPermissoes && !usuarioMasterCentral && !mercadoBloqueado) {
        validarMercadoAtivoOuBloquear(
          ehMasterCentral: usuarioMasterCentral,
          silencioso: true,
        );
      }

      if (!mercadoBloqueado && !carregandoPermissoes) {
        unawaited(atualizarPermissoesRemotas(silencioso: true, forcar: true));
        iniciarMonitorPedidos();
        iniciarMonitorAcoesValidade();
        carregarAlertaValidadePainel();
        testarConexaoApi();
      }
    }
  }

  String? textoOuNull(String? valor) {
    final texto = valor?.trim() ?? '';

    if (texto.isEmpty) {
      return null;
    }

    return texto;
  }

  Future<void> testarConexaoApi() async {
    final api = SessaoLoja.apiBaseUrl?.trim();

    if (api == null || api.isEmpty) {
      if (!mounted) return;

      setState(() {
        testandoApi = false;
        apiConectada = false;
      });
      return;
    }

    if (mounted) {
      setState(() {
        testandoApi = true;
      });
    }

    try {
      final url = api.replaceAll(RegExp(r'/+$'), '');
      final resposta = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      if (!mounted) return;

      setState(() {
        apiConectada = resposta.statusCode >= 200 && resposta.statusCode < 500;
        testandoApi = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        apiConectada = false;
        testandoApi = false;
      });
    }
  }

  Future<bool> validarMercadoAtivoOuBloquear({
    required bool ehMasterCentral,
    bool silencioso = false,
  }) async {
    if (ehMasterCentral) {
      return true;
    }

    if (!SessaoLoja.lojaSelecionada) {
      return true;
    }

    final mercadoId = textoOuNull(SessaoLoja.mercadoId);
    final mercadoCodigo = textoOuNull(SessaoLoja.mercadoCodigo);

    if (mercadoId == null && mercadoCodigo == null) {
      await bloquearLojaInativa(
        'Não foi possível identificar a loja atual. Faça login novamente.',
      );
      return false;
    }

    try {
      final resposta = await centralService.validarMercadoAtivo(
        mercadoId: mercadoId,
        mercadoCodigo: mercadoCodigo,
      );

      final ativo = resposta['ativo'] == true;
      final bloqueado = resposta['bloqueado'] == true || !ativo;

      if (bloqueado) {
        final mensagem =
            resposta['mensagem']?.toString() ??
            'Esta loja foi desativada. Entre em contato com o suporte para reativar o acesso.';

        await bloquearLojaInativa(mensagem);
        return false;
      }

      return true;
    } catch (e) {
      if (!silencioso && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível validar o status da loja: ${CentralService.mensagemErroUsuario(e)}',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }

      return true;
    }
  }

  Future<void> bloquearLojaInativa(String mensagem) async {
    if (bloqueioExecutado || !mounted) {
      return;
    }

    bloqueioExecutado = true;

    await pararMonitorPedidos();
    await pararMonitorAcoesValidade();

    if (!mounted) {
      return;
    }

    setState(() {
      mercadoBloqueado = true;
      carregandoPermissoes = false;
    });

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Loja desativada'),
        content: Text(mensagem),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: vermelho,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );

    try {
      await SessaoLoja.supabaseLoja?.auth.signOut();
    } catch (_) {}

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    SessaoLoja.limpar();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginCentralPage()),
      (route) => false,
    );
  }

  bool conjuntosIguais(Set<String> a, Set<String> b) {
    if (a.length != b.length) {
      return false;
    }

    return a.containsAll(b);
  }

  List<String> extrairPermissoesPermitidas(Map<String, dynamic> resposta) {
    final origem = resposta['permissoes'] ?? resposta['modulos'];

    if (origem is! List) {
      return const [];
    }

    final codigos = <String>{};

    for (final item in origem) {
      if (item is String) {
        final codigo = item.trim();

        if (codigo.isNotEmpty) {
          codigos.add(codigo);
        }

        continue;
      }

      if (item is Map) {
        final permitido = item['permitido'];

        if (permitido == false) {
          continue;
        }

        final codigo =
            (item['codigo'] ?? item['modulo_codigo'])?.toString().trim() ?? '';

        if (codigo.isNotEmpty) {
          codigos.add(codigo);
        }
      }
    }

    return codigos.toList();
  }

  Future<Set<String>?> buscarPermissoesRemotas() async {
    final mercadoId = SessaoLoja.mercadoId?.trim() ?? '';
    final userId = SessaoLoja.usuarioId?.trim() ?? '';

    if (mercadoId.isEmpty || userId.isEmpty) {
      return null;
    }

    final resposta = await centralService.listarPermissoesUsuario(
      mercadoId: mercadoId,
      userId: userId,
    );

    return extrairPermissoesPermitidas(resposta).toSet();
  }

  Future<void> aplicarPermissoesAtualizadas(Set<String> novasPermissoes) async {
    final permissoesAtuais = permissoes.toSet();
    final permissoesSessao = SessaoLoja.permissoesUsuario.toSet();
    final mudouSessao = !conjuntosIguais(permissoesSessao, novasPermissoes);

    if (mudouSessao) {
      SessaoLoja.atualizarPermissoes(novasPermissoes.toList());
    }

    if (mounted && !conjuntosIguais(permissoesAtuais, novasPermissoes)) {
      setState(() {
        permissoes = novasPermissoes;
      });
    } else if (mounted && !conjuntosIguais(permissoes, novasPermissoes)) {
      setState(() {
        permissoes = novasPermissoes;
      });
    }

    if (novasPermissoes.contains('pedidos')) {
      await iniciarMonitorPedidos();
    } else {
      await pararMonitorPedidos();
    }

    if (novasPermissoes.contains('acoes_validade')) {
      await iniciarMonitorAcoesValidade();
    } else {
      await pararMonitorAcoesValidade();
      await carregarAlertaValidadePainel();
    }

    if (mudouSessao) {
      await SessaoLoja.salvarSessaoLojaPersistida();
    }
  }

  Future<void> atualizarPermissoesRemotas({
    bool silencioso = true,
    bool forcar = false,
  }) async {
    if (!mounted ||
        mercadoBloqueado ||
        carregandoPermissoes ||
        atualizandoPermissoesRemotas ||
        usuarioMasterCentral ||
        !SessaoLoja.usuarioLogadoNaLoja) {
      return;
    }

    final agora = DateTime.now();

    if (!forcar &&
        ultimaAtualizacaoPermissoesRemotas != null &&
        agora.difference(ultimaAtualizacaoPermissoesRemotas!) <
            const Duration(seconds: 20)) {
      return;
    }

    atualizandoPermissoesRemotas = true;

    try {
      final permissoesAtualizadas = await buscarPermissoesRemotas();
      ultimaAtualizacaoPermissoesRemotas = DateTime.now();

      if (permissoesAtualizadas == null) {
        return;
      }

      await aplicarPermissoesAtualizadas(permissoesAtualizadas);
    } catch (e) {
      ultimaAtualizacaoPermissoesRemotas = DateTime.now();

      if (!silencioso && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao atualizar permissões: ${CentralService.mensagemErroUsuario(e)}',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      atualizandoPermissoesRemotas = false;
    }
  }

  Future<void> carregarPermissoesUsuario({
    bool forcarAtualizacaoRemota = false,
  }) async {
    if (!mounted) return;

    setState(() {
      carregandoPermissoes = true;
    });

    try {
      SessaoLoja.sincronizarSessaoAtual();

      bool ehMasterCentral = false;

      try {
        ehMasterCentral = await centralService.usuarioEhMaster();
      } catch (_) {
        ehMasterCentral = false;
      }

      final mercadoAtivo = await validarMercadoAtivoOuBloquear(
        ehMasterCentral: ehMasterCentral,
        silencioso: true,
      );

      if (!mercadoAtivo) {
        return;
      }

      if (ehMasterCentral) {
        if (!mounted) return;

        setState(() {
          usuarioMasterCentral = ehMasterCentral;
          permissoes = todasPermissoes;
          carregandoPermissoes = false;
        });

        await iniciarMonitorPedidos();
        await iniciarMonitorAcoesValidade();

        return;
      }

      final permissoesUsuario = forcarAtualizacaoRemota
          ? (await buscarPermissoesRemotas()) ??
                SessaoLoja.permissoesUsuario.toSet()
          : SessaoLoja.permissoesUsuario.toSet();

      SessaoLoja.atualizarPermissoes(permissoesUsuario.toList());

      if (!mounted) return;

      setState(() {
        usuarioMasterCentral = false;
        permissoes = permissoesUsuario;
        carregandoPermissoes = false;
      });

      if (permissoesUsuario.contains('pedidos')) {
        await iniciarMonitorPedidos();
      }

      if (permissoesUsuario.contains('acoes_validade')) {
        await iniciarMonitorAcoesValidade();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        usuarioMasterCentral = false;
        permissoes = {};
        carregandoPermissoes = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao carregar permissões: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  bool temPermissao(String codigo) {
    if (usuarioMasterCentral) {
      return true;
    }

    return permissoes.contains(codigo);
  }

  bool temAlgumaPermissao(List<String> codigos) {
    if (usuarioMasterCentral) {
      return true;
    }

    return codigos.any(permissoes.contains);
  }

  void mostrarSemPermissao(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Você não tem permissão para acessar esta função.'),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> sair(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sair do sistema'),
        content: const Text('Deseja realmente sair desta conta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Sair',
              style: TextStyle(color: vermelho, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmar != true) {
      return;
    }

    await pararMonitorPedidos();
    await pararMonitorAcoesValidade();

    await SessaoLoja.supabaseLoja?.auth.signOut();
    await Supabase.instance.client.auth.signOut();

    SessaoLoja.limpar();

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginCentralPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final nomeLoja = SessaoLoja.mercadoNome ?? 'Painel da loja';

    return Scaffold(
      backgroundColor: fundo,
      appBar: AppBar(
        title: Text(nomeLoja),
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: 'Atualizar permissões',
            onPressed: carregandoPermissoes || mercadoBloqueado
                ? null
                : () async {
                    await carregarPermissoesUsuario(
                      forcarAtualizacaoRemota: true,
                    );
                    await testarConexaoApi();
                  },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: () => sair(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: carregandoPermissoes || mercadoBloqueado
            ? Center(
                child: mercadoBloqueado
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 48,
                            color: Colors.black38,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Acesso bloqueado',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'A loja foi desativada.',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ],
                      )
                    : const CircularProgressIndicator(),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Painel Administrativo',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      usuarioMasterCentral
                          ? 'Acesso master central: todas as funções da loja estão liberadas.'
                          : SessaoLoja.usuarioAdminLoja
                          ? 'Acesso administrador da loja: todas as funções estão liberadas.'
                          : SessaoLoja.lojaSelecionada
                          ? 'Gerencie apenas as funções liberadas para o seu usuário.'
                          : 'Nenhuma loja selecionada. Volte e selecione uma loja.',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 14),
                    statusApiTopo(),
                    if (kIsWeb && temPermissao('pedidos')) ...[
                      const SizedBox(height: 14),
                      statusNotificacoesWeb(),
                    ],
                    const SizedBox(height: 14),
                    montarGridMenu(context),
                    const SizedBox(height: 24),
                    resumoRodape(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget statusNotificacoesWeb() {
    final cor = notificacoesWebAtivas ? Colors.green : vermelho;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        border: Border.all(color: cor.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            notificacoesWebAtivas
                ? Icons.notifications_active
                : Icons.notifications_none,
            color: cor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              notificacoesWebAtivas
                  ? 'Notificacoes ativas neste dispositivo'
                  : 'Ative os avisos de novos pedidos',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (!notificacoesWebAtivas)
            FilledButton.icon(
              onPressed: ativandoNotificacoesWeb
                  ? null
                  : ativarNotificacoesDoPwa,
              icon: ativandoNotificacoesWeb
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.notifications_active_outlined),
              label: const Text('Ativar'),
            ),
        ],
      ),
    );
  }

  Widget montarGridMenu(BuildContext context) {
    final itens = <Widget>[];

    if (temPermissao('pedidos')) {
      itens.add(
        cardMenu(
          context: context,
          titulo: 'Pedidos',
          subtitulo: 'Visualizar pedidos',
          icone: Icons.receipt_long,
          pagina: const PedidosMercadoPage(),
          permitido: temPermissao('pedidos'),
        ),
      );
    }

    if (temPermissao('consulta_preco')) {
      itens.add(
        cardMenu(
          context: context,
          titulo: 'Consultar Item',
          subtitulo: 'Compra, venda e estoque',
          icone: Icons.query_stats,
          pagina: const TelaHome(),
          permitido: temPermissao('consulta_preco'),
        ),
      );
    }

    if (temPermissao('consulta_item')) {
      itens.add(
        cardMenu(
          context: context,
          titulo: 'Consultar Preço',
          subtitulo: 'Imagem ampliada',
          icone: Icons.image_search,
          pagina: const ConsultaItemPage(),
          permitido: temPermissao('consulta_item'),
        ),
      );
    }

    if (temPermissao('balanco')) {
      itens.add(
        cardMenu(
          context: context,
          titulo: 'Balanço',
          subtitulo: 'Coletar itens TXT',
          icone: Icons.assignment_turned_in_outlined,
          pagina: BalancoPage(
            podeGerarTxt:
                usuarioMasterCentral ||
                SessaoLoja.usuarioAdminLoja ||
                SessaoLoja.usuarioAcessoTotal,
          ),
          permitido: temPermissao('balanco'),
        ),
      );
    }

    if (temPermissao('conferencia_notas') &&
        SessaoLoja.mercadoCodigo == 'sao_mateus') {
      itens.add(
        cardMenu(
          context: context,
          titulo: 'Conferencia NF-e',
          subtitulo: 'Notas de entrada',
          icone: Icons.fact_check_outlined,
          pagina: const ConferenciaNotasPage(),
          permitido: temPermissao('conferencia_notas'),
        ),
      );
    }

    if (temAlgumaPermissao([
      'estoque',
      'estoque_entrada',
      'estoque_correcao',
      'estoque_baixa_avaria',
      'estoque_baixa_validade',
    ])) {
      itens.add(
        cardMenu(
          context: context,
          titulo: 'Estoque',
          subtitulo: 'Entrada, correções e baixas',
          icone: Icons.inventory_2,
          pagina: const EstoquePage(),
          permitido: temAlgumaPermissao([
            'estoque',
            'estoque_entrada',
            'estoque_correcao',
            'estoque_baixa_avaria',
            'estoque_baixa_validade',
          ]),
        ),
      );
    }

    if (temPermissao('estoque_consumo_interno')) {
      itens.add(
        cardMenu(
          context: context,
          titulo: 'Consumo Interno',
          subtitulo: 'Uso interno da loja',
          icone: Icons.remove_circle,
          pagina: const ConsultaEstoquePage(
            titulo: 'Consumo Interno',
            subtitulo: 'Escaneie ou busque o item e confirme o consumo.',
            tipo: 'CONSUMO_INTERNO',
            permissao: 'estoque_consumo_interno',
            cor: Colors.orange,
            icone: Icons.remove_circle,
          ),
          permitido: temPermissao('estoque_consumo_interno'),
        ),
      );
    }

    if (temPermissao('estoque_auditoria')) {
      itens.add(
        cardMenu(
          context: context,
          titulo: 'Auditoria',
          subtitulo: 'Historico de estoque',
          icone: Icons.fact_check_outlined,
          pagina: const EstoqueAuditoriaPage(),
          permitido: temPermissao('estoque_auditoria'),
        ),
      );
    }

    if (temPermissao('loja_configuracoes')) {
      itens.add(
        cardMenu(
          context: context,
          titulo: 'Loja',
          subtitulo: 'Configurações',
          icone: Icons.store,
          pagina: const LojaConfiguracoesPage(),
          permitido: temPermissao('loja_configuracoes'),
        ),
      );
    }

    if (temPermissao('cupons')) {
      itens.add(
        cardMenu(
          context: context,
          titulo: 'Cupons',
          subtitulo: 'Descontos do app',
          icone: Icons.local_offer,
          pagina: const CuponsDescontoPage(),
          permitido: temPermissao('cupons'),
        ),
      );
    }

    if (temPermissao('ofertas')) {
      itens.add(
        cardMenu(
          context: context,
          titulo: 'Ofertas',
          subtitulo: 'Produtos em destaque',
          icone: Icons.campaign,
          pagina: const OfertasPage(),
          permitido: temPermissao('ofertas'),
        ),
      );
    }

    if (temPermissao('jornal_promocoes')) {
      itens.add(
        cardMenu(
          context: context,
          titulo: 'Jornal',
          subtitulo: 'Impressao e redes',
          icone: Icons.newspaper_outlined,
          pagina: const JornalPromocoesPage(),
          permitido: temPermissao('jornal_promocoes'),
        ),
      );
    }

    if (temPermissao('clientes_app')) {
      itens.add(
        cardMenu(
          context: context,
          titulo: 'Clientes',
          subtitulo: 'Cadastros e bloqueios',
          icone: Icons.people_alt_outlined,
          pagina: const ClientesAppPage(),
          permitido: temPermissao('clientes_app'),
        ),
      );
    }

    if (temPermissao('acoes_validade')) {
      itens.add(
        cardMenu(
          context: context,
          titulo: 'Validade',
          subtitulo: 'Desconto por vencimento',
          icone: Icons.timer_outlined,
          pagina: const AcoesValidadePage(),
          permitido: temPermissao('acoes_validade'),
          destaqueAlerta: alertaValidadePendente,
          aoRetornar: carregarAlertaValidadePainel,
        ),
      );
    }

    if (temPermissao('produtos_app')) {
      itens.add(
        cardMenu(
          context: context,
          titulo: 'Produtos app',
          subtitulo: 'Cadastro BANCO_LOJA',
          icone: Icons.shopping_basket,
          pagina: const ProdutosAppPage(),
          permitido: temPermissao('produtos_app'),
        ),
      );
    }

    if (temPermissao('receitas')) {
      itens.add(
        cardMenu(
          context: context,
          titulo: 'Receitas',
          subtitulo: 'Produção e baixa',
          icone: Icons.receipt_long,
          pagina: const ReceitasProducaoPage(),
          permitido: temPermissao('receitas'),
        ),
      );
    }

    if (temPermissao('peso_variavel')) {
      itens.add(
        cardMenu(
          context: context,
          titulo: 'Peso variável',
          subtitulo: 'Produtos KG do app',
          icone: Icons.scale_outlined,
          pagina: const ProdutosPesoVariavelPage(),
          permitido: temPermissao('peso_variavel'),
        ),
      );
    }

    if (temPermissao('usuarios')) {
      itens.add(
        cardMenu(
          context: context,
          titulo: 'Usuários',
          subtitulo: 'Senhas e acessos',
          icone: Icons.people,
          pagina: UsuariosSistemaPage(
            mercadoId: SessaoLoja.mercadoId,
            titulo: 'Usuários da loja',
          ),
          permitido: temPermissao('usuarios'),
        ),
      );
    }

    if (temPermissao('relatorios')) {
      itens.add(
        cardMenu(
          context: context,
          titulo: 'Relatórios',
          subtitulo: 'Consumo interno',
          icone: Icons.bar_chart,
          pagina: const RelatoriosPage(),
          permitido: temPermissao('relatorios'),
        ),
      );
    }

    if (itens.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        ),
        child: const Column(
          children: [
            Icon(Icons.lock_outline, size: 42, color: Colors.black38),
            SizedBox(height: 12),
            Text(
              'Nenhuma função liberada',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 6),
            Text(
              'Peça para o administrador liberar permissões para o seu usuário.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 1.06,
      children: itens,
    );
  }

  Widget topoDashboard(BuildContext context) {
    final nomeLoja = SessaoLoja.mercadoNome ?? 'Loja não selecionada';
    final logoUrl = SessaoLoja.logoUrl?.trim() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [SessaoLoja.corPrimaria, SessaoLoja.corSecundaria],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: vermelho.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 76,
            height: 76,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: logoUrl.isEmpty
                ? Icon(
                    Icons.storefront_rounded,
                    color: vermelho.withValues(alpha: 0.55),
                    size: 38,
                  )
                : Image.network(
                    logoUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.storefront_rounded,
                      color: vermelho.withValues(alpha: 0.55),
                      size: 38,
                    ),
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nomeLoja,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  usuarioMasterCentral
                      ? 'Acesso master central'
                      : SessaoLoja.usuarioNome == null ||
                            SessaoLoja.usuarioNome!.isEmpty
                      ? 'Painel de controle da loja'
                      : 'Usuário: ${SessaoLoja.usuarioNome}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget cardMenu({
    required BuildContext context,
    required String titulo,
    required String subtitulo,
    required IconData icone,
    required Widget pagina,
    required bool permitido,
    bool destaqueAlerta = false,
    Future<void> Function()? aoRetornar,
  }) {
    final destaque = destaqueAlerta ? const Color(0xFFF97316) : vermelho;
    final fundoCard = destaqueAlerta ? const Color(0xFFFFF7ED) : Colors.white;
    final bordaCard = destaqueAlerta
        ? const Color(0xFFF97316)
        : Colors.black.withValues(alpha: 0.08);
    final tituloCor = destaqueAlerta
        ? const Color(0xFF9A3412)
        : const Color(0xFF1F2937);
    final subtituloCor = destaqueAlerta
        ? const Color(0xFFC2410C)
        : const Color(0xFF6B7280);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final mercadoAtivo = await validarMercadoAtivoOuBloquear(
          ehMasterCentral: usuarioMasterCentral,
          silencioso: true,
        );

        if (!mercadoAtivo) {
          return;
        }

        if (!context.mounted) return;

        if (!SessaoLoja.lojaSelecionada) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nenhuma loja selecionada'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        if (!permitido) {
          mostrarSemPermissao(context);
          return;
        }

        await iniciarMonitorPedidos();

        if (!context.mounted) return;

        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => pagina),
        );

        await atualizarPermissoesRemotas(silencioso: true, forcar: true);

        if (aoRetornar != null) {
          await aoRetornar();
        }
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 7, 6, 6),
        decoration: BoxDecoration(
          color: fundoCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: bordaCard, width: destaqueAlerta ? 1.4 : 1),
          boxShadow: [
            BoxShadow(
              color: destaqueAlerta
                  ? const Color(0xFFF97316).withValues(alpha: 0.20)
                  : Colors.black.withValues(alpha: 0.055),
              blurRadius: destaqueAlerta ? 16 : 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 31,
                  height: 31,
                  decoration: BoxDecoration(
                    color: destaque.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icone, color: destaque, size: 23),
                ),
                if (destaqueAlerta)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: destaqueAlerta ? 4 : 5),
            Text(
              titulo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.02,
                fontWeight: FontWeight.w900,
                color: tituloCor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              destaqueAlerta ? 'Conferir prateleira' : subtitulo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9.5,
                height: 1.03,
                fontWeight: FontWeight.w600,
                color: subtituloCor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget statusApiTopo() {
    final conectado = apiConectada;
    final corStatus = testandoApi
        ? Colors.orange
        : conectado
        ? Colors.green
        : Colors.red;

    final textoStatus = testandoApi
        ? 'Testando conexão com a API...'
        : conectado
        ? 'API conectada'
        : 'API não conectada';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: corStatus.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(color: corStatus, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              textoStatus,
              style: const TextStyle(
                color: Color(0xFF1F2937),
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          InkWell(
            onTap: testandoApi ? null : testarConexaoApi,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.refresh_rounded,
                color: testandoApi ? Colors.black26 : vermelho,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget resumoRodape() {
    String perfil;

    if (usuarioMasterCentral) {
      perfil = 'master central';
    } else if (SessaoLoja.usuarioAdminLoja) {
      perfil = 'admin loja';
    } else {
      perfil = SessaoLoja.usuarioPerfil ?? 'usuário';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.black45),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Perfil: $perfil • Use este painel para administrar o app do mercado.',
              style: const TextStyle(color: Colors.black54, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

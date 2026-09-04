// ABA-FLUANTE-GLOBAL-CORRECAO-REAL
// MAIS-FUNCIONANDO-ABRE-PAINEL
// MASTER-ACESSA-LOJA-MUDA-ABA-PELA-SESSAO
// NAVIGATOR-KEY-CORRIGE-CONTEXTO-SEM-NAVIGATOR
// ABA-MODO-MASTER-LOJA-FORCADO-CORRIGIDO
// ABA-REBUILD-MODO-LOJA-SEM-CONST-CORRIGIDO

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/app_navigator.dart';
import '../../services/sessao_loja.dart';
import '../auth/login_central_page.dart';
import '../loja/cupons_desconto_page.dart';
import '../loja/estoque/estoque_page.dart';
import '../loja/home.dart';
import '../loja/loja_configuracoes_page.dart';
import '../loja/menu_inicial.dart';
import '../loja/pedidos_mercado.dart';
import '../loja/relatorios_page.dart';
import '../master/admin_geral_page.dart';
import '../master/cadastrar_mercado_page.dart';
import '../master/cadastrar_usuario_page.dart';
import '../master/gerenciar_mercados_page.dart';
import '../selecionar_loja_page.dart';
import 'usuarios_sistema_page.dart';

class AbaFlutuanteGlobalHost extends StatelessWidget {
  final Widget child;

  const AbaFlutuanteGlobalHost({super.key, required this.child});

  static const double alturaAba = 78;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, _) {
        return ValueListenableBuilder<int>(
          valueListenable: SessaoLoja.alteracoes,
          builder: (context, __, ___) {
            return ValueListenableBuilder<int>(
              valueListenable: AppNavigator.alteracoesAba,
              builder: (context, ___, ____) {
                final tecladoAberto =
                    MediaQuery.of(context).viewInsets.bottom > 0;
                final usuarioCentralLogado =
                    Supabase.instance.client.auth.currentSession != null;
                final lojaSelecionada =
                    SessaoLoja.lojaSelecionada || AppNavigator.modoLojaForcado;
                final conteudoEstendido =
                    AppNavigator.conteudoEstendidoAteRodape;
                final deveMostrar =
                    !tecladoAberto &&
                    (usuarioCentralLogado || lojaSelecionada) &&
                    child is! LoginCentralPage;

                if (!deveMostrar) {
                  return child;
                }

                // ABA-NAO-SOBREPOE-CONTEUDO-CORRIGIDO
                // A aba é flutuante, mas o conteúdo precisa perder altura
                // na parte inferior para não ficar escondido atrás dela.
                final safeBottom = MediaQuery.of(context).padding.bottom;
                final espacoInferiorConteudo =
                    AbaFlutuanteGlobalHost.alturaAba + safeBottom + 22;

                return ColoredBox(
                  color: const Color(0xFFF5F7FA),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        bottom: conteudoEstendido ? 0 : espacoInferiorConteudo,
                        child: child,
                      ),
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: 10 + safeBottom,
                        child: AbaFlutuanteGlobal(
                          key: ValueKey(
                            lojaSelecionada
                                ? 'aba_modo_loja'
                                : 'aba_modo_master',
                          ),
                          modoLojaAtivo: lojaSelecionada,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class AbaFlutuanteGlobal extends StatelessWidget {
  final bool modoLojaAtivo;

  const AbaFlutuanteGlobal({super.key, required this.modoLojaAtivo});

  static Color get vermelho => SessaoLoja.corPrimaria;
  static const Color textoCinza = Color(0xFF667085);

  NavigatorState? get _navigator => AppNavigator.state;

  BuildContext? get _navigatorContext => AppNavigator.context;

  bool get modoLoja {
    // IMPORTANTE:
    // O modo precisa vir do host por parâmetro. Se este widget fosse const
    // e consultasse apenas variáveis estáticas, o Flutter poderia reaproveitar
    // o mesmo widget e a aba continuaria visualmente no modo Master.
    return modoLojaAtivo;
  }

  @override
  Widget build(BuildContext context) {
    final itens = modoLoja ? _itensLoja(context) : _itensMaster(context);

    return Material(
      color: Colors.transparent,
      child: Container(
        height: AbaFlutuanteGlobalHost.alturaAba,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: itens,
        ),
      ),
    );
  }

  List<Widget> _itensMaster(BuildContext context) {
    return [
      _item(
        context: context,
        titulo: 'Painel',
        icone: Icons.dashboard_rounded,
        ativo: true,
        onTap: () => _irParaMaster(const AdminGeralPage()),
      ),
      _item(
        context: context,
        titulo: 'Mercados',
        icone: Icons.store_rounded,
        onTap: () => _abrirPagina(const GerenciarMercadosPage()),
      ),
      _item(
        context: context,
        titulo: 'Cadastrar',
        icone: Icons.add_business_rounded,
        onTap: () => _abrirPagina(const CadastrarMercadoPage()),
      ),
      _item(
        context: context,
        titulo: 'Usuários',
        icone: Icons.people_alt_rounded,
        onTap: () => _abrirPagina(const UsuariosSistemaPage()),
      ),
      _item(
        context: context,
        titulo: 'Mais',
        icone: Icons.more_horiz_rounded,
        onTap: _abrirMaisMaster,
      ),
    ];
  }

  List<Widget> _itensLoja(BuildContext context) {
    return [
      _item(
        context: context,
        titulo: 'Painel',
        icone: Icons.dashboard_rounded,
        ativo: true,
        onTap: () => _abrirPagina(const MenuInicialPage()),
      ),
      _item(
        context: context,
        titulo: 'Pedidos',
        icone: Icons.receipt_long_rounded,
        onTap: () => _abrirPagina(const PedidosMercadoPage()),
      ),
      _item(
        context: context,
        titulo: 'Consulta',
        icone: Icons.search_rounded,
        onTap: () => _abrirPagina(const TelaHome()),
      ),
      _item(
        context: context,
        titulo: 'Estoque',
        icone: Icons.inventory_2_rounded,
        onTap: () => _abrirPagina(const EstoquePage()),
      ),
      _item(
        context: context,
        titulo: 'Mais',
        icone: Icons.more_horiz_rounded,
        onTap: _abrirMaisLoja,
      ),
    ];
  }

  Widget _item({
    required BuildContext context,
    required String titulo,
    required IconData icone,
    required VoidCallback onTap,
    bool ativo = false,
  }) {
    final cor = ativo ? vermelho : textoCinza;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 32,
              decoration: BoxDecoration(
                color: ativo
                    ? vermelho.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icone, color: cor, size: 23),
            ),
            const SizedBox(height: 2),
            Text(
              titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cor,
                fontSize: 11.2,
                fontWeight: ativo ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirPagina(Widget pagina) async {
    final navigator = _navigator;

    if (navigator == null) {
      return;
    }

    await navigator.push(MaterialPageRoute(builder: (_) => pagina));
  }

  void _irParaMaster(Widget pagina) {
    SessaoLoja.limpar();

    final navigator = _navigator;

    if (navigator == null) {
      return;
    }

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => pagina),
      (route) => false,
    );
  }

  Future<void> _abrirMaisMaster() async {
    final modalContext = _navigatorContext;

    if (modalContext == null) {
      return;
    }

    await showModalBottomSheet<void>(
      context: modalContext,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return _PainelMais(
          titulo: 'Mais opções do Master',
          itens: [
            _MaisItem(
              icone: Icons.storefront_rounded,
              cor: vermelho,
              titulo: 'Selecionar loja',
              subtitulo: 'Entrar no painel de uma loja',
              onTap: () {
                _fecharEAbrir(const SelecionarLojaPage());
              },
            ),
            _MaisItem(
              icone: Icons.add_business_rounded,
              cor: Colors.deepOrange,
              titulo: 'Cadastrar mercado',
              subtitulo: 'Criar uma nova loja',
              onTap: () {
                _fecharEAbrir(const CadastrarMercadoPage());
              },
            ),
            _MaisItem(
              icone: Icons.person_add_alt_1_rounded,
              cor: Colors.purple,
              titulo: 'Cadastrar usuário',
              subtitulo: 'Criar usuários do sistema',
              onTap: () {
                _fecharEAbrir(const CadastrarUsuarioPage());
              },
            ),
            _MaisItem(
              icone: Icons.logout_rounded,
              cor: Colors.red,
              titulo: 'Sair',
              subtitulo: 'Encerrar sessão',
              onTap: _sairDoSistema,
            ),
          ],
        );
      },
    );
  }

  Future<void> _abrirMaisLoja() async {
    final modalContext = _navigatorContext;

    if (modalContext == null) {
      return;
    }

    final podeVoltarMaster =
        Supabase.instance.client.auth.currentSession != null &&
        !SessaoLoja.usuarioLogadoNaLoja;

    await showModalBottomSheet<void>(
      context: modalContext,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return _PainelMais(
          titulo: 'Mais opções da loja',
          itens: [
            if (podeVoltarMaster)
              _MaisItem(
                icone: Icons.admin_panel_settings_rounded,
                cor: vermelho,
                titulo: 'Voltar ao Admin Master',
                subtitulo: 'Sair da loja e voltar ao painel central',
                onTap: _voltarAoMaster,
              ),
            _MaisItem(
              icone: Icons.store_rounded,
              cor: vermelho,
              titulo: 'Configurações da loja',
              subtitulo: 'Dados, frete, horários e redes sociais',
              onTap: () {
                _fecharEAbrir(const LojaConfiguracoesPage());
              },
            ),
            _MaisItem(
              icone: Icons.local_offer_rounded,
              cor: Colors.deepOrange,
              titulo: 'Cupons',
              subtitulo: 'Descontos do app',
              onTap: () {
                _fecharEAbrir(const CuponsDescontoPage());
              },
            ),
            _MaisItem(
              icone: Icons.bar_chart_rounded,
              cor: Colors.orange,
              titulo: 'Relatórios',
              subtitulo: 'Consumo interno e informações',
              onTap: () {
                _fecharEAbrir(const RelatoriosPage());
              },
            ),
            _MaisItem(
              icone: Icons.people_alt_rounded,
              cor: Colors.purple,
              titulo: 'Usuários',
              subtitulo: 'Senhas e acessos da loja',
              onTap: () {
                _fecharEAbrir(
                  UsuariosSistemaPage(
                    mercadoId: SessaoLoja.mercadoId,
                    titulo: 'Usuários da loja',
                  ),
                );
              },
            ),
            _MaisItem(
              icone: Icons.logout_rounded,
              cor: Colors.red,
              titulo: 'Sair',
              subtitulo: 'Encerrar sessão',
              onTap: _sairDoSistema,
            ),
          ],
        );
      },
    );
  }

  Future<void> _fecharEAbrir(Widget pagina) async {
    final navigator = _navigator;

    if (navigator == null) {
      return;
    }

    if (navigator.canPop()) {
      navigator.pop();
    }

    await Future<void>.delayed(const Duration(milliseconds: 120));

    await navigator.push(MaterialPageRoute(builder: (_) => pagina));
  }

  Future<void> _voltarAoMaster() async {
    final navigator = _navigator;

    if (navigator == null) {
      return;
    }

    if (navigator.canPop()) {
      navigator.pop();
    }

    await Future<void>.delayed(const Duration(milliseconds: 120));

    _irParaMaster(const AdminGeralPage());
  }

  Future<void> _sairDoSistema() async {
    final navigator = _navigator;

    if (navigator != null && navigator.canPop()) {
      navigator.pop();
    }

    try {
      await SessaoLoja.supabaseLoja?.auth.signOut();
    } catch (_) {}

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    SessaoLoja.limpar();

    if (navigator == null) {
      return;
    }

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginCentralPage()),
      (route) => false,
    );
  }
}

class _PainelMais extends StatelessWidget {
  final String titulo;
  final List<_MaisItem> itens;

  const _PainelMais({required this.titulo, required this.itens});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...itens.map((item) => item),
          ],
        ),
      ),
    );
  }
}

class _MaisItem extends StatelessWidget {
  final IconData icone;
  final Color cor;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  const _MaisItem({
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icone, color: cor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitulo,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.black38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

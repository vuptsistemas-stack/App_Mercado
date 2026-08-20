import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_page.dart';
import 'onboarding_page.dart';
import '../services/sessao_mercado_cliente.dart' as sessao;
import 'main_navigation_page.dart';
import 'completar_cadastro_page.dart';
import 'redefinir_senha_page.dart';
import '../services/app_tema_service.dart';
import '../services/loja_funcionamento_service.dart';

enum _DestinoAuth {
  carregando,
  onboarding,
  login,
  completarCadastro,
  redefinirSenha,
  bloqueado,
  app,
  erro,
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _authSubscription;

  _DestinoAuth destino = _DestinoAuth.carregando;
  String? mensagemErro;
  String? mensagemBloqueio;
  static const String chaveOnboardingVisto = 'app_mercado_onboarding_visto_v1';

  bool verificando = false;
  bool onboardingExibidoNestaSessao = false;
  bool recuperacaoSenhaAtiva = false;

  @override
  void initState() {
    super.initState();

    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      event,
    ) {
      debugPrint(
        'APP_MERCADO AUTH: ${event.event.name} | session=${event.session != null}',
      );

      if (event.event == AuthChangeEvent.passwordRecovery) {
        recuperacaoSenhaAtiva = true;

        if (!mounted) {
          return;
        }

        setState(() {
          destino = _DestinoAuth.redefinirSenha;
          mensagemErro = null;
        });
        return;
      }

      // Durante a recuperação, não deixa eventos como signedIn/initialSession
      // enviarem o usuário para o app antes de definir a nova senha.
      if (recuperacaoSenhaAtiva) {
        return;
      }

      // Evita ficar reconstruindo a tela infinitamente durante refresh de token.
      if (event.event == AuthChangeEvent.tokenRefreshed) {
        return;
      }

      verificarSessao();
    });

    verificarSessao();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  bool erroSessaoExpirada(Object erro) {
    final texto = erro.toString().toLowerCase();

    return texto.contains('jwt expired') ||
        texto.contains('pgrst303') ||
        texto.contains('unauthorized') ||
        texto.contains('401');
  }

  Future<bool> tentarRenovarSessao() async {
    try {
      final resposta = await Supabase.instance.client.auth.refreshSession();
      return resposta.session != null ||
          Supabase.instance.client.auth.currentSession != null;
    } catch (e) {
      debugPrint('APP_MERCADO AUTH REFRESH FALHOU: $e');
      return false;
    }
  }

  Future<void> renovarSessaoEVerificar() async {
    if (verificando) {
      return;
    }

    setState(() {
      destino = _DestinoAuth.carregando;
      mensagemErro = null;
    });

    try {
      final renovou = await tentarRenovarSessao();

      if (!renovou) {
        throw Exception('Nao foi possivel renovar a sessao.');
      }

      if (!mounted) {
        return;
      }

      await verificarSessao();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        destino = _DestinoAuth.erro;
        mensagemErro =
            'Nao conseguimos renovar sua sessao agora. Verifique sua conexao e tente novamente.';
      });
    }
  }

  Future<void> verificarSessao() async {
    if (recuperacaoSenhaAtiva || verificando) {
      return;
    }

    verificando = true;

    if (mounted) {
      setState(() {
        destino = _DestinoAuth.carregando;
        mensagemErro = null;
      });
    }

    try {
      final client = Supabase.instance.client;
      final session = client.auth.currentSession;
      final user = client.auth.currentUser;

      debugPrint(
        'APP_MERCADO AUTH CHECK: session=${session != null} user=${user?.id}',
      );

      if (session == null || user == null) {
        LojaFuncionamentoService.limparCategoriasBloqueadasCliente();

        if (!mounted) return;

        final mostrarOnboarding = await deveExibirOnboarding();

        setState(() {
          destino = mostrarOnboarding
              ? _DestinoAuth.onboarding
              : _DestinoAuth.login;
        });
        return;
      }

      final response = await client
          .from('clientes')
          .select(
            'id, telefone, endereco, numero, bairro, cidade, bloqueado, bloqueio_motivo, categorias_bloqueadas',
          )
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .eq('user_id', user.id)
          .maybeSingle()
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () {
              throw TimeoutException(
                'Tempo excedido ao consultar cadastro do cliente.',
              );
            },
          );

      debugPrint('APP_MERCADO AUTH CLIENTE: $response');

      if (!mounted) return;

      if (response == null) {
        LojaFuncionamentoService.limparCategoriasBloqueadasCliente();
        setState(() {
          destino = _DestinoAuth.completarCadastro;
        });
        return;
      }

      final clienteBloqueado =
          response['bloqueado'] == true ||
          response['bloqueado']?.toString().toLowerCase() == 'true';

      LojaFuncionamentoService.configurarCategoriasBloqueadasCliente(
        response['categorias_bloqueadas'],
      );

      if (clienteBloqueado) {
        final motivo = response['bloqueio_motivo']?.toString().trim() ?? '';

        setState(() {
          destino = _DestinoAuth.bloqueado;
          mensagemBloqueio = motivo;
        });
        return;
      }

      final telefone = response['telefone']?.toString().trim() ?? '';
      final endereco = response['endereco']?.toString().trim() ?? '';
      final numero = response['numero']?.toString().trim() ?? '';
      final bairro = response['bairro']?.toString().trim() ?? '';
      final cidade = response['cidade']?.toString().trim() ?? '';

      final cadastroCompleto =
          telefone.isNotEmpty &&
          endereco.isNotEmpty &&
          numero.isNotEmpty &&
          bairro.isNotEmpty &&
          cidade.isNotEmpty;

      setState(() {
        destino = cadastroCompleto
            ? _DestinoAuth.app
            : _DestinoAuth.completarCadastro;
      });
    } on TimeoutException catch (e) {
      debugPrint('APP_MERCADO AUTH TIMEOUT: ${e.message}');

      if (!mounted) return;

      setState(() {
        destino = _DestinoAuth.erro;
        mensagemErro = e.message;
      });
    } on AuthException catch (e) {
      debugPrint('APP_MERCADO AUTH ERRO AUTH: ${e.message}');

      if (erroSessaoExpirada(e)) {
        final renovou = await tentarRenovarSessao();

        if (renovou) {
          verificando = false;
          await verificarSessao();
          return;
        }

        if (!mounted) return;

        setState(() {
          destino = _DestinoAuth.erro;
          mensagemErro =
              'Nao conseguimos renovar sua sessao agora. Verifique sua conexao e tente novamente.';
        });
        return;
      }

      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}

      if (!mounted) return;

      setState(() {
        destino = _DestinoAuth.login;
        mensagemErro = e.message;
      });
    } catch (e) {
      debugPrint('APP_MERCADO AUTH ERRO: $e');

      if (!mounted) return;

      if (erroSessaoExpirada(e)) {
        final renovou = await tentarRenovarSessao();

        if (renovou) {
          verificando = false;
          await verificarSessao();
          return;
        }

        setState(() {
          destino = _DestinoAuth.erro;
          mensagemErro =
              'Nao conseguimos renovar sua sessao agora. Verifique sua conexao e tente novamente.';
        });
        return;
      }

      setState(() {
        destino = _DestinoAuth.erro;
        mensagemErro =
            'Não conseguimos validar seu cadastro agora. Verifique sua conexão e tente novamente.';
      });
    } finally {
      verificando = false;
    }
  }

  Future<bool> deveExibirOnboarding() async {
    if (!sessao.SessaoMercadoCliente.exibirOnboarding ||
        onboardingExibidoNestaSessao ||
        sessao.SessaoMercadoCliente.onboardingSlides.isEmpty) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final jaVisto = prefs.getBool(chaveOnboardingVisto) ?? false;

    return !jaVisto;
  }

  Future<void> concluirOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(chaveOnboardingVisto, true);

    if (!mounted) return;

    setState(() {
      onboardingExibidoNestaSessao = true;
      destino = _DestinoAuth.login;
    });
  }

  Future<void> concluirRedefinicaoSenha() async {
    recuperacaoSenhaAtiva = false;
    LojaFuncionamentoService.limparCategoriasBloqueadasCliente();

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      debugPrint('APP_MERCADO RESET PASSWORD SIGNOUT: $e');
    }

    if (!mounted) {
      return;
    }

    setState(() {
      destino = _DestinoAuth.login;
      mensagemErro = null;
    });
  }

  Future<void> sairELimparSessao() async {
    LojaFuncionamentoService.limparCategoriasBloqueadasCliente();

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      destino = _DestinoAuth.login;
      mensagemErro = null;
    });
  }

  Widget telaErro() {
    final sessaoExpirada = mensagemErro == 'sessao_expirada';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: AppTemaService.primaria.withValues(alpha: 0.16),
                  width: 1.6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTemaService.primaria.withValues(alpha: 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE30613).withOpacity(0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      sessaoExpirada
                          ? Icons.lock_clock_rounded
                          : Icons.wifi_off_rounded,
                      color: const Color(0xFFE30613),
                      size: 42,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    sessaoExpirada
                        ? 'Sua sessão expirou'
                        : 'Não foi possível validar seu cadastro',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF1F2937),
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      height: 1.12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    sessaoExpirada
                        ? 'Por segurança, entre novamente para continuar usando o aplicativo.'
                        : (mensagemErro ??
                              'Verifique sua conexão e tente novamente em alguns instantes.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: sessaoExpirada
                          ? sairELimparSessao
                          : renovarSessaoEVerificar,
                      icon: Icon(
                        sessaoExpirada
                            ? Icons.login_rounded
                            : Icons.refresh_rounded,
                      ),
                      label: Text(
                        sessaoExpirada
                            ? 'Entrar novamente'
                            : 'Tentar novamente',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE30613),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (!sessaoExpirada)
                    TextButton(
                      onPressed: sairELimparSessao,
                      child: const Text(
                        'Sair e entrar novamente',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget telaClienteBloqueado() {
    final motivo = mensagemBloqueio?.trim() ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: AppTemaService.primaria.withValues(alpha: 0.18),
                  width: 1.6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTemaService.primaria.withValues(alpha: 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      color: AppTemaService.primaria.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.block_rounded,
                      color: AppTemaService.primaria,
                      size: 42,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Compras temporariamente bloqueadas',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF1F2937),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    motivo.isEmpty
                        ? 'Entre em contato com a loja para consultar a situação do seu cadastro.'
                        : motivo,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: sairELimparSessao,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text(
                        'Sair da conta',
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
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (destino) {
      case _DestinoAuth.onboarding:
        return OnboardingPage(onConcluir: concluirOnboarding);

      case _DestinoAuth.login:
        return const LoginPage();

      case _DestinoAuth.completarCadastro:
        return const CompletarCadastroPage();

      case _DestinoAuth.redefinirSenha:
        return RedefinirSenhaPage(onConcluido: concluirRedefinicaoSenha);

      case _DestinoAuth.bloqueado:
        return telaClienteBloqueado();

      case _DestinoAuth.app:
        return const MainNavigationPage();

      case _DestinoAuth.erro:
        return telaErro();

      case _DestinoAuth.carregando:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
  }
}

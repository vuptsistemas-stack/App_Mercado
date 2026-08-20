import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/sessao_mercado_cliente.dart' as sessao;
import 'cadastro_cliente_page.dart';
import 'recuperar_senha_page.dart';
import '../services/app_tema_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  static const String appPackage = String.fromEnvironment(
    'APP_PACKAGE',
    defaultValue: 'br.com.apppreco.appmercado',
  );

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final senhaController = TextEditingController();

  bool carregandoGoogle = false;
  bool carregandoApple = false;
  bool carregandoEmail = false;
  bool senhaVisivel = false;

  bool get mostrarLoginApple =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  String get redirectLogin {
    final package = LoginPage.appPackage.trim();

    if (package.isEmpty) {
      return 'br.com.apppreco.appmercado://login-callback';
    }

    return '$package://login-callback';
  }

  @override
  void dispose() {
    emailController.dispose();
    senhaController.dispose();
    super.dispose();
  }

  Future<void> loginGoogle() async {
    if (carregandoGoogle || carregandoApple || carregandoEmail) return;

    setState(() {
      carregandoGoogle = true;
    });

    try {
      final redirectTo = redirectLogin;

      debugPrint('APP_MERCADO LOGIN REDIRECT: $redirectTo');

      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
      );
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem('Erro ao iniciar login: $e', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          carregandoGoogle = false;
        });
      }
    }
  }

  Future<void> loginApple() async {
    if (!mostrarLoginApple ||
        carregandoGoogle ||
        carregandoApple ||
        carregandoEmail) {
      return;
    }

    setState(() {
      carregandoApple = true;
    });

    try {
      final auth = Supabase.instance.client.auth;
      final rawNonce = auth.generateRawNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credencial = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credencial.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthException(
          'A Apple não retornou uma credencial válida.',
        );
      }

      await auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      final nomeCompleto = [credencial.givenName, credencial.familyName]
          .whereType<String>()
          .map((parte) => parte.trim())
          .where((parte) {
            return parte.isNotEmpty;
          })
          .join(' ');

      if (nomeCompleto.isNotEmpty) {
        await auth.updateUser(
          UserAttributes(
            data: {
              'full_name': nomeCompleto,
              'given_name': credencial.givenName,
              'family_name': credencial.familyName,
            },
          ),
        );
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      if (!mounted || e.code == AuthorizationErrorCode.canceled) return;
      mostrarMensagem('Não foi possível entrar com a Apple.', erro: true);
    } on AuthException catch (e) {
      if (!mounted) return;
      mostrarMensagem(e.message, erro: true);
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem('Erro ao entrar com a Apple: $e', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          carregandoApple = false;
        });
      }
    }
  }

  Future<void> loginEmail() async {
    if (carregandoGoogle || carregandoApple || carregandoEmail) return;

    final email = emailController.text.trim();
    final senha = senhaController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      mostrarMensagem('Informe um e-mail válido.', erro: true);
      return;
    }

    if (senha.length < 6) {
      mostrarMensagem(
        'Informe a senha com pelo menos 6 caracteres.',
        erro: true,
      );
      return;
    }

    setState(() {
      carregandoEmail = true;
    });

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: senha,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      mostrarMensagem(e.message, erro: true);
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem('Erro ao entrar: $e', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          carregandoEmail = false;
        });
      }
    }
  }

  Future<void> criarContaEmail() async {
    if (carregandoGoogle || carregandoApple || carregandoEmail) return;

    final email = emailController.text.trim();
    final senha = senhaController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      mostrarMensagem('Informe seu e-mail para criar a conta.', erro: true);
      return;
    }

    if (senha.length < 6) {
      mostrarMensagem(
        'A senha precisa ter pelo menos 6 caracteres.',
        erro: true,
      );
      return;
    }

    setState(() {
      carregandoEmail = true;
    });

    try {
      await Supabase.instance.client.auth.signUp(email: email, password: senha);

      if (!mounted) return;
      mostrarMensagem(
        'Conta criada. Se o Supabase pedir confirmação, verifique seu e-mail.',
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      mostrarMensagem(e.message, erro: true);
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem('Erro ao criar conta: $e', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          carregandoEmail = false;
        });
      }
    }
  }

  Future<void> abrirRecuperacaoSenha() async {
    if (carregandoGoogle || carregandoApple || carregandoEmail) {
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecuperarSenhaPage(
          emailInicial: emailController.text.trim(),
          appPackage: LoginPage.appPackage,
        ),
      ),
    );
  }

  Future<void> abrirCadastroCliente() async {
    if (carregandoGoogle || carregandoApple || carregandoEmail) {
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CadastroClientePage()),
    );
  }

  void mostrarMensagem(String texto, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: erro ? Colors.red : const Color(0xFF0F9D58),
      ),
    );
  }

  Color corHex(String valor, Color padrao) {
    var texto = valor.trim();

    if (texto.isEmpty) {
      return padrao;
    }

    if (texto.startsWith('#')) {
      texto = texto.substring(1);
    }

    if (texto.length == 6) {
      texto = 'FF$texto';
    }

    final numero = int.tryParse(texto, radix: 16);

    if (numero == null) {
      return padrao;
    }

    return Color(numero);
  }

  @override
  Widget build(BuildContext context) {
    final corPrimaria = corHex(
      sessao.SessaoMercadoCliente.clienteCorPrimaria,
      const Color(0xFFE30613),
    );
    final corSecundaria = corHex(
      sessao.SessaoMercadoCliente.clienteCorSecundaria,
      const Color(0xFFC90010),
    );
    final corFundo = corHex(
      sessao.SessaoMercadoCliente.clienteCorFundo,
      const Color(0xFFFFF7F7),
    );

    final nomeMercado =
        sessao.SessaoMercadoCliente.clienteLoginTitulo.trim().isEmpty
        ? (sessao.SessaoMercadoCliente.mercadoNome.trim().isEmpty
              ? 'Mercado Online'
              : sessao.SessaoMercadoCliente.mercadoNome.trim())
        : sessao.SessaoMercadoCliente.clienteLoginTitulo.trim();

    final subtitulo =
        sessao.SessaoMercadoCliente.clienteLoginSubtitulo.trim().isEmpty
        ? 'Compre e receba em casa'
        : sessao.SessaoMercadoCliente.clienteLoginSubtitulo.trim();

    final imagemUrl = sessao.SessaoMercadoCliente.clienteLoginImagemUrl.trim();
    final logoMercadoUrl = sessao.SessaoMercadoCliente.logoUrl.trim();

    return Scaffold(
      backgroundColor: corFundo,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final largura = constraints.maxWidth;
            final altura = constraints.maxHeight;

            final escalaLargura = largura / 390;
            final escalaAltura = altura / 820;
            // Pequena redução para evitar overflow em telas com barra do sistema
            // diferente entre aparelhos/emuladores.
            final escalaBase = escalaLargura < escalaAltura
                ? escalaLargura
                : escalaAltura;

            final escala = (escalaBase * 0.965).clamp(0.78, 1.04);

            final alturaHero = (altura * 0.30).clamp(184.0, 254.0);
            final larguraConteudo = largura.clamp(320.0, 430.0);

            return Center(
              child: SizedBox(
                width: largura,
                height: altura,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _FundoLoginImagem(
                        imagemUrl: imagemUrl,
                        corPrimaria: corPrimaria,
                        corSecundaria: corSecundaria,
                        corFundo: corFundo,
                        alturaHero: alturaHero,
                      ),
                    ),
                    Positioned.fill(
                      child: Center(
                        child: Transform.scale(
                          scale: escala,
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: larguraConteudo,
                            height: altura / escala,
                            child: Column(
                              children: [
                                SizedBox(height: alturaHero - 76),
                                _CardMarcaLogin(
                                  logoUrl: logoMercadoUrl,
                                  nomeMercado: nomeMercado,
                                  subtitulo: subtitulo,
                                  corPrimaria: corPrimaria,
                                ),
                                const SizedBox(height: 14),
                                _FormularioLoginSemRolagem(
                                  corPrimaria: corPrimaria,
                                  carregandoGoogle: carregandoGoogle,
                                  carregandoApple: carregandoApple,
                                  carregandoEmail: carregandoEmail,
                                  mostrarApple: mostrarLoginApple,
                                  senhaVisivel: senhaVisivel,
                                  emailController: emailController,
                                  senhaController: senhaController,
                                  onGoogle: loginGoogle,
                                  onApple: loginApple,
                                  onEntrar: loginEmail,
                                  onCriarConta: abrirCadastroCliente,
                                  onResetarSenha: abrirRecuperacaoSenha,
                                  onToggleSenha: () {
                                    setState(() {
                                      senhaVisivel = !senhaVisivel;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FundoLoginImagem extends StatelessWidget {
  final String imagemUrl;
  final Color corPrimaria;
  final Color corSecundaria;
  final Color corFundo;
  final double alturaHero;

  const _FundoLoginImagem({
    required this.imagemUrl,
    required this.corPrimaria,
    required this.corSecundaria,
    required this.corFundo,
    required this.alturaHero,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: Container(color: corFundo)),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: alturaHero,
          child: _HeroMercadoImagem(
            imagemUrl: imagemUrl,
            corPrimaria: corPrimaria,
            corSecundaria: corSecundaria,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: alturaHero - 42,
          child: Container(
            height: 88,
            decoration: BoxDecoration(
              color: corFundo,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(42),
              ),
            ),
          ),
        ),
        Positioned(
          left: -70,
          bottom: -34,
          child: Container(
            width: 190,
            height: 104,
            decoration: BoxDecoration(
              color: corPrimaria.withOpacity(0.08),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(120),
              ),
            ),
          ),
        ),
        Positioned(
          right: -58,
          bottom: -24,
          child: Container(
            width: 178,
            height: 86,
            decoration: BoxDecoration(
              color: corPrimaria.withOpacity(0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(120),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroMercadoImagem extends StatelessWidget {
  final String imagemUrl;
  final Color corPrimaria;
  final Color corSecundaria;

  const _HeroMercadoImagem({
    required this.imagemUrl,
    required this.corPrimaria,
    required this.corSecundaria,
  });

  @override
  Widget build(BuildContext context) {
    if (imagemUrl.isNotEmpty) {
      return Image.network(
        imagemUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }

    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [corPrimaria, corSecundaria],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: CustomPaint(
        painter: _DesenhosMercadoPainter(cor: Colors.white.withOpacity(0.16)),
      ),
    );
  }
}

class _CardMarcaLogin extends StatelessWidget {
  final String logoUrl;
  final String nomeMercado;
  final String subtitulo;
  final Color corPrimaria;

  const _CardMarcaLogin({
    required this.logoUrl,
    required this.nomeMercado,
    required this.subtitulo,
    required this.corPrimaria,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 288,
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
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
          SizedBox(
            height: 70,
            child: logoUrl.trim().isEmpty
                ? Center(
                    child: Text(
                      nomeMercado,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF211A1D),
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                  )
                : Image.network(
                    logoUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Center(
                      child: Text(
                        nomeMercado,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF211A1D),
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 7),
          Text(
            subtitulo,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: corPrimaria,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 1.2,
                color: corPrimaria.withOpacity(0.32),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.favorite, color: corPrimaria, size: 18),
              ),
              Container(
                width: 48,
                height: 1.2,
                color: corPrimaria.withOpacity(0.32),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FormularioLoginSemRolagem extends StatelessWidget {
  final Color corPrimaria;
  final bool carregandoGoogle;
  final bool carregandoApple;
  final bool carregandoEmail;
  final bool mostrarApple;
  final bool senhaVisivel;
  final TextEditingController emailController;
  final TextEditingController senhaController;
  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final VoidCallback onEntrar;
  final VoidCallback onCriarConta;
  final VoidCallback onResetarSenha;
  final VoidCallback onToggleSenha;

  const _FormularioLoginSemRolagem({
    required this.corPrimaria,
    required this.carregandoGoogle,
    required this.carregandoApple,
    required this.carregandoEmail,
    required this.mostrarApple,
    required this.senhaVisivel,
    required this.emailController,
    required this.senhaController,
    required this.onGoogle,
    required this.onApple,
    required this.onEntrar,
    required this.onCriarConta,
    required this.onResetarSenha,
    required this.onToggleSenha,
  });

  @override
  Widget build(BuildContext context) {
    final bloqueado = carregandoGoogle || carregandoApple || carregandoEmail;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _LabelLogin('E-mail'),
          const SizedBox(height: 5),
          _CampoLogin(
            controller: emailController,
            corPrimaria: corPrimaria,
            hint: 'Digite seu e-mail',
            icon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            altura: 52,
          ),
          const SizedBox(height: 10),
          const _LabelLogin('Senha'),
          const SizedBox(height: 5),
          _CampoLogin(
            controller: senhaController,
            corPrimaria: corPrimaria,
            hint: 'Digite sua senha',
            icon: Icons.lock_outline,
            obscureText: !senhaVisivel,
            altura: 52,
            suffixIcon: IconButton(
              onPressed: onToggleSenha,
              icon: Icon(
                senhaVisivel
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: Colors.black45,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: bloqueado ? null : onResetarSenha,
              style: TextButton.styleFrom(
                foregroundColor: corPrimaria,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Esqueci minha senha',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
              ),
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 51,
            child: ElevatedButton(
              onPressed: bloqueado ? null : onEntrar,
              style: ElevatedButton.styleFrom(
                backgroundColor: corPrimaria,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: carregandoEmail
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Entrar',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Divider(color: Colors.black.withOpacity(0.14))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  'ou continue com',
                  style: TextStyle(
                    color: Colors.black45,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(child: Divider(color: Colors.black.withOpacity(0.14))),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 49,
            child: OutlinedButton(
              onPressed: bloqueado ? null : onGoogle,
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1F2937),
                side: BorderSide(color: Colors.black.withOpacity(0.08)),
                elevation: 4,
                shadowColor: Colors.black.withOpacity(0.14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: carregandoGoogle
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: corPrimaria,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        _GoogleG(),
                        SizedBox(width: 14),
                        Text(
                          'Entrar com Google',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          if (mostrarApple) ...[
            const SizedBox(height: 9),
            SignInWithAppleButton(
              onPressed: bloqueado ? null : onApple,
              text: carregandoApple
                  ? 'Conectando com a Apple...'
                  : 'Entrar com Apple',
              style: SignInWithAppleButtonStyle.black,
              height: 49,
              borderRadius: const BorderRadius.all(Radius.circular(15)),
            ),
          ],
          const SizedBox(height: 10),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              children: [
                const Text(
                  'Não tem conta? ',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                GestureDetector(
                  onTap: bloqueado ? null : onCriarConta,
                  child: Text(
                    'Cadastre-se',
                    style: TextStyle(
                      color: corPrimaria,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LabelLogin extends StatelessWidget {
  final String texto;

  const _LabelLogin(this.texto);

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        color: Color(0xFF374151),
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _DesenhosMercadoPainter extends CustomPainter {
  final Color cor;

  _DesenhosMercadoPainter({required this.cor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = cor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void garrafa(double x, double y) {
      final path = Path()
        ..moveTo(x + 8, y)
        ..lineTo(x + 18, y)
        ..lineTo(x + 18, y + 9)
        ..quadraticBezierTo(x + 26, y + 15, x + 26, y + 24)
        ..lineTo(x + 26, y + 46)
        ..quadraticBezierTo(x + 26, y + 52, x + 20, y + 52)
        ..lineTo(x + 6, y + 52)
        ..quadraticBezierTo(x, y + 52, x, y + 46)
        ..lineTo(x, y + 24)
        ..quadraticBezierTo(x, y + 15, x + 8, y + 9)
        ..close();
      canvas.drawPath(path, paint);
    }

    void caixa(double x, double y) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, 42, 34),
          const Radius.circular(7),
        ),
        paint,
      );
      canvas.drawLine(Offset(x + 9, y + 12), Offset(x + 33, y + 12), paint);
      canvas.drawLine(Offset(x + 9, y + 23), Offset(x + 33, y + 23), paint);
    }

    void cesta(double x, double y) {
      final path = Path()
        ..moveTo(x, y + 11)
        ..lineTo(x + 44, y + 11)
        ..lineTo(x + 35, y + 38)
        ..lineTo(x + 9, y + 38)
        ..close();
      canvas.drawPath(path, paint);
      canvas.drawArc(
        Rect.fromLTWH(x + 10, y, 24, 20),
        3.14,
        3.14,
        false,
        paint,
      );
    }

    for (var linha = 0; linha < 3; linha++) {
      final y = 24.0 + (linha * 70);
      garrafa(34, y);
      caixa(112, y + 8);
      caixa(198, y + 6);
      cesta(290, y + 10);
    }
  }

  @override
  bool shouldRepaint(covariant _DesenhosMercadoPainter oldDelegate) {
    return oldDelegate.cor != cor;
  }
}

class _CampoLogin extends StatelessWidget {
  final TextEditingController controller;
  final Color corPrimaria;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final double altura;

  const _CampoLogin({
    required this.controller,
    required this.corPrimaria,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.altura = 56,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: altura,
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            color: Color(0xFFB3B6BD),
            fontWeight: FontWeight.w600,
          ),
          prefixIcon: Icon(icon, color: corPrimaria),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.black.withOpacity(0.10)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: corPrimaria, width: 1.4),
          ),
        ),
      ),
    );
  }
}

class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 24,
      height: 24,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.17;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    Paint paint(Color color) {
      return Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.square;
    }

    // Logo Google em quatro cores, desenhado sem depender de imagem/asset.
    canvas.drawArc(rect, -0.05, 1.25, false, paint(const Color(0xFF4285F4)));
    canvas.drawArc(rect, 1.20, 1.55, false, paint(const Color(0xFF34A853)));
    canvas.drawArc(rect, 2.75, 1.05, false, paint(const Color(0xFFFBBC05)));
    canvas.drawArc(rect, 3.80, 1.55, false, paint(const Color(0xFFEA4335)));

    final blue = paint(const Color(0xFF4285F4))..strokeCap = StrokeCap.square;

    final y = size.height * 0.52;
    canvas.drawLine(
      Offset(size.width * 0.52, y),
      Offset(size.width * 0.91, y),
      blue,
    );

    canvas.drawLine(
      Offset(size.width * 0.91, y),
      Offset(size.width * 0.91, size.height * 0.68),
      blue,
    );
  }

  @override
  bool shouldRepaint(covariant _GoogleLogoPainter oldDelegate) => false;
}

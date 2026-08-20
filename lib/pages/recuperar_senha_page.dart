import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/sessao_mercado_cliente.dart' as sessao;

class RecuperarSenhaPage extends StatefulWidget {
  final String emailInicial;
  final String appPackage;

  const RecuperarSenhaPage({
    super.key,
    this.emailInicial = '',
    required this.appPackage,
  });

  @override
  State<RecuperarSenhaPage> createState() => _RecuperarSenhaPageState();
}

class _RecuperarSenhaPageState extends State<RecuperarSenhaPage> {
  late final TextEditingController emailController;

  bool enviando = false;

  @override
  void initState() {
    super.initState();
    emailController = TextEditingController(text: widget.emailInicial.trim());
  }

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  String get redirectRecuperacaoSenha {
    final package = widget.appPackage.trim();

    if (package.isEmpty) {
      return 'br.com.apppreco.appmercado://reset-password';
    }

    return '$package://reset-password';
  }

  Future<void> enviarLink() async {
    if (enviando) {
      return;
    }

    final email = emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      mostrarMensagem('Informe um e-mail válido.', erro: true);
      return;
    }

    setState(() {
      enviando = true;
    });

    try {
      debugPrint(
        'APP_MERCADO RESET PASSWORD REDIRECT: $redirectRecuperacaoSenha',
      );

      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: redirectRecuperacaoSenha,
      );

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            icon: const Icon(
              Icons.mark_email_read_outlined,
              color: Color(0xFF0F9D58),
              size: 52,
            ),
            title: const Text(
              'Verifique seu e-mail',
              textAlign: TextAlign.center,
            ),
            content: Text(
              'Enviamos um link de recuperação para:\n\n$email',
              textAlign: TextAlign.center,
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.pop(context);
                },
                child: const Text('Voltar para o login'),
              ),
            ],
          );
        },
      );
    } on AuthException catch (e) {
      if (!mounted) {
        return;
      }

      mostrarMensagem(e.message, erro: true);
    } catch (e) {
      if (!mounted) {
        return;
      }

      mostrarMensagem(
        'Não foi possível enviar o link de recuperação: $e',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          enviando = false;
        });
      }
    }
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

    final corFundo = corHex(
      sessao.SessaoMercadoCliente.clienteCorFundo,
      const Color(0xFFFFF7F7),
    );

    return Scaffold(
      backgroundColor: corFundo,
      appBar: AppBar(
        backgroundColor: corFundo,
        foregroundColor: const Color(0xFF1F2937),
        elevation: 0,
        title: const Text(
          'Recuperar senha',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: corPrimaria.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_reset_rounded,
                  color: corPrimaria,
                  size: 49,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Esqueceu sua senha?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF1F2937),
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Digite o e-mail cadastrado na sua conta. '
                'Enviaremos um link para você criar uma nova senha.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 15.5,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.07),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'E-mail',
                      style: TextStyle(
                        color: Color(0xFF374151),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: emailController,
                      enabled: !enviando,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      onSubmitted: (_) => enviarLink(),
                      decoration: InputDecoration(
                        hintText: 'Digite seu e-mail',
                        prefixIcon: Icon(
                          Icons.mail_outline,
                          color: corPrimaria,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide(
                            color: Colors.black.withOpacity(0.10),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide(
                            color: corPrimaria,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: enviando ? null : enviarLink,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: corPrimaria,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child: enviando
                            ? const SizedBox(
                                width: 23,
                                height: 23,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                'Enviar link de recuperação',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: enviando ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text(
                  'Voltar para o login',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                style: TextButton.styleFrom(foregroundColor: corPrimaria),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

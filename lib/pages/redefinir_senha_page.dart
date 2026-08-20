import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/sessao_mercado_cliente.dart' as sessao;

class RedefinirSenhaPage extends StatefulWidget {
  final Future<void> Function() onConcluido;

  const RedefinirSenhaPage({
    super.key,
    required this.onConcluido,
  });

  @override
  State<RedefinirSenhaPage> createState() => _RedefinirSenhaPageState();
}

class _RedefinirSenhaPageState extends State<RedefinirSenhaPage> {
  final senhaController = TextEditingController();
  final confirmarSenhaController = TextEditingController();

  bool salvando = false;
  bool ocultarSenha = true;
  bool ocultarConfirmacao = true;

  @override
  void dispose() {
    senhaController.dispose();
    confirmarSenhaController.dispose();
    super.dispose();
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
    return numero == null ? padrao : Color(numero);
  }

  Future<void> salvarNovaSenha() async {
    if (salvando) {
      return;
    }

    final senha = senhaController.text;
    final confirmacao = confirmarSenhaController.text;

    if (senha.length < 6) {
      mostrarMensagem(
        'A nova senha precisa ter pelo menos 6 caracteres.',
        erro: true,
      );
      return;
    }

    if (senha != confirmacao) {
      mostrarMensagem('As senhas não são iguais.', erro: true);
      return;
    }

    final session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      mostrarMensagem(
        'O link de recuperação expirou ou já foi utilizado. Solicite um novo link.',
        erro: true,
      );
      return;
    }

    setState(() {
      salvando = true;
    });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: senha),
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
              Icons.check_circle_rounded,
              color: Color(0xFF0F9D58),
              size: 54,
            ),
            title: const Text(
              'Senha alterada',
              textAlign: TextAlign.center,
            ),
            content: const Text(
              'Sua nova senha foi salva. Entre novamente para continuar.',
              textAlign: TextAlign.center,
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Ir para o login'),
              ),
            ],
          );
        },
      );

      if (!mounted) {
        return;
      }

      await widget.onConcluido();
    } on AuthException catch (e) {
      if (!mounted) {
        return;
      }

      mostrarMensagem(
        traduzirErroAuth(e.message),
        erro: true,
      );
    } catch (e, stack) {
      debugPrint('APP_MERCADO RESET SENHA ERRO: $e');
      debugPrint(stack.toString());

      if (!mounted) {
        return;
      }

      mostrarMensagem(
        'Não foi possível alterar a senha. Verifique sua conexão e tente novamente.',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          salvando = false;
        });
      }
    }
  }

  String traduzirErroAuth(String mensagemOriginal) {
    final mensagem = mensagemOriginal.trim().toLowerCase();

    if (mensagem.contains('different from the old password') ||
        mensagem.contains('different from the previous password') ||
        mensagem.contains('same password') ||
        mensagem.contains('password is the same')) {
      return 'A nova senha deve ser diferente da senha anterior.';
    }

    if (mensagem.contains('password should be at least') ||
        mensagem.contains('password must be at least') ||
        mensagem.contains('password is too short')) {
      return 'A nova senha precisa ter pelo menos 6 caracteres.';
    }

    if (mensagem.contains('password is too weak') ||
        mensagem.contains('weak password')) {
      return 'A senha informada é muito fraca. Use uma combinação mais segura de letras, números e símbolos.';
    }

    if (mensagem.contains('auth session missing') ||
        mensagem.contains('session not found') ||
        mensagem.contains('invalid session')) {
      return 'A sessão de recuperação não está mais válida. Solicite um novo link de recuperação.';
    }

    if (mensagem.contains('token has expired') ||
        mensagem.contains('token is expired') ||
        mensagem.contains('invalid token') ||
        mensagem.contains('otp expired') ||
        mensagem.contains('expired')) {
      return 'O link de recuperação expirou ou já foi utilizado. Solicite um novo link.';
    }

    if (mensagem.contains('rate limit') ||
        mensagem.contains('too many requests')) {
      return 'Foram feitas muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.';
    }

    if (mensagem.contains('network') ||
        mensagem.contains('socket') ||
        mensagem.contains('connection')) {
      return 'Não foi possível conectar ao servidor. Verifique sua internet e tente novamente.';
    }

    return 'Não foi possível alterar a senha. Tente novamente ou solicite um novo link de recuperação.';
  }

  void mostrarMensagem(String texto, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: erro ? Colors.red : const Color(0xFF0F9D58),
      ),
    );
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

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: corFundo,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 440),
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: corPrimaria.withOpacity(0.10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.password_rounded,
                          color: corPrimaria,
                          size: 46,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Crie uma nova senha',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Digite e confirme a nova senha da sua conta.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 15,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: senhaController,
                      enabled: !salvando,
                      obscureText: ocultarSenha,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Nova senha',
                        prefixIcon: Icon(
                          Icons.lock_outline_rounded,
                          color: corPrimaria,
                        ),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              ocultarSenha = !ocultarSenha;
                            });
                          },
                          icon: Icon(
                            ocultarSenha
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: confirmarSenhaController,
                      enabled: !salvando,
                      obscureText: ocultarConfirmacao,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => salvarNovaSenha(),
                      decoration: InputDecoration(
                        labelText: 'Confirmar nova senha',
                        prefixIcon: Icon(
                          Icons.lock_reset_rounded,
                          color: corPrimaria,
                        ),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              ocultarConfirmacao = !ocultarConfirmacao;
                            });
                          },
                          icon: Icon(
                            ocultarConfirmacao
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: salvando ? null : salvarNovaSenha,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: corPrimaria,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: salvando
                            ? const SizedBox(
                                width: 23,
                                height: 23,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                'Salvar nova senha',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Por segurança, ao concluir você será direcionado novamente para o login.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

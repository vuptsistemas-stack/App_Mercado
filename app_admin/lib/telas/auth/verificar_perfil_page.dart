import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/central_service.dart';
import '../../services/sessao_loja.dart';
import '../master/admin_geral_page.dart';
import '../selecionar_loja_page.dart';
import 'login_central_page.dart';

class VerificarPerfilPage extends StatefulWidget {
  const VerificarPerfilPage({super.key});

  @override
  State<VerificarPerfilPage> createState() => _VerificarPerfilPageState();
}

class _VerificarPerfilPageState extends State<VerificarPerfilPage> {
  final service = CentralService();

  @override
  void initState() {
    super.initState();

    SessaoLoja.limpar();

    verificarPerfil();
  }

  Future<void> verificarPerfil() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;

      if (user == null) {
        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginCentralPage()),
        );
        return;
      }

      final master = await service.usuarioEhMaster();

      if (!mounted) return;

      if (master) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminGeralPage()),
        );
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              const SelecionarLojaPage(abrirAutomaticamenteSeUmaLoja: true),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao verificar perfil: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginCentralPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF5F7FA),
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

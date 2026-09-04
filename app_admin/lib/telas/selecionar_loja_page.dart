import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/central_service.dart';
import '../services/app_navigator.dart';
import '../services/sessao_loja.dart';
import 'auth/login_central_page.dart';
import 'loja/menu_inicial.dart';

// SELECIONAR-LOJA-FORCA-ABA-LOJA
// ABA-REBUILD-MODO-LOJA-SEM-CONST-CORRIGIDO
class SelecionarLojaPage extends StatefulWidget {
  final bool abrirAutomaticamenteSeUmaLoja;

  const SelecionarLojaPage({
    super.key,
    this.abrirAutomaticamenteSeUmaLoja = false,
  });

  @override
  State<SelecionarLojaPage> createState() => _SelecionarLojaPageState();
}

class _SelecionarLojaPageState extends State<SelecionarLojaPage> {
  final service = CentralService();

  bool carregando = true;
  bool abrindoLoja = false;

  List<Map<String, dynamic>> lojas = [];

  String primeiroTexto(List<dynamic> valores) {
    for (final valor in valores) {
      final texto = valor?.toString().trim() ?? '';
      if (texto.isNotEmpty) {
        return texto;
      }
    }

    return '';
  }

  @override
  void initState() {
    super.initState();
    carregarLojas();
  }

  Future<void> carregarLojas() async {
    try {
      final resposta = await service.listarLojas();

      if (!mounted) return;

      setState(() {
        lojas = resposta;
        carregando = false;
      });

      if (widget.abrirAutomaticamenteSeUmaLoja && resposta.length == 1) {
        await abrirLoja(resposta.first);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao carregar lojas: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> abrirLoja(Map<String, dynamic> loja) async {
    setState(() {
      abrindoLoja = true;
    });

    try {
      final mercadoId = loja['id'].toString();
      final mercadoNome = loja['nome'].toString();

      final conexao = await service.buscarConexaoMercado(mercadoId);

      SessaoLoja.configurar(
        id: mercadoId,
        nome: mercadoNome,
        codigo: loja['codigo']?.toString(),
        apiUrl: conexao['api_base_url'].toString(),
        urlSupabase: conexao['supabase_url'].toString(),
        anonKeySupabase: conexao['supabase_anon_key'].toString(),
        fonteProdutos: conexao['fonte_produtos']?.toString(),
        adminCorPrimaria:
            (conexao['admin_cor_primaria'] ?? loja['admin_cor_primaria'])
                ?.toString(),
        adminCorSecundaria:
            (conexao['admin_cor_secundaria'] ?? loja['admin_cor_secundaria'])
                ?.toString(),
        adminCorFundo: (conexao['admin_cor_fundo'] ?? loja['admin_cor_fundo'])
            ?.toString(),
        logo: primeiroTexto([
          conexao['admin_logo_url'],
          conexao['logo_admin_url'],
          conexao['logo_login_url'],
          loja['admin_logo_url'],
          loja['logo_admin_url'],
          loja['logo_login_url'],
        ]),
        estoqueDetalhadoAtivo: SessaoLoja.booleanoDinamico(
          conexao['estoque_detalhado_ativo'] ??
              conexao['estoqueDetalhadoAtivo'],
        ),
        alterarPrecoConsultaAtivo: SessaoLoja.booleanoDinamico(
          conexao['alterar_preco_consulta_ativo'] ??
              conexao['alterarPrecoConsultaAtivo'],
        ),
      );

      AppNavigator.definirModoLoja();

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MenuInicialPage()),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        abrindoLoja = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao abrir loja: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> sair() async {
    await Supabase.instance.client.auth.signOut();

    SessaoLoja.limpar();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginCentralPage()),
    );
  }

  Widget cardLoja(Map<String, dynamic> loja) {
    final nome = loja['nome']?.toString() ?? 'Loja';
    final cidade = loja['cidade']?.toString() ?? '';
    final estado = loja['estado']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFFFE5E8),
            child: Icon(Icons.store, color: Color(0xFFE30613)),
          ),
          title: Text(
            nome,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            cidade.isEmpty && estado.isEmpty
                ? 'Toque para acessar'
                : '$cidade - $estado',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => abrirLoja(loja),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Selecionar loja'),
        backgroundColor: const Color(0xFFE30613),
        foregroundColor: Colors.white,
        actions: [IconButton(onPressed: sair, icon: const Icon(Icons.logout))],
      ),
      body: carregando || abrindoLoja
          ? const Center(child: CircularProgressIndicator())
          : lojas.isEmpty
          ? const Center(
              child: Text('Nenhuma loja disponível para este usuário'),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: lojas.length,
              itemBuilder: (context, index) {
                final loja = lojas[index];
                return cardLoja(loja);
              },
            ),
    );
  }
}

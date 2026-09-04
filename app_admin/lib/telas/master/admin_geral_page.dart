import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/central_service.dart';
import '../../services/sessao_loja.dart';
import '../../services/app_navigator.dart';

import '../auth/login_central_page.dart';
import '../loja/menu_inicial.dart';
import '../selecionar_loja_page.dart';
import '../shared/usuarios_sistema_page.dart';

import 'cadastrar_mercado_page.dart';
import 'cadastrar_usuario_page.dart';
import 'gerenciar_mercados_page.dart';

// MASTER-ACESSAR-LOJA-FORCA-ABA-LOJA
// ABA-REBUILD-MODO-LOJA-SEM-CONST-CORRIGIDO
class AdminGeralPage extends StatefulWidget {
  const AdminGeralPage({super.key});

  @override
  State<AdminGeralPage> createState() => _AdminGeralPageState();
}

class _AdminGeralPageState extends State<AdminGeralPage> {
  final service = CentralService();

  static const Color vermelho = Color(0xFFE30613);
  static const Color fundo = Color(0xFFF5F7FA);

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
    SessaoLoja.limpar();
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
    } catch (e) {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao carregar mercados: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> acessarLoja(Map<String, dynamic> loja) async {
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
      SessaoLoja.notificarAlteracao();

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MenuInicialPage()),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao acessar loja: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }

    if (!mounted) return;

    setState(() {
      abrindoLoja = false;
    });
  }

  Future<void> sair() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sair do sistema'),
        content: const Text('Deseja realmente sair da conta master?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
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

    await Supabase.instance.client.auth.signOut();

    SessaoLoja.limpar();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginCentralPage()),
      (route) => false,
    );
  }

  Future<void> abrirCadastroMercado() async {
    final cadastrado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CadastrarMercadoPage()),
    );

    if (cadastrado == true) {
      carregarLojas();
    }
  }

  Future<void> abrirGerenciarMercados() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const GerenciarMercadosPage()),
    );

    carregarLojas();
  }

  Future<void> abrirCadastroUsuario() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CadastrarUsuarioPage()),
    );
  }

  void abrirUsuariosSistema() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UsuariosSistemaPage()),
    );
  }

  void abrirSelecaoLojas() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SelecionarLojaPage()),
    );
  }

  Widget topoMaster() {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE30613), Color(0xFFB8000D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: vermelho.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.admin_panel_settings,
              color: vermelho,
              size: 38,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Admin Master',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  email.isEmpty ? 'Controle geral do sistema' : email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget cardResumo({
    required String titulo,
    required String subtitulo,
    required IconData icone,
    required Color cor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: cor.withOpacity(0.12),
              child: Icon(icone, color: cor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitulo,
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Widget itemMercado(Map<String, dynamic> loja) {
    final nome = loja['nome']?.toString() ?? 'Mercado';
    final codigo = loja['codigo']?.toString() ?? '';
    final cidade = loja['cidade']?.toString() ?? '';
    final estado = loja['estado']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.all(14),
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFFFE5E8),
            child: Icon(Icons.store, color: vermelho),
          ),
          title: Text(
            nome,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            cidade.isEmpty && estado.isEmpty
                ? codigo
                : '$codigo • $cidade - $estado',
          ),
          trailing: ElevatedButton(
            onPressed: abrindoLoja ? null : () => acessarLoja(loja),
            style: ElevatedButton.styleFrom(
              backgroundColor: vermelho,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Acessar'),
          ),
        ),
      ),
    );
  }

  Widget resumoQuantidade() {
    return Row(
      children: [
        Expanded(
          child: cardContador(
            titulo: 'Mercados',
            valor: lojas.length.toString(),
            icone: Icons.store,
            cor: vermelho,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: cardContador(
            titulo: 'Ativos',
            valor: lojas.length.toString(),
            icone: Icons.check_circle,
            cor: Colors.green,
          ),
        ),
      ],
    );
  }

  Widget cardContador({
    required String titulo,
    required String valor,
    required IconData icone,
    required Color cor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: cor.withOpacity(0.12),
            child: Icon(icone, color: cor),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                titulo,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget tituloSecao(String titulo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        titulo,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1F2937),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fundo,
      appBar: AppBar(
        title: const Text('Admin Geral'),
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: carregarLojas,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: sair,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: carregando || abrindoLoja
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: carregarLojas,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  topoMaster(),

                  const SizedBox(height: 18),

                  resumoQuantidade(),

                  const SizedBox(height: 24),

                  tituloSecao('Ações do master'),

                  cardResumo(
                    titulo: 'Cadastrar novo cliente',
                    subtitulo: 'Criar mercado, conexão e primeiro usuário',
                    icone: Icons.add_business,
                    cor: Colors.green,
                    onTap: abrirCadastroMercado,
                  ),

                  const SizedBox(height: 12),

                  cardResumo(
                    titulo: 'Gerenciar mercados',
                    subtitulo: 'Listar e editar mercados cadastrados',
                    icone: Icons.edit_location_alt,
                    cor: Colors.deepOrange,
                    onTap: abrirGerenciarMercados,
                  ),

                  const SizedBox(height: 12),

                  cardResumo(
                    titulo: 'Cadastrar usuário',
                    subtitulo: 'Criar master, admin, operador ou entregador',
                    icone: Icons.person_add_alt_1,
                    cor: Colors.purple,
                    onTap: abrirCadastroUsuario,
                  ),

                  const SizedBox(height: 12),

                  cardResumo(
                    titulo: 'Usuários e senhas',
                    subtitulo: 'Listar usuários, resetar ou excluir',
                    icone: Icons.manage_accounts,
                    cor: Colors.blueGrey,
                    onTap: abrirUsuariosSistema,
                  ),

                  const SizedBox(height: 12),

                  cardResumo(
                    titulo: 'Selecionar loja',
                    subtitulo: 'Abrir painel de uma loja cadastrada',
                    icone: Icons.storefront,
                    cor: vermelho,
                    onTap: abrirSelecaoLojas,
                  ),

                  const SizedBox(height: 12),

                  cardResumo(
                    titulo: 'Atualizar mercados',
                    subtitulo: 'Recarregar lista de clientes',
                    icone: Icons.refresh,
                    cor: Colors.blue,
                    onTap: carregarLojas,
                  ),

                  const SizedBox(height: 24),

                  tituloSecao('Mercados cadastrados'),

                  if (lojas.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Nenhum mercado cadastrado'),
                      ),
                    )
                  else
                    ...lojas.map(itemMercado),
                ],
              ),
            ),
    );
  }
}

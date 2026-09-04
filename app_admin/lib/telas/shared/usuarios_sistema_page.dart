import 'package:flutter/material.dart';

import '../../services/central_service.dart';
import '../../services/sessao_loja.dart';
import '../master/cadastrar_usuario_page.dart';

const Map<String, String> nomesPadraoPermissoes = {
  'pedidos': 'Pedidos',
  'consulta_preco': 'Consulta Item P/ Compra',
  'produtos_inativos': 'Produtos inativos',
  'consulta_item': 'Consulta Item',
  'alterar_preco': 'Alterar preço',
  'balanco': 'Balanço',
  'conferencia_notas': 'Conferencia NF-e',
  'estoque': 'Estoque',
  'estoque_entrada': 'Entrada de estoque',
  'estoque_correcao': 'Correção de estoque',
  'estoque_baixa_avaria': 'Baixa por avaria',
  'estoque_baixa_validade': 'Baixa por validade',
  'estoque_abrir_pacote': 'Abrir pacote / granel',
  'estoque_consumo_interno': 'Consumo interno',
  'estoque_auditoria': 'Auditoria de estoque',
  'produtos_app': 'Produtos app',
  'receitas': 'Receitas',
  'cupons': 'Cupons',
  'ofertas': 'Ofertas',
  'jornal_promocoes': 'Jornal de promocoes',
  'clientes_app': 'Clientes do app',
  'acoes_validade': 'Ações de validade',
  'peso_variavel': 'Peso variável',
  'loja_configuracoes': 'Configurações da loja',
  'usuarios': 'Usuários',
  'relatorios': 'Relatórios',
};

const Map<String, String> descricoesPadraoPermissoes = {
  'pedidos': 'Visualizar e alterar pedidos da loja.',
  'consulta_preco': 'Consulta antiga/padrão de item para compra.',
  'produtos_inativos':
      'Consultar produtos inativos quando o item não for encontrado.',
  'consulta_item': 'Consulta visual com imagem grande do produto.',
  'alterar_preco': 'Alterar preço do produto pela tela de consulta.',
  'balanco': 'Coletar itens e gerar arquivo TXT.',
  'conferencia_notas': 'Consultar notas de entrada para conferencia.',
  'estoque': 'Acesso ao menu geral de estoque.',
  'estoque_entrada': 'Registrar entrada de estoque.',
  'estoque_correcao': 'Corrigir saldo de estoque.',
  'estoque_baixa_avaria': 'Baixar produtos avariados do estoque.',
  'estoque_baixa_validade': 'Baixar produtos vencidos do estoque.',
  'estoque_abrir_pacote':
      'Abrir embalagem fechada e somar quantidade no item a granel.',
  'estoque_consumo_interno': 'Registrar consumo interno de produtos.',
  'estoque_auditoria': 'Consultar alterações de estoque.',
  'produtos_app': 'Cadastrar produtos do modo BANCO_LOJA.',
  'receitas': 'Criar ficha técnica e produzir itens.',
  'cupons': 'Criar e gerenciar cupons de desconto.',
  'ofertas': 'Criar ofertas do app Mercado.',
  'jornal_promocoes': 'Gerar encarte para impressao e redes sociais.',
  'clientes_app': 'Listar e bloquear clientes cadastrados no app Mercado.',
  'acoes_validade': 'Criar descontos por validade e monitorar estoque.',
  'peso_variavel': 'Configurar produtos vendidos por KG/peso.',
  'loja_configuracoes': 'Editar dados, entrega, horários e aparência da loja.',
  'usuarios': 'Cadastrar usuários e liberar permissões.',
  'relatorios': 'Visualizar relatórios da loja.',
};

class UsuariosSistemaPage extends StatefulWidget {
  final String? mercadoId;
  final String? titulo;

  const UsuariosSistemaPage({super.key, this.mercadoId, this.titulo});

  @override
  State<UsuariosSistemaPage> createState() => _UsuariosSistemaPageState();
}

class _UsuariosSistemaPageState extends State<UsuariosSistemaPage> {
  final service = CentralService();

  static Color get vermelho => SessaoLoja.corPrimaria;
  static Color get vermelhoEscuro => SessaoLoja.corSecundaria;
  static Color get fundo => SessaoLoja.corFundo;
  static const Color textoPrincipal = Color(0xFF111827);

  bool carregando = true;
  bool processando = false;

  List<Map<String, dynamic>> usuarios = [];

  String get mercadoIdEfetivo {
    final idWidget = widget.mercadoId?.trim() ?? '';

    if (idWidget.isNotEmpty) {
      return idWidget;
    }

    final idSessao = SessaoLoja.mercadoId?.trim() ?? '';

    if (idSessao.isNotEmpty) {
      return idSessao;
    }

    return '';
  }

  bool get modoMaster {
    return mercadoIdEfetivo.isEmpty && !SessaoLoja.usuarioLogadoNaLoja;
  }

  String get mercadoId {
    final id = mercadoIdEfetivo;

    if (id.isEmpty) {
      throw Exception('mercado_id não informado');
    }

    return id;
  }

  String? get mercadoNome {
    final titulo = widget.titulo?.trim() ?? '';

    if (titulo.isNotEmpty && titulo != 'Usuários da loja') {
      return titulo;
    }

    return SessaoLoja.mercadoNome;
  }

  @override
  void initState() {
    super.initState();
    carregarUsuarios();
  }

  Future<void> carregarUsuarios() async {
    if (!mounted) return;

    setState(() {
      carregando = true;
    });

    try {
      final resposta = modoMaster
          ? await service.listarUsuariosMaster()
          : await service.listarUsuariosSistema(mercadoId: mercadoId);

      if (!mounted) return;

      setState(() {
        usuarios = resposta;
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
            'Erro ao listar usuários: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> abrirCadastrarUsuario() async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) {
          if (modoMaster) {
            return const CadastrarUsuarioPage();
          }

          return CadastrarUsuarioPage(
            mercadoIdFixo: mercadoId,
            mercadoNomeFixo: mercadoNome,
          );
        },
      ),
    );

    if (resultado == true) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usuário cadastrado com sucesso'),
          backgroundColor: Colors.green,
        ),
      );

      await carregarUsuarios();
    }
  }

  Future<void> abrirEditarUsuario(Map<String, dynamic> usuario) async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditarUsuarioSistemaPage(
          usuario: usuario,
          mercadoId: modoMaster ? null : mercadoId,
          modoMaster: modoMaster,
        ),
      ),
    );

    if (resultado == true) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usuário atualizado com sucesso'),
          backgroundColor: Colors.green,
        ),
      );

      await carregarUsuarios();
    }
  }

  Future<void> abrirPermissoesUsuario(Map<String, dynamic> usuario) async {
    if (modoMaster) return;

    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PermissoesUsuarioPage(usuario: usuario, mercadoId: mercadoId),
      ),
    );

    if (resultado == true) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permissões salvas com sucesso'),
          backgroundColor: Colors.green,
        ),
      );

      await carregarUsuarios();
    }
  }

  Future<void> abrirResetSenha(Map<String, dynamic> usuario) async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ResetarSenhaUsuarioPage(
          usuario: usuario,
          mercadoId: modoMaster ? null : mercadoId,
          modoMaster: modoMaster,
        ),
      ),
    );

    if (resultado == true) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Senha resetada com sucesso'),
          backgroundColor: Colors.green,
        ),
      );

      await carregarUsuarios();
    }
  }

  Future<void> abrirExcluirUsuario(Map<String, dynamic> usuario) async {
    if (modoMaster) return;

    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ExcluirUsuarioSistemaPage(usuario: usuario, mercadoId: mercadoId),
      ),
    );

    if (resultado == true) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usuário excluído com sucesso'),
          backgroundColor: Colors.green,
        ),
      );

      await carregarUsuarios();
    }
  }

  String textoTipo(Map<String, dynamic> usuario) {
    if (modoMaster) return 'Master';

    final perfil = usuario['perfil']?.toString() ?? '';

    switch (perfil) {
      case 'admin_loja':
        return 'Admin da loja';
      case 'estoque':
        return 'Estoque';
      case 'caixa':
        return 'Caixa';
      case 'entregador':
        return 'Motoboy / entregador';
      case 'usuario':
        return 'Usuário da loja';
      default:
        return perfil.isEmpty ? 'Usuário da loja' : perfil;
    }
  }

  Color corTipo(Map<String, dynamic> usuario) {
    if (modoMaster) return Colors.indigo;

    final perfil = usuario['perfil']?.toString() ?? '';

    if (perfil == 'admin_loja') return Colors.purple;
    if (perfil == 'estoque') return Colors.teal;
    if (perfil == 'caixa') return Colors.green;
    if (perfil == 'entregador') return Colors.deepOrange;

    return Colors.blueGrey;
  }

  bool usuarioAtivo(Map<String, dynamic> usuario) {
    return usuario['ativo'] == true;
  }

  Widget botaoAcao({
    required String texto,
    required Color cor,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 96,
      child: ElevatedButton(
        onPressed: processando ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: cor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          texto,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget topoUsuarios({required int total}) {
    final titulo = modoMaster ? 'Usuários master' : 'Usuários da loja';
    final subtitulo = modoMaster
        ? 'Gerencie os usuários master do sistema central'
        : mercadoNome == null
        ? 'Gerencie usuários, permissões e acessos'
        : 'Gerencie acessos de $mercadoNome';

    final ativos = usuarios.where(usuarioAtivo).length;
    final inativos = total - ativos;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [vermelho, vermelhoEscuro],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: vermelho.withOpacity(0.25),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(19),
            ),
            child: Icon(
              modoMaster ? Icons.admin_panel_settings : Icons.group,
              color: vermelho,
              size: 34,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    miniResumo(texto: '$total total', icone: Icons.people_alt),
                    miniResumo(
                      texto: '$ativos ativos',
                      icone: Icons.check_circle,
                    ),
                    if (inativos > 0)
                      miniResumo(
                        texto: '$inativos inativos',
                        icone: Icons.block,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget miniResumo({required String texto, required IconData icone}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            texto,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget chipStatus({
    required String texto,
    required Color cor,
    required IconData icone,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: cor),
          const SizedBox(width: 5),
          Text(
            texto,
            style: TextStyle(
              color: cor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget botaoIconeUsuario({
    required String tooltip,
    required IconData icone,
    required Color cor,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: processando ? null : onPressed,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: cor.withOpacity(0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cor.withOpacity(0.12)),
          ),
          child: Icon(icone, color: cor, size: 21),
        ),
      ),
    );
  }

  Widget linhaUsuarioInfo({required IconData icone, required String texto}) {
    if (texto.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Icon(icone, size: 15, color: Colors.black45),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget cardUsuario(Map<String, dynamic> usuario) {
    final nome = usuario['nome']?.toString() ?? 'Usuário';
    final login = usuario['login']?.toString() ?? '';
    final email = (usuario['email'] ?? usuario['email_auth'] ?? '').toString();
    final tipo = textoTipo(usuario);
    final cor = corTipo(usuario);
    final ativo = usuarioAtivo(usuario);

    final textoLoginUsuario = modoMaster
        ? email
        : login.isEmpty
        ? email
        : login;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => abrirEditarUsuario(usuario),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 6,
                  decoration: BoxDecoration(
                    color: ativo ? cor : Colors.red,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(22),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(13, 13, 12, 13),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: cor.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                modoMaster
                                    ? Icons.admin_panel_settings
                                    : Icons.person,
                                color: cor,
                                size: 29,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nome,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: textoPrincipal,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Wrap(
                                    spacing: 7,
                                    runSpacing: 6,
                                    children: [
                                      chipStatus(
                                        texto: tipo,
                                        cor: cor,
                                        icone: modoMaster
                                            ? Icons.shield
                                            : Icons.badge,
                                      ),
                                      chipStatus(
                                        texto: ativo ? 'ATIVO' : 'INATIVO',
                                        cor: ativo ? Colors.green : Colors.red,
                                        icone: ativo
                                            ? Icons.check_circle
                                            : Icons.block,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Divider(height: 1, color: Colors.grey.shade200),
                        linhaUsuarioInfo(
                          icone: modoMaster ? Icons.email : Icons.login,
                          texto: textoLoginUsuario.isEmpty
                              ? 'Sem login'
                              : modoMaster
                              ? textoLoginUsuario
                              : 'Login: $textoLoginUsuario',
                        ),
                        if (!modoMaster && email.isNotEmpty)
                          linhaUsuarioInfo(
                            icone: Icons.email_outlined,
                            texto: email,
                          ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            botaoIconeUsuario(
                              tooltip: 'Editar',
                              icone: Icons.edit_outlined,
                              cor: Colors.blueGrey,
                              onPressed: () => abrirEditarUsuario(usuario),
                            ),
                            if (!modoMaster &&
                                usuario['perfil']?.toString() != 'entregador')
                              botaoIconeUsuario(
                                tooltip: 'Permissões',
                                icone: Icons.tune,
                                cor: Colors.deepPurple,
                                onPressed: () =>
                                    abrirPermissoesUsuario(usuario),
                              ),
                            botaoIconeUsuario(
                              tooltip: 'Resetar senha',
                              icone: Icons.lock_reset,
                              cor: vermelho,
                              onPressed: () => abrirResetSenha(usuario),
                            ),
                            if (!modoMaster)
                              botaoIconeUsuario(
                                tooltip: 'Excluir',
                                icone: Icons.delete_outline,
                                cor: Colors.red,
                                onPressed: () => abrirExcluirUsuario(usuario),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget estadoVazio() {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.only(top: 50),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.black.withOpacity(0.05)),
        ),
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: vermelho.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person_add_alt_1, color: vermelho, size: 36),
            ),
            const SizedBox(height: 14),
            const Text(
              'Nenhum usuário encontrado',
              style: TextStyle(
                color: textoPrincipal,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Cadastre um novo usuário para liberar acesso ao sistema.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: processando ? null : abrirCadastrarUsuario,
                icon: const Icon(Icons.person_add),
                label: const Text('Cadastrar usuário'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: vermelho,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget conteudoLista() {
    if (carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: carregarUsuarios,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          topoUsuarios(total: usuarios.length),
          if (usuarios.isEmpty)
            estadoVazio()
          else ...[
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Usuários cadastrados',
                    style: TextStyle(
                      color: textoPrincipal,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: carregarUsuarios,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Atualizar'),
                  style: TextButton.styleFrom(foregroundColor: vermelho),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...usuarios.map(cardUsuario),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titulo =
        widget.titulo ?? (modoMaster ? 'Usuários master' : 'Usuários da loja');

    return Scaffold(
      backgroundColor: fundo,
      appBar: AppBar(
        title: Text(titulo),
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: processando ? null : carregarUsuarios,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: processando ? null : abrirCadastrarUsuario,
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
        elevation: 6,
        icon: const Icon(Icons.person_add),
        label: const Text(
          'Cadastrar',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Stack(
        children: [
          conteudoLista(),
          if (processando)
            Container(
              color: Colors.black.withOpacity(0.08),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class EditarUsuarioSistemaPage extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final String? mercadoId;
  final bool modoMaster;

  const EditarUsuarioSistemaPage({
    super.key,
    required this.usuario,
    required this.modoMaster,
    this.mercadoId,
  });

  @override
  State<EditarUsuarioSistemaPage> createState() =>
      _EditarUsuarioSistemaPageState();
}

class _EditarUsuarioSistemaPageState extends State<EditarUsuarioSistemaPage> {
  final service = CentralService();

  final nomeController = TextEditingController();
  final loginController = TextEditingController();

  static Color get vermelho => SessaoLoja.corPrimaria;

  bool processando = false;
  bool ativo = true;
  String perfilSelecionado = 'usuario';

  final List<Map<String, String>> perfis = const [
    {'codigo': 'admin_loja', 'nome': 'Admin da loja'},
    {'codigo': 'usuario', 'nome': 'Usuário da loja'},
    {'codigo': 'estoque', 'nome': 'Estoque'},
    {'codigo': 'caixa', 'nome': 'Caixa'},
    {'codigo': 'entregador', 'nome': 'Motoboy / entregador'},
  ];

  @override
  void initState() {
    super.initState();

    nomeController.text = widget.usuario['nome']?.toString() ?? '';

    if (widget.modoMaster) {
      loginController.text = widget.usuario['email']?.toString() ?? '';
    } else {
      loginController.text = widget.usuario['login']?.toString() ?? '';
    }

    ativo = widget.usuario['ativo'] == true;

    final perfilAtual = widget.usuario['perfil']?.toString() ?? 'usuario';
    final existePerfil = perfis.any((item) => item['codigo'] == perfilAtual);

    perfilSelecionado = existePerfil ? perfilAtual : 'usuario';
  }

  @override
  void dispose() {
    nomeController.dispose();
    loginController.dispose();
    super.dispose();
  }

  Future<void> salvar() async {
    final userId = widget.usuario['user_id']?.toString() ?? '';
    final nome = nomeController.text.trim();
    final loginOuEmail = loginController.text.trim();

    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usuário sem user_id'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o nome'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (loginOuEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.modoMaster ? 'Informe o e-mail' : 'Informe o login',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      processando = true;
    });

    try {
      if (widget.modoMaster) {
        await service.editarUsuarioMaster(
          userId: userId,
          nome: nome,
          email: loginOuEmail,
          ativo: ativo,
        );
      } else {
        final mercadoId = widget.mercadoId?.trim() ?? '';

        if (mercadoId.isEmpty) {
          throw Exception('mercado_id não informado');
        }

        await service.editarUsuarioSistema(
          mercadoId: mercadoId,
          userId: userId,
          nome: nome,
          login: loginOuEmail,
          perfil: perfilSelecionado,
          ativo: ativo,
        );

        if (perfilSelecionado == 'entregador') {
          await service.salvarPermissoesUsuario(
            mercadoId: mercadoId,
            userId: userId,
            permissoes: ['pedidos'],
          );
        }
      }

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        processando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao salvar usuário: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final titulo = widget.modoMaster ? 'Editar master' : 'Editar usuário';

    return Scaffold(
      backgroundColor: SessaoLoja.corFundo,
      appBar: AppBar(
        title: Text(titulo),
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.modoMaster
                    ? 'Altere os dados do usuário master no sistema central.'
                    : 'Altere os dados do usuário da loja.',
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 22),
              TextField(
                controller: nomeController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Nome',
                  prefixIcon: const Icon(Icons.person),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: loginController,
                keyboardType: widget.modoMaster
                    ? TextInputType.emailAddress
                    : TextInputType.text,
                decoration: InputDecoration(
                  labelText: widget.modoMaster ? 'E-mail' : 'Login',
                  prefixIcon: Icon(
                    widget.modoMaster ? Icons.email : Icons.badge,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              if (!widget.modoMaster) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: perfilSelecionado,
                  decoration: InputDecoration(
                    labelText: 'Perfil',
                    prefixIcon: const Icon(Icons.admin_panel_settings),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  items: perfis.map((perfil) {
                    return DropdownMenuItem<String>(
                      value: perfil['codigo'],
                      child: Text(perfil['nome'] ?? ''),
                    );
                  }).toList(),
                  onChanged: processando
                      ? null
                      : (valor) {
                          if (valor == null) return;

                          setState(() {
                            perfilSelecionado = valor;
                          });
                        },
                ),
              ],
              const SizedBox(height: 14),
              SwitchListTile(
                value: ativo,
                onChanged: processando
                    ? null
                    : (valor) {
                        setState(() {
                          ativo = valor;
                        });
                      },
                title: const Text('Usuário ativo'),
                subtitle: const Text(
                  'Desative para bloquear o acesso sem excluir o cadastro.',
                ),
                activeColor: vermelho,
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: processando ? null : salvar,
                  icon: const Icon(Icons.save),
                  label: const Text('Salvar alterações'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: vermelho,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (processando)
            Container(
              color: Colors.black.withOpacity(0.08),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class PermissoesUsuarioPage extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final String mercadoId;

  const PermissoesUsuarioPage({
    super.key,
    required this.usuario,
    required this.mercadoId,
  });

  @override
  State<PermissoesUsuarioPage> createState() => _PermissoesUsuarioPageState();
}

class _PermissoesUsuarioPageState extends State<PermissoesUsuarioPage> {
  final service = CentralService();

  static Color get vermelho => SessaoLoja.corPrimaria;

  bool carregando = true;
  bool processando = false;

  List<Map<String, dynamic>> modulos = [];
  Set<String> permissoesSelecionadas = {};

  @override
  void initState() {
    super.initState();
    carregarPermissoes();
  }

  Future<void> carregarPermissoes() async {
    final userId = widget.usuario['user_id']?.toString() ?? '';

    if (userId.isEmpty) {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usuário sem user_id'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final resposta = await service.listarPermissoesUsuario(
        mercadoId: widget.mercadoId,
        userId: userId,
      );

      final listaModulos = resposta['modulos'];

      final modulosConvertidos = listaModulos == null
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(listaModulos);

      final selecionadas = modulosConvertidos
          .where((modulo) => modulo['permitido'] == true)
          .map((modulo) => modulo['codigo']?.toString() ?? '')
          .where((codigo) => codigo.isNotEmpty)
          .toSet();

      if (!mounted) return;

      setState(() {
        modulos = modulosConvertidos;
        permissoesSelecionadas = selecionadas;
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
            'Erro ao carregar permissões: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> salvarPermissoes() async {
    final userId = widget.usuario['user_id']?.toString() ?? '';

    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usuário sem user_id'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      processando = true;
    });

    try {
      await service.salvarPermissoesUsuario(
        mercadoId: widget.mercadoId,
        userId: userId,
        permissoes: permissoesSelecionadas.toList(),
      );

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        processando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao salvar permissões: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget itemModulo(Map<String, dynamic> modulo) {
    final codigo = modulo['codigo']?.toString() ?? '';
    final nome =
        nomesPadraoPermissoes[codigo] ?? modulo['nome']?.toString() ?? codigo;
    final descricao =
        descricoesPadraoPermissoes[codigo] ??
        modulo['descricao']?.toString() ??
        '';
    final selecionado = permissoesSelecionadas.contains(codigo);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selecionado
              ? vermelho.withOpacity(0.35)
              : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SwitchListTile(
          value: selecionado,
          onChanged: processando
              ? null
              : (valor) {
                  setState(() {
                    if (valor) {
                      permissoesSelecionadas.add(codigo);
                    } else {
                      permissoesSelecionadas.remove(codigo);
                    }
                  });
                },
          title: Text(
            nome,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: descricao.isEmpty ? null : Text(descricao),
          activeColor: vermelho,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nome = widget.usuario['nome']?.toString() ?? 'Usuário';
    final login = widget.usuario['login']?.toString() ?? '';

    return Scaffold(
      backgroundColor: SessaoLoja.corFundo,
      appBar: AppBar(
        title: const Text('Permissões'),
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          if (carregando)
            const Center(child: CircularProgressIndicator())
          else
            ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const Text(
                  'Permissões do usuário',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  login.isEmpty ? nome : '$nome • $login',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 22),
                if (modulos.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Text('Nenhum módulo cadastrado'),
                    ),
                  )
                else
                  ...modulos.map(itemModulo),
                const SizedBox(height: 18),
                SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: processando ? null : salvarPermissoes,
                    icon: const Icon(Icons.save),
                    label: const Text('Salvar permissões'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: vermelho,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          if (processando)
            Container(
              color: Colors.black.withOpacity(0.08),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class ResetarSenhaUsuarioPage extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final String? mercadoId;
  final bool modoMaster;

  const ResetarSenhaUsuarioPage({
    super.key,
    required this.usuario,
    required this.modoMaster,
    this.mercadoId,
  });

  @override
  State<ResetarSenhaUsuarioPage> createState() =>
      _ResetarSenhaUsuarioPageState();
}

class _ResetarSenhaUsuarioPageState extends State<ResetarSenhaUsuarioPage> {
  final service = CentralService();

  final senhaController = TextEditingController();
  final confirmarSenhaController = TextEditingController();

  static Color get vermelho => SessaoLoja.corPrimaria;

  bool processando = false;

  @override
  void dispose() {
    senhaController.dispose();
    confirmarSenhaController.dispose();
    super.dispose();
  }

  Future<void> resetarSenha() async {
    final userId = widget.usuario['user_id']?.toString() ?? '';
    final novaSenha = senhaController.text.trim();
    final confirmarSenha = confirmarSenhaController.text.trim();

    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usuário sem user_id'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (novaSenha.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A senha precisa ter pelo menos 6 caracteres'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (confirmarSenha.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Confirme a nova senha'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (novaSenha != confirmarSenha) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('As senhas não conferem'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      processando = true;
    });

    try {
      if (widget.modoMaster) {
        await service.resetarSenhaMaster(userId: userId, novaSenha: novaSenha);
      } else {
        final mercadoId = widget.mercadoId?.trim() ?? '';

        if (mercadoId.isEmpty) {
          throw Exception('mercado_id não informado');
        }

        await service.resetarSenhaUsuario(
          mercadoId: mercadoId,
          userId: userId,
          novaSenha: novaSenha,
        );
      }

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        processando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao resetar senha: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nome = widget.usuario['nome']?.toString() ?? 'Usuário';
    final login = widget.usuario['login']?.toString() ?? '';
    final email =
        (widget.usuario['email'] ?? widget.usuario['email_auth'] ?? '')
            .toString();

    return Scaffold(
      backgroundColor: SessaoLoja.corFundo,
      appBar: AppBar(
        title: const Text('Resetar senha'),
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Text(
                'Nova senha do usuário',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Digite e confirme a nova senha para o usuário selecionado.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.black.withOpacity(0.05)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: vermelho.withValues(alpha: 0.10),
                      child: Icon(Icons.person, color: vermelho),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nome,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            login.isNotEmpty
                                ? 'Login: $login'
                                : email.isNotEmpty
                                ? email
                                : 'Sem login',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: senhaController,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Nova senha',
                  hintText: 'Mínimo 6 caracteres',
                  prefixIcon: const Icon(Icons.lock_reset),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: confirmarSenhaController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Confirmar nova senha',
                  hintText: 'Digite novamente a senha',
                  prefixIcon: const Icon(Icons.lock),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: processando ? null : resetarSenha,
                  icon: const Icon(Icons.save),
                  label: const Text('Salvar nova senha'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: vermelho,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (processando)
            Container(
              color: Colors.black.withOpacity(0.08),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class ExcluirUsuarioSistemaPage extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final String mercadoId;

  const ExcluirUsuarioSistemaPage({
    super.key,
    required this.usuario,
    required this.mercadoId,
  });

  @override
  State<ExcluirUsuarioSistemaPage> createState() =>
      _ExcluirUsuarioSistemaPageState();
}

class _ExcluirUsuarioSistemaPageState extends State<ExcluirUsuarioSistemaPage> {
  final service = CentralService();

  static Color get vermelho => SessaoLoja.corPrimaria;

  bool processando = false;

  Future<void> excluir() async {
    final userId = widget.usuario['user_id']?.toString() ?? '';

    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usuário sem user_id'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      processando = true;
    });

    try {
      await service.excluirUsuarioSistema(
        mercadoId: widget.mercadoId,
        userId: userId,
      );

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        processando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao excluir usuário: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nome = widget.usuario['nome']?.toString() ?? 'Usuário';
    final login = widget.usuario['login']?.toString() ?? '';
    final email = widget.usuario['email_auth']?.toString() ?? '';

    return Scaffold(
      backgroundColor: SessaoLoja.corFundo,
      appBar: AppBar(
        title: const Text('Excluir usuário'),
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Text(
                'Confirmar exclusão',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Essa ação remove o acesso do usuário ao sistema.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.red.withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Colors.red,
                      child: Icon(Icons.warning, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nome,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            login.isEmpty ? 'Sem login' : 'Login: $login',
                            style: const TextStyle(color: Colors.black54),
                          ),
                          if (email.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              email,
                              style: const TextStyle(color: Colors.black45),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: processando ? null : excluir,
                  icon: const Icon(Icons.delete),
                  label: const Text('Excluir usuário'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 54,
                child: OutlinedButton.icon(
                  onPressed: processando
                      ? null
                      : () {
                          Navigator.pop(context, false);
                        },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Cancelar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: vermelho,
                    side: BorderSide(color: vermelho),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (processando)
            Container(
              color: Colors.black.withOpacity(0.08),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

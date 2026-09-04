import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/central_service.dart';
import '../../services/pedidos_web_browser.dart';
import '../../services/push_notification_service.dart';
import '../../services/sessao_loja.dart';
import '../loja/pedidos_status_page.dart';

const String _mercadoCodigoDefine = String.fromEnvironment('MERCADO_CODIGO');
const String _adminPwaUrl = String.fromEnvironment(
  'ADMIN_PWA_URL',
  defaultValue: 'https://admin.vuptsistemas.com.br',
);
const String _downloadsAdminUrl = String.fromEnvironment(
  'DOWNLOADS_ADMIN_URL',
  defaultValue: 'https://downloads.vuptsistemas.com.br/baixar',
);

String _normalizarCodigo(String valor) {
  return valor.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '');
}

String _codigoMercadoDaUrl() {
  final segmentos = Uri.base.pathSegments
      .map(Uri.decodeComponent)
      .map(_normalizarCodigo)
      .where((segmento) => segmento.isNotEmpty)
      .toList();

  if (segmentos.isNotEmpty && segmentos.first != 'index.html') {
    return segmentos.first;
  }

  return _normalizarCodigo(_mercadoCodigoDefine);
}

bool get _podeOferecerAplicativo =>
    PedidosWebBrowser.dispositivoAndroid || PedidosWebBrowser.dispositivoIos;

String get _rotuloAplicativo => PedidosWebBrowser.dispositivoAndroid
    ? 'Baixar app Android'
    : 'Adicionar Admin no iPhone';

IconData get _iconeAplicativo => PedidosWebBrowser.dispositivoAndroid
    ? Icons.android
    : Icons.install_mobile_outlined;

void _mostrarErroAplicativo(BuildContext context, String mensagem) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
}

Future<void> _obterAplicativoAdmin(
  BuildContext context,
  String codigoInformado,
) async {
  final codigoLoja = _normalizarCodigo(codigoInformado);
  if (codigoLoja.isEmpty) {
    _mostrarErroAplicativo(
      context,
      'Não foi possível identificar a loja para baixar o app.',
    );
    return;
  }

  if (PedidosWebBrowser.dispositivoAndroid) {
    final abriu = await launchUrl(
      Uri.parse('$_downloadsAdminUrl/$codigoLoja'),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_self',
    );
    if (!context.mounted) return;
    if (!abriu) {
      _mostrarErroAplicativo(
        context,
        'Não foi possível iniciar o download do aplicativo.',
      );
    }
    return;
  }

  if (!PedidosWebBrowser.dispositivoIos || !context.mounted) return;

  final abrirAdmin = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.install_mobile_outlined),
          SizedBox(width: 10),
          Expanded(child: Text('Adicionar o Admin ao iPhone')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('O Admin será aberto. No Safari:'),
            SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.ios_share_outlined),
                SizedBox(width: 10),
                Expanded(child: Text('1. Toque em Compartilhar.')),
              ],
            ),
            SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.add_box_outlined),
                SizedBox(width: 10),
                Expanded(child: Text('2. Escolha Adicionar à Tela de Início.')),
              ],
            ),
            SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_outline),
                SizedBox(width: 10),
                Expanded(child: Text('3. Confirme tocando em Adicionar.')),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Abrir Admin'),
        ),
      ],
    ),
  );

  if (abrirAdmin != true || !context.mounted) return;
  final abriu = await launchUrl(
    Uri.parse('$_adminPwaUrl/$codigoLoja'),
    mode: LaunchMode.externalApplication,
    webOnlyWindowName: '_self',
  );
  if (!context.mounted) return;
  if (!abriu) {
    _mostrarErroAplicativo(
      context,
      'Não foi possível abrir o Admin. Tente pelo Safari.',
    );
  }
}

bool _podeAcessarPedidos() {
  return SessaoLoja.usuarioAdminLoja ||
      SessaoLoja.usuarioEntregador ||
      SessaoLoja.temPermissao('pedidos');
}

class PedidosWebBootstrapPage extends StatefulWidget {
  const PedidosWebBootstrapPage({super.key});

  @override
  State<PedidosWebBootstrapPage> createState() =>
      _PedidosWebBootstrapPageState();
}

class _PedidosWebBootstrapPageState extends State<PedidosWebBootstrapPage> {
  final CentralService _central = CentralService();

  late final String _mercadoCodigo = _codigoMercadoDaUrl();
  bool _carregando = true;
  String? _erro;
  Map<String, dynamic> _mercado = {};
  bool _autenticado = false;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    if (_mercadoCodigo.isEmpty) {
      setState(() {
        _carregando = false;
        _erro = 'Endereço incompleto. Use o link da loja, por exemplo: /sao_mateus.';
      });
      return;
    }

    try {
      final mercado = await _central.validarMercadoAtivo(
        mercadoCodigo: _mercadoCodigo,
      );

      if (mercado['ativo'] != true || mercado['bloqueado'] == true) {
        throw Exception(
          mercado['mensagem']?.toString() ?? 'Esta loja não está disponível.',
        );
      }

      var autenticado = await SessaoLoja.restaurarSessaoLojaPersistida();
      final codigoSessao = _normalizarCodigo(SessaoLoja.mercadoCodigo ?? '');

      if (autenticado && codigoSessao != _mercadoCodigo) {
        try {
          await SessaoLoja.supabaseLoja?.auth.signOut();
        } catch (_) {}
        SessaoLoja.limpar();
        autenticado = false;
      }

      if (autenticado && !_podeAcessarPedidos()) {
        try {
          await SessaoLoja.supabaseLoja?.auth.signOut();
        } catch (_) {}
        SessaoLoja.limpar();
        autenticado = false;
        _erro = 'Seu usuário não possui permissão para acessar Pedidos.';
      }

      if (!mounted) return;
      setState(() {
        _mercado = mercado;
        _autenticado = autenticado;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = CentralService.mensagemErroUsuario(e);
      });
    }
  }

  void _aoEntrar() {
    setState(() {
      _autenticado = true;
      _erro = null;
    });
  }

  Future<void> _sair() async {
    try {
      await SessaoLoja.supabaseLoja?.auth.signOut();
    } catch (_) {}
    SessaoLoja.limpar();
    await SessaoLoja.limparSessaoLojaPersistida();

    if (!mounted) return;
    setState(() {
      _autenticado = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const _EstadoCentral(
        icone: Icons.receipt_long_outlined,
        titulo: 'Abrindo painel de pedidos',
        carregando: true,
      );
    }

    if (_erro != null && _mercado.isEmpty) {
      return _EstadoCentral(
        icone: Icons.link_off_outlined,
        titulo: 'Painel indisponível',
        mensagem: _erro,
        onTentarNovamente: _inicializar,
      );
    }

    if (!_autenticado) {
      return LoginPedidosWebPage(
        mercadoCodigo: _mercadoCodigo,
        mercado: _mercado,
        mensagemInicial: _erro,
        onEntrou: _aoEntrar,
      );
    }

    return PainelPedidosWebPage(onSair: _sair);
  }
}

class LoginPedidosWebPage extends StatefulWidget {
  final String mercadoCodigo;
  final Map<String, dynamic> mercado;
  final String? mensagemInicial;
  final VoidCallback onEntrou;

  const LoginPedidosWebPage({
    super.key,
    required this.mercadoCodigo,
    required this.mercado,
    required this.onEntrou,
    this.mensagemInicial,
  });

  @override
  State<LoginPedidosWebPage> createState() => _LoginPedidosWebPageState();
}

class _LoginPedidosWebPageState extends State<LoginPedidosWebPage> {
  final CentralService _central = CentralService();
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _senhaController = TextEditingController();

  bool _carregando = false;
  bool _ocultarSenha = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _erro = widget.mensagemInicial;
  }

  @override
  void dispose() {
    _loginController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  List<String> _permissoes(Map<String, dynamic> dados) {
    final valor = dados['permissoes'];
    if (valor is! List) return const [];

    return valor
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> _entrar() async {
    final login = _loginController.text.trim();
    final senha = _senhaController.text;

    if (login.isEmpty || senha.isEmpty) {
      setState(() => _erro = 'Informe login e senha.');
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final dados = await _central.resolverLogin(
        login,
        mercadoCodigo: widget.mercadoCodigo,
      );

      if (dados['destino_auth']?.toString() != 'loja') {
        throw Exception(
          'Este painel aceita somente usuários cadastrados nesta loja.',
        );
      }

      final mercadoId = dados['mercado_id']?.toString().trim() ?? '';
      final mercadoNome = dados['mercado_nome']?.toString().trim() ?? '';
      final supabaseUrl = dados['supabase_url']?.toString().trim() ?? '';
      final anonKey = dados['supabase_anon_key']?.toString().trim() ?? '';
      final emailAuth = dados['email_auth']?.toString().trim() ?? '';

      if (mercadoId.isEmpty ||
          mercadoNome.isEmpty ||
          supabaseUrl.isEmpty ||
          anonKey.isEmpty ||
          emailAuth.isEmpty) {
        throw Exception('A conexão desta loja está incompleta.');
      }

      final clienteLoja = SupabaseClient(
        supabaseUrl,
        anonKey,
        authOptions: const AuthClientOptions(autoRefreshToken: true),
      );
      final resposta = await clienteLoja.auth.signInWithPassword(
        email: emailAuth,
        password: senha,
      );

      if (resposta.user == null || resposta.session == null) {
        throw Exception('Não foi possível autenticar o usuário.');
      }

      final permissoes = _permissoes(dados);
      final perfil = dados['perfil']?.toString() ?? 'usuario';
      final possuiAcesso =
          perfil == 'admin_loja' ||
          perfil == 'entregador' ||
          perfil == 'motoboy' ||
          permissoes.contains('pedidos');

      if (!possuiAcesso) {
        await clienteLoja.auth.signOut();
        throw Exception('Seu usuário não possui permissão para Pedidos.');
      }

      SessaoLoja.limpar();
      SessaoLoja.configurarLoginLoja(
        id: mercadoId,
        nome: mercadoNome,
        codigo: dados['mercado_codigo']?.toString(),
        apiUrl: dados['api_base_url']?.toString(),
        urlSupabase: supabaseUrl,
        anonKeySupabase: anonKey,
        userId: dados['user_id']?.toString().trim().isNotEmpty == true
            ? dados['user_id'].toString()
            : resposta.user!.id,
        userNome: dados['nome']?.toString(),
        userLogin: dados['login']?.toString(),
        userEmail: emailAuth,
        userPerfil: perfil,
        accessToken: resposta.session!.accessToken,
        refreshToken: resposta.session!.refreshToken,
        clienteLoja: clienteLoja,
        permissoes: permissoes,
        fonteProdutos: dados['fonte_produtos']?.toString(),
        adminCorPrimaria: dados['admin_cor_primaria']?.toString(),
        adminCorSecundaria: dados['admin_cor_secundaria']?.toString(),
        adminCorFundo: dados['admin_cor_fundo']?.toString(),
        logo: _primeiroTexto([
          dados['admin_logo_url'],
          dados['logo_login_url'],
          dados['logo_url'],
        ]),
        estoqueDetalhadoAtivo: SessaoLoja.booleanoDinamico(
          dados['estoque_detalhado_ativo'],
        ),
        alterarPrecoConsultaAtivo: SessaoLoja.booleanoDinamico(
          dados['alterar_preco_consulta_ativo'],
        ),
      );
      await SessaoLoja.salvarSessaoLojaPersistida();

      if (!mounted) return;
      widget.onEntrou();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = _mensagemLogin(e);
      });
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  String _mensagemLogin(Object erro) {
    final texto = erro.toString().toLowerCase();
    if (texto.contains('invalid login credentials')) {
      return 'Login ou senha inválidos.';
    }
    if (texto.contains('login não encontrado') ||
        texto.contains('login nao encontrado') ||
        texto.contains('usuário inativo') ||
        texto.contains('usuario inativo')) {
      return 'Usuário não cadastrado ou inativo nesta loja.';
    }
    return CentralService.mensagemErroUsuario(erro);
  }

  String _primeiroTexto(List<dynamic> valores) {
    for (final valor in valores) {
      final texto = valor?.toString().trim() ?? '';
      if (texto.isNotEmpty) return texto;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final nome = widget.mercado['mercado_nome']?.toString() ?? 'Loja';
    final logo = widget.mercado['logo_login_url']?.toString().trim() ?? '';
    final primaria = _corHex(
      widget.mercado['admin_cor_primaria']?.toString(),
      const Color(0xFF166534),
    );

    return Scaffold(
      body: Row(
        children: [
          if (MediaQuery.sizeOf(context).width >= 900)
            Expanded(
              flex: 6,
              child: Container(
                color: const Color(0xFF111827),
                padding: const EdgeInsets.all(56),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _MarcaVupt(clara: true),
                    const Spacer(),
                    Container(width: 58, height: 4, color: primaria),
                    const SizedBox(height: 24),
                    Text(
                      nome,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const SizedBox(
                      width: 520,
                      child: Text(
                        'Pedidos da loja em um só lugar: aceite, separação, entrega e acompanhamento.',
                        style: TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 18,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      'Acesso seguro e exclusivo para a equipe da loja.',
                      style: TextStyle(color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            flex: 5,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (MediaQuery.sizeOf(context).width < 900) ...[
                        const _MarcaVupt(),
                        const SizedBox(height: 36),
                      ],
                      if (logo.isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            constraints: const BoxConstraints(
                              maxWidth: 210,
                              maxHeight: 94,
                            ),
                            margin: const EdgeInsets.only(bottom: 28),
                            child: Image.network(
                              logo,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const SizedBox(),
                            ),
                          ),
                        ),
                      const Text(
                        'Painel de pedidos',
                        style: TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Entre com o usuário cadastrado em $nome.',
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _loginController,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        enabled: !_carregando,
                        decoration: const InputDecoration(
                          labelText: 'Login',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _senhaController,
                        obscureText: _ocultarSenha,
                        enabled: !_carregando,
                        onSubmitted: (_) => _entrar(),
                        decoration: InputDecoration(
                          labelText: 'Senha',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _ocultarSenha
                                ? 'Mostrar senha'
                                : 'Ocultar senha',
                            onPressed: () =>
                                setState(() => _ocultarSenha = !_ocultarSenha),
                            icon: Icon(
                              _ocultarSenha
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      if (_erro != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F2),
                            border: Border.all(color: const Color(0xFFFECACA)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Color(0xFFDC2626),
                                size: 20,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  _erro!,
                                  style: const TextStyle(
                                    color: Color(0xFF991B1B),
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: primaria,
                        ),
                        onPressed: _carregando ? null : _entrar,
                        icon: _carregando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(
                          _carregando ? 'Entrando...' : 'Entrar no painel',
                        ),
                      ),
                      if (_podeOferecerAplicativo) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _obterAplicativoAdmin(
                            context,
                            widget.mercadoCodigo,
                          ),
                          icon: Icon(_iconeAplicativo),
                          label: Text(_rotuloAplicativo),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PainelPedidosWebPage extends StatefulWidget {
  final Future<void> Function() onSair;

  const PainelPedidosWebPage({super.key, required this.onSair});

  @override
  State<PainelPedidosWebPage> createState() => _PainelPedidosWebPageState();
}

class _PainelPedidosWebPageState extends State<PainelPedidosWebPage> {
  final TextEditingController _buscaController = TextEditingController();

  RealtimeChannel? _canal;
  Timer? _timer;
  bool _carregando = true;
  bool _atualizando = false;
  bool _consultaEmAndamento = false;
  bool _pedidosInicializados = false;
  String _statusSelecionado = 'todos';
  List<Map<String, dynamic>> _pedidos = [];
  Set<String> _idsPedidosConhecidos = <String>{};
  String? _erro;

  static const _status = <_StatusPedidoWeb>[
    _StatusPedidoWeb('todos', 'Todos', Icons.list_alt_outlined),
    _StatusPedidoWeb('novo', 'Aguardando aceite', Icons.notifications_none),
    _StatusPedidoWeb('aceito', 'Aceitos', Icons.verified_outlined),
    _StatusPedidoWeb('preparando', 'Em preparação', Icons.inventory_2_outlined),
    _StatusPedidoWeb(
      'saiu_para_entrega',
      'Em entrega',
      Icons.local_shipping_outlined,
    ),
    _StatusPedidoWeb('entregue', 'Entregues', Icons.check_circle_outline),
    _StatusPedidoWeb('cancelado', 'Cancelados', Icons.cancel_outlined),
  ];

  @override
  void initState() {
    super.initState();
    if (SessaoLoja.usuarioEntregador) {
      _statusSelecionado = 'saiu_para_entrega';
    }
    _iniciar();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    _timer?.cancel();
    final canal = _canal;
    final cliente = SessaoLoja.supabaseLoja;
    if (canal != null && cliente != null) {
      cliente.removeChannel(canal);
    }
    super.dispose();
  }

  Future<void> _abrirConfiguracaoSom() async {
    var ativo = PedidosWebBrowser.somNovoPedidoAtivo;
    var som = PedidosWebBrowser.somNovoPedido;
    var volume = PedidosWebBrowser.volumeNovoPedido;
    var nomeAudioPersonalizado = PedidosWebBrowser.nomeAudioPersonalizado;
    String? erroAudio;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.notifications_active_outlined),
                  SizedBox(width: 10),
                  Text('Som de novos pedidos'),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Emitir alerta sonoro'),
                      subtitle: const Text(
                        'Toca quando um novo pedido chega neste computador.',
                      ),
                      value: ativo,
                      onChanged: (valor) {
                        setDialogState(() => ativo = valor);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: som,
                      decoration: const InputDecoration(
                        labelText: 'Toque da notificação',
                        prefixIcon: Icon(Icons.music_note_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'campainha',
                          child: Text('Campainha'),
                        ),
                        const DropdownMenuItem(
                          value: 'urgente',
                          child: Text('Alerta urgente'),
                        ),
                        const DropdownMenuItem(
                          value: 'caixa',
                          child: Text('Aviso de caixa'),
                        ),
                        const DropdownMenuItem(
                          value: 'suave',
                          child: Text('Toque suave'),
                        ),
                        if (PedidosWebBrowser.temAudioPersonalizado)
                          const DropdownMenuItem(
                            value: 'personalizado',
                            child: Text('Áudio personalizado'),
                          ),
                      ],
                      onChanged: ativo
                          ? (valor) {
                              if (valor != null) {
                                setDialogState(() => som = valor);
                              }
                            }
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: ativo
                                ? () async {
                                    try {
                                      final nome =
                                          await PedidosWebBrowser.escolherAudioPersonalizado();
                                      if (nome == null) return;
                                      setDialogState(() {
                                        nomeAudioPersonalizado = nome;
                                        som = 'personalizado';
                                        erroAudio = null;
                                      });
                                    } catch (erro) {
                                      setDialogState(() {
                                        erroAudio = erro
                                            .toString()
                                            .replaceFirst('Bad state: ', '');
                                      });
                                    }
                                  }
                                : null,
                            icon: const Icon(Icons.upload_file_outlined),
                            label: Text(
                              nomeAudioPersonalizado.isEmpty
                                  ? 'Enviar áudio'
                                  : 'Trocar áudio',
                            ),
                          ),
                        ),
                        if (nomeAudioPersonalizado.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            tooltip: 'Remover áudio personalizado',
                            onPressed: ativo
                                ? () {
                                    PedidosWebBrowser.removerAudioPersonalizado();
                                    setDialogState(() {
                                      nomeAudioPersonalizado = '';
                                      if (som == 'personalizado') {
                                        som = 'campainha';
                                      }
                                      erroAudio = null;
                                    });
                                  }
                                : null,
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ],
                    ),
                    if (nomeAudioPersonalizado.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        nomeAudioPersonalizado,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF475467),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (erroAudio != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        erroAudio!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Icon(Icons.volume_down_outlined),
                        Expanded(
                          child: Slider(
                            value: volume,
                            divisions: 10,
                            label: '${(volume * 100).round()}%',
                            onChanged: ativo
                                ? (valor) {
                                    setDialogState(() => volume = valor);
                                  }
                                : null,
                          ),
                        ),
                        const Icon(Icons.volume_up_outlined),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: ativo
                            ? () => PedidosWebBrowser.tocarAlertaNovoPedido(
                                som: som,
                                volume: volume,
                                ignorarDesativado: true,
                              )
                            : null,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Testar toque'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'A configuração fica salva neste navegador. Use Testar toque uma vez para liberar o áudio no computador.',
                      style: TextStyle(color: Color(0xFF667085), fontSize: 12),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    PedidosWebBrowser.salvarConfiguracaoSom(
                      ativo: ativo,
                      som: som,
                      volume: volume,
                    );
                    Navigator.pop(dialogContext);
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _iniciar() async {
    await _carregarPedidos();
    _assinarAtualizacoes();
    _timer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _carregarPedidos(silencioso: true),
    );
  }

  void _assinarAtualizacoes() {
    final cliente = SessaoLoja.supabaseLoja;
    final mercadoId = SessaoLoja.mercadoId;
    if (cliente == null || mercadoId == null || mercadoId.isEmpty) return;

    _canal = cliente
        .channel('pedidos-web-$mercadoId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pedidos',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'mercado_id',
            value: mercadoId,
          ),
          callback: (_) => _carregarPedidos(silencioso: true),
        )
        .subscribe();
  }

  Future<void> _carregarPedidos({bool silencioso = false}) async {
    final cliente = SessaoLoja.supabaseLoja;
    if (cliente == null || _consultaEmAndamento) return;

    _consultaEmAndamento = true;

    if (!silencioso && mounted) setState(() => _carregando = true);
    if (silencioso && mounted) setState(() => _atualizando = true);

    try {
      dynamic resposta;
      try {
        resposta = await cliente
            .from('pedidos')
            .select('*, pedido_itens(id)')
            .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
            .order('criado_em', ascending: false)
            .limit(500);
      } catch (_) {
        // Mantem o painel funcional em bases antigas sem o relacionamento
        // exposto no PostgREST. Nesse caso, a quantidade de itens fica oculta.
        resposta = await cliente
            .from('pedidos')
            .select()
            .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
            .order('criado_em', ascending: false)
            .limit(500);
      }

      final pedidosCarregados = List<Map<String, dynamic>>.from(resposta);
      final idsAtuais = pedidosCarregados
          .map((pedido) => pedido['id']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final recebeuPedidoNovo =
          _pedidosInicializados &&
          pedidosCarregados.any((pedido) {
            final id = pedido['id']?.toString().trim() ?? '';
            return id.isNotEmpty &&
                !_idsPedidosConhecidos.contains(id) &&
                _statusPedido(pedido) == 'novo';
          });

      if (!mounted) return;
      setState(() {
        _pedidos = pedidosCarregados;
        _idsPedidosConhecidos = idsAtuais;
        _pedidosInicializados = true;
        _erro = null;
      });

      if (recebeuPedidoNovo) {
        unawaited(PedidosWebBrowser.tocarAlertaNovoPedido());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = CentralService.mensagemErroUsuario(e));
    } finally {
      _consultaEmAndamento = false;
      if (mounted) {
        setState(() {
          _carregando = false;
          _atualizando = false;
        });
      }
    }
  }

  int _quantidadeStatus(String status) {
    if (status == 'todos') return _pedidos.length;
    return _pedidos.where((pedido) => _statusPedido(pedido) == status).length;
  }

  List<Map<String, dynamic>> get _pedidosFiltrados {
    final termo = _buscaController.text.trim().toLowerCase();

    final filtrados = _pedidos.where((pedido) {
      if (SessaoLoja.usuarioEntregador &&
          _statusPedido(pedido) != 'saiu_para_entrega') {
        return false;
      }
      if (_statusSelecionado != 'todos' &&
          _statusPedido(pedido) != _statusSelecionado) {
        return false;
      }
      if (termo.isEmpty) return true;

      return [
        pedido['numero_pedido'],
        pedido['cliente_nome'],
        pedido['cliente_telefone'],
        pedido['responsavel_nome'],
      ].any((valor) => valor?.toString().toLowerCase().contains(termo) == true);
    }).toList();

    filtrados.sort((a, b) {
      final dataA = DateTime.tryParse(a['criado_em']?.toString() ?? '');
      final dataB = DateTime.tryParse(b['criado_em']?.toString() ?? '');
      if (dataA == null && dataB == null) return 0;
      if (dataA == null) return 1;
      if (dataB == null) return -1;
      return dataB.compareTo(dataA);
    });
    return filtrados;
  }

  Future<bool> _atualizarStatus(
    String pedidoId,
    String novoStatus, {
    Map<String, dynamic>? dadosExtras,
  }) async {
    final cliente = SessaoLoja.supabaseLoja;
    if (cliente == null) return false;

    try {
      dynamic consulta = cliente
          .from('pedidos')
          .update({
            'status': novoStatus,
            'atualizado_em': DateTime.now().toUtc().toIso8601String(),
            ...?dadosExtras,
          })
          .eq('id', pedidoId)
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio);

      if (novoStatus == 'aceito') {
        consulta = consulta.eq('status', 'novo');
      } else if (novoStatus == 'preparando') {
        consulta = consulta.eq('status', 'aceito');
      }

      final resposta = await consulta.select('id');
      if (resposta is List && resposta.isEmpty) {
        throw Exception('Este pedido já foi atualizado por outro funcionário.');
      }

      await PushNotificationService.instance.notificarStatusPedido(
        pedidoId: pedidoId,
      );
      await _carregarPedidos(silencioso: true);
      return true;
    } catch (e) {
      if (mounted) _mostrarErro(CentralService.mensagemErroUsuario(e));
      return false;
    }
  }

  Future<bool> _recusarPedido(String pedidoId) async {
    final cliente = SessaoLoja.supabaseLoja;
    if (cliente == null) return false;

    try {
      await cliente.rpc(
        'recusar_pedido_loja_app',
        params: {
          'p_pedido_id': pedidoId,
          'p_mercado_id': SessaoLoja.mercadoIdObrigatorio,
          'p_motivo': 'Pedido recusado pela loja',
        },
      );
      await PushNotificationService.instance.notificarStatusPedido(
        pedidoId: pedidoId,
      );
      await _carregarPedidos(silencioso: true);
      return true;
    } catch (e) {
      if (mounted) _mostrarErro(CentralService.mensagemErroUsuario(e));
      return false;
    }
  }

  Future<void> _abrirMapa(String? url) async {
    final texto = url?.trim() ?? '';
    if (texto.isEmpty) {
      _mostrarErro('Este pedido não possui localização enviada.');
      return;
    }
    await launchUrl(Uri.parse(texto), mode: LaunchMode.externalApplication);
  }

  Future<void> _abrirDetalhes(Map<String, dynamic> pedido) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DetalhesPedidoWebPage(
          pedido: pedido,
          onAbrirMapa: _abrirMapa,
          onAtualizarStatus: _atualizarStatus,
          onRecusarPedido: _recusarPedido,
        ),
      ),
    );
    await _carregarPedidos(silencioso: true);
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.sizeOf(context).width;
    final compacto = largura < 850;

    return Scaffold(
      body: Row(
        children: [
          if (!compacto) _barraLateral(),
          Expanded(
            child: Column(
              children: [
                _cabecalho(compacto: compacto),
                Expanded(
                  child: _carregando
                      ? const Center(child: CircularProgressIndicator())
                      : _conteudo(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _barraLateral() {
    final statusDisponiveis = SessaoLoja.usuarioEntregador
        ? _status.where((item) => item.codigo == 'saiu_para_entrega').toList()
        : _status;

    return Container(
      width: 264,
      color: const Color(0xFF111827),
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _MarcaVupt(clara: true),
          const SizedBox(height: 30),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'PEDIDOS',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final item in statusDisponiveis) _itemMenu(item),
          const Spacer(),
          if (_podeOferecerAplicativo) ...[
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              leading: Icon(_iconeAplicativo, color: const Color(0xFFCBD5E1)),
              title: Text(
                _rotuloAplicativo,
                style: const TextStyle(color: Color(0xFFE2E8F0)),
              ),
              onTap: () => _obterAplicativoAdmin(
                context,
                SessaoLoja.mercadoCodigo ?? '',
              ),
            ),
            const SizedBox(height: 4),
          ],
          const Divider(color: Color(0xFF334155)),
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            leading: const Icon(Icons.logout, color: Color(0xFFCBD5E1)),
            title: const Text(
              'Sair',
              style: TextStyle(color: Color(0xFFE2E8F0)),
            ),
            onTap: widget.onSair,
          ),
        ],
      ),
    );
  }

  Widget _itemMenu(_StatusPedidoWeb item) {
    final selecionado = _statusSelecionado == item.codigo;
    final cor = SessaoLoja.corPrimaria;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selecionado ? cor : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: () => setState(() => _statusSelecionado = item.codigo),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            child: Row(
              children: [
                Icon(
                  item.icone,
                  color: selecionado ? Colors.white : const Color(0xFFCBD5E1),
                  size: 20,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    item.rotulo,
                    style: TextStyle(
                      color: selecionado
                          ? Colors.white
                          : const Color(0xFFE2E8F0),
                      fontWeight: selecionado
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 25),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: selecionado
                        ? Colors.white.withValues(alpha: 0.20)
                        : const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_quantidadeStatus(item.codigo)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
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

  Widget _cabecalho({required bool compacto}) {
    return Container(
      height: 76,
      padding: EdgeInsets.symmetric(horizontal: compacto ? 16 : 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          if (compacto) ...[
            PopupMenuButton<String>(
              tooltip: 'Filtrar pedidos',
              icon: const Icon(Icons.menu),
              onSelected: (valor) => setState(() => _statusSelecionado = valor),
              itemBuilder: (_) => _status
                  .where(
                    (item) =>
                        !SessaoLoja.usuarioEntregador ||
                        item.codigo == 'saiu_para_entrega',
                  )
                  .map(
                    (item) => PopupMenuItem(
                      value: item.codigo,
                      child: Text(
                        '${item.rotulo} (${_quantidadeStatus(item.codigo)})',
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  SessaoLoja.mercadoNome ?? 'Pedidos',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  _status
                      .firstWhere(
                        (item) => item.codigo == _statusSelecionado,
                        orElse: () => _status.first,
                      )
                      .rotulo,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (_atualizando)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (compacto && _podeOferecerAplicativo)
            IconButton(
              tooltip: _rotuloAplicativo,
              onPressed: () => _obterAplicativoAdmin(
                context,
                SessaoLoja.mercadoCodigo ?? '',
              ),
              icon: Icon(_iconeAplicativo),
            ),
          IconButton(
            tooltip: 'Atualizar pedidos',
            onPressed: _atualizando
                ? null
                : () => _carregarPedidos(silencioso: true),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Configurar som de novos pedidos',
            onPressed: _abrirConfiguracaoSom,
            icon: const Icon(Icons.volume_up_outlined),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 18,
            backgroundColor: SessaoLoja.corPrimaria.withValues(alpha: 0.12),
            child: Text(
              _inicialUsuario(),
              style: TextStyle(
                color: SessaoLoja.corPrimaria,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (!compacto) ...[
            const SizedBox(width: 9),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                SessaoLoja.usuarioNome ?? SessaoLoja.usuarioLogin ?? 'Usuário',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _conteudo() {
    final pedidos = _pedidosFiltrados;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _resumo(
                    'novo',
                    'Aguardando',
                    _quantidadeStatus('novo'),
                    Icons.notifications_active_outlined,
                    const Color(0xFFDC2626),
                  ),
                  _resumo(
                    'preparando',
                    'Em preparação',
                    _quantidadeStatus('preparando'),
                    Icons.inventory_2_outlined,
                    const Color(0xFF2563EB),
                  ),
                  _resumo(
                    'saiu_para_entrega',
                    'Em entrega',
                    _quantidadeStatus('saiu_para_entrega'),
                    Icons.local_shipping_outlined,
                    const Color(0xFF7C3AED),
                  ),
                  _resumo(
                    'entregue',
                    'Entregues',
                    _quantidadeStatus('entregue'),
                    Icons.check_circle_outline,
                    const Color(0xFF16A34A),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _buscaController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Buscar por pedido, cliente, telefone ou responsável',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  if (_buscaController.text.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Limpar busca',
                      onPressed: () {
                        _buscaController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ],
              ),
              if (_erro != null) ...[
                const SizedBox(height: 14),
                _avisoErro(_erro!),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    '${pedidos.length} ${pedidos.length == 1 ? 'pedido' : 'pedidos'}',
                    style: const TextStyle(
                      color: Color(0xFF344054),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Atualização automática',
                    style: TextStyle(color: Color(0xFF667085), fontSize: 12),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.circle, color: Color(0xFF16A34A), size: 8),
                ],
              ),
              const SizedBox(height: 10),
              if (pedidos.isEmpty) _vazio() else _tabelaPedidos(pedidos),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resumo(
    String status,
    String titulo,
    int valor,
    IconData icone,
    Color cor,
  ) {
    final selecionado = _statusSelecionado == status;

    return Semantics(
      button: true,
      selected: selecionado,
      label: 'Filtrar por $titulo, $valor pedidos',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _statusSelecionado = status),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 205,
            height: 86,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selecionado ? cor.withValues(alpha: 0.06) : Colors.white,
              border: Border.all(
                color: selecionado ? cor : const Color(0xFFE5E7EB),
                width: selecionado ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(icone, color: cor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$valor',
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabelaPedidos(List<Map<String, dynamic>> pedidos) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 700;
        final mostrarHorario = constraints.maxWidth >= 820;
        final mostrarAcao = constraints.maxWidth >= 980;

        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                if (!compacto)
                  _cabecalhoTabela(
                    mostrarHorario: mostrarHorario,
                    mostrarAcao: mostrarAcao,
                  ),
                for (var indice = 0; indice < pedidos.length; indice++) ...[
                  if (indice > 0)
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  if (compacto)
                    _linhaPedidoCompacta(pedidos[indice])
                  else
                    _linhaPedidoTabela(
                      pedidos[indice],
                      mostrarHorario: mostrarHorario,
                      mostrarAcao: mostrarAcao,
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cabecalhoTabela({
    required bool mostrarHorario,
    required bool mostrarAcao,
  }) {
    return Container(
      height: 46,
      padding: const EdgeInsets.only(left: 20, right: 16),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          _tituloColuna('PEDIDO', flex: 12),
          _tituloColuna('CLIENTE', flex: 26),
          if (mostrarHorario) _tituloColuna('HORÁRIO', flex: 12),
          _tituloColuna('STATUS', flex: 19),
          _tituloColuna('TOTAL', flex: 14),
          if (mostrarAcao) _tituloColuna('AÇÃO', flex: 13),
        ],
      ),
    );
  }

  Widget _tituloColuna(String texto, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        texto,
        style: const TextStyle(
          color: Color(0xFF667085),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _linhaPedidoTabela(
    Map<String, dynamic> pedido, {
    required bool mostrarHorario,
    required bool mostrarAcao,
  }) {
    final status = _statusPedido(pedido);
    final cor = _corStatus(status);
    final numero = _texto(pedido['numero_pedido']);
    final cliente = _texto(pedido['cliente_nome']);
    final quantidadeItens = _quantidadeItensPedido(pedido);

    return SizedBox(
      height: 78,
      child: InkWell(
        onTap: () => _abrirDetalhes(pedido),
        child: Row(
          children: [
            Container(
              width: 4,
              color: status == 'novo' ? cor : Colors.transparent,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 16),
                child: Row(
                  children: [
                    Expanded(
                      flex: 12,
                      child: Text(
                        '#$numero',
                        style: const TextStyle(
                          color: Color(0xFF344054),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 26,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cliente,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF344054),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (quantidadeItens != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              '$quantidadeItens ${quantidadeItens == 1 ? 'item' : 'itens'}',
                              style: const TextStyle(
                                color: Color(0xFF667085),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (mostrarHorario)
                      Expanded(
                        flex: 12,
                        child: Text(
                          _formatarHorario(pedido['criado_em']),
                          style: const TextStyle(color: Color(0xFF475467)),
                        ),
                      ),
                    Expanded(
                      flex: 19,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _etiquetaStatus(status, cor),
                      ),
                    ),
                    Expanded(
                      flex: 14,
                      child: Text(
                        _formatarMoeda(pedido['total']),
                        style: const TextStyle(
                          color: Color(0xFF344054),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (mostrarAcao)
                      Expanded(
                        flex: 13,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => _abrirDetalhes(pedido),
                            child: const Text('Ver pedido'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linhaPedidoCompacta(Map<String, dynamic> pedido) {
    final status = _statusPedido(pedido);
    final cor = _corStatus(status);
    final numero = _texto(pedido['numero_pedido']);
    final quantidadeItens = _quantidadeItensPedido(pedido);

    return InkWell(
      onTap: () => _abrirDetalhes(pedido),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 4,
              color: status == 'novo' ? cor : Colors.transparent,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '#$numero',
                          style: const TextStyle(
                            color: Color(0xFF344054),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        _etiquetaStatus(status, cor),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _texto(pedido['cliente_nome']),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF344054),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Text(
                          quantidadeItens == null
                              ? _formatarHorario(pedido['criado_em'])
                              : '$quantidadeItens ${quantidadeItens == 1 ? 'item' : 'itens'} · ${_formatarHorario(pedido['criado_em'])}',
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatarMoeda(pedido['total']),
                          style: TextStyle(
                            color: SessaoLoja.corPrimaria,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right,
                          color: Color(0xFF98A2B3),
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
    );
  }

  Widget _etiquetaStatus(String status, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        _rotuloStatus(status),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _vazio() {
    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, color: Color(0xFF98A2B3), size: 42),
            SizedBox(height: 12),
            Text(
              'Nenhum pedido encontrado',
              style: TextStyle(
                color: Color(0xFF475467),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avisoErro(String mensagem) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        border: Border.all(color: const Color(0xFFFECACA)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFDC2626)),
          const SizedBox(width: 9),
          Expanded(child: Text(mensagem)),
          TextButton(
            onPressed: _carregarPedidos,
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  String _inicialUsuario() {
    final nome = SessaoLoja.usuarioNome?.trim() ?? '';
    final login = SessaoLoja.usuarioLogin?.trim() ?? '';
    final texto = nome.isNotEmpty ? nome : login;
    return texto.isEmpty ? 'U' : texto.substring(0, 1).toUpperCase();
  }

  String _statusPedido(Map<String, dynamic> pedido) {
    final status = pedido['status']?.toString().trim().toLowerCase() ?? '';
    if (status == 'em_preparacao' || status == 'em preparação') {
      return 'preparando';
    }
    if (status == 'pedido_aceito') return 'aceito';
    if (status == 'em_entrega') return 'saiu_para_entrega';
    return status.isEmpty ? 'novo' : status;
  }

  String _rotuloStatus(String status) {
    switch (status) {
      case 'novo':
        return 'Aguardando aceite';
      case 'aceito':
        return 'Aceito';
      case 'preparando':
        return 'Em preparação';
      case 'saiu_para_entrega':
        return 'Em entrega';
      case 'entregue':
        return 'Entregue';
      case 'cancelado':
        return 'Cancelado';
      default:
        return status;
    }
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'novo':
        return const Color(0xFFDC2626);
      case 'aceito':
        return const Color(0xFF0891B2);
      case 'preparando':
        return const Color(0xFF2563EB);
      case 'saiu_para_entrega':
        return const Color(0xFF7C3AED);
      case 'entregue':
        return const Color(0xFF16A34A);
      case 'cancelado':
        return const Color(0xFF64748B);
      default:
        return const Color(0xFF475467);
    }
  }

  String _texto(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? '-' : texto;
  }

  String _formatarMoeda(dynamic valor) {
    final numero = double.tryParse(valor?.toString() ?? '') ?? 0;
    return 'R\$ ${numero.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  int? _quantidadeItensPedido(Map<String, dynamic> pedido) {
    final itens = pedido['pedido_itens'];
    if (itens is List) return itens.length;

    return int.tryParse(pedido['quantidade_itens']?.toString() ?? '');
  }

  String _formatarHorario(dynamic valor) {
    final data = DateTime.tryParse(valor?.toString() ?? '')?.toLocal();
    if (data == null) return '-';
    final hora = data.hour.toString().padLeft(2, '0');
    final minuto = data.minute.toString().padLeft(2, '0');
    return '$hora:$minuto';
  }
}

class DetalhesPedidoWebPage extends StatefulWidget {
  final Map<String, dynamic> pedido;
  final Function(String?) onAbrirMapa;
  final Future<bool> Function(
    String pedidoId,
    String novoStatus, {
    Map<String, dynamic>? dadosExtras,
  })
  onAtualizarStatus;
  final Future<bool> Function(String pedidoId) onRecusarPedido;

  const DetalhesPedidoWebPage({
    super.key,
    required this.pedido,
    required this.onAbrirMapa,
    required this.onAtualizarStatus,
    required this.onRecusarPedido,
  });

  @override
  State<DetalhesPedidoWebPage> createState() => _DetalhesPedidoWebPageState();
}

class _DetalhesPedidoWebPageState extends State<DetalhesPedidoWebPage> {
  bool _carregandoItens = true;
  List<Map<String, dynamic>> _itens = [];

  @override
  void initState() {
    super.initState();
    _carregarItens();
  }

  Future<void> _carregarItens() async {
    final cliente = SessaoLoja.supabaseLoja;
    if (cliente == null) return;

    try {
      final resposta = await cliente
          .from('pedido_itens')
          .select()
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
          .eq('pedido_id', widget.pedido['id'])
          .order('nome_produto');

      if (!mounted) return;
      setState(() {
        _itens = List<Map<String, dynamic>>.from(resposta);
        _carregandoItens = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregandoItens = false);
    }
  }

  void _imprimirPedido() {
    if (_carregandoItens) return;
    PedidosWebBrowser.imprimirHtml(_htmlImpressao());
  }

  @override
  Widget build(BuildContext context) {
    final numero = _texto(widget.pedido['numero_pedido']);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
        leading: const BackButton(),
        title: Text(
          'Pedido #$numero',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: OutlinedButton.icon(
              onPressed: _carregandoItens ? null : _imprimirPedido,
              icon: _carregandoItens
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print_outlined),
              label: const Text('Imprimir pedido'),
            ),
          ),
        ],
      ),
      body: ColoredBox(
        color: const Color(0xFFF7F4FA),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: DetalhesPedidoSheet(
              pedido: widget.pedido,
              onAbrirMapa: widget.onAbrirMapa,
              onAtualizarStatus: widget.onAtualizarStatus,
              onRecusarPedido: widget.onRecusarPedido,
              modoPagina: true,
            ),
          ),
        ),
      ),
    );
  }

  String _htmlImpressao() {
    final pedido = widget.pedido;
    final numero = _escapar(_texto(pedido['numero_pedido']));
    final cliente = _escapar(_texto(pedido['cliente_nome']));
    final telefone = _escapar(_texto(pedido['cliente_telefone']));
    final status = _escapar(_rotuloStatus(pedido['status']));
    final pagamento = _escapar(_texto(pedido['forma_pagamento']));
    final entrega = _escapar(_texto(pedido['local_entrega']));
    final endereco = _escapar(_enderecoPedido(pedido));
    final observacao = _escapar(_texto(pedido['observacao']));
    final criadoEm = _escapar(_formatarDataCompleta(pedido['criado_em']));
    final logo = SessaoLoja.logoUrl?.trim() ?? '';
    final logoHtml = logo.isEmpty
        ? ''
        : '<img class="logo" src="${_escaparAtributo(logo)}" alt="Logo da loja">';

    final linhas = _itens.map((item) {
      final nome = _escapar(_texto(item['nome_produto']));
      final ean = _escapar(
        _texto(item['ean'] ?? item['codigo_barras'] ?? item['produto_ean']),
      );
      final quantidade = _numero(
        item['quantidade'] ?? item['qtd'] ?? item['quantidade_pedida'],
      );
      final unidade = _escapar(_texto(item['unidade']));
      final unitario = _numero(
        item['preco_unitario'] ?? item['preco'] ?? item['valor_unitario'],
      );
      final totalItem = _numero(
        item['subtotal'] ?? item['total'] ?? item['valor_total'],
        padrao: quantidade * unitario,
      );

      return '''
        <tr>
          <td><strong>$nome</strong><small>EAN: $ean</small></td>
          <td class="centro">${_formatarQuantidade(quantidade)} $unidade</td>
          <td class="direita">${_moeda(unitario)}</td>
          <td class="direita"><strong>${_moeda(totalItem)}</strong></td>
        </tr>
      ''';
    }).join();

    return '''
<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <title>Pedido #$numero</title>
  <style>
    @page { size: A4; margin: 14mm; }
    * { box-sizing: border-box; }
    body { font-family: Arial, sans-serif; color: #111827; margin: 0; font-size: 12px; }
    header { display: flex; align-items: center; justify-content: space-between; gap: 24px; border-bottom: 2px solid #111827; padding-bottom: 14px; }
    .logo { max-width: 170px; max-height: 78px; object-fit: contain; }
    h1 { margin: 0 0 4px; font-size: 25px; }
    h2 { font-size: 15px; margin: 20px 0 8px; }
    p { margin: 3px 0; line-height: 1.4; }
    .status { display: inline-block; margin-top: 6px; padding: 5px 9px; border: 1px solid #d1d5db; border-radius: 4px; font-weight: 700; }
    .dados { display: grid; grid-template-columns: 1fr 1fr; gap: 12px 28px; margin-top: 16px; }
    .bloco { border: 1px solid #d1d5db; padding: 10px; border-radius: 5px; }
    .rotulo { color: #6b7280; font-size: 10px; text-transform: uppercase; font-weight: 700; }
    table { width: 100%; border-collapse: collapse; margin-top: 8px; }
    th { background: #f3f4f6; text-align: left; padding: 8px; border-bottom: 1px solid #9ca3af; }
    td { padding: 9px 8px; border-bottom: 1px solid #e5e7eb; vertical-align: top; }
    small { display: block; color: #6b7280; margin-top: 3px; }
    .centro { text-align: center; white-space: nowrap; }
    .direita { text-align: right; white-space: nowrap; }
    .totais { margin: 16px 0 0 auto; width: 300px; }
    .total-linha { display: flex; justify-content: space-between; padding: 5px 0; }
    .total-final { border-top: 2px solid #111827; margin-top: 5px; padding-top: 8px; font-size: 17px; font-weight: 800; }
    footer { margin-top: 28px; color: #6b7280; text-align: center; font-size: 10px; }
  </style>
</head>
<body>
  <header>
    <div>
      <h1>Pedido #$numero</h1>
      <p><strong>${_escapar(SessaoLoja.mercadoNome ?? 'Loja')}</strong></p>
      <p>Realizado em $criadoEm</p>
      <span class="status">$status</span>
    </div>
    $logoHtml
  </header>

  <section class="dados">
    <div class="bloco"><div class="rotulo">Cliente</div><p><strong>$cliente</strong></p><p>$telefone</p></div>
    <div class="bloco"><div class="rotulo">Entrega</div><p><strong>$entrega</strong></p><p>$endereco</p></div>
    <div class="bloco"><div class="rotulo">Pagamento</div><p><strong>$pagamento</strong></p></div>
    <div class="bloco"><div class="rotulo">Observação</div><p>$observacao</p></div>
  </section>

  <h2>Itens do pedido</h2>
  <table>
    <thead><tr><th>Produto</th><th class="centro">Quantidade</th><th class="direita">Unitário</th><th class="direita">Total</th></tr></thead>
    <tbody>$linhas</tbody>
  </table>

  <section class="totais">
    <div class="total-linha"><span>Subtotal</span><strong>${_moeda(_numero(pedido['subtotal'] ?? pedido['subtotal_produtos']))}</strong></div>
    <div class="total-linha"><span>Desconto</span><strong>${_moeda(_numero(pedido['desconto'] ?? pedido['valor_desconto']))}</strong></div>
    <div class="total-linha"><span>Taxa de entrega</span><strong>${_moeda(_numero(pedido['taxa_entrega'] ?? pedido['taxa_entrega_calculada']))}</strong></div>
    <div class="total-linha total-final"><span>Total</span><span>${_moeda(_numero(pedido['total']))}</span></div>
  </section>

  <footer>Impresso pelo Vupt Pedidos em ${_formatarDataCompleta(DateTime.now().toIso8601String())}</footer>
  <script>window.addEventListener('load', function () { setTimeout(function () { window.print(); }, 350); });</script>
</body>
</html>
''';
  }

  String _rotuloStatus(dynamic valor) {
    final status = valor?.toString().trim().toLowerCase() ?? '';
    switch (status) {
      case 'novo':
        return 'Aguardando aceite';
      case 'aceito':
      case 'pedido_aceito':
        return 'Pedido aceito';
      case 'preparando':
      case 'em_preparacao':
        return 'Em preparação';
      case 'saiu_para_entrega':
      case 'em_entrega':
        return 'Em entrega';
      case 'entregue':
        return 'Entregue';
      case 'cancelado':
        return 'Cancelado';
      default:
        return status.isEmpty ? '-' : status;
    }
  }

  String _enderecoPedido(Map<String, dynamic> pedido) {
    final formatado = pedido['endereco_entrega_formatado']?.toString().trim();
    if (formatado != null && formatado.isNotEmpty) return formatado;

    return [
      [pedido['endereco'], pedido['numero']]
          .map((valor) => valor?.toString().trim() ?? '')
          .where((valor) => valor.isNotEmpty)
          .join(', '),
      [pedido['bairro'], pedido['cidade']]
          .map((valor) => valor?.toString().trim() ?? '')
          .where((valor) => valor.isNotEmpty)
          .join(' - '),
      pedido['referencia']?.toString().trim() ?? '',
    ].where((valor) => valor.isNotEmpty).join(' | ');
  }

  String _texto(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? '-' : texto;
  }

  double _numero(dynamic valor, {double padrao = 0}) {
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ??
        padrao;
  }

  String _moeda(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String _formatarQuantidade(double valor) {
    if (valor == valor.roundToDouble()) return valor.toInt().toString();
    return valor
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r',$'), '')
        .replaceAll('.', ',');
  }

  String _formatarDataCompleta(dynamic valor) {
    final data = DateTime.tryParse(valor?.toString() ?? '')?.toLocal();
    if (data == null) return '-';
    String dois(int numero) => numero.toString().padLeft(2, '0');
    return '${dois(data.day)}/${dois(data.month)}/${data.year} às ${dois(data.hour)}:${dois(data.minute)}';
  }

  String _escapar(String valor) {
    return valor
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  String _escaparAtributo(String valor) => _escapar(valor);
}

class _StatusPedidoWeb {
  final String codigo;
  final String rotulo;
  final IconData icone;

  const _StatusPedidoWeb(this.codigo, this.rotulo, this.icone);
}

class _MarcaVupt extends StatelessWidget {
  final bool clara;

  const _MarcaVupt({this.clara = false});

  @override
  Widget build(BuildContext context) {
    final nomeMercado = SessaoLoja.mercadoNome?.trim() ?? '';
    final titulo = nomeMercado.isEmpty ? 'Vupt Pedidos' : nomeMercado;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: SessaoLoja.corPrimaria,
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(
            Icons.receipt_long_outlined,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 11),
        Flexible(
          child: Text(
            titulo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: clara ? Colors.white : const Color(0xFF111827),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _EstadoCentral extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String? mensagem;
  final bool carregando;
  final Future<void> Function()? onTentarNovamente;

  const _EstadoCentral({
    required this.icone,
    required this.titulo,
    this.mensagem,
    this.carregando = false,
    this.onTentarNovamente,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icone, size: 48, color: const Color(0xFF667085)),
                const SizedBox(height: 18),
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (mensagem != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    mensagem!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      height: 1.4,
                    ),
                  ),
                ],
                if (carregando) ...[
                  const SizedBox(height: 22),
                  const CircularProgressIndicator(),
                ],
                if (onTentarNovamente != null) ...[
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: onTentarNovamente,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _corHex(String? valor, Color padrao) {
  final texto = valor?.replaceAll('#', '').trim() ?? '';
  final numero = int.tryParse(texto, radix: 16);
  return numero == null ? padrao : Color(0xFF000000 | numero);
}

// BUSCAR-BRANDING-MERCADO-ADMIN - LOGO, NOME, HINT E CORES DINAMICAS DA CENTRAL
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/central_service.dart';
import '../../services/sessao_loja.dart';
import '../loja/menu_inicial.dart';
import 'verificar_perfil_page.dart';

class LoginCentralPage extends StatefulWidget {
  const LoginCentralPage({super.key});

  @override
  State<LoginCentralPage> createState() => _LoginCentralPageState();
}

class _LoginCentralPageState extends State<LoginCentralPage> {
  final CentralService service = CentralService();

  final codigoLojaController = TextEditingController();
  final loginController = TextEditingController();
  final senhaController = TextEditingController();

  bool inicializandoAcesso = true;
  bool carregandoSelecaoLoja = false;
  bool carregando = false;
  bool carregandoBranding = false;
  bool senhaVisivel = false;

  String? mercadoCodigoSelecionado;
  String? tituloLoginCentral;
  String? logoLoginUrlCentral;
  String? mercadoCodigoCentral;

  String adminCorPrimariaHex = '#E30613';
  String adminCorSecundariaHex = '#C90010';
  String adminCorFundoHex = '#F5F7FA';

  int versaoLogo = DateTime.now().millisecondsSinceEpoch;

  static const String mercadoCodigoDefine = String.fromEnvironment(
    'MERCADO_CODIGO',
    defaultValue: '',
  );

  static const String mercadoIdDefine = String.fromEnvironment(
    'MERCADO_ID',
    defaultValue: '',
  );

  static const String nomeAppDefine = String.fromEnvironment(
    'NOME_APP',
    defaultValue: '',
  );

  static const String appNameDefine = String.fromEnvironment(
    'APP_NAME',
    defaultValue: '',
  );

  static const String appPackageDefine = String.fromEnvironment(
    'APP_PACKAGE',
    defaultValue: '',
  );

  static const String adminAppNameDefine = String.fromEnvironment(
    'ADMIN_APP_NAME',
    defaultValue: '',
  );

  static const String _chaveMercadoCodigoSelecionado =
      'vupt_admin_mercado_codigo_selecionado_v1';

  bool get modoVuptMultiLoja =>
      !kIsWeb &&
      mercadoCodigoDefine.trim().isEmpty &&
      mercadoIdDefine.trim().isEmpty;

  String get mercadoCodigoEfetivo =>
      primeiroTexto([mercadoCodigoSelecionado, mercadoCodigoDefine]);

  String get tituloLogin {
    final tituloCentral = tituloLoginCentral?.trim() ?? '';

    if (tituloCentral.isNotEmpty) {
      return tituloCentral;
    }

    final adminAppName = adminAppNameDefine.trim();

    if (adminAppName.isNotEmpty) {
      return adminAppName;
    }

    final nomeApp = nomeAppDefine.trim();

    if (nomeApp.isNotEmpty) {
      return nomeApp;
    }

    final appName = appNameDefine.trim();

    if (appName.isNotEmpty) {
      return appName;
    }

    return 'Admin Geral';
  }

  String get hintLogin {
    final codigo = primeiroTexto([
      mercadoCodigoCentral,
      mercadoCodigoSelecionado,
      mercadoCodigoDefine,
    ]);

    if (codigo.isEmpty) {
      return 'Ex: seu_login';
    }

    final codigoFormatado = codigo
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    if (codigoFormatado.isEmpty) {
      return 'Ex: seu_login';
    }

    return 'Ex: admin_$codigoFormatado';
  }

  @override
  void initState() {
    super.initState();
    inicializarAcessoAdmin();
  }

  @override
  void dispose() {
    codigoLojaController.dispose();
    loginController.dispose();
    senhaController.dispose();
    super.dispose();
  }

  String normalizarCodigoLoja(String valor) {
    return valor
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  Future<void> inicializarAcessoAdmin() async {
    if (!modoVuptMultiLoja) {
      inicializandoAcesso = false;
      await carregarBrandingAdmin();
      return;
    }

    String codigoSalvo = '';

    try {
      final preferencias = await SharedPreferences.getInstance();
      codigoSalvo = normalizarCodigoLoja(
        preferencias.getString(_chaveMercadoCodigoSelecionado) ?? '',
      );
    } catch (e) {
      debugPrint('VUPT ADMIN - falha ao restaurar loja selecionada: $e');
    }

    if (!mounted) return;

    setState(() {
      mercadoCodigoSelecionado = codigoSalvo.isEmpty ? null : codigoSalvo;
      codigoLojaController.text = codigoSalvo;
      inicializandoAcesso = false;
    });

    if (codigoSalvo.isNotEmpty) {
      final brandingCarregado = await carregarBrandingLojaSelecionada();

      if (!brandingCarregado && mounted) {
        await trocarLoja();
      }
    }
  }

  String mensagemErroCodigoLoja(Object erro) {
    final mensagem = erro.toString().toLowerCase();

    if (mensagem.contains('not found') ||
        mensagem.contains('não encontrado') ||
        mensagem.contains('nao encontrado') ||
        mensagem.contains('status: 404')) {
      return 'Código da loja não encontrado. Confira o código informado.';
    }

    if (mensagem.contains('socketexception') ||
        mensagem.contains('failed host lookup') ||
        mensagem.contains('connection refused') ||
        mensagem.contains('network')) {
      return CentralService.mensagemSemInternet;
    }

    if (mensagem.contains('não está disponível') ||
        mensagem.contains('nao esta disponivel') ||
        mensagem.contains('desativada') ||
        mensagem.contains('inativa') ||
        mensagem.contains('bloqueada')) {
      return erro.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    }

    return 'Não foi possível validar o código da loja. Tente novamente.';
  }

  Future<void> selecionarLoja() async {
    final codigo = normalizarCodigoLoja(codigoLojaController.text);

    if (codigo.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Informe o código da loja')));
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      carregandoSelecaoLoja = true;
    });

    try {
      final resposta = await service.validarMercadoAtivo(mercadoCodigo: codigo);
      final bloqueado = SessaoLoja.booleanoDinamico(resposta['bloqueado']);
      final ativo = SessaoLoja.booleanoDinamico(
        resposta['ativo'],
        padrao: !bloqueado,
      );

      if (bloqueado || !ativo) {
        final mensagem =
            resposta['mensagem']?.toString().trim() ??
            'Esta loja não está disponível. Entre em contato com o suporte.';
        throw Exception(mensagem);
      }

      final codigoConfirmado = normalizarCodigoLoja(
        primeiroTexto([resposta['mercado_codigo'], resposta['codigo'], codigo]),
      );
      final preferencias = await SharedPreferences.getInstance();
      await preferencias.setString(
        _chaveMercadoCodigoSelecionado,
        codigoConfirmado,
      );

      if (!mounted) return;

      setState(() {
        mercadoCodigoSelecionado = codigoConfirmado;
        mercadoCodigoCentral = codigoConfirmado;
        tituloLoginCentral = null;
        logoLoginUrlCentral = null;
        versaoLogo = DateTime.now().millisecondsSinceEpoch;
      });

      await carregarBrandingLojaSelecionada(mercadoValidado: resposta);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagemErroCodigoLoja(e)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          carregandoSelecaoLoja = false;
        });
      }
    }
  }

  Future<void> trocarLoja() async {
    final preferencias = await SharedPreferences.getInstance();
    await preferencias.remove(_chaveMercadoCodigoSelecionado);

    if (!mounted) return;

    setState(() {
      mercadoCodigoSelecionado = null;
      mercadoCodigoCentral = null;
      tituloLoginCentral = null;
      logoLoginUrlCentral = null;
      adminCorPrimariaHex = '#E30613';
      adminCorSecundariaHex = '#C90010';
      adminCorFundoHex = '#F5F7FA';
      versaoLogo = DateTime.now().millisecondsSinceEpoch;
      codigoLojaController.clear();
      loginController.clear();
      senhaController.clear();
    });
  }

  String texto(dynamic valor) {
    if (valor == null) {
      return '';
    }

    return valor.toString().trim();
  }

  String primeiroTexto(List<dynamic> valores) {
    for (final valor in valores) {
      final convertido = texto(valor);

      if (convertido.isNotEmpty) {
        return convertido;
      }
    }

    return '';
  }

  String corHex(dynamic valor, String padrao) {
    var textoCor = texto(valor);

    if (textoCor.isEmpty) {
      textoCor = padrao;
    }

    if (!textoCor.startsWith('#')) {
      textoCor = '#$textoCor';
    }

    textoCor = textoCor.toUpperCase();

    final valido = RegExp(r'^#[0-9A-F]{6}$').hasMatch(textoCor);

    return valido ? textoCor : padrao;
  }

  Future<bool> carregarBrandingLojaSelecionada({
    Map<String, dynamic>? mercadoValidado,
  }) async {
    final codigo = mercadoCodigoEfetivo;

    if (codigo.isEmpty) {
      return false;
    }

    if (mounted) {
      setState(() {
        carregandoBranding = true;
      });
    }

    try {
      final dados =
          mercadoValidado ??
          await service.validarMercadoAtivo(mercadoCodigo: codigo);
      final bloqueado = SessaoLoja.booleanoDinamico(dados['bloqueado']);
      final ativo = SessaoLoja.booleanoDinamico(
        dados['ativo'],
        padrao: !bloqueado,
      );

      if (bloqueado || !ativo) {
        throw Exception(
          dados['mensagem']?.toString().trim() ??
              'Esta loja não está disponível.',
        );
      }

      final codigoConfirmado = normalizarCodigoLoja(
        primeiroTexto([dados['mercado_codigo'], dados['codigo'], codigo]),
      );
      final titulo = primeiroTexto([
        dados['titulo_admin'],
        dados['admin_app_nome'],
        dados['mercado_nome'],
        dados['nome'],
      ]);
      final logo = primeiroTexto([
        dados['admin_logo_url'],
        dados['logo_admin_url'],
        dados['logo_login_url'],
        dados['logo_url'],
      ]);
      final corPrimaria = corHex(dados['admin_cor_primaria'], '#E30613');
      final corSecundaria = corHex(dados['admin_cor_secundaria'], '#C90010');
      final corFundoResposta = corHex(dados['admin_cor_fundo'], '#F5F7FA');

      if (!mounted) {
        return false;
      }

      setState(() {
        mercadoCodigoSelecionado = codigoConfirmado;
        mercadoCodigoCentral = codigoConfirmado;
        tituloLoginCentral = titulo.isEmpty ? null : titulo;
        logoLoginUrlCentral = logo.isEmpty ? null : logo;
        adminCorPrimariaHex = corPrimaria;
        adminCorSecundariaHex = corSecundaria;
        adminCorFundoHex = corFundoResposta;
        versaoLogo = DateTime.now().millisecondsSinceEpoch;
      });

      return true;
    } catch (e) {
      debugPrint(
        'VUPT ADMIN - falha ao carregar identidade da loja selecionada: '
        '${CentralService.mensagemErroUsuario(e)}',
      );
      return false;
    } finally {
      if (mounted) {
        setState(() {
          carregandoBranding = false;
        });
      }
    }
  }

  Color corHexParaColor(String hex, Color fallback) {
    final cor = corHex(hex, '');
    if (cor.isEmpty) {
      return fallback;
    }

    try {
      return Color(int.parse('FF${cor.substring(1)}', radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  Color get corPrimaria =>
      corHexParaColor(adminCorPrimariaHex, const Color(0xFFE30613));

  Color get corSecundaria =>
      corHexParaColor(adminCorSecundariaHex, const Color(0xFFC90010));

  Color get corFundo =>
      corHexParaColor(adminCorFundoHex, const Color(0xFFF5F7FA));

  String mensagemErroLogin(Object erro) {
    final textoErro = erro.toString();
    final erroMinusculo = textoErro.toLowerCase();

    if (erro is AuthException) {
      final mensagemAuth = erro.message.toLowerCase();
      final codigoAuth = erro.code?.toLowerCase() ?? '';

      if (mensagemAuth.contains('invalid login credentials') ||
          codigoAuth.contains('invalid_credentials')) {
        return 'Senha incorreta. Confira sua senha e tente novamente.';
      }
    }

    if (erroMinusculo.contains('login não encontrado') ||
        erroMinusculo.contains('login nao encontrado') ||
        erroMinusculo.contains('usuário inativo') ||
        erroMinusculo.contains('usuario inativo') ||
        erroMinusculo.contains('not found') ||
        erroMinusculo.contains('status: 404')) {
      return 'Login não cadastrado ou usuário inativo. Confira o login ou fale com o administrador.';
    }

    if (erroMinusculo.contains('invalid login credentials') ||
        erroMinusculo.contains('invalid_credentials')) {
      return 'Senha incorreta. Confira sua senha e tente novamente.';
    }

    if (erroMinusculo.contains('e-mail de autenticação') ||
        erroMinusculo.contains('email de autenticacao')) {
      return 'Não foi possível validar esse usuário. Fale com o administrador da loja.';
    }

    if (erroMinusculo.contains('socketexception') ||
        erroMinusculo.contains('failed host lookup') ||
        erroMinusculo.contains('connection refused') ||
        erroMinusculo.contains('network')) {
      return CentralService.mensagemSemInternet;
    }

    return 'Não foi possível entrar. Confira o login e a senha.';
  }

  String urlSemCache(String url) {
    final separador = url.contains('?') ? '&' : '?';
    return '$url${separador}v=$versaoLogo';
  }

  dynamic normalizarRespostaBranding(dynamic data) {
    if (data is String) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return data;
      }
    }

    if (data is Map && data['data'] is Map) {
      return data['data'];
    }

    return data;
  }

  Future<Map<String, String>> resolverInfoAppInstalado() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return {
        'package': primeiroTexto([appPackageDefine, packageInfo.packageName]),
        'nome': primeiroTexto([
          adminAppNameDefine,
          nomeAppDefine,
          appNameDefine,
          packageInfo.appName,
        ]),
      };
    } catch (e) {
      debugPrint(
        'BRANDING ADMIN - falha ao ler info do app instalado: ${CentralService.mensagemErroUsuario(e)}',
      );
      return {
        'package': appPackageDefine.trim(),
        'nome': primeiroTexto([
          adminAppNameDefine,
          nomeAppDefine,
          appNameDefine,
        ]),
      };
    }
  }

  Future<void> carregarBrandingAdmin() async {
    final mercadoCodigo = mercadoCodigoEfetivo;
    final mercadoId = mercadoIdDefine.trim();
    final infoApp = await resolverInfoAppInstalado();
    final appPackage = infoApp['package']?.trim() ?? '';
    final appNome = infoApp['nome']?.trim() ?? '';

    debugPrint('BRANDING ADMIN - MERCADO_CODIGO: $mercadoCodigo');
    debugPrint('BRANDING ADMIN - MERCADO_ID: $mercadoId');
    debugPrint('BRANDING ADMIN - APP_PACKAGE: $appPackage');
    debugPrint('BRANDING ADMIN - APP_NOME: $appNome');
    debugPrint(
      'BRANDING ADMIN - executando function buscar-branding-mercado-admin',
    );

    if (mounted && appNome.isNotEmpty) {
      setState(() {
        tituloLoginCentral ??= appNome;
      });
    }

    if (mercadoCodigo.isEmpty &&
        mercadoId.isEmpty &&
        appPackage.isEmpty &&
        appNome.isEmpty) {
      debugPrint(
        'BRANDING ADMIN - sem MERCADO_CODIGO/MERCADO_ID/APP_PACKAGE/APP_NOME. Usando padrão local.',
      );
      return;
    }

    if (mounted) {
      setState(() {
        carregandoBranding = true;
      });
    }

    try {
      final resposta = await Supabase.instance.client.functions.invoke(
        'buscar-branding-mercado-admin',
        body: {
          'mercado_codigo': mercadoCodigo.isEmpty ? null : mercadoCodigo,
          'mercado_id': mercadoId.isEmpty ? null : mercadoId,
          'app_package': appPackage.isEmpty ? null : appPackage,
          'app_nome': appNome.isEmpty ? null : appNome,
          'admin_app_nome': appNome.isEmpty ? null : appNome,
        },
      );

      final data = normalizarRespostaBranding(resposta.data);

      debugPrint('BRANDING ADMIN - status: ${resposta.status}');
      debugPrint('BRANDING ADMIN - resposta normalizada: $data');

      if (data is! Map) {
        debugPrint('BRANDING ADMIN - resposta inválida da function: $data');
        return;
      }

      if (data['erro'] != null) {
        debugPrint('BRANDING ADMIN - erro function: ${data['erro']}');
        return;
      }

      final titulo = primeiroTexto([
        data['titulo_admin'],
        data['admin_app_nome'],
        data['app_nome'],
        data['nome'],
      ]);

      final logo = primeiroTexto([
        data['admin_logo_url'],
        data['logo_admin_url'],
        data['logo_login_url'],
      ]);

      final codigo = primeiroTexto([data['codigo'], mercadoCodigo]);

      final corPrimaria = corHex(data['admin_cor_primaria'], '#E30613');
      final corSecundaria = corHex(data['admin_cor_secundaria'], '#C90010');
      final corFundoResposta = corHex(data['admin_cor_fundo'], '#F5F7FA');

      if (!mounted) return;

      setState(() {
        tituloLoginCentral = titulo.isEmpty ? null : titulo;
        logoLoginUrlCentral = logo.isEmpty ? null : logo;
        mercadoCodigoCentral = codigo.isEmpty ? null : codigo;
        adminCorPrimariaHex = corPrimaria;
        adminCorSecundariaHex = corSecundaria;
        adminCorFundoHex = corFundoResposta;
        versaoLogo = DateTime.now().millisecondsSinceEpoch;
      });
    } catch (e) {
      debugPrint(
        'BRANDING ADMIN - falha ao buscar branding: ${CentralService.mensagemErroUsuario(e)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          carregandoBranding = false;
        });
      }
    }
  }

  Widget logoLocal() {
    return Image.asset(
      modoVuptMultiLoja
          ? 'assets/images/logo_vupt_sistemas.jpg'
          : 'assets/images/logo.png',
      width: 160,
      height: 82,
      fit: BoxFit.contain,
      errorBuilder: (_, error, stackTrace) {
        debugPrint('BRANDING ADMIN - erro ao carregar logo local: $error');
        return Icon(Icons.storefront_rounded, color: corPrimaria, size: 54);
      },
    );
  }

  Widget logoFallbackBox() {
    return SizedBox(width: 160, height: 82, child: Center(child: logoLocal()));
  }

  Widget logoLogin() {
    final logoUrl = logoLoginUrlCentral?.trim() ?? '';

    Widget imagem;

    if (logoUrl.isEmpty) {
      imagem = logoFallbackBox();
    } else {
      imagem = Image.network(
        urlSemCache(logoUrl),
        headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
        width: 160,
        height: 82,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }

          return const SizedBox(
            width: 160,
            height: 82,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (_, error, stackTrace) {
          debugPrint('BRANDING ADMIN - erro ao carregar Image.network: $error');
          return logoFallbackBox();
        },
      );
    }

    return Container(
      width: 190,
      height: 112,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.9),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Center(child: imagem),
    );
  }

  InputDecoration decoracaoCampo({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF7F8FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE6E8EF), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: corPrimaria, width: 1.8),
      ),
    );
  }

  Future<void> entrar() async {
    final loginDigitado = loginController.text.trim();
    final senha = senhaController.text.trim();

    if (loginDigitado.isEmpty || senha.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Informe login e senha')));
      return;
    }

    setState(() {
      carregando = true;
    });

    try {
      final mercadoIdApk = mercadoIdDefine.trim();
      final mercadoCodigoApk = mercadoCodigoEfetivo;

      final dadosLogin = await service.resolverLogin(
        loginDigitado,
        mercadoId: mercadoIdApk.isEmpty ? null : mercadoIdApk,
        mercadoCodigo: mercadoCodigoApk.isEmpty ? null : mercadoCodigoApk,
      );

      final destinoAuth =
          dadosLogin['destino_auth']?.toString().trim().toLowerCase() ??
          'central';

      final emailAuth = dadosLogin['email_auth']?.toString() ?? '';

      if (emailAuth.isEmpty) {
        throw Exception('E-mail de autenticação não encontrado');
      }

      if (destinoAuth == 'loja') {
        await entrarComoUsuarioLoja(
          dadosLogin: dadosLogin,
          emailAuth: emailAuth,
          senha: senha,
        );
      } else {
        await entrarComoMaster(emailAuth: emailAuth, senha: senha);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagemErroLogin(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> entrarComoMaster({
    required String emailAuth,
    required String senha,
  }) async {
    SessaoLoja.limpar();

    await Supabase.instance.client.auth.signInWithPassword(
      email: emailAuth,
      password: senha,
    );

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const VerificarPerfilPage()),
    );
  }

  List<String> permissoesAdminLoja() {
    return [
      'pedidos',
      'consulta_preco',
      'produtos_inativos',
      'balanco',
      'lista_compras',
      'conferencia_notas',
      'estoque_entrada',
      'estoque_correcao',
      'estoque_transferencia',
      'estoque_baixa_avaria',
      'estoque_baixa_validade',
      'estoque_abrir_pacote',
      'estoque_consumo_interno',
      'estoque_auditoria',
      'acoes_validade',
      'jornal_promocoes',
      'clientes_app',
      'relatorios',
      'loja_configuracoes',
      'usuarios',
    ];
  }

  Future<List<String>> carregarPermissoesDoUsuario({
    required SupabaseClient supabaseLoja,
    required String userId,
    required String perfil,
    required Map<String, dynamic> dadosLogin,
  }) async {
    final permissoesResolver = dadosLogin['permissoes'];

    if (permissoesResolver is List) {
      final lista = permissoesResolver
          .map((item) => item.toString())
          .where((codigo) => codigo.isNotEmpty)
          .toSet()
          .toList();

      if (lista.isNotEmpty || perfil == 'admin_loja') {
        return lista;
      }
    }

    if (perfil == 'admin_loja') {
      return permissoesAdminLoja();
    }

    final mercadoId = dadosLogin['mercado_id']?.toString().trim() ?? '';

    dynamic consultaPermissoes = supabaseLoja
        .from('usuario_permissoes')
        .select('modulo_codigo, permitido')
        .eq('user_id', userId)
        .eq('permitido', true);

    if (mercadoId.isNotEmpty) {
      consultaPermissoes = consultaPermissoes.eq('mercado_id', mercadoId);
    }

    final resposta = await consultaPermissoes;

    final lista = List<Map<String, dynamic>>.from(resposta);

    return lista
        .map((permissao) => permissao['modulo_codigo']?.toString() ?? '')
        .where((codigo) => codigo.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> entrarComoUsuarioLoja({
    required Map<String, dynamic> dadosLogin,
    required String emailAuth,
    required String senha,
  }) async {
    final mercadoId = dadosLogin['mercado_id']?.toString() ?? '';
    final mercadoNome = dadosLogin['mercado_nome']?.toString() ?? '';
    final mercadoCodigo = dadosLogin['mercado_codigo']?.toString();

    final supabaseUrl = dadosLogin['supabase_url']?.toString() ?? '';
    final supabaseAnonKey = dadosLogin['supabase_anon_key']?.toString() ?? '';
    final apiBaseUrl = dadosLogin['api_base_url']?.toString();

    if (mercadoId.isEmpty || mercadoNome.isEmpty) {
      throw Exception('Dados do mercado não encontrados');
    }

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw Exception('Dados de conexão da loja não encontrados');
    }

    SessaoLoja.limpar();

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    final supabaseLoja = SupabaseClient(
      supabaseUrl,
      supabaseAnonKey,
      authOptions: const AuthClientOptions(autoRefreshToken: true),
    );

    final authResponse = await supabaseLoja.auth.signInWithPassword(
      email: emailAuth,
      password: senha,
    );

    if (authResponse.user == null || authResponse.session == null) {
      throw Exception('Usuário da loja não autenticado');
    }

    final accessToken = authResponse.session!.accessToken;
    final refreshToken = authResponse.session!.refreshToken;

    final userIdDaTabela = dadosLogin['user_id']?.toString() ?? '';
    final userIdFinal = userIdDaTabela.isNotEmpty
        ? userIdDaTabela
        : authResponse.user!.id;

    final perfil = dadosLogin['perfil']?.toString() ?? 'usuario';

    final permissoes = await carregarPermissoesDoUsuario(
      supabaseLoja: supabaseLoja,
      userId: userIdFinal,
      perfil: perfil,
      dadosLogin: dadosLogin,
    );

    SessaoLoja.configurarLoginLoja(
      id: mercadoId,
      nome: mercadoNome,
      codigo: mercadoCodigo,
      apiUrl: apiBaseUrl,
      urlSupabase: supabaseUrl,
      anonKeySupabase: supabaseAnonKey,
      userId: userIdFinal,
      userNome: dadosLogin['nome']?.toString(),
      userLogin: dadosLogin['login']?.toString(),
      userEmail: emailAuth,
      userPerfil: perfil,
      accessToken: accessToken,
      refreshToken: refreshToken,
      clienteLoja: supabaseLoja,
      permissoes: permissoes,
      fonteProdutos: dadosLogin['fonte_produtos']?.toString(),
      adminCorPrimaria:
          dadosLogin['admin_cor_primaria']?.toString() ?? adminCorPrimariaHex,
      adminCorSecundaria:
          dadosLogin['admin_cor_secundaria']?.toString() ??
          adminCorSecundariaHex,
      adminCorFundo:
          dadosLogin['admin_cor_fundo']?.toString() ?? adminCorFundoHex,
      logo: primeiroTexto([
        dadosLogin['admin_logo_url'],
        dadosLogin['logo_admin_url'],
        dadosLogin['logo_login_url'],
        logoLoginUrlCentral,
      ]),
      estoqueDetalhadoAtivo: SessaoLoja.booleanoDinamico(
        dadosLogin['estoque_detalhado_ativo'] ??
            dadosLogin['estoqueDetalhadoAtivo'],
      ),
      alterarPrecoConsultaAtivo: SessaoLoja.booleanoDinamico(
        dadosLogin['alterar_preco_consulta_ativo'] ??
            dadosLogin['alterarPrecoConsultaAtivo'],
      ),
    );

    await SessaoLoja.salvarSessaoLojaPersistida();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MenuInicialPage()),
    );
  }

  Widget marcaVuptAdmin() {
    return SizedBox(
      height: 118,
      child: Image.asset(
        'assets/images/logo_vupt_sistemas.jpg',
        fit: BoxFit.contain,
        errorBuilder: (_, error, stackTrace) {
          debugPrint('VUPT ADMIN - falha ao carregar logo local: $error');
          return const Center(
            child: Text(
              'Vupt Sistemas',
              style: TextStyle(
                color: Color(0xFF05275B),
                fontSize: 29,
                fontWeight: FontWeight.w900,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget telaIdentificarLoja() {
    const azul = Color(0xFF155EEF);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FA),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  28,
                  20,
                  28 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      marcaVuptAdmin(),
                      const SizedBox(height: 34),
                      Container(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE4E7EC)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF101828)
                                  .withValues(alpha: 0.08),
                              blurRadius: 28,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Identifique sua loja',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF101828),
                                fontSize: 25,
                                height: 1.15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 9),
                            const Text(
                              'Digite o código fornecido para acessar o painel administrativo.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF667085),
                                fontSize: 14,
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 26),
                            TextField(
                              controller: codigoLojaController,
                              autofocus: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              keyboardType: TextInputType.text,
                              textCapitalization: TextCapitalization.none,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) {
                                if (!carregandoSelecaoLoja) {
                                  selecionarLoja();
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'Código da loja',
                                hintText: 'Digite o código da loja',
                                prefixIcon: const Icon(
                                  Icons.store_mall_directory_rounded,
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF9FAFB),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFD0D5DD),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFD0D5DD),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: azul,
                                    width: 1.6,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 54,
                              child: FilledButton.icon(
                                onPressed: carregandoSelecaoLoja
                                    ? null
                                    : selecionarLoja,
                                style: FilledButton.styleFrom(
                                  backgroundColor: azul,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: azul.withValues(
                                    alpha: 0.55,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: carregandoSelecaoLoja
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.arrow_forward_rounded),
                                label: Text(
                                  carregandoSelecaoLoja
                                      ? 'Validando loja'
                                      : 'Continuar',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Vupt Sistemas e Tecnologias',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF98A2B3),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (inicializandoAcesso) {
      return const Scaffold(
        backgroundColor: Color(0xFFF3F6FA),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (modoVuptMultiLoja && mercadoCodigoEfetivo.isEmpty) {
      return telaIdentificarLoja();
    }

    return Scaffold(
      backgroundColor: corFundo,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [corPrimaria, corSecundaria, corFundo, corFundo],
            stops: [0.0, 0.26, 0.26, 1.0],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    22,
                    20,
                    22 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(34),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 30,
                                offset: const Offset(0, 18),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(child: logoLogin()),
                              const SizedBox(height: 22),
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: corPrimaria.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.admin_panel_settings_rounded,
                                        size: 16,
                                        color: corPrimaria,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'PAINEL ADMINISTRATIVO',
                                        style: TextStyle(
                                          color: corPrimaria,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                tituloLogin,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 27,
                                  height: 1.12,
                                  color: Color(0xFF1F2430),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      'Entre para gerenciar sua loja',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.black.withValues(
                                          alpha: 0.52,
                                        ),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  if (carregandoBranding) ...[
                                    const SizedBox(width: 8),
                                    const SizedBox(
                                      width: 13,
                                      height: 13,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (modoVuptMultiLoja) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    8,
                                    8,
                                    8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF7F8FA),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: const Color(0xFFE6E8EF),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: corPrimaria.withValues(
                                            alpha: 0.10,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            11,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.storefront_rounded,
                                          color: corPrimaria,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Loja selecionada',
                                              style: TextStyle(
                                                color: Color(0xFF667085),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              mercadoCodigoEfetivo,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Color(0xFF1F2430),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: carregandoBranding
                                            ? null
                                            : trocarLoja,
                                        icon: const Icon(
                                          Icons.swap_horiz_rounded,
                                          size: 18,
                                        ),
                                        label: const Text('Trocar'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 26),
                              TextField(
                                controller: loginController,
                                keyboardType: TextInputType.text,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: decoracaoCampo(
                                  label: 'Login',
                                  hint: hintLogin,
                                  icon: Icons.person_rounded,
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: senhaController,
                                obscureText: !senhaVisivel,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => entrar(),
                                decoration: decoracaoCampo(
                                  label: 'Senha',
                                  hint: 'Digite sua senha',
                                  icon: Icons.lock_rounded,
                                  suffixIcon: IconButton(
                                    onPressed: () {
                                      setState(() {
                                        senhaVisivel = !senhaVisivel;
                                      });
                                    },
                                    icon: Icon(
                                      senhaVisivel
                                          ? Icons.visibility_off_rounded
                                          : Icons.visibility_rounded,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton(
                                  onPressed: carregando ? null : entrar,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: corPrimaria,
                                    disabledBackgroundColor: corPrimaria
                                        .withValues(alpha: 0.55),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  child: carregando
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.login_rounded),
                                            SizedBox(width: 10),
                                            Text(
                                              'Entrar no painel',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF7F8FA),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFE6E8EF),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: corPrimaria.withValues(
                                          alpha: 0.10,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.info_outline_rounded,
                                        size: 20,
                                        color: corPrimaria,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        'Digite apenas o login fornecido pelo sistema.',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          height: 1.25,
                                          color: Color(0xFF667085),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Acesso seguro integrado à Base Central',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.38),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_navigator.dart';

class SessaoLoja {
  static const String _sessaoLojaPersistidaKey =
      'app_preco_sessao_loja_persistida_v1';

  static int _versaoPersistencia = 0;
  static Future<bool>? _renovacaoSessaoEmAndamento;
  static const int _margemRenovacaoSegundos = 90;

  static const String _corPrimariaPadrao = '#E30613';
  static const String _corSecundariaPadrao = '#B8000D';
  static const String _corFundoPadrao = '#F5F7FA';

  // ABA-FLUANTE-GLOBAL-CORRECAO-REAL
  // ABA-MODO-MASTER-LOJA-FORCADO-CORRIGIDO
  // Notifica a aba global quando entramos/saímos de uma loja.
  static final ValueNotifier<int> alteracoes = ValueNotifier<int>(0);

  static bool _notificacaoAgendada = false;

  static void notificarAlteracao() {
    if (_notificacaoAgendada) {
      return;
    }

    _notificacaoAgendada = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificacaoAgendada = false;
      alteracoes.value++;
    });
  }

  static String? mercadoId;
  static String? mercadoNome;
  static String? mercadoCodigo;
  static String? logoUrl;

  static String? apiBaseUrl;
  static String fonteProdutos = 'API';

  static String? supabaseUrl;
  static String? supabaseAnonKey;

  static String corPrimariaHex = _corPrimariaPadrao;
  static String corSecundariaHex = _corSecundariaPadrao;
  static String corFundoHex = _corFundoPadrao;

  static String? usuarioId;
  static String? usuarioNome;
  static String? usuarioLogin;
  static String? usuarioEmail;
  static String? usuarioPerfil;

  static String? lojaAccessToken;
  static String? lojaRefreshToken;

  static bool logadoNaLoja = false;
  static bool estoqueDetalhadoAtivo = false;
  static bool alterarPrecoConsultaAtivo = false;

  static SupabaseClient? supabaseLoja;

  static Set<String> permissoesUsuario = {};

  static const Set<String> permissoesAcessoTotal = {
    'pedidos',
    'consulta_preco',
    'produtos_inativos',
    'alterar_preco',
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
  };

  static void configurar({
    required String id,
    required String nome,
    required String apiUrl,
    required String urlSupabase,
    required String anonKeySupabase,
    String? codigo,
    String? userId,
    String? userNome,
    String? userLogin,
    String? userEmail,
    String? userPerfil,
    String? accessToken,
    String? refreshToken,
    SupabaseClient? clienteLoja,
    List<String> permissoes = const [],
    String? fonteProdutos,
    String? adminCorPrimaria,
    String? adminCorSecundaria,
    String? adminCorFundo,
    String? logo,
    bool estoqueDetalhadoAtivo = false,
    bool alterarPrecoConsultaAtivo = false,
  }) {
    mercadoId = id;
    mercadoNome = nome;
    mercadoCodigo = codigo;
    logoUrl = _textoOuNull(logo);

    apiBaseUrl = apiUrl;
    SessaoLoja.fonteProdutos = normalizarFonteProdutos(fonteProdutos);
    SessaoLoja.estoqueDetalhadoAtivo = estoqueDetalhadoAtivo;
    SessaoLoja.alterarPrecoConsultaAtivo = alterarPrecoConsultaAtivo;

    supabaseUrl = urlSupabase;
    supabaseAnonKey = anonKeySupabase;

    configurarCores(
      primaria: adminCorPrimaria,
      secundaria: adminCorSecundaria,
      fundo: adminCorFundo,
      notificar: false,
    );

    usuarioId = userId;
    usuarioNome = userNome;
    usuarioLogin = userLogin;
    usuarioEmail = userEmail;
    usuarioPerfil = userPerfil;

    lojaAccessToken = accessToken;
    lojaRefreshToken = refreshToken;

    permissoesUsuario = usuarioAcessoTotal
        ? permissoesAcessoTotal.toSet()
        : permissoes.toSet();

    logadoNaLoja = userId != null && userId.isNotEmpty;

    supabaseLoja =
        clienteLoja ??
        SupabaseClient(
          urlSupabase,
          anonKeySupabase,
          authOptions: const AuthClientOptions(autoRefreshToken: true),
        );

    AppNavigator.definirModoLoja();
    notificarAlteracao();
  }

  static void configurarLoginLoja({
    required String id,
    required String nome,
    String? codigo,
    String? apiUrl,
    required String urlSupabase,
    required String anonKeySupabase,
    required String userId,
    String? userNome,
    String? userLogin,
    String? userEmail,
    String? userPerfil,
    String? accessToken,
    String? refreshToken,
    SupabaseClient? clienteLoja,
    List<String> permissoes = const [],
    String? fonteProdutos,
    String? adminCorPrimaria,
    String? adminCorSecundaria,
    String? adminCorFundo,
    String? logo,
    bool estoqueDetalhadoAtivo = false,
    bool alterarPrecoConsultaAtivo = false,
  }) {
    mercadoId = id;
    mercadoNome = nome;
    mercadoCodigo = codigo;
    logoUrl = _textoOuNull(logo);

    apiBaseUrl = apiUrl;
    SessaoLoja.fonteProdutos = normalizarFonteProdutos(fonteProdutos);
    SessaoLoja.estoqueDetalhadoAtivo = estoqueDetalhadoAtivo;
    SessaoLoja.alterarPrecoConsultaAtivo = alterarPrecoConsultaAtivo;

    supabaseUrl = urlSupabase;
    supabaseAnonKey = anonKeySupabase;

    configurarCores(
      primaria: adminCorPrimaria,
      secundaria: adminCorSecundaria,
      fundo: adminCorFundo,
      notificar: false,
    );

    usuarioId = userId;
    usuarioNome = userNome;
    usuarioLogin = userLogin;
    usuarioEmail = userEmail;
    usuarioPerfil = userPerfil;

    lojaAccessToken = accessToken;
    lojaRefreshToken = refreshToken;

    permissoesUsuario = usuarioAcessoTotal
        ? permissoesAcessoTotal.toSet()
        : permissoes.toSet();

    logadoNaLoja = true;

    supabaseLoja =
        clienteLoja ??
        SupabaseClient(
          urlSupabase,
          anonKeySupabase,
          authOptions: const AuthClientOptions(autoRefreshToken: true),
        );

    AppNavigator.definirModoLoja();
    notificarAlteracao();
  }

  static void sincronizarSessaoAtual() {
    final cliente = supabaseLoja;

    if (cliente == null) {
      return;
    }

    final usuarioAtual = cliente.auth.currentUser;
    final sessaoAtual = cliente.auth.currentSession;

    if (usuarioAtual != null) {
      usuarioId ??= usuarioAtual.id;
      usuarioEmail ??= usuarioAtual.email;
      logadoNaLoja = true;
    }

    if (sessaoAtual != null) {
      lojaAccessToken = sessaoAtual.accessToken;
      lojaRefreshToken = sessaoAtual.refreshToken;
      logadoNaLoja = true;
    }
  }

  static Future<void> salvarSessaoLojaPersistida() async {
    if (!logadoNaLoja ||
        mercadoId == null ||
        mercadoId!.isEmpty ||
        supabaseUrl == null ||
        supabaseUrl!.isEmpty ||
        supabaseAnonKey == null ||
        supabaseAnonKey!.isEmpty ||
        usuarioId == null ||
        usuarioId!.isEmpty ||
        lojaRefreshToken == null ||
        lojaRefreshToken!.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _versaoPersistencia++;

    await prefs.setString(
      _sessaoLojaPersistidaKey,
      jsonEncode({
        'mercado_id': mercadoId,
        'mercado_nome': mercadoNome,
        'mercado_codigo': mercadoCodigo,
        'logo_url': logoUrl,
        'api_base_url': apiBaseUrl,
        'fonte_produtos': fonteProdutos,
        'supabase_url': supabaseUrl,
        'supabase_anon_key': supabaseAnonKey,
        'usuario_id': usuarioId,
        'usuario_nome': usuarioNome,
        'usuario_login': usuarioLogin,
        'usuario_email': usuarioEmail,
        'usuario_perfil': usuarioPerfil,
        'access_token': lojaAccessToken,
        'refresh_token': lojaRefreshToken,
        'permissoes': permissoesUsuario.toList(),
        'admin_cor_primaria': corPrimariaHex,
        'admin_cor_secundaria': corSecundariaHex,
        'admin_cor_fundo': corFundoHex,
        'estoque_detalhado_ativo': estoqueDetalhadoAtivo,
        'alterar_preco_consulta_ativo': alterarPrecoConsultaAtivo,
      }),
    );
  }

  static Future<void> limparSessaoLojaPersistida() async {
    final prefs = await SharedPreferences.getInstance();
    _versaoPersistencia++;
    await prefs.remove(_sessaoLojaPersistidaKey);
  }

  static List<String> _listaStrings(dynamic valor) {
    if (valor is! List) {
      return const [];
    }

    return valor
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }

  static Future<bool> restaurarSessaoLojaPersistida() async {
    final prefs = await SharedPreferences.getInstance();
    final conteudo = prefs.getString(_sessaoLojaPersistidaKey);

    if (conteudo == null || conteudo.isEmpty) {
      return false;
    }

    try {
      final dados = jsonDecode(conteudo);

      if (dados is! Map) {
        await limparSessaoLojaPersistida();
        return false;
      }

      final urlSupabase = dados['supabase_url']?.toString().trim() ?? '';
      final anonKeySupabase =
          dados['supabase_anon_key']?.toString().trim() ?? '';
      final refreshToken = dados['refresh_token']?.toString().trim() ?? '';
      final accessToken = dados['access_token']?.toString().trim() ?? '';
      final id = dados['mercado_id']?.toString().trim() ?? '';
      final nome = dados['mercado_nome']?.toString().trim() ?? '';

      if (urlSupabase.isEmpty ||
          anonKeySupabase.isEmpty ||
          refreshToken.isEmpty ||
          id.isEmpty ||
          nome.isEmpty) {
        await limparSessaoLojaPersistida();
        return false;
      }

      final clienteLoja = SupabaseClient(
        urlSupabase,
        anonKeySupabase,
        authOptions: const AuthClientOptions(autoRefreshToken: true),
      );

      final resposta = await clienteLoja.auth.setSession(
        refreshToken,
        accessToken: accessToken.isEmpty ? null : accessToken,
      );
      final sessao = resposta.session ?? clienteLoja.auth.currentSession;
      final usuario = resposta.user ?? clienteLoja.auth.currentUser;

      if (sessao == null || usuario == null) {
        await limparSessaoLojaPersistida();
        return false;
      }

      final userIdSalvo = dados['usuario_id']?.toString().trim() ?? '';

      configurarLoginLoja(
        id: id,
        nome: nome,
        codigo: dados['mercado_codigo']?.toString(),
        apiUrl: dados['api_base_url']?.toString(),
        urlSupabase: urlSupabase,
        anonKeySupabase: anonKeySupabase,
        userId: userIdSalvo.isNotEmpty ? userIdSalvo : usuario.id,
        userNome: dados['usuario_nome']?.toString(),
        userLogin: dados['usuario_login']?.toString(),
        userEmail: dados['usuario_email']?.toString() ?? usuario.email,
        userPerfil: dados['usuario_perfil']?.toString(),
        accessToken: sessao.accessToken,
        refreshToken: sessao.refreshToken,
        clienteLoja: clienteLoja,
        permissoes: _listaStrings(dados['permissoes']),
        fonteProdutos: dados['fonte_produtos']?.toString(),
        adminCorPrimaria: dados['admin_cor_primaria']?.toString(),
        adminCorSecundaria: dados['admin_cor_secundaria']?.toString(),
        adminCorFundo: dados['admin_cor_fundo']?.toString(),
        logo: dados['logo_url']?.toString(),
        estoqueDetalhadoAtivo: booleanoDinamico(
          dados['estoque_detalhado_ativo'],
        ),
        alterarPrecoConsultaAtivo: booleanoDinamico(
          dados['alterar_preco_consulta_ativo'],
        ),
      );

      await salvarSessaoLojaPersistida();

      return true;
    } catch (_) {
      await limparSessaoLojaPersistida();
      return false;
    }
  }

  static bool erroSessaoExpirada(Object erro) {
    final mensagem = erro.toString().toLowerCase();

    // Não trate "401" ou "unauthorized" genérico como sessão expirada,
    // porque pode ser apenas falta de permissão na loja.
    return mensagem.contains('jwt expired') ||
        mensagem.contains('pgrst303') ||
        mensagem.contains('sessão expirou') ||
        mensagem.contains('sessao expirou') ||
        mensagem.contains('session expired');
  }

  static bool _sessaoPrecisaRenovar(Session? sessao) {
    if (sessao == null) {
      return true;
    }

    final expiraEm = sessao.expiresAt;
    if (expiraEm == null) {
      return false;
    }

    final agora = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return expiraEm - agora <= _margemRenovacaoSegundos;
  }

  static Future<bool> renovarSessaoLojaSePossivel({bool forcar = false}) {
    final cliente = supabaseLoja;

    if (cliente == null) {
      return Future.value(false);
    }

    sincronizarSessaoAtual();

    if (!forcar && !_sessaoPrecisaRenovar(cliente.auth.currentSession)) {
      return Future.value(true);
    }

    final renovacaoAtual = _renovacaoSessaoEmAndamento;
    if (renovacaoAtual != null) {
      return renovacaoAtual;
    }

    final renovacao = _renovarSessaoLoja(cliente);
    _renovacaoSessaoEmAndamento = renovacao;

    return renovacao.whenComplete(() {
      if (identical(_renovacaoSessaoEmAndamento, renovacao)) {
        _renovacaoSessaoEmAndamento = null;
      }
    });
  }

  static Future<bool> _renovarSessaoLoja(SupabaseClient cliente) async {
    try {
      final refreshToken =
          cliente.auth.currentSession?.refreshToken?.trim() ??
          lojaRefreshToken?.trim() ??
          '';

      if (refreshToken.isEmpty) {
        return false;
      }

      final resposta = await cliente.auth.refreshSession(refreshToken);

      final sessao = resposta.session ?? cliente.auth.currentSession;
      final usuario = resposta.user ?? cliente.auth.currentUser;

      if (sessao == null || usuario == null) {
        return false;
      }

      usuarioId ??= usuario.id;
      usuarioEmail ??= usuario.email;
      lojaAccessToken = sessao.accessToken;
      lojaRefreshToken = sessao.refreshToken;
      logadoNaLoja = true;
      notificarAlteracao();
      await salvarSessaoLojaPersistida();

      return true;
    } catch (_) {
      return false;
    }
  }

  static void atualizarPermissoes(List<String> permissoes) {
    permissoesUsuario = usuarioAcessoTotal
        ? permissoesAcessoTotal.toSet()
        : permissoes.toSet();

    notificarAlteracao();
  }

  static void configurarCores({
    String? primaria,
    String? secundaria,
    String? fundo,
    bool notificar = true,
  }) {
    corPrimariaHex = _normalizarCor(primaria, _corPrimariaPadrao);
    corSecundariaHex = _normalizarCor(secundaria, _corSecundariaPadrao);
    corFundoHex = _normalizarCor(fundo, _corFundoPadrao);

    if (notificar) {
      notificarAlteracao();
    }
  }

  static String _normalizarCor(String? valor, String fallback) {
    final texto = valor?.trim() ?? '';
    final hexadecimal = texto.startsWith('#') ? texto.substring(1) : texto;

    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hexadecimal)) {
      return '#${hexadecimal.toUpperCase()}';
    }

    return fallback;
  }

  static String? _textoOuNull(String? valor) {
    final texto = valor?.trim() ?? '';
    return texto.isEmpty ? null : texto;
  }

  static String normalizarFonteProdutos(String? valor) {
    final texto = valor?.trim().toUpperCase() ?? '';

    if (texto == 'BANCO_LOJA' || texto == 'SUPABASE') {
      return 'BANCO_LOJA';
    }

    return 'API';
  }

  static bool booleanoDinamico(dynamic valor, {bool padrao = false}) {
    if (valor == true) {
      return true;
    }

    if (valor == false) {
      return false;
    }

    if (valor is num) {
      return valor == 1;
    }

    final texto = valor?.toString().trim().toLowerCase() ?? '';

    if (texto == 'true' || texto == '1' || texto == 'sim' || texto == 's') {
      return true;
    }

    if (texto == 'false' ||
        texto == '0' ||
        texto == 'nao' ||
        texto == 'nÃ£o' ||
        texto == 'n') {
      return false;
    }

    return padrao;
  }

  static Color _corHex(String valor, Color fallback) {
    final hexadecimal = valor.replaceFirst('#', '');
    final numero = int.tryParse(hexadecimal, radix: 16);

    if (numero == null) {
      return fallback;
    }

    return Color(0xFF000000 | numero);
  }

  static Color get corPrimaria =>
      _corHex(corPrimariaHex, const Color(0xFFE30613));

  static Color get corSecundaria =>
      _corHex(corSecundariaHex, const Color(0xFFB8000D));

  static Color get corFundo => _corHex(corFundoHex, const Color(0xFFF5F7FA));

  static bool temPermissao(String codigo) {
    if (usuarioAcessoTotal) {
      return true;
    }

    return permissoesUsuario.contains(codigo);
  }

  static bool temAlgumaPermissao(List<String> codigos) {
    if (usuarioAcessoTotal) {
      return true;
    }

    return codigos.any(permissoesUsuario.contains);
  }

  static void limpar() {
    mercadoId = null;
    mercadoNome = null;
    mercadoCodigo = null;
    logoUrl = null;

    apiBaseUrl = null;
    fonteProdutos = 'API';

    supabaseUrl = null;
    supabaseAnonKey = null;

    corPrimariaHex = _corPrimariaPadrao;
    corSecundariaHex = _corSecundariaPadrao;
    corFundoHex = _corFundoPadrao;

    usuarioId = null;
    usuarioNome = null;
    usuarioLogin = null;
    usuarioEmail = null;
    usuarioPerfil = null;

    lojaAccessToken = null;
    lojaRefreshToken = null;
    estoqueDetalhadoAtivo = false;
    alterarPrecoConsultaAtivo = false;

    permissoesUsuario = {};

    logadoNaLoja = false;

    supabaseLoja = null;

    final versaoLimpeza = ++_versaoPersistencia;
    SharedPreferences.getInstance().then((prefs) {
      if (versaoLimpeza == _versaoPersistencia) {
        prefs.remove(_sessaoLojaPersistidaKey);
      }
    });

    AppNavigator.definirModoMaster();
    notificarAlteracao();
  }

  static String get mercadoIdObrigatorio {
    final id = mercadoId?.trim();

    if (id == null || id.isEmpty) {
      throw Exception('Mercado não selecionado na sessão');
    }

    return id;
  }

  static String get mercadoCodigoObrigatorio {
    final codigo = mercadoCodigo?.trim();

    if (codigo == null || codigo.isEmpty) {
      throw Exception('Código do mercado não encontrado na sessão');
    }

    return codigo;
  }

  static Map<String, dynamic> get dadosMercadoRegistro {
    return {
      'mercado_id': mercadoIdObrigatorio,
      'mercado_codigo': mercadoCodigoObrigatorio,
    };
  }

  static Map<String, dynamic> dadosComMercado(Map<String, dynamic> dados) {
    return {...dadosMercadoRegistro, ...dados};
  }

  static bool mesmoMercado(Map<String, dynamic> registro) {
    final idRegistro = registro['mercado_id']?.toString().trim();
    final codigoRegistro = registro['mercado_codigo']?.toString().trim();

    final idSessao = mercadoId?.trim();
    final codigoSessao = mercadoCodigo?.trim();

    if (idSessao != null && idSessao.isNotEmpty && idRegistro == idSessao) {
      return true;
    }

    if (codigoSessao != null &&
        codigoSessao.isNotEmpty &&
        codigoRegistro == codigoSessao) {
      return true;
    }

    return false;
  }

  static bool get lojaSelecionada {
    return mercadoId != null &&
        supabaseUrl != null &&
        supabaseAnonKey != null &&
        supabaseLoja != null;
  }

  static bool get usuarioLogadoNaLoja {
    sincronizarSessaoAtual();

    return logadoNaLoja && usuarioId != null && usuarioId!.isNotEmpty;
  }

  static bool get usuarioAdminLoja {
    return usuarioPerfil == 'admin_loja';
  }

  static bool get usuarioEntregador {
    final perfil = usuarioPerfil?.trim().toLowerCase();

    return perfil == 'entregador' ||
        perfil == 'motoboy' ||
        perfil == 'delivery';
  }

  static bool get usuarioMasterCentral {
    final perfil = usuarioPerfil?.trim().toLowerCase();

    return perfil == 'master' ||
        perfil == 'admin_master' ||
        perfil == 'master_central' ||
        perfil == 'super_admin';
  }

  static bool get usuarioAcessoTotal {
    return usuarioMasterCentral;
  }

  static bool get temApiConfigurada {
    final url = apiBaseUrl?.trim().toLowerCase() ?? '';
    return url.isNotEmpty && url != 'null';
  }
}

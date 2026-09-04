import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'sessao_loja.dart';

class ErroUsuarioException implements Exception {
  final String mensagem;

  const ErroUsuarioException(this.mensagem);

  @override
  String toString() => mensagem;
}

class CentralService {
  final SupabaseClient supabase = Supabase.instance.client;

  static const String bucketLogosMercados = 'logos-mercados';
  static const String mensagemSemInternet =
      'Sem conexão com a internet. Verifique o Wi-Fi ou os dados móveis e tente novamente.';

  static String mensagemErroUsuario(Object erro) {
    if (erro is ErroUsuarioException) {
      return erro.mensagem;
    }

    if (erro is AuthException) {
      final mensagem = erro.message.toLowerCase();
      final codigo = erro.code?.toLowerCase() ?? '';

      if (mensagem.contains('invalid login credentials') ||
          codigo.contains('invalid_credentials')) {
        return 'Senha incorreta. Confira sua senha e tente novamente.';
      }

      if (_textoIndicaSessaoExpirada('$mensagem $codigo')) {
        return 'Sua sessão expirou. Entre novamente para continuar.';
      }
    }

    if (erro is FunctionException) {
      final detalhes = erro.details?.toString() ?? '';
      final texto = '${erro.status} $detalhes ${erro.reasonPhrase ?? ''}';

      return _mensagemErroTexto(
        texto,
        status: erro.status,
        fallback: 'Não foi possível concluir a operação. Tente novamente.',
      );
    }

    return _mensagemErroTexto(
      erro.toString(),
      fallback: 'Não foi possível concluir a operação. Tente novamente.',
    );
  }

  static bool _textoIndicaSessaoExpirada(String texto) {
    final normalizado = texto.toLowerCase();

    return normalizado.contains('jwt expired') ||
        normalizado.contains('token is expired') ||
        normalizado.contains('invalid jwt') ||
        normalizado.contains('unable to parse or verify signature') ||
        normalizado.contains('pgrst303') ||
        normalizado.contains('sessão expirou') ||
        normalizado.contains('sessao expirou') ||
        normalizado.contains('session expired');
  }

  static String _mensagemErroTexto(
    String texto, {
    int? status,
    required String fallback,
  }) {
    final normalizado = texto.toLowerCase();

    if (_textoIndicaSessaoExpirada(normalizado) ||
        status == 401 ||
        normalizado.contains('usuario nao autenticado') ||
        normalizado.contains('usuário não autenticado')) {
      return 'Sua sessão expirou. Entre novamente para continuar.';
    }

    if (normalizado.contains('permission denied') ||
        normalizado.contains('sem permiss') ||
        normalizado.contains('acesso negado') ||
        normalizado.contains('row-level security') ||
        normalizado.contains('42501')) {
      return 'Você não tem permissão para executar esta ação.';
    }

    if (normalizado.contains('login não encontrado') ||
        normalizado.contains('login nao encontrado') ||
        normalizado.contains('usuário inativo') ||
        normalizado.contains('usuario inativo') ||
        status == 404) {
      return 'Login não cadastrado ou usuário inativo. Confira o login ou fale com o administrador.';
    }

    if (normalizado.contains('invalid login credentials') ||
        normalizado.contains('invalid_credentials')) {
      return 'Senha incorreta. Confira sua senha e tente novamente.';
    }

    if (normalizado.contains('socketexception') ||
        normalizado.contains('clientexception') ||
        normalizado.contains('failed host lookup') ||
        normalizado.contains('no address associated with hostname') ||
        normalizado.contains('connection refused') ||
        normalizado.contains('connection reset') ||
        normalizado.contains('connection closed') ||
        normalizado.contains('connection aborted') ||
        normalizado.contains('software caused connection abort') ||
        normalizado.contains('network is unreachable') ||
        normalizado.contains('network request failed') ||
        normalizado.contains('xmlhttprequest error') ||
        normalizado.contains('fetch failed') ||
        normalizado.contains('timeoutexception') ||
        normalizado.contains('timed out') ||
        normalizado.contains('connection timeout') ||
        normalizado.contains('connection timed out') ||
        normalizado.contains('handshakeexception')) {
      return mensagemSemInternet;
    }

    return fallback;
  }

  Future<String?> _tokenCentralAtualizado() async {
    var sessao = supabase.auth.currentSession;

    if (sessao == null) {
      return null;
    }

    final expiraEm = sessao.expiresAt;
    final agora = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final deveRenovar = expiraEm == null || expiraEm - agora <= 60;

    if (deveRenovar) {
      try {
        final resposta = await supabase.auth.refreshSession();
        sessao = resposta.session ?? supabase.auth.currentSession;
      } catch (_) {
        sessao = supabase.auth.currentSession;
      }
    }

    final token = sessao?.accessToken.trim();

    return token == null || token.isEmpty ? null : token;
  }

  Future<Map<String, String>?> _headersAutenticacaoAtualizados({
    bool renovarTokenLoja = true,
  }) async {
    SessaoLoja.sincronizarSessaoAtual();

    // Usuário de loja: envia sempre o token da loja/base única.
    // Isso é necessário para as Edge Functions validarem usuários como "max".
    if (SessaoLoja.logadoNaLoja &&
        SessaoLoja.usuarioId != null &&
        SessaoLoja.usuarioId!.isNotEmpty) {
      if (renovarTokenLoja) {
        await SessaoLoja.renovarSessaoLojaSePossivel();
      }

      final tokenLoja = SessaoLoja.lojaAccessToken?.trim();

      if (tokenLoja != null && tokenLoja.isNotEmpty) {
        return {'Authorization': 'Bearer $tokenLoja'};
      }
    }

    // Usuário master central: envia o token da Base Central.
    final tokenCentral = await _tokenCentralAtualizado();

    if (tokenCentral != null && tokenCentral.isNotEmpty) {
      return {'Authorization': 'Bearer $tokenCentral'};
    }

    return null;
  }

  bool _respostaIndicaTokenExpirado(FunctionResponse resposta) {
    final data = resposta.data;

    if (data == null) {
      return false;
    }

    final texto = data.toString().toLowerCase();

    return texto.contains('jwt expired') ||
        texto.contains('pgrst303') ||
        texto.contains('sessão expirou') ||
        texto.contains('sessao expirou') ||
        texto.contains('session expired');
  }

  bool _erroIndicaTokenExpirado(Object erro) {
    if (erro is FunctionException) {
      return _textoIndicaSessaoExpirada(
        '${erro.details ?? ''} ${erro.reasonPhrase ?? ''} ${erro.toString()}',
      );
    }

    return _textoIndicaSessaoExpirada(erro.toString());
  }

  Future<FunctionResponse> _invokeCentral(
    String nomeFunction, {
    Map<String, dynamic> body = const {},
    bool usarTokenLoja = true,
  }) async {
    try {
      final headers = usarTokenLoja
          ? await _headersAutenticacaoAtualizados()
          : null;

      final primeiraResposta = await supabase.functions.invoke(
        nomeFunction,
        body: body,
        headers: headers,
      );

      // Se o token da loja expirou, renova e tenta apenas mais uma vez.
      // Não trata "401" genérico como expiração, porque pode ser permissão.
      if (usarTokenLoja && _respostaIndicaTokenExpirado(primeiraResposta)) {
        final renovou = await SessaoLoja.renovarSessaoLojaSePossivel();

        if (renovou) {
          final headersRenovados = await _headersAutenticacaoAtualizados(
            renovarTokenLoja: false,
          );

          return await supabase.functions.invoke(
            nomeFunction,
            body: body,
            headers: headersRenovados,
          );
        }
      }

      return primeiraResposta;
    } catch (e) {
      if (usarTokenLoja && _erroIndicaTokenExpirado(e)) {
        final renovou = await SessaoLoja.renovarSessaoLojaSePossivel();

        if (renovou) {
          try {
            final headersRenovados = await _headersAutenticacaoAtualizados(
              renovarTokenLoja: false,
            );

            return await supabase.functions.invoke(
              nomeFunction,
              body: body,
              headers: headersRenovados,
            );
          } catch (erroRepeticao) {
            throw ErroUsuarioException(mensagemErroUsuario(erroRepeticao));
          }
        }
      }

      throw ErroUsuarioException(mensagemErroUsuario(e));
    }
  }

  String? _mercadoCodigoAtual(String mercadoId) {
    final idSessao = SessaoLoja.mercadoId?.trim();
    final codigoSessao = SessaoLoja.mercadoCodigo?.trim();

    if (idSessao != null &&
        idSessao.isNotEmpty &&
        idSessao == mercadoId.trim() &&
        codigoSessao != null &&
        codigoSessao.isNotEmpty) {
      return codigoSessao;
    }

    return null;
  }

  dynamic _validarResposta(FunctionResponse resposta) {
    final data = resposta.data;

    if (data == null) {
      throw const ErroUsuarioException(
        'Não foi possível obter resposta do servidor. Tente novamente.',
      );
    }

    if (data is Map && data['erro'] != null) {
      final detalhe = data['detalhe']?.toString();
      final etapa = data['etapa']?.toString();

      if (detalhe != null && detalhe.isNotEmpty) {
        throw ErroUsuarioException(
          mensagemErroUsuario('${data['erro']} - $detalhe'),
        );
      }

      if (etapa != null && etapa.isNotEmpty) {
        throw ErroUsuarioException(
          mensagemErroUsuario('${data['erro']} - etapa: $etapa'),
        );
      }

      throw ErroUsuarioException(mensagemErroUsuario(data['erro'].toString()));
    }

    return data;
  }

  String _contentTypeImagem(String extensao) {
    switch (extensao.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  Future<bool> usuarioEhMaster() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      return false;
    }

    final resposta = await supabase.rpc('is_master');

    return resposta == true;
  }

  Future<Map<String, dynamic>> resolverLogin(
    String login, {
    String? mercadoId,
    String? mercadoCodigo,
  }) async {
    final resposta = await _invokeCentral(
      'resolver-login',
      usarTokenLoja: false,
      body: {
        'login': login,
        if (mercadoId != null && mercadoId.trim().isNotEmpty)
          'mercado_id': mercadoId.trim(),
        if (mercadoCodigo != null && mercadoCodigo.trim().isNotEmpty)
          'mercado_codigo': mercadoCodigo.trim(),
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> validarMercadoAtivo({
    String? mercadoId,
    String? mercadoCodigo,
  }) async {
    final resposta = await _invokeCentral(
      'validar-mercado-ativo',
      usarTokenLoja: false,
      body: {'mercado_id': mercadoId, 'mercado_codigo': mercadoCodigo},
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<List<Map<String, dynamic>>> listarLojas() async {
    final resposta = await supabase
        .from('mercados')
        .select(
          'id, nome, codigo, ativo, cidade, estado, logo_url, logo_path, logo_login_url, logo_login_path, splash_logo_url, splash_logo_path, admin_cor_primaria, admin_cor_secundaria, admin_cor_fundo, gerar_apk_admin, admin_app_nome, admin_app_package, admin_app_build_codigo, gerar_apk_mercado, mercado_app_nome, mercado_app_package, mercado_app_build_codigo, apk_personalizado, app_nome, app_package, app_build_codigo, app_icone_url, app_icone_path, mercado_splash_logo_url, mercado_splash_logo_path, mercado_app_icone_url, mercado_app_icone_path, fonte_produtos, alterar_preco_consulta_ativo',
        )
        .eq('ativo', true)
        .order('nome');

    return List<Map<String, dynamic>>.from(resposta);
  }

  Future<List<Map<String, dynamic>>> listarMercadosAdmin() async {
    final resposta = await _invokeCentral('listar-mercados-admin', body: {});

    final data = _validarResposta(resposta);

    final mercados = data['mercados'];

    if (mercados == null) {
      return [];
    }

    return List<Map<String, dynamic>>.from(mercados);
  }

  Future<Map<String, String>> _uploadImagemMercado({
    required String mercadoId,
    required File imagemFile,
    required String prefixo,
    required String urlCampo,
    required String pathCampo,
    required String mensagemErro,
    bool atualizarLogoCompatibilidade = false,
  }) async {
    try {
      final extensao = imagemFile.path.split('.').last.toLowerCase();

      final nomeArquivo =
          '${prefixo}_${DateTime.now().millisecondsSinceEpoch}.$extensao';

      final caminhoStorage = '$mercadoId/$nomeArquivo';

      final contentType = _contentTypeImagem(extensao);

      await supabase.storage
          .from(bucketLogosMercados)
          .upload(
            caminhoStorage,
            imagemFile,
            fileOptions: FileOptions(
              cacheControl: '3600',
              upsert: true,
              contentType: contentType,
            ),
          );

      final imagemUrl = supabase.storage
          .from(bucketLogosMercados)
          .getPublicUrl(caminhoStorage);

      final dadosUpdate = <String, dynamic>{
        urlCampo: imagemUrl,
        pathCampo: caminhoStorage,
      };

      // Compatibilidade: telas antigas ainda leem logo_url/logo_path.
      if (atualizarLogoCompatibilidade) {
        dadosUpdate['logo_url'] = imagemUrl;
        dadosUpdate['logo_path'] = caminhoStorage;
      }

      await supabase.from('mercados').update(dadosUpdate).eq('id', mercadoId);

      return {urlCampo: imagemUrl, pathCampo: caminhoStorage};
    } catch (e) {
      throw Exception('$mensagemErro: $e');
    }
  }

  Future<Map<String, String>> uploadLogoLoginMercado({
    required String mercadoId,
    required File logoFile,
  }) async {
    return _uploadImagemMercado(
      mercadoId: mercadoId,
      imagemFile: logoFile,
      prefixo: 'logo_login',
      urlCampo: 'logo_login_url',
      pathCampo: 'logo_login_path',
      mensagemErro: 'Erro ao enviar logo da tela de login',
    );
  }

  Future<Map<String, String>> uploadLogoMercado({
    required String mercadoId,
    required File logoFile,
  }) async {
    return _uploadImagemMercado(
      mercadoId: mercadoId,
      imagemFile: logoFile,
      prefixo: 'logo_mercado',
      urlCampo: 'logo_url',
      pathCampo: 'logo_path',
      mensagemErro: 'Erro ao enviar logo do app Mercado',
    );
  }

  Future<void> atualizarLogoLoginMercado({
    required String mercadoId,
    required File logoFile,
  }) async {
    await uploadLogoLoginMercado(mercadoId: mercadoId, logoFile: logoFile);
  }

  Future<void> atualizarLogoMercado({
    required String mercadoId,
    required File logoFile,
  }) async {
    await uploadLogoMercado(mercadoId: mercadoId, logoFile: logoFile);
  }

  Future<Map<String, String>> uploadSplashLogoMercado({
    required String mercadoId,
    required File splashFile,
  }) async {
    return _uploadImagemMercado(
      mercadoId: mercadoId,
      imagemFile: splashFile,
      prefixo: 'splash',
      urlCampo: 'splash_logo_url',
      pathCampo: 'splash_logo_path',
      mensagemErro: 'Erro ao enviar splash do app',
    );
  }

  Future<void> atualizarSplashLogoMercado({
    required String mercadoId,
    required File splashFile,
  }) async {
    await uploadSplashLogoMercado(mercadoId: mercadoId, splashFile: splashFile);
  }

  Future<Map<String, String>> uploadSplashLogoMercadoCliente({
    required String mercadoId,
    required File splashFile,
  }) async {
    return _uploadImagemMercado(
      mercadoId: mercadoId,
      imagemFile: splashFile,
      prefixo: 'splash_mercado',
      urlCampo: 'mercado_splash_logo_url',
      pathCampo: 'mercado_splash_logo_path',
      mensagemErro: 'Erro ao enviar splash do app Mercado',
    );
  }

  Future<void> atualizarSplashLogoMercadoCliente({
    required String mercadoId,
    required File splashFile,
  }) async {
    await uploadSplashLogoMercadoCliente(
      mercadoId: mercadoId,
      splashFile: splashFile,
    );
  }

  Future<Map<String, String>> uploadIconeAppMercado({
    required String mercadoId,
    required File iconeFile,
  }) async {
    return _uploadImagemMercado(
      mercadoId: mercadoId,
      imagemFile: iconeFile,
      prefixo: 'icone',
      urlCampo: 'app_icone_url',
      pathCampo: 'app_icone_path',
      mensagemErro: 'Erro ao enviar ícone do app',
    );
  }

  Future<void> atualizarIconeAppMercado({
    required String mercadoId,
    required File iconeFile,
  }) async {
    await uploadIconeAppMercado(mercadoId: mercadoId, iconeFile: iconeFile);
  }

  Future<Map<String, String>> uploadIconeAppMercadoCliente({
    required String mercadoId,
    required File iconeFile,
  }) async {
    return _uploadImagemMercado(
      mercadoId: mercadoId,
      imagemFile: iconeFile,
      prefixo: 'icone_mercado',
      urlCampo: 'mercado_app_icone_url',
      pathCampo: 'mercado_app_icone_path',
      mensagemErro: 'Erro ao enviar ícone do app Mercado',
    );
  }

  Future<void> atualizarIconeAppMercadoCliente({
    required String mercadoId,
    required File iconeFile,
  }) async {
    await uploadIconeAppMercadoCliente(
      mercadoId: mercadoId,
      iconeFile: iconeFile,
    );
  }

  Future<List<Map<String, dynamic>>> listarProdutoOfertas({
    required String mercadoId,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-produto-ofertas',
      body: {
        'acao': 'listar',
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
      },
    );

    final data = _validarResposta(resposta);
    final ofertas = data['ofertas'];

    if (ofertas == null) {
      return [];
    }

    return List<Map<String, dynamic>>.from(ofertas);
  }

  Future<Map<String, dynamic>> salvarProdutoOferta({
    required String mercadoId,
    required Map<String, dynamic> oferta,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-produto-ofertas',
      body: {
        'acao': 'salvar',
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
        'oferta': {
          if (_mercadoCodigoAtual(mercadoId) != null)
            'mercado_codigo': _mercadoCodigoAtual(mercadoId),
          ...oferta,
        },
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<void> alternarProdutoOferta({
    required String mercadoId,
    required String ofertaId,
    required bool ativo,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-produto-ofertas',
      body: {
        'acao': 'alternar',
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
        'oferta_id': ofertaId,
        'ativo': ativo,
      },
    );

    _validarResposta(resposta);
  }

  Future<void> excluirProdutoOferta({
    required String mercadoId,
    required String ofertaId,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-produto-ofertas',
      body: {
        'acao': 'excluir',
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
        'oferta_id': ofertaId,
      },
    );

    _validarResposta(resposta);
  }

  Future<List<Map<String, dynamic>>> listarCuponsDesconto({
    required String mercadoId,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-cupons-desconto',
      body: {
        'acao': 'listar',
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
      },
    );

    final data = _validarResposta(resposta);
    return List<Map<String, dynamic>>.from(data['cupons'] ?? const []);
  }

  Future<Map<String, dynamic>> salvarCupomDesconto({
    required String mercadoId,
    required Map<String, dynamic> cupom,
    List<Map<String, dynamic>> alvos = const [],
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-cupons-desconto',
      body: {
        'acao': 'salvar',
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
        'cupom': cupom,
        'alvos': alvos,
      },
    );

    return Map<String, dynamic>.from(_validarResposta(resposta));
  }

  Future<void> alternarCupomDesconto({
    required String mercadoId,
    required String cupomId,
    required bool ativo,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-cupons-desconto',
      body: {
        'acao': 'alternar',
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
        'cupom_id': cupomId,
        'ativo': ativo,
      },
    );

    _validarResposta(resposta);
  }

  Future<void> excluirCupomDesconto({
    required String mercadoId,
    required String cupomId,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-cupons-desconto',
      body: {
        'acao': 'excluir',
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
        'cupom_id': cupomId,
      },
    );

    _validarResposta(resposta);
  }

  Future<Map<String, dynamic>> listarAcoesValidade({
    required String mercadoId,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-acoes-validade',
      body: {
        'acao': 'listar',
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
      },
    );

    final data = _validarResposta(resposta);

    return {
      'acoes': List<Map<String, dynamic>>.from(data['acoes'] ?? const []),
      'alertas': List<Map<String, dynamic>>.from(data['alertas'] ?? const []),
    };
  }

  Future<Map<String, dynamic>> salvarAcaoValidade({
    required String mercadoId,
    required Map<String, dynamic> acaoValidade,
    String? acaoId,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-acoes-validade',
      body: {
        'acao': 'salvar',
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
        if (acaoId != null && acaoId.trim().isNotEmpty) 'acao_id': acaoId,
        'acao_validade': acaoValidade,
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> monitorarAcoesValidade({
    required String mercadoId,
    required List<Map<String, dynamic>> estoques,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-acoes-validade',
      body: {
        'acao': 'monitorar',
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
        'estoques': estoques,
      },
    );

    final data = _validarResposta(resposta);

    return {
      'atualizadas': List<Map<String, dynamic>>.from(
        data['atualizadas'] ?? const [],
      ),
      'encerradas': List<Map<String, dynamic>>.from(
        data['encerradas'] ?? const [],
      ),
    };
  }

  Future<Map<String, dynamic>> encerrarAcaoValidade({
    required String mercadoId,
    required String acaoId,
    required String motivo,
    required double estoqueAtual,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-acoes-validade',
      body: {
        'acao': 'encerrar',
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
        'acao_id': acaoId,
        'motivo': motivo,
        'estoque_atual': estoqueAtual,
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<void> marcarAlertaAcaoValidadeLido({
    required String mercadoId,
    String? alertaId,
    String? acaoId,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-acoes-validade',
      body: {
        'acao': 'marcar_alerta_lido',
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
        if (alertaId != null && alertaId.trim().isNotEmpty)
          'alerta_id': alertaId,
        if (acaoId != null && acaoId.trim().isNotEmpty) 'acao_id': acaoId,
      },
    );

    _validarResposta(resposta);
  }

  Future<Map<String, String>> buscarImagensProdutos({
    required String mercadoId,
    required List<Map<String, dynamic>> produtos,
  }) async {
    final listaProdutos = produtos
        .map((produto) {
          final ean =
              (produto['ean'] ??
                      produto['ean_principal'] ??
                      produto['codigo_barras'] ??
                      produto['codigo'] ??
                      '')
                  .toString();

          final nomeProduto =
              (produto['nome_produto'] ??
                      produto['nome'] ??
                      produto['descricao'] ??
                      produto['produto'] ??
                      '')
                  .toString();

          return {'ean': ean, 'nome_produto': nomeProduto};
        })
        .where((produto) {
          return produto['ean'].toString().trim().isNotEmpty;
        })
        .toList();

    if (listaProdutos.isEmpty) {
      return {};
    }

    final resposta = await _invokeCentral(
      'buscar-imagens-produtos',
      body: {
        'mercado_id': mercadoId,
        'produtos': listaProdutos,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
      },
    );

    final data = _validarResposta(resposta);

    final imagens = data['imagens'];

    if (imagens == null) {
      return {};
    }

    final resultado = <String, String>{};

    for (final item in imagens) {
      final ean = item['ean']?.toString() ?? '';
      final imagemUrl = item['imagem_url']?.toString() ?? '';

      if (ean.isNotEmpty && imagemUrl.isNotEmpty) {
        resultado[ean] = imagemUrl;
      }
    }

    return resultado;
  }

  Future<Map<String, dynamic>> buscarImagemProdutoCentral({
    required String mercadoId,
    String? mercadoCodigo,
    String? ean,
    String? codigoBarras,
    String? nomeProduto,
  }) async {
    final resposta = await _invokeCentral(
      'buscar-imagem-produto',
      body: {
        'mercado_id': mercadoId,
        'mercado_codigo': mercadoCodigo ?? _mercadoCodigoAtual(mercadoId),
        'ean': ean,
        'codigo_barras': codigoBarras,
        'nome_produto': nomeProduto,
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> salvarImagemProdutoCentral({
    required String mercadoId,
    String? mercadoCodigo,
    required String imagemUrl,
    String? ean,
    String? codigoBarras,
    String? nomeProduto,
  }) async {
    final resposta = await _invokeCentral(
      'buscar-imagem-produto',
      body: {
        'acao': 'salvar_imagem',
        'mercado_id': mercadoId,
        'mercado_codigo': mercadoCodigo ?? _mercadoCodigoAtual(mercadoId),
        'ean': ean,
        'codigo_barras': codigoBarras,
        'nome_produto': nomeProduto,
        'imagem_url': imagemUrl,
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> alterarPrecoProdutoApi({
    required String mercadoId,
    String? mercadoCodigo,
    required Map<String, dynamic> produto,
    required double preco,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-acoes-validade',
      body: {
        'acao': 'alterar_preco',
        'mercado_id': mercadoId,
        'mercado_codigo': mercadoCodigo ?? _mercadoCodigoAtual(mercadoId),
        'produto': produto,
        'preco': preco,
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> atualizarMercado({
    required String mercadoId,
    required String nome,
    required String codigo,
    required bool ativo,
    required String cidade,
    required String estado,
    required String apiBaseUrl,
    required String supabaseUrl,
    required String supabaseAnonKey,
    String? supabaseServiceRoleKey,
    required bool usarApiImagens,
    String fonteProdutos = 'API',
    String? serpapiKey,

    // Cores dinâmicas do layout Admin.
    String? adminCorPrimaria,
    String? adminCorSecundaria,
    String? adminCorFundo,

    // Cores dinâmicas do App Mercado/Cliente.
    String? clienteCorPrimaria,
    String? clienteCorSecundaria,
    String? clienteCorFundo,

    // Configuração de autorização para update de estoque pela API da loja.
    String? estoqueUpdateToken,
    bool estoqueUpdateTokenAtivo = false,
    bool estoqueDetalhadoAtivo = false,
    bool alterarPrecoConsultaAtivo = false,

    // Campos antigos mantidos por compatibilidade.
    // Eles representam o APK Mercado/Cliente.
    bool apkPersonalizado = false,
    String? appNome,
    String? appPackage,
    String? appBuildCodigo,
    String? logoLoginUrl,
    String? logoLoginPath,
    String? logoUrl,
    String? logoPath,
    String? splashLogoUrl,
    String? splashLogoPath,
    String? appIconeUrl,
    String? appIconePath,
    String? mercadoSplashLogoUrl,
    String? mercadoSplashLogoPath,
    String? mercadoAppIconeUrl,
    String? mercadoAppIconePath,

    // Configuração separada do APK Admin.
    bool gerarApkAdmin = false,
    String? adminAppNome,
    String? adminAppPackage,
    String? adminAppBuildCodigo,

    // Configuração separada do APK Mercado/Cliente.
    bool gerarApkMercado = false,
    String? mercadoAppNome,
    String? mercadoAppPackage,
    String? mercadoAppBuildCodigo,
  }) async {
    final gerarMercadoFinal = gerarApkMercado || apkPersonalizado;

    final mercadoAppNomeFinal = mercadoAppNome ?? appNome;
    final mercadoAppPackageFinal = mercadoAppPackage ?? appPackage;
    final mercadoAppBuildCodigoFinal = mercadoAppBuildCodigo ?? appBuildCodigo;

    final resposta = await _invokeCentral(
      'atualizar-mercado',
      body: {
        'mercado_id': mercadoId,
        'nome': nome,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),

        'codigo': codigo,
        'ativo': ativo,
        'cidade': cidade,
        'estado': estado,
        'api_base_url': apiBaseUrl,
        'supabase_url': supabaseUrl,
        'supabase_anon_key': supabaseAnonKey,
        'supabase_service_role_key': supabaseServiceRoleKey,
        'usar_api_imagens': usarApiImagens,
        'fonte_produtos': fonteProdutos,
        'serpapi_key': serpapiKey,
        'admin_cor_primaria': adminCorPrimaria,
        'admin_cor_secundaria': adminCorSecundaria,
        'admin_cor_fundo': adminCorFundo,
        'cliente_cor_primaria': clienteCorPrimaria,
        'cliente_cor_secundaria': clienteCorSecundaria,
        'cliente_cor_fundo': clienteCorFundo,
        'estoque_update_token': estoqueUpdateToken,
        'estoque_update_token_ativo': estoqueUpdateTokenAtivo,
        'estoque_detalhado_ativo': estoqueDetalhadoAtivo,
        'alterar_preco_consulta_ativo': alterarPrecoConsultaAtivo,

        // APK Admin
        'gerar_apk_admin': gerarApkAdmin,
        'admin_app_nome': adminAppNome,
        'admin_app_package': adminAppPackage,
        'admin_app_build_codigo': adminAppBuildCodigo,

        // APK Mercado / Cliente
        'gerar_apk_mercado': gerarMercadoFinal,
        'mercado_app_nome': mercadoAppNomeFinal,
        'mercado_app_package': mercadoAppPackageFinal,
        'mercado_app_build_codigo': mercadoAppBuildCodigoFinal,

        // Compatibilidade com os campos antigos.
        'apk_personalizado': gerarMercadoFinal,
        'app_nome': mercadoAppNomeFinal,
        'app_package': mercadoAppPackageFinal,
        'app_build_codigo': mercadoAppBuildCodigoFinal,
        'logo_login_url': logoLoginUrl,
        'logo_login_path': logoLoginPath,
        'logo_url': logoUrl,
        'logo_path': logoPath,
        'splash_logo_url': splashLogoUrl,
        'splash_logo_path': splashLogoPath,
        'app_icone_url': appIconeUrl,
        'app_icone_path': appIconePath,
        'mercado_splash_logo_url': mercadoSplashLogoUrl,
        'mercado_splash_logo_path': mercadoSplashLogoPath,
        'mercado_app_icone_url': mercadoAppIconeUrl,
        'mercado_app_icone_path': mercadoAppIconePath,
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> buscarConexaoMercado(String mercadoId) async {
    final resposta = await _invokeCentral(
      'buscar-conexao-mercado',
      body: {
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
      },
    );

    final data = _validarResposta(resposta);

    final conexao = data['conexao'];

    if (conexao == null) {
      throw Exception('Conexão do mercado não encontrada');
    }

    return Map<String, dynamic>.from(conexao);
  }

  Future<Map<String, dynamic>> cadastrarMercado({
    required String nome,
    required String codigo,
    required String cidade,
    required String estado,
    required String apiBaseUrl,
    required String supabaseUrl,
    required String supabaseAnonKey,
    String? supabaseServiceRoleKey,
    required bool usarApiImagens,
    String fonteProdutos = 'API',
    String? serpapiKey,

    // Cores dinâmicas do layout Admin.
    String? adminCorPrimaria,
    String? adminCorSecundaria,
    String? adminCorFundo,

    // Cores dinâmicas do App Mercado/Cliente.
    String? clienteCorPrimaria,
    String? clienteCorSecundaria,
    String? clienteCorFundo,

    // Configuração de autorização para update de estoque pela API da loja.
    String? estoqueUpdateToken,
    bool estoqueUpdateTokenAtivo = false,
    bool estoqueDetalhadoAtivo = false,
    bool alterarPrecoConsultaAtivo = false,

    // Campos antigos mantidos por compatibilidade.
    // Eles representam o APK Mercado/Cliente.
    bool apkPersonalizado = false,
    String? appNome,
    String? appPackage,
    String? appBuildCodigo,
    String? logoLoginUrl,
    String? logoLoginPath,
    String? logoUrl,
    String? logoPath,
    String? splashLogoUrl,
    String? splashLogoPath,
    String? appIconeUrl,
    String? appIconePath,
    String? mercadoSplashLogoUrl,
    String? mercadoSplashLogoPath,
    String? mercadoAppIconeUrl,
    String? mercadoAppIconePath,

    // Configuração separada do APK Admin.
    bool gerarApkAdmin = false,
    String? adminAppNome,
    String? adminAppPackage,
    String? adminAppBuildCodigo,

    // Configuração separada do APK Mercado/Cliente.
    bool gerarApkMercado = false,
    String? mercadoAppNome,
    String? mercadoAppPackage,
    String? mercadoAppBuildCodigo,
  }) async {
    final gerarMercadoFinal = gerarApkMercado || apkPersonalizado;

    final mercadoAppNomeFinal = mercadoAppNome ?? appNome;
    final mercadoAppPackageFinal = mercadoAppPackage ?? appPackage;
    final mercadoAppBuildCodigoFinal = mercadoAppBuildCodigo ?? appBuildCodigo;

    final resposta = await _invokeCentral(
      'cadastrar-mercado',
      body: {
        'nome': nome,
        'codigo': codigo,
        'cidade': cidade,
        'estado': estado,
        'api_base_url': apiBaseUrl,
        'supabase_url': supabaseUrl,
        'supabase_anon_key': supabaseAnonKey,
        'supabase_service_role_key': supabaseServiceRoleKey,
        'usar_api_imagens': usarApiImagens,
        'fonte_produtos': fonteProdutos,
        'serpapi_key': serpapiKey,
        'admin_cor_primaria': adminCorPrimaria,
        'admin_cor_secundaria': adminCorSecundaria,
        'admin_cor_fundo': adminCorFundo,
        'cliente_cor_primaria': clienteCorPrimaria,
        'cliente_cor_secundaria': clienteCorSecundaria,
        'cliente_cor_fundo': clienteCorFundo,
        'estoque_update_token': estoqueUpdateToken,
        'estoque_update_token_ativo': estoqueUpdateTokenAtivo,
        'estoque_detalhado_ativo': estoqueDetalhadoAtivo,
        'alterar_preco_consulta_ativo': alterarPrecoConsultaAtivo,

        // APK Admin
        'gerar_apk_admin': gerarApkAdmin,
        'admin_app_nome': adminAppNome,
        'admin_app_package': adminAppPackage,
        'admin_app_build_codigo': adminAppBuildCodigo,

        // APK Mercado / Cliente
        'gerar_apk_mercado': gerarMercadoFinal,
        'mercado_app_nome': mercadoAppNomeFinal,
        'mercado_app_package': mercadoAppPackageFinal,
        'mercado_app_build_codigo': mercadoAppBuildCodigoFinal,

        // Compatibilidade com os campos antigos.
        'apk_personalizado': gerarMercadoFinal,
        'app_nome': mercadoAppNomeFinal,
        'app_package': mercadoAppPackageFinal,
        'app_build_codigo': mercadoAppBuildCodigoFinal,
        'logo_login_url': logoLoginUrl,
        'logo_login_path': logoLoginPath,
        'logo_url': logoUrl,
        'logo_path': logoPath,
        'splash_logo_url': splashLogoUrl,
        'splash_logo_path': splashLogoPath,
        'app_icone_url': appIconeUrl,
        'app_icone_path': appIconePath,
        'mercado_splash_logo_url': mercadoSplashLogoUrl,
        'mercado_splash_logo_path': mercadoSplashLogoPath,
        'mercado_app_icone_url': mercadoAppIconeUrl,
        'mercado_app_icone_path': mercadoAppIconePath,
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> cadastrarUsuarioMercado({
    required String mercadoId,
    required String nome,
    required String login,
    required String senha,
    required String perfil,
    List<String> permissoes = const [],
  }) async {
    final resposta = await _invokeCentral(
      'cadastrar-usuario-mercado',
      body: {
        'mercado_id': mercadoId,
        'nome': nome,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),

        'login': login,
        'senha': senha,
        'perfil': perfil,
        'permissoes': permissoes,
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> listarModulosLoja({
    required String mercadoId,
  }) async {
    final resposta = await _invokeCentral(
      'listar-modulos-loja',
      body: {
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> salvarModulosLoja({
    required String mercadoId,
    required List<String> modulosLiberados,
  }) async {
    final resposta = await _invokeCentral(
      'salvar-modulos-loja',
      body: {
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
        'modulos_liberados': modulosLiberados,
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<List<Map<String, dynamic>>> listarUsuariosSistema({
    required String mercadoId,
  }) async {
    final resposta = await _invokeCentral(
      'listar-usuarios-sistema',
      body: {
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
      },
    );

    final data = _validarResposta(resposta);

    final usuarios = data['usuarios'];

    if (usuarios == null) {
      return [];
    }

    return List<Map<String, dynamic>>.from(usuarios);
  }

  Future<Map<String, dynamic>> editarUsuarioSistema({
    required String mercadoId,
    required String userId,
    required String nome,
    required String login,
    required String perfil,
    required bool ativo,
  }) async {
    final resposta = await _invokeCentral(
      'editar-usuario-sistema',
      body: {
        'mercado_id': mercadoId,
        'user_id': userId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),

        'nome': nome,
        'login': login,
        'perfil': perfil,
        'ativo': ativo,
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> resetarSenhaUsuario({
    required String mercadoId,
    required String userId,
    required String novaSenha,
  }) async {
    final resposta = await _invokeCentral(
      'resetar-senha-usuario',
      body: {
        'mercado_id': mercadoId,
        'user_id': userId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),

        'nova_senha': novaSenha,
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> excluirUsuarioSistema({
    required String mercadoId,
    required String userId,
  }) async {
    final resposta = await _invokeCentral(
      'excluir-usuario-sistema',
      body: {
        'mercado_id': mercadoId,
        'user_id': userId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> listarPermissoesUsuario({
    required String mercadoId,
    required String userId,
  }) async {
    final resposta = await _invokeCentral(
      'listar-permissoes-usuario',
      body: {
        'mercado_id': mercadoId,
        'user_id': userId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> salvarPermissoesUsuario({
    required String mercadoId,
    required String userId,
    required List<String> permissoes,
  }) async {
    final resposta = await _invokeCentral(
      'salvar-permissoes-usuario',
      body: {
        'mercado_id': mercadoId,
        'user_id': userId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),

        'permissoes': permissoes,
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<List<Map<String, dynamic>>> listarClientesApp({
    required String mercadoId,
    String busca = '',
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-clientes-app',
      body: {
        'acao': 'listar',
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
        'busca': busca,
      },
    );

    final data = _validarResposta(resposta);
    final clientes = data['clientes'];

    if (clientes == null) {
      return [];
    }

    return List<Map<String, dynamic>>.from(clientes);
  }

  Future<Map<String, dynamic>> alterarBloqueioClienteApp({
    required String mercadoId,
    required String clienteId,
    required bool bloqueado,
    String motivo = '',
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-clientes-app',
      body: {
        'acao': 'alterar_bloqueio',
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
        'cliente_id': clienteId,
        'bloqueado': bloqueado,
        'motivo': motivo.trim(),
      },
    );

    final data = _validarResposta(resposta);
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> salvarCategoriasBloqueadasClienteApp({
    required String mercadoId,
    required String clienteId,
    required List<String> categorias,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-clientes-app',
      body: {
        'acao': 'salvar_categorias_bloqueadas',
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
        'cliente_id': clienteId,
        'categorias_bloqueadas': categorias,
      },
    );

    final data = _validarResposta(resposta);
    return Map<String, dynamic>.from(data);
  }

  Future<List<String>> listarMotivosConsumoInterno({
    required String mercadoId,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-motivos-consumo-interno',
      body: {
        'acao': 'listar',
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
      },
    );

    final data = _validarResposta(resposta);
    final motivos = data['motivos'];

    if (motivos is! List) {
      return [];
    }

    return motivos
        .map((motivo) => motivo is Map ? motivo['nome'] : motivo)
        .map((nome) => nome?.toString().trim() ?? '')
        .where((nome) => nome.isNotEmpty)
        .toList();
  }

  Future<String> cadastrarMotivoConsumoInterno({
    required String mercadoId,
    required String nome,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-motivos-consumo-interno',
      body: {
        'acao': 'cadastrar',
        'mercado_id': mercadoId,
        if (_mercadoCodigoAtual(mercadoId) != null)
          'mercado_codigo': _mercadoCodigoAtual(mercadoId),
        'nome': nome.trim(),
      },
    );

    final data = _validarResposta(resposta);
    final motivo = data['motivo'];

    if (motivo is Map) {
      return motivo['nome']?.toString().trim() ?? nome.trim();
    }

    return nome.trim();
  }

  Future<List<Map<String, dynamic>>> listarProdutosApp({
    required String mercadoId,
    String? mercadoCodigo,
    String busca = '',
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-produtos-app',
      body: {
        'acao': 'listar',
        'mercado_id': mercadoId,
        'mercado_codigo': mercadoCodigo ?? _mercadoCodigoAtual(mercadoId),
        'busca': busca,
      },
    );

    final data = _validarResposta(resposta);
    final produtos = data['produtos'];

    if (produtos == null) {
      return [];
    }

    return List<Map<String, dynamic>>.from(produtos);
  }

  Future<List<Map<String, dynamic>>> listarProdutosAppEstoque({
    required String mercadoId,
    String? mercadoCodigo,
    String busca = '',
    int limite = 300,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-produtos-app',
      body: {
        'acao': 'listar_estoque',
        'mercado_id': mercadoId,
        'mercado_codigo': mercadoCodigo ?? _mercadoCodigoAtual(mercadoId),
        'busca': busca,
        'limite': limite,
      },
    );

    final data = _validarResposta(resposta);
    final produtos = data['produtos'];

    if (produtos == null) {
      return [];
    }

    return List<Map<String, dynamic>>.from(produtos);
  }

  Future<Map<String, dynamic>> salvarProdutoApp({
    required String mercadoId,
    String? mercadoCodigo,
    String? id,
    required Map<String, dynamic> produto,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-produtos-app',
      body: {
        'acao': 'salvar',
        'mercado_id': mercadoId,
        'mercado_codigo': mercadoCodigo ?? _mercadoCodigoAtual(mercadoId),
        if (id != null && id.trim().isNotEmpty) 'id': id.trim(),
        'produto': produto,
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> atualizarEstoqueProdutoApp({
    required String mercadoId,
    String? mercadoCodigo,
    required String id,
    required String tipoMovimentacao,
    required double quantidade,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-produtos-app',
      body: {
        'acao': 'atualizar_estoque',
        'mercado_id': mercadoId,
        'mercado_codigo': mercadoCodigo ?? _mercadoCodigoAtual(mercadoId),
        'id': id,
        'tipo_movimentacao': tipoMovimentacao,
        'quantidade': quantidade,
        'estoque_novo': quantidade,
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> uploadImagemProdutoApp({
    required String mercadoId,
    String? mercadoCodigo,
    required File imagemFile,
    String? ean,
    String? codigoBarras,
    String? nomeProduto,
  }) async {
    final extensao = imagemFile.path.split('.').last.toLowerCase();
    final bytes = await imagemFile.readAsBytes();

    final resposta = await _invokeCentral(
      'gerenciar-produtos-app',
      body: {
        'acao': 'upload_imagem',
        'mercado_id': mercadoId,
        'mercado_codigo': mercadoCodigo ?? _mercadoCodigoAtual(mercadoId),
        'ean': ean,
        'codigo_barras': codigoBarras,
        'nome_produto': nomeProduto,
        'nome_arquivo': imagemFile.path.split(Platform.pathSeparator).last,
        'content_type': _contentTypeImagem(extensao),
        'imagem_base64': base64Encode(bytes),
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> uploadLogoConfiguracaoLoja({
    required String mercadoId,
    String? mercadoCodigo,
    String tipoLogo = 'mercado',
    required File logoFile,
  }) async {
    final extensao = logoFile.path.split('.').last.toLowerCase();
    final bytes = await logoFile.readAsBytes();

    final resposta = await _invokeCentral(
      'gerenciar-produtos-app',
      body: {
        'acao': 'upload_logo_loja',
        'mercado_id': mercadoId,
        'mercado_codigo': mercadoCodigo ?? _mercadoCodigoAtual(mercadoId),
        'tipo_logo': tipoLogo,
        'nome_arquivo': logoFile.path.split(Platform.pathSeparator).last,
        'content_type': _contentTypeImagem(extensao),
        'imagem_base64': base64Encode(bytes),
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> alternarProdutoApp({
    required String mercadoId,
    String? mercadoCodigo,
    required String id,
    required bool ativo,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-produtos-app',
      body: {
        'acao': 'alternar',
        'mercado_id': mercadoId,
        'mercado_codigo': mercadoCodigo ?? _mercadoCodigoAtual(mercadoId),
        'id': id,
        'ativo': ativo,
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> excluirProdutoApp({
    required String mercadoId,
    String? mercadoCodigo,
    required String id,
  }) async {
    final resposta = await _invokeCentral(
      'gerenciar-produtos-app',
      body: {
        'acao': 'excluir',
        'mercado_id': mercadoId,
        'mercado_codigo': mercadoCodigo ?? _mercadoCodigoAtual(mercadoId),
        'id': id,
      },
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> cadastrarUsuarioMaster({
    required String nome,
    required String login,
    required String senha,
  }) async {
    final resposta = await _invokeCentral(
      'cadastrar-usuario-master',
      body: {'nome': nome, 'login': login, 'senha': senha},
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<List<Map<String, dynamic>>> listarUsuariosMaster() async {
    final resposta = await _invokeCentral('listar-usuarios-master', body: {});

    final data = _validarResposta(resposta);

    final usuarios = data['usuarios'];

    if (usuarios == null) {
      return [];
    }

    return List<Map<String, dynamic>>.from(usuarios);
  }

  Future<Map<String, dynamic>> editarUsuarioMaster({
    required String userId,
    required String nome,
    required String email,
    required bool ativo,
  }) async {
    final resposta = await _invokeCentral(
      'editar-usuario-master',
      body: {'user_id': userId, 'nome': nome, 'email': email, 'ativo': ativo},
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> resetarSenhaMaster({
    required String userId,
    required String novaSenha,
  }) async {
    final resposta = await _invokeCentral(
      'resetar-senha-master',
      body: {'user_id': userId, 'nova_senha': novaSenha},
    );

    final data = _validarResposta(resposta);

    return Map<String, dynamic>.from(data);
  }
}

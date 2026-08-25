const String mensagemSemInternet =
    'Sem conexão com a internet. Verifique o Wi-Fi ou os dados móveis e tente novamente.';

bool erroDeConexao(Object erro) {
  final texto = erro.toString().toLowerCase();

  return <String>[
    'socketexception',
    'clientexception',
    'failed host lookup',
    'no address associated with hostname',
    'network is unreachable',
    'network request failed',
    'connection refused',
    'connection reset',
    'connection closed',
    'connection aborted',
    'software caused connection abort',
    'xmlhttprequest error',
    'fetch failed',
    'timeoutexception',
    'timed out',
    'connection timeout',
    'handshakeexception',
  ].any(texto.contains);
}

String mensagemErroAmigavel(Object erro, {required String mensagemPadrao}) {
  if (erroDeConexao(erro)) {
    return mensagemSemInternet;
  }

  return mensagemPadrao;
}

String mensagemErroAutenticacao(Object erro) {
  if (erroDeConexao(erro)) {
    return mensagemSemInternet;
  }

  final texto = erro.toString().toLowerCase();

  if (texto.contains('invalid login credentials') ||
      texto.contains('invalid credentials')) {
    return 'E-mail ou senha inválidos.';
  }

  if (texto.contains('email not confirmed')) {
    return 'Confirme seu e-mail antes de entrar.';
  }

  if (texto.contains('user already registered') ||
      texto.contains('already been registered')) {
    return 'Este e-mail já possui cadastro.';
  }

  if (texto.contains('rate limit') || texto.contains('too many requests')) {
    return 'Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.';
  }

  return 'Não foi possível concluir a autenticação. Tente novamente.';
}

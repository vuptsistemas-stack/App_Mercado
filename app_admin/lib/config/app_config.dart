class AppConfig {
  static const String mercadoCodigoFixo = String.fromEnvironment(
    'MERCADO_CODIGO',
    defaultValue: '',
  );

  static const String nomeApp = String.fromEnvironment(
    'NOME_APP',
    defaultValue: 'App Preço',
  );

  static const String appPackage = String.fromEnvironment(
    'APP_PACKAGE',
    defaultValue: 'br.com.apppreco.app',
  );

  static bool get apkDeLojaFixa {
    return mercadoCodigoFixo.trim().isNotEmpty;
  }

  static bool get apkMultiLoja {
    return mercadoCodigoFixo.trim().isEmpty;
  }
}
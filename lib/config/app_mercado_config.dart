class AppMercadoConfig {
  const AppMercadoConfig._();

  /// Nome do app enviado no build.
  ///
  /// Exemplo:
  /// --dart-define=APP_NAME=SM Compras
  static const String appName = String.fromEnvironment(
    'APP_NAME',
    defaultValue: 'App Mercado',
  );

  /// Package instalado no Android enviado no build.
  ///
  /// Exemplo:
  /// --dart-define=APP_PACKAGE=br.com.apppreco.mercado.saomateus
  static const String appPackage = String.fromEnvironment(
    'APP_PACKAGE',
    defaultValue: 'br.com.apppreco.appmercado',
  );


  /// ID da loja na base Central.
  ///
  /// A function atual buscar-conexao-mercado exige mercado_id.
  /// No APK personalizado, o script deverá enviar:
  /// --dart-define=MERCADO_ID=ID_DA_LOJA
  ///
  /// Para desenvolvimento, deixei o São Mateus como padrão.
  static const String mercadoId = String.fromEnvironment(
    'MERCADO_ID',
    defaultValue: '464a6ab3-31ed-431b-a43a-e8cd57d7c44e',
  );

  /// Código da loja na base Central.
  ///
  /// Mantemos também o código porque ele é útil para identificação,
  /// logs, app personalizado e compatibilidade futura.
  ///
  /// No APK personalizado, o script deverá enviar:
  /// --dart-define=MERCADO_CODIGO=sao_mateus
  static const String mercadoCodigo = String.fromEnvironment(
    'MERCADO_CODIGO',
    defaultValue: 'sao_mateus',
  );

  /// Fonte dos produtos enviada no build.
  ///
  /// Valores esperados:
  /// API ou BANCO_LOJA
  static const String fonteProdutos = String.fromEnvironment(
    'FONTE_PRODUTOS',
    defaultValue: 'API',
  );

  /// URL da base Central.
  static const String centralSupabaseUrl =
      'https://pkrkeeupcvxnqhynfvbw.supabase.co';

  /// ANON KEY da base Central.
  ///
  /// Nunca coloque service_role_key no app.
  static const String centralSupabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBrcmtlZXVwY3Z4bnFoeW5mdmJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE3MjAyNjQsImV4cCI6MjA5NzI5NjI2NH0.THMGXQ24hOWVt_UDxy-qlW6_BGfFt2vkLB1I9j4dGi0';

  static String get mercadoIdObrigatorio {
    final id = mercadoId.trim();

    if (id.isEmpty) {
      throw Exception(
        'MERCADO_ID não informado. Gere o APK pelo script da loja.',
      );
    }

    return id;
  }

  static String get mercadoCodigoObrigatorio {
    final codigo = mercadoCodigo.trim();

    if (codigo.isEmpty) {
      throw Exception(
        'MERCADO_CODIGO não informado. Gere o APK pelo script da loja.',
      );
    }

    return codigo;
  }
}

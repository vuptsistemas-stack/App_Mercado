import '../config/app_mercado_config.dart';

class OnboardingMercadoSlide {
  final int ordem;
  final String titulo;
  final String subtitulo;
  final String imagemUrl;

  const OnboardingMercadoSlide({
    required this.ordem,
    required this.titulo,
    required this.subtitulo,
    required this.imagemUrl,
  });
}

class SessaoMercadoCliente {
  SessaoMercadoCliente._();

  static bool carregado = false;

  static String mercadoId = '';
  static String mercadoCodigo = '';
  static String mercadoNome = '';

  static String supabaseUrl = '';
  static String supabaseAnonKey = '';

  static String apiBaseUrl = '';
  static String fonteProdutosCentral = '';
  static String logoUrl = '';
  static String whatsapp = '';

  static bool ativo = true;
  static bool cobrarFrete = true;
  static bool exibirOnboarding = true;

  // Personalização dinâmica do login do app cliente.
  static String clienteCorPrimaria = '#E30613';
  static String clienteCorSecundaria = '#C90010';
  static String clienteCorFundo = '#FFF7F7';
  static String clienteLoginTitulo = '';
  static String clienteLoginSubtitulo = '';
  static String clienteLoginImagemUrl = '';

  static double pedidoMinimo = 0;
  static double taxaEntrega = 0;
  static double valorFreteGratis = 0;

  static List<OnboardingMercadoSlide> onboardingSlides = [];

  static Map<String, dynamic> dadosOriginais = {};

  static void carregarDaCentral(Map<String, dynamic> dados) {
    dadosOriginais = Map<String, dynamic>.from(dados);
    final lojaConfiguracoesRaw = dados['loja_configuracoes'];
    final lojaConfiguracoes = lojaConfiguracoesRaw is Map
        ? Map<String, dynamic>.from(lojaConfiguracoesRaw)
        : <String, dynamic>{};

    mercadoId = primeiroTexto(
      dados['mercado_id'],
      dados['id'],
      dados['loja_id'],
      AppMercadoConfig.mercadoId,
    );

    mercadoCodigo = primeiroTexto(
      dados['mercado_codigo'],
      dados['codigo'],
      dados['app_build_codigo'],
      AppMercadoConfig.mercadoCodigo,
    );

    mercadoNome = texto(
      dados['mercado_nome'] ??
          dados['nome'] ??
          dados['nome_loja'] ??
          dados['app_nome'],
    );

    supabaseUrl = texto(dados['supabase_url'] ?? dados['loja_supabase_url']);

    supabaseAnonKey = texto(
      dados['supabase_anon_key'] ??
          dados['anon_key'] ??
          dados['loja_supabase_anon_key'],
    );

    apiBaseUrl = texto(
      dados['api_base_url'] ?? dados['api_url'] ?? dados['url_api'],
    );

    fonteProdutosCentral = primeiroTexto(
      dados['fonte_produtos'],
      dados['fonteProdutos'],
      AppMercadoConfig.fonteProdutos,
    ).toUpperCase();

    logoUrl = texto(
      dados['logo_url'] ?? dados['logo_login_url'] ?? dados['app_logo_url'],
    );

    whatsapp = texto(
      dados['whatsapp'] ??
          dados['telefone_whatsapp'] ??
          lojaConfiguracoes['whatsapp'] ??
          lojaConfiguracoes['telefone_whatsapp'] ??
          lojaConfiguracoes['telefone_loja'] ??
          lojaConfiguracoes['telefone'] ??
          lojaConfiguracoes['celular'] ??
          dados['telefone'] ??
          dados['telefone_loja'],
    );

    ativo = boolDinamico(
      dados['ativo'] ?? dados['loja_ativa'] ?? dados['mercado_ativo'],
      padrao: true,
    );

    cobrarFrete = boolDinamico(
      dados['cobrar_frete'] ?? lojaConfiguracoes['cobrar_frete'],
      padrao: true,
    );

    exibirOnboarding = boolDinamico(
      dados['exibir_onboarding'] ?? dados['onboarding_ativo'],
      padrao: true,
    );

    pedidoMinimo = numeroDinamico(
      dados['pedido_minimo'] ?? lojaConfiguracoes['pedido_minimo'],
    );
    taxaEntrega = numeroDinamico(
      dados['taxa_entrega'] ??
          lojaConfiguracoes['frete_taxa_base'] ??
          lojaConfiguracoes['taxa_entrega'],
    );
    valorFreteGratis = numeroDinamico(
      dados['valor_frete_gratis'] ??
          dados['frete_gratis_acima'] ??
          lojaConfiguracoes['frete_gratis_acima'] ??
          lojaConfiguracoes['valor_frete_gratis'],
    );

    clienteCorPrimaria = primeiroTexto(
      dados['cliente_cor_primaria'],
      dados['login_cor_primaria'],
      '#E30613',
    );

    clienteCorSecundaria = primeiroTexto(
      dados['cliente_cor_secundaria'],
      dados['login_cor_secundaria'],
      '#C90010',
    );

    clienteCorFundo = primeiroTexto(
      dados['cliente_cor_fundo'],
      dados['login_cor_fundo'],
      '#FFF7F7',
    );

    clienteLoginTitulo = primeiroTexto(
      dados['cliente_login_titulo'],
      dados['login_titulo'],
      mercadoNome,
      'Mercado Online',
    );

    clienteLoginSubtitulo = primeiroTexto(
      dados['cliente_login_subtitulo'],
      dados['login_subtitulo'],
      'Compre e receba em casa',
    );

    clienteLoginImagemUrl = primeiroTexto(
      dados['cliente_login_imagem_url'],
      dados['login_imagem_url'],
    );

    onboardingSlides = carregarSlidesOnboarding(dados);

    carregado = true;
  }

  static List<OnboardingMercadoSlide> carregarSlidesOnboarding(
    Map<String, dynamic> dados,
  ) {
    final slides = <OnboardingMercadoSlide>[];

    final listaDinamica =
        dados['onboarding'] ??
        dados['onboarding_slides'] ??
        dados['slides_onboarding'];

    if (listaDinamica is List) {
      for (final item in listaDinamica) {
        if (item is Map) {
          final slide = normalizarSlideOnboarding(item);

          if (slide != null) {
            slides.add(slide);
          }
        }
      }
    }

    if (slides.isEmpty) {
      for (var i = 1; i <= 5; i++) {
        final titulo = texto(
          dados['onboarding_${i}_titulo'] ??
              dados['onboarding${i}_titulo'] ??
              dados['slide_${i}_titulo'],
        );

        final subtitulo = texto(
          dados['onboarding_${i}_subtitulo'] ??
              dados['onboarding${i}_subtitulo'] ??
              dados['slide_${i}_subtitulo'],
        );

        final imagemUrl = texto(
          dados['onboarding_${i}_imagem_url'] ??
              dados['onboarding${i}_imagem_url'] ??
              dados['slide_${i}_imagem_url'],
        );

        if (titulo.isNotEmpty || subtitulo.isNotEmpty || imagemUrl.isNotEmpty) {
          slides.add(
            OnboardingMercadoSlide(
              ordem: i,
              titulo: titulo.isEmpty ? tituloPadraoOnboarding(i) : titulo,
              subtitulo: subtitulo.isEmpty
                  ? subtituloPadraoOnboarding(i)
                  : subtitulo,
              imagemUrl: imagemUrl,
            ),
          );
        }
      }
    }

    if (slides.isEmpty) {
      return slidesPadraoOnboarding();
    }

    slides.sort((a, b) => a.ordem.compareTo(b.ordem));

    return slides;
  }

  static OnboardingMercadoSlide? normalizarSlideOnboarding(Map item) {
    final ativoSlide = boolDinamico(item['ativo'], padrao: true);

    if (!ativoSlide) {
      return null;
    }

    final ordem =
        int.tryParse(
          texto(item['ordem'] ?? item['posicao'] ?? item['index']),
        ) ??
        999;

    final titulo = texto(item['titulo'] ?? item['title']);
    final subtitulo = texto(
      item['subtitulo'] ?? item['descricao'] ?? item['subtitle'],
    );
    final imagemUrl = texto(
      item['imagem_url'] ??
          item['imagemUrl'] ??
          item['image_url'] ??
          item['url'],
    );

    if (titulo.isEmpty && subtitulo.isEmpty && imagemUrl.isEmpty) {
      return null;
    }

    return OnboardingMercadoSlide(
      ordem: ordem,
      titulo: titulo.isEmpty ? tituloPadraoOnboarding(ordem) : titulo,
      subtitulo: subtitulo.isEmpty
          ? subtituloPadraoOnboarding(ordem)
          : subtitulo,
      imagemUrl: imagemUrl,
    );
  }

  static List<OnboardingMercadoSlide> slidesPadraoOnboarding() {
    return const [
      OnboardingMercadoSlide(
        ordem: 1,
        titulo: 'Ofertas todos os dias',
        subtitulo:
            'Acompanhe promoções, novidades e preços especiais direto no app.',
        imagemUrl: '',
      ),
      OnboardingMercadoSlide(
        ordem: 2,
        titulo: 'Receba suas compras em casa',
        subtitulo:
            'Monte seu carrinho com facilidade e receba tudo com praticidade e rapidez.',
        imagemUrl: '',
      ),
      OnboardingMercadoSlide(
        ordem: 3,
        titulo: 'Compre fácil pelo celular',
        subtitulo:
            'Encontre produtos, acompanhe pedidos e aproveite uma experiência simples e moderna.',
        imagemUrl: '',
      ),
    ];
  }

  static String tituloPadraoOnboarding(int ordem) {
    switch (ordem) {
      case 2:
        return 'Receba suas compras em casa';
      case 3:
        return 'Compre fácil pelo celular';
      default:
        return 'Ofertas todos os dias';
    }
  }

  static String subtituloPadraoOnboarding(int ordem) {
    switch (ordem) {
      case 2:
        return 'Monte seu carrinho com facilidade e receba tudo com praticidade.';
      case 3:
        return 'Encontre produtos e acompanhe seus pedidos de forma simples.';
      default:
        return 'Acompanhe promoções, novidades e preços especiais direto no app.';
    }
  }

  static String get mercadoIdObrigatorio {
    final id = mercadoId.trim().isNotEmpty
        ? mercadoId.trim()
        : AppMercadoConfig.mercadoIdObrigatorio;

    if (id.isEmpty) {
      throw Exception('Mercado não identificado no app.');
    }

    return id;
  }

  static String get mercadoCodigoObrigatorio {
    final codigo = mercadoCodigo.trim().isNotEmpty
        ? mercadoCodigo.trim()
        : AppMercadoConfig.mercadoCodigoObrigatorio;

    if (codigo.isEmpty) {
      throw Exception('Código do mercado não identificado no app.');
    }

    return codigo;
  }

  static String get fonteProdutos {
    final fonteBuild = AppMercadoConfig.fonteProdutos.trim().toUpperCase();
    final fonteCentral = fonteProdutosCentral.trim().toUpperCase();

    // A Central manda a configuração oficial do mercado.
    // Mas, para teste local, se rodar com --dart-define=FONTE_PRODUTOS=BANCO_LOJA,
    // o app força BANCO_LOJA mesmo que a Central ainda esteja em API.
    if (_fonteIndicaBancoLoja(fonteBuild)) {
      return 'BANCO_LOJA';
    }

    if (_fonteIndicaBancoLoja(fonteCentral)) {
      return 'BANCO_LOJA';
    }

    if (_apiBaseUrlIndicaBancoLoja(apiBaseUrl)) {
      return 'BANCO_LOJA';
    }

    return 'API';
  }

  static String get fonteProdutosOrigem {
    final fonteBuild = AppMercadoConfig.fonteProdutos.trim().toUpperCase();
    final fonteCentral = fonteProdutosCentral.trim().toUpperCase();

    if (_fonteIndicaBancoLoja(fonteBuild)) {
      return 'BUILD';
    }

    if (_fonteIndicaBancoLoja(fonteCentral)) {
      return 'CENTRAL';
    }

    if (_apiBaseUrlIndicaBancoLoja(apiBaseUrl)) {
      return 'API_PLACEHOLDER_SUPABASE';
    }

    if (fonteCentral.isNotEmpty) {
      return 'CENTRAL';
    }

    return 'BUILD';
  }

  static bool _fonteIndicaBancoLoja(String valor) {
    final fonte = valor.trim().toUpperCase();

    return fonte == 'BANCO_LOJA' ||
        fonte == 'SUPABASE' ||
        fonte == 'BANCO_SUPABASE' ||
        fonte == 'BANCO_DA_LOJA' ||
        fonte == 'PRODUTOS_APP' ||
        fonte.contains('BANCO') && fonte.contains('LOJA') ||
        fonte.contains('SUPABASE');
  }

  static bool _apiBaseUrlIndicaBancoLoja(String valor) {
    final api = valor.trim().toLowerCase();

    return api.contains('produtos-supabase.local');
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

  static void limpar() {
    carregado = false;

    mercadoId = '';
    mercadoCodigo = '';
    mercadoNome = '';

    supabaseUrl = '';
    supabaseAnonKey = '';

    apiBaseUrl = '';
    fonteProdutosCentral = '';
    logoUrl = '';
    whatsapp = '';

    ativo = true;
    cobrarFrete = true;
    exibirOnboarding = true;

    pedidoMinimo = 0;
    taxaEntrega = 0;
    valorFreteGratis = 0;

    clienteCorPrimaria = '#E30613';
    clienteCorSecundaria = '#C90010';
    clienteCorFundo = '#FFF7F7';
    clienteLoginTitulo = '';
    clienteLoginSubtitulo = '';
    clienteLoginImagemUrl = '';

    onboardingSlides = [];

    dadosOriginais = {};
  }

  static String texto(dynamic valor) {
    if (valor == null) {
      return '';
    }

    return valor.toString().trim();
  }

  static String primeiroTexto(
    dynamic primeiro, [
    dynamic segundo,
    dynamic terceiro,
    dynamic quarto,
  ]) {
    final valores = [primeiro, segundo, terceiro, quarto];

    for (final valor in valores) {
      final convertido = texto(valor);

      if (convertido.isNotEmpty) {
        return convertido;
      }
    }

    return '';
  }

  static double numeroDinamico(dynamic valor) {
    if (valor == null) {
      return 0;
    }

    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor.toString().replaceAll(',', '.')) ?? 0;
  }

  static bool boolDinamico(dynamic valor, {required bool padrao}) {
    if (valor is bool) {
      return valor;
    }

    if (valor is num) {
      return valor == 1;
    }

    if (valor is String) {
      final textoValor = valor.trim().toLowerCase();

      if (textoValor == 'true' ||
          textoValor == '1' ||
          textoValor == 'sim' ||
          textoValor == 's') {
        return true;
      }

      if (textoValor == 'false' ||
          textoValor == '0' ||
          textoValor == 'nao' ||
          textoValor == 'não' ||
          textoValor == 'n') {
        return false;
      }
    }

    return padrao;
  }
}

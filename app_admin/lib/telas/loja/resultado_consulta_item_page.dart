import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/app_navigator.dart';
import '../../services/sessao_loja.dart';

class ResultadoConsultaItemPage extends StatefulWidget {
  final Map<String, dynamic> produto;

  const ResultadoConsultaItemPage({super.key, required this.produto});

  @override
  State<ResultadoConsultaItemPage> createState() =>
      _ResultadoConsultaItemPageState();
}

class _ResultadoConsultaItemPageState extends State<ResultadoConsultaItemPage> {
  static Color get vermelho => SessaoLoja.corPrimaria;
  static Color get fundo => SessaoLoja.corFundo;

  late Map<String, dynamic> produto;
  String? imagemUrl;
  bool carregandoImagem = true;

  @override
  void initState() {
    super.initState();
    AppNavigator.definirConteudoEstendidoAteRodape(true);
    produto = Map<String, dynamic>.from(widget.produto);
    buscarImagemCentral();
  }

  @override
  void dispose() {
    AppNavigator.definirConteudoEstendidoAteRodape(false);
    super.dispose();
  }

  String texto(dynamic valor) {
    return valor?.toString().trim() ?? '';
  }

  String get nomeProduto {
    final nome = texto(
      produto['nome_produto'] ??
          produto['descricao'] ??
          produto['produto'] ??
          produto['nome'],
    );

    if (nome.isEmpty) {
      return 'PRODUTO NÃO IDENTIFICADO';
    }

    return nome.toUpperCase();
  }

  String get eanProduto {
    final ean = texto(
      produto['ean_principal'] ??
          produto['ean'] ??
          produto['codigo_barras'] ??
          produto['codigo'],
    );

    if (ean.isEmpty) {
      return '-';
    }

    return ean;
  }

  double numero(dynamic valor) {
    if (valor == null) return 0;
    if (valor is num) return valor.toDouble();

    var textoValor = valor.toString().trim();

    if (textoValor.isEmpty) return 0;

    textoValor = textoValor
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll('KG', '')
        .replaceAll('UN', '');

    if (textoValor.contains(',') && textoValor.contains('.')) {
      textoValor = textoValor.replaceAll('.', '').replaceAll(',', '.');
    } else if (textoValor.contains(',')) {
      textoValor = textoValor.replaceAll(',', '.');
    }

    return double.tryParse(textoValor) ?? 0;
  }

  String precoFormatado() {
    final preco = numero(
      produto['preco_venda'] ??
          produto['preco'] ??
          produto['valor'] ??
          produto['preco_promocional'],
    );

    final partes = preco.toStringAsFixed(2).replaceAll('.', ',').split(',');
    return '${partes[0]},${partes[1]}';
  }

  Future<void> buscarImagemCentral() async {
    final imagemLocal = texto(
      produto['imagem_url'] ?? produto['imagem'] ?? produto['url_imagem'],
    );

    if (imagemLocal.isNotEmpty) {
      setState(() {
        imagemUrl = imagemLocal;
        carregandoImagem = false;
      });
      return;
    }

    try {
      final resposta = await Supabase.instance.client.functions.invoke(
        'buscar-imagem-produto',
        body: {
          'ean': eanProduto == '-' ? null : eanProduto,
          'codigo_barras': eanProduto == '-' ? null : eanProduto,
          'nome_produto': nomeProduto,
          'mercado_id': SessaoLoja.mercadoId,
          'mercado_codigo': SessaoLoja.mercadoCodigo,
        },
      );

      final data = resposta.data;

      if (data is Map) {
        final url = texto(
          data['imagem_url'] ??
              data['url'] ??
              data['image'] ??
              data['thumbnail'],
        );

        if (url.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            imagemUrl = url;
          });
        }
      }
    } catch (_) {
      // Se a imagem central falhar, a tela continua funcionando sem travar.
    } finally {
      if (mounted) {
        setState(() {
          carregandoImagem = false;
        });
      }
    }
  }

  Widget imagemProduto() {
    final url = imagemUrl;

    return SizedBox(
      width: double.infinity,
      height: 180,
      child: Center(
        child: carregandoImagem
            ? CircularProgressIndicator(color: vermelho)
            : url == null || url.isEmpty
            ? Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Icon(
                  Icons.image_not_supported_outlined,
                  size: 92,
                  color: Colors.grey.shade300,
                ),
              )
            : Image.network(
                url,
                height: 174,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    size: 92,
                    color: Colors.grey.shade300,
                  ),
                ),
              ),
      ),
    );
  }

  Widget logoLoja() {
    final logoUrl = SessaoLoja.logoUrl?.trim() ?? '';
    final fallback = SizedBox(
      height: 96,
      child: Icon(
        Icons.storefront_rounded,
        size: 58,
        color: vermelho.withValues(alpha: 0.35),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 235),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: vermelho.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: logoUrl.isEmpty
              ? fallback
              : Image.network(
                  logoUrl,
                  height: 96,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }

  Widget codigoBarra() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        'Código de barras: $eanProduto',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget nomeProdutoWidget() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Text(
        nomeProduto,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          height: 1.12,
        ),
      ),
    );
  }

  Widget precoWidget() {
    final preco = precoFormatado();
    final partes = preco.split(',');
    final inteiro = partes.first;
    final centavos = partes.length > 1 ? partes.last : '00';

    return Expanded(
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _FaixaPrecoPainter(
                corPrimaria: vermelho,
                corSecundaria: SessaoLoja.corSecundaria,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 28, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 39),
                          child: Text(
                            'R\$',
                            style: TextStyle(
                              fontSize: 28,
                              color: Colors.black87,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          inteiro,
                          style: const TextStyle(
                            fontSize: 96,
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Text(
                            centavos,
                            style: const TextStyle(
                              fontSize: 31,
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                const SizedBox(
                  width: double.infinity,
                  child: Text(
                    'PREÇO ATUAL',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fundo,
      appBar: AppBar(
        title: const Text('Resultado da busca'),
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final conteudo = Column(
              children: [
                logoLoja(),
                imagemProduto(),
                codigoBarra(),
                nomeProdutoWidget(),
                const SizedBox(height: 6),
                precoWidget(),
              ],
            );

            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ResultadoFundoPainter(
                      corPrimaria: vermelho,
                      corSecundaria: SessaoLoja.corSecundaria,
                      corFundo: fundo,
                    ),
                  ),
                ),
                if (constraints.maxHeight < 640)
                  SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(child: conteudo),
                    ),
                  )
                else
                  conteudo,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ResultadoFundoPainter extends CustomPainter {
  final Color corPrimaria;
  final Color corSecundaria;
  final Color corFundo;

  const _ResultadoFundoPainter({
    required this.corPrimaria,
    required this.corSecundaria,
    required this.corFundo,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), base);

    final fundoSuave = Paint()..color = corFundo.withValues(alpha: 0.38);
    canvas.drawCircle(
      Offset(size.width * 0.08, size.height * 0.52),
      72,
      fundoSuave,
    );
    canvas.drawCircle(
      Offset(size.width * 0.84, size.height * 0.24),
      50,
      fundoSuave,
    );
    canvas.drawCircle(
      Offset(size.width * 0.24, size.height * 0.14),
      46,
      fundoSuave,
    );
    canvas.drawCircle(
      Offset(size.width * 0.10, size.height * 0.70),
      48,
      fundoSuave,
    );

    final circuloClaro = Paint()
      ..color = corFundo.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(
      Offset(size.width * 0.98, size.height * 0.02),
      50,
      circuloClaro,
    );

    final primarioLinha = Paint()
      ..color = corPrimaria.withValues(alpha: 0.26)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final secundarioLinha = Paint()
      ..color = corSecundaria.withValues(alpha: 0.18)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < 6; i++) {
      final y = 24.0 + (i * 18);
      canvas.drawLine(
        Offset(size.width * 0.02, y),
        Offset(size.width * 0.19, y - 14),
        secundarioLinha,
      );
    }

    for (var i = 0; i < 4; i++) {
      final x = size.width * 0.82 + (i * 18);
      canvas.drawLine(Offset(x, 24), Offset(x + 24, 0), secundarioLinha);
    }

    canvas.drawLine(
      Offset(size.width * 0.08, size.height * 0.54),
      Offset(size.width * 0.32, size.height * 0.33),
      secundarioLinha,
    );
    canvas.drawLine(
      Offset(size.width * 0.10, size.height * 0.60),
      Offset(size.width * 0.38, size.height * 0.36),
      secundarioLinha,
    );

    final bolinha = Paint()..color = corPrimaria.withValues(alpha: 0.88);
    canvas.drawCircle(Offset(size.width * 0.73, 52), 4, bolinha);
    canvas.drawCircle(Offset(size.width * 0.82, 18), 2.5, bolinha);
    canvas.drawCircle(
      Offset(size.width * 0.92, size.height * 0.42),
      3.5,
      bolinha,
    );

    _desenharPontos(
      canvas,
      Offset(size.width * 0.53, size.height * 0.17),
      corSecundaria.withValues(alpha: 0.22),
      5,
      7,
      4.2,
      raio: 1.35,
    );
    _desenharPontos(
      canvas,
      Offset(size.width * -0.01, size.height * 0.01),
      corSecundaria.withValues(alpha: 0.28),
      9,
      12,
      5.5,
      raio: 1.75,
    );
    _desenharPontosRotacionados(
      canvas,
      Offset(size.width * 0.68, size.height * 0.27),
      corSecundaria.withValues(alpha: 0.24),
      6,
      8,
      4.0,
      -0.34,
      raio: 1.5,
    );
    _desenharPontos(
      canvas,
      Offset(size.width * 0.76, size.height * 0.50),
      corSecundaria.withValues(alpha: 0.18),
      7,
      10,
      4.6,
      raio: 1.45,
    );

    _desenharCirculoCifrao(
      canvas,
      Offset(size.width * 0.82, size.height * 0.13),
      corPrimaria,
      30,
    );

    _desenharLosangoCarrinho(
      canvas,
      Offset(size.width * 0.77, size.height * 0.32),
      corPrimaria,
      1.0,
    );

    _desenharCarrinho(
      canvas,
      Offset(size.width * 0.10, size.height * 0.24),
      corSecundaria.withValues(alpha: 0.72),
      1.0,
    );
    _desenharCarrinho(
      canvas,
      Offset(size.width * 0.78, size.height * 0.36),
      corPrimaria.withValues(alpha: 0.72),
      0.75,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.70, size.height * 0.17, 112, 112),
        const Radius.circular(28),
      ),
      primarioLinha,
    );

    _desenharCifrao(
      canvas,
      Offset(size.width * 0.18, size.height * 0.56),
      corSecundaria.withValues(alpha: 0.18),
      84,
    );
    _desenharCifrao(
      canvas,
      Offset(size.width * 0.88, size.height * 0.72),
      Colors.white.withValues(alpha: 0.20),
      76,
      contorno: true,
    );
  }

  void _desenharCarrinho(
    Canvas canvas,
    Offset offset,
    Color color,
    double escala,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3 * escala
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(offset.dx, offset.dy)
      ..lineTo(offset.dx + 16 * escala, offset.dy)
      ..lineTo(offset.dx + 24 * escala, offset.dy + 34 * escala)
      ..lineTo(offset.dx + 62 * escala, offset.dy + 34 * escala)
      ..lineTo(offset.dx + 70 * escala, offset.dy + 10 * escala)
      ..lineTo(offset.dx + 20 * escala, offset.dy + 10 * escala);
    canvas.drawPath(path, paint);
    canvas.drawLine(
      Offset(offset.dx + 30 * escala, offset.dy + 18 * escala),
      Offset(offset.dx + 66 * escala, offset.dy + 18 * escala),
      paint,
    );
    canvas.drawCircle(
      Offset(offset.dx + 34 * escala, offset.dy + 46 * escala),
      4 * escala,
      paint,
    );
    canvas.drawCircle(
      Offset(offset.dx + 58 * escala, offset.dy + 46 * escala),
      4 * escala,
      paint,
    );
  }

  void _desenharCirculoCifrao(
    Canvas canvas,
    Offset centro,
    Color color,
    double raio,
  ) {
    final sombra = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(centro.translate(0, 4), raio, sombra);

    final paint = Paint()
      ..shader = RadialGradient(
        colors: [Color.lerp(color, Colors.white, 0.10) ?? color, color],
      ).createShader(Rect.fromCircle(center: centro, radius: raio));
    canvas.drawCircle(centro, raio, paint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: r'$',
        style: TextStyle(
          color: Colors.white,
          fontSize: raio * 1.12,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        centro.dx - textPainter.width / 2,
        centro.dy - textPainter.height / 2,
      ),
    );
  }

  void _desenharLosangoCarrinho(
    Canvas canvas,
    Offset centro,
    Color color,
    double escala,
  ) {
    canvas.save();
    canvas.translate(centro.dx, centro.dy);
    canvas.rotate(-0.62);

    final largura = 112 * escala;
    final altura = 86 * escala;
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: largura,
      height: altura,
    );
    final linha = Paint()
      ..color = color.withValues(alpha: 0.56)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * escala;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(18 * escala)),
      linha,
    );

    _desenharCarrinho(
      canvas,
      Offset(-36 * escala, -20 * escala),
      color.withValues(alpha: 0.86),
      0.80 * escala,
    );
    canvas.restore();
  }

  void _desenharPontos(
    Canvas canvas,
    Offset inicio,
    Color color,
    int linhas,
    int colunas,
    double espacamento, {
    double raio = 1.2,
  }) {
    final paint = Paint()..color = color;
    for (var linha = 0; linha < linhas; linha++) {
      for (var coluna = 0; coluna < colunas; coluna++) {
        final opacidade = 1 - ((linha + coluna) / (linhas + colunas + 1));
        paint.color = color.withValues(alpha: color.a * opacidade);
        canvas.drawCircle(
          Offset(
            inicio.dx + coluna * espacamento,
            inicio.dy + linha * espacamento,
          ),
          raio,
          paint,
        );
      }
    }
  }

  void _desenharPontosRotacionados(
    Canvas canvas,
    Offset inicio,
    Color color,
    int linhas,
    int colunas,
    double espacamento,
    double rotacao, {
    double raio = 1.2,
  }) {
    canvas.save();
    canvas.translate(inicio.dx, inicio.dy);
    canvas.rotate(rotacao);
    _desenharPontos(
      canvas,
      Offset.zero,
      color,
      linhas,
      colunas,
      espacamento,
      raio: raio,
    );
    canvas.restore();
  }

  void _desenharCifrao(
    Canvas canvas,
    Offset offset,
    Color color,
    double size, {
    bool contorno = false,
  }) {
    final foreground = contorno
        ? (Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..color = color)
        : null;
    final textPainter = TextPainter(
      text: TextSpan(
        text: r'$',
        style: TextStyle(
          color: contorno ? null : color,
          foreground: foreground,
          fontSize: size,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _ResultadoFundoPainter oldDelegate) {
    return oldDelegate.corPrimaria != corPrimaria ||
        oldDelegate.corSecundaria != corSecundaria ||
        oldDelegate.corFundo != corFundo;
  }
}

class _FaixaPrecoPainter extends CustomPainter {
  final Color corPrimaria;
  final Color corSecundaria;

  const _FaixaPrecoPainter({
    required this.corPrimaria,
    required this.corSecundaria,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintSuave = Paint()..color = corPrimaria.withValues(alpha: 0.10);
    final pathSuave = Path()
      ..moveTo(size.width * 0.52, size.height)
      ..lineTo(size.width * 0.84, size.height)
      ..lineTo(size.width, size.height * 0.30)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(pathSuave, paintSuave);

    final paintForte = Paint()..color = corSecundaria.withValues(alpha: 0.95);
    final pathForte = Path()
      ..moveTo(size.width * 0.70, size.height)
      ..lineTo(size.width, size.height * 0.14)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(pathForte, paintForte);

    _desenharPontosCinza(
      canvas,
      Offset(size.width * 0.76, size.height * 0.08),
      5,
      8,
      4.5,
    );

    final linhaClara = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.82, size.height * 0.64),
      Offset(size.width * 1.04, size.height * 0.18),
      linhaClara,
    );
    canvas.drawLine(
      Offset(size.width * 0.88, size.height * 0.66),
      Offset(size.width * 1.06, size.height * 0.30),
      linhaClara,
    );

    _desenharCifraoContorno(
      canvas,
      Offset(size.width * 0.84, size.height * 0.42),
      86,
      Colors.white.withValues(alpha: 0.20),
    );

    _desenharBarrasPreco(
      canvas,
      Offset(size.width * 0.08, size.height * 0.91),
      corPrimaria,
      corSecundaria,
    );
    _desenharBarrasPreco(
      canvas,
      Offset(size.width * 0.80, size.height * 0.91),
      corPrimaria,
      corSecundaria,
    );
  }

  void _desenharPontosCinza(
    Canvas canvas,
    Offset inicio,
    int linhas,
    int colunas,
    double espacamento,
  ) {
    final paint = Paint();
    for (var linha = 0; linha < linhas; linha++) {
      for (var coluna = 0; coluna < colunas; coluna++) {
        final opacidade = 0.18 - ((linha + coluna) * 0.010);
        paint.color = Colors.blueGrey.withValues(
          alpha: opacidade.clamp(0.05, 0.18),
        );
        canvas.drawCircle(
          Offset(
            inicio.dx + coluna * espacamento,
            inicio.dy + linha * espacamento,
          ),
          1.25,
          paint,
        );
      }
    }
  }

  void _desenharCifraoContorno(
    Canvas canvas,
    Offset offset,
    double size,
    Color color,
  ) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: r'$',
        style: TextStyle(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.1
            ..color = color,
          fontSize: size,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(canvas, offset);
  }

  void _desenharBarrasPreco(
    Canvas canvas,
    Offset offset,
    Color corPrimaria,
    Color corSecundaria,
  ) {
    final primario = Paint()
      ..color = corPrimaria
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final secundario = Paint()
      ..color = corSecundaria
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(offset, offset.translate(22, 0), primario);
    canvas.drawLine(offset.translate(6, 9), offset.translate(19, 9), primario);
    canvas.drawLine(
      offset.translate(-19, 5),
      offset.translate(-8, 5),
      secundario,
    );
  }

  @override
  bool shouldRepaint(covariant _FaixaPrecoPainter oldDelegate) {
    return oldDelegate.corPrimaria != corPrimaria ||
        oldDelegate.corSecundaria != corSecundaria;
  }
}

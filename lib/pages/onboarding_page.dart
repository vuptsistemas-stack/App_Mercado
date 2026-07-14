import 'dart:async';

import 'package:flutter/material.dart';

import '../services/sessao_mercado_cliente.dart' as sessao;
import '../services/app_tema_service.dart';

class OnboardingPage extends StatefulWidget {
  final VoidCallback onConcluir;

  const OnboardingPage({
    super.key,
    required this.onConcluir,
  });

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const Color vermelhoPadrao = Color(0xFFE30613);
  static const Color textoEscuro = Color(0xFF101322);

  late final PageController pageController;
  Timer? timer;

  int paginaAtual = 0;

  List<sessao.OnboardingMercadoSlide> get slides {
    final itens = sessao.SessaoMercadoCliente.onboardingSlides;

    if (itens.isEmpty) {
      return sessao.SessaoMercadoCliente.slidesPadraoOnboarding();
    }

    return itens;
  }

  String get logoUrl => sessao.SessaoMercadoCliente.logoUrl.trim();

  Color get corPrimaria {
    final dados = sessao.SessaoMercadoCliente.dadosOriginais;
    return corHex(
      dados['cliente_cor_primaria'] ??
          dados['cor_primaria'] ??
          dados['app_cor_primaria'] ??
          dados['tema_cor_primaria'],
      vermelhoPadrao,
    );
  }

  Color get corFundo {
    final dados = sessao.SessaoMercadoCliente.dadosOriginais;
    return corHex(
      dados['cliente_cor_fundo'] ??
          dados['cor_fundo'] ??
          dados['app_cor_fundo'] ??
          dados['tema_cor_fundo'],
      const Color(0xFFFFFBFA),
    );
  }

  @override
  void initState() {
    super.initState();
    pageController = PageController();
    iniciarRotacaoAutomatica();
  }

  @override
  void dispose() {
    timer?.cancel();
    pageController.dispose();
    super.dispose();
  }

  void iniciarRotacaoAutomatica() {
    timer?.cancel();

    if (slides.length <= 1) {
      return;
    }

    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !pageController.hasClients) {
        return;
      }

      final proxima = paginaAtual >= slides.length - 1 ? 0 : paginaAtual + 1;

      pageController.animateToPage(
        proxima,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void avancar() {
    if (paginaAtual >= slides.length - 1) {
      widget.onConcluir();
      return;
    }

    pageController.animateToPage(
      paginaAtual + 1,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  static Color corHex(dynamic valor, Color padrao) {
    if (valor == null) {
      return padrao;
    }

    var texto = valor.toString().trim();

    if (texto.isEmpty) {
      return padrao;
    }

    texto = texto.replaceAll('#', '');

    if (texto.length == 6) {
      texto = 'FF$texto';
    }

    if (texto.length != 8) {
      return padrao;
    }

    final numero = int.tryParse(texto, radix: 16);
    if (numero == null) {
      return padrao;
    }

    return Color(numero);
  }

  Widget logoMercado() {
    final cor = corPrimaria;

    return Container(
      width: 176,
      height: 92,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
      border: Border.all(color: AppTemaService.primaria.withValues(alpha: 0.16), width: 1.6),
      boxShadow: [
        BoxShadow(
          color: AppTemaService.primaria.withValues(alpha: 0.08),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
      ),
      child: logoUrl.isEmpty
          ? Icon(
              Icons.shopping_cart_rounded,
              color: cor,
              size: 54,
            )
          : Image.network(
              logoUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                Icons.shopping_cart_rounded,
                color: cor,
                size: 54,
              ),
            ),
    );
  }

  IconData iconeCentral(int index) {
    switch (index % 3) {
      case 0:
        return Icons.local_offer_outlined;
      case 1:
        return Icons.delivery_dining_rounded;
      default:
        return Icons.shopping_bag_outlined;
    }
  }

  List<_IconeOrbitando> iconesOrbitando(int index) {
    switch (index % 3) {
      case 0:
        return const [
          _IconeOrbitando(Icons.percent_rounded, Alignment(-0.78, -0.72)),
          _IconeOrbitando(Icons.receipt_long_outlined, Alignment(0.78, -0.62)),
          _IconeOrbitando(Icons.shopping_cart_outlined, Alignment(-0.86, 0.55)),
          _IconeOrbitando(Icons.attach_money_rounded, Alignment(0.78, 0.48)),
        ];
      case 1:
        return const [
          _IconeOrbitando(Icons.location_on_outlined, Alignment(-0.82, -0.67)),
          _IconeOrbitando(Icons.home_outlined, Alignment(0.82, -0.62)),
          _IconeOrbitando(Icons.shopping_bag_outlined, Alignment(-0.82, 0.58)),
          _IconeOrbitando(Icons.verified_outlined, Alignment(0.78, 0.55)),
        ];
      default:
        return const [
          _IconeOrbitando(Icons.search_rounded, Alignment(-0.88, -0.08)),
          _IconeOrbitando(Icons.local_offer_outlined, Alignment(0.0, -0.92)),
          _IconeOrbitando(Icons.inventory_2_outlined, Alignment(0.86, -0.08)),
          _IconeOrbitando(Icons.location_on_outlined, Alignment(0.0, 0.90)),
        ];
    }
  }

  Widget arteSlide(sessao.OnboardingMercadoSlide slide, int index) {
    final imagemUrl = slide.imagemUrl.trim();

    if (imagemUrl.isNotEmpty) {
      return SizedBox(
        height: 318,
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Image.network(
              imagemUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => artePadrao(index),
            ),
          ),
        ),
      );
    }

    return artePadrao(index);
  }

  Widget artePadrao(int index) {
    final cor = corPrimaria;
    final icone = iconeCentral(index);
    final orbitas = iconesOrbitando(index);

    return SizedBox(
      height: 318,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 238,
            height: 238,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  cor.withOpacity(0.10),
                  cor.withOpacity(0.035),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Container(
            width: 244,
            height: 244,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: cor.withOpacity(0.26),
                width: 2,
              ),
            ),
          ),
          Container(
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: cor.withOpacity(0.12),
                  blurRadius: 34,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Icon(
              icone,
              color: cor,
              size: 92,
            ),
          ),
          for (final item in orbitas)
            Align(
              alignment: item.alignment,
              child: circuloIcone(item.icone),
            ),
          Positioned(
            top: 32,
            left: 76,
            child: ponto(10, cor.withOpacity(0.42)),
          ),
          Positioned(
            top: 98,
            right: 66,
            child: pequenoMais(cor.withOpacity(0.32)),
          ),
          Positioned(
            bottom: 54,
            left: 68,
            child: pequenoMais(cor.withOpacity(0.28)),
          ),
          Positioned(
            right: 82,
            bottom: 66,
            child: ponto(8, cor.withOpacity(0.30)),
          ),
        ],
      ),
    );
  }

  Widget circuloIcone(IconData icone) {
    final cor = corPrimaria;

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(
        icone,
        color: cor.withOpacity(0.72),
        size: 26,
      ),
    );
  }

  Widget ponto(double tamanho, Color cor) {
    return Container(
      width: tamanho,
      height: tamanho,
      decoration: BoxDecoration(
        color: cor,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget pequenoMais(Color cor) {
    return Icon(
      Icons.add_rounded,
      size: 20,
      color: cor,
    );
  }

  Widget indicador() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(slides.length, (index) {
        final ativo = index == paginaAtual;
        final cor = corPrimaria;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: ativo ? 24 : 10,
          height: 10,
          decoration: BoxDecoration(
            color: ativo ? cor : cor.withOpacity(0.22),
            borderRadius: BorderRadius.circular(20),
          ),
        );
      }),
    );
  }

  Widget cabecalho() {
    final cor = corPrimaria;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      child: Column(
        children: [
          Row(
            children: [
              const Spacer(),
              TextButton(
                onPressed: widget.onConcluir,
                style: TextButton.styleFrom(
                  foregroundColor: cor,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                child: const Text(
                  'Pular',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Center(child: logoMercado()),
        ],
      ),
    );
  }

  Widget slideWidget(sessao.OnboardingMercadoSlide slide, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 12),
          arteSlide(slide, index),
          const SizedBox(height: 20),
          Text(
            slide.titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: textoEscuro,
              fontSize: 31,
              fontWeight: FontWeight.w900,
              height: 1.08,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            slide.subtitulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 17,
              height: 1.48,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cor = corPrimaria;

    return Scaffold(
      backgroundColor: corFundo,
      body: SafeArea(
        child: Column(
          children: [
            cabecalho(),
            Expanded(
              child: PageView.builder(
                controller: pageController,
                itemCount: slides.length,
                onPageChanged: (index) {
                  setState(() {
                    paginaAtual = index;
                  });
                },
                itemBuilder: (context, index) {
                  return slideWidget(slides[index], index);
                },
              ),
            ),
            indicador(),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 0, 26, 22),
              child: SizedBox(
                width: double.infinity,
                height: 62,
                child: ElevatedButton(
                  onPressed: avancar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'Começar',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconeOrbitando {
  final IconData icone;
  final Alignment alignment;

  const _IconeOrbitando(this.icone, this.alignment);
}

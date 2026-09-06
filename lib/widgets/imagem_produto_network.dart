import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/imagem_service.dart';

class ImagemProdutoNetwork extends StatefulWidget {
  final String imagemUrl;
  final String ean;
  final String nomeProduto;
  final String imagemUrlCadastroProdutoApp;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget placeholder;
  final Widget fallback;

  const ImagemProdutoNetwork({
    super.key,
    required this.imagemUrl,
    required this.ean,
    required this.nomeProduto,
    required this.imagemUrlCadastroProdutoApp,
    required this.placeholder,
    required this.fallback,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
  });

  @override
  State<ImagemProdutoNetwork> createState() => _ImagemProdutoNetworkState();
}

class _ImagemProdutoNetworkState extends State<ImagemProdutoNetwork> {
  late String _imagemUrl;
  bool _tentouRecuperar = false;
  bool _recuperacaoAgendada = false;

  @override
  void initState() {
    super.initState();
    _imagemUrl = widget.imagemUrl.trim();
  }

  @override
  void didUpdateWidget(covariant ImagemProdutoNetwork oldWidget) {
    super.didUpdateWidget(oldWidget);

    final novaUrl = widget.imagemUrl.trim();
    final mudouProduto = oldWidget.ean != widget.ean ||
        oldWidget.nomeProduto != widget.nomeProduto;

    if (mudouProduto || novaUrl != oldWidget.imagemUrl.trim()) {
      _imagemUrl = novaUrl;
      _tentouRecuperar = false;
      _recuperacaoAgendada = false;
    }
  }

  void _agendarRecuperacao(String urlQuebrada) {
    if (_tentouRecuperar || _recuperacaoAgendada) {
      return;
    }

    _recuperacaoAgendada = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tentouRecuperar) {
        return;
      }

      _recuperacaoAgendada = false;
      _tentouRecuperar = true;
      unawaited(_recuperarImagem(urlQuebrada));
    });
  }

  Future<void> _recuperarImagem(String urlQuebrada) async {
    try {
      await CachedNetworkImage.evictFromCache(urlQuebrada);

      final novaUrl = await ImagemService.buscarImagemProduto(
        ean: widget.ean,
        nomeProduto: widget.nomeProduto,
        imagemUrlCadastroProdutoApp: widget.imagemUrlCadastroProdutoApp,
        forcarAtualizacao: true,
        urlImagemQuebrada: urlQuebrada,
      );
      final urlLimpa = novaUrl?.trim() ?? '';

      if (!mounted || urlLimpa.isEmpty || urlLimpa == urlQuebrada) {
        return;
      }

      setState(() {
        _imagemUrl = urlLimpa;
      });
    } catch (error) {
      debugPrint('Erro ao recuperar imagem do produto: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_imagemUrl.isEmpty) {
      return widget.fallback;
    }

    return CachedNetworkImage(
      imageUrl: _imagemUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      placeholder: (context, url) => widget.placeholder,
      errorWidget: (context, url, error) {
        _agendarRecuperacao(url);
        return widget.fallback;
      },
    );
  }
}

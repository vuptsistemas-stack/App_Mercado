import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/app_tema_service.dart';
import '../services/jornal_ofertas_service.dart';

class JornalOfertasPage extends StatefulWidget {
  final VoidCallback? onVoltarInicio;

  const JornalOfertasPage({super.key, this.onVoltarInicio});

  @override
  State<JornalOfertasPage> createState() => _JornalOfertasPageState();
}

class _JornalOfertasPageState extends State<JornalOfertasPage> {
  JornalPublicado? jornal;
  bool carregando = true;
  String? erro;

  @override
  void initState() {
    super.initState();
    carregar();
  }

  Future<void> carregar() async {
    if (mounted) {
      setState(() {
        carregando = true;
        erro = null;
      });
    }

    try {
      final resultado = await JornalOfertasService.instance.buscarAtual();
      if (!mounted) return;
      setState(() => jornal = resultado);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        erro = _mensagemErro(e);
        jornal = null;
      });
    } finally {
      if (mounted) setState(() => carregando = false);
    }
  }

  String _mensagemErro(Object e) {
    final texto = e.toString().replaceFirst('Exception: ', '').trim();
    final normalizado = texto.toLowerCase();
    if (normalizado.contains('socket') ||
        normalizado.contains('network') ||
        normalizado.contains('host lookup') ||
        normalizado.contains('connection')) {
      return 'Sem conexão. Verifique sua internet e tente novamente.';
    }
    return texto.isEmpty ? 'Não foi possível carregar o jornal.' : texto;
  }

  String _dataPublicacao(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return 'Publicado em $dia/$mes/${data.year}';
  }

  void abrirImagem(JornalPublicado atual) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _JornalImagemPage(jornal: atual)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.onVoltarInicio == null
            ? null
            : IconButton(
                onPressed: widget.onVoltarInicio,
                tooltip: 'Voltar ao início',
                icon: const Icon(Icons.arrow_back),
              ),
        title: const Text(
          'Jornal de ofertas',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        backgroundColor: AppTemaService.primaria,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: carregando ? null : carregar,
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: carregando
          ? Center(
              child: CircularProgressIndicator(color: AppTemaService.primaria),
            )
          : RefreshIndicator(
              color: AppTemaService.primaria,
              onRefresh: carregar,
              child: _conteudo(),
            ),
    );
  }

  Widget _conteudo() {
    if (erro != null) {
      return _estadoVazio(
        icone: Icons.cloud_off_outlined,
        titulo: 'Não foi possível carregar',
        mensagem: erro!,
        mostrarBotao: true,
      );
    }

    final atual = jornal;
    if (atual == null) {
      return _estadoVazio(
        icone: Icons.newspaper_outlined,
        titulo: 'Nenhum jornal publicado',
        mensagem: 'As próximas ofertas da loja aparecerão aqui.',
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  atual.titulo,
                  style: const TextStyle(
                    color: Color(0xFF172033),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 18,
                  runSpacing: 6,
                  children: [
                    if (atual.validade.isNotEmpty)
                      _informacao(Icons.event_outlined, atual.validade),
                    if (atual.publicadoEm != null)
                      _informacao(
                        Icons.schedule_outlined,
                        _dataPublicacao(atual.publicadoEm!),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Material(
                  color: Colors.white,
                  elevation: 2,
                  borderRadius: BorderRadius.circular(6),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => abrirImagem(atual),
                    child: Hero(
                      tag: 'jornal-publicado-atual',
                      child: CachedNetworkImage(
                        imageUrl: atual.imagemUrl,
                        fit: BoxFit.fitWidth,
                        fadeInDuration: const Duration(milliseconds: 180),
                        placeholder: (context, url) => AspectRatio(
                          aspectRatio: _proporcao(atual),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppTemaService.primaria,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => AspectRatio(
                          aspectRatio: _proporcao(atual),
                          child: const Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              size: 54,
                              color: Colors.black38,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.zoom_in, size: 18, color: Color(0xFF687182)),
                    SizedBox(width: 6),
                    Text(
                      'Toque na imagem para ampliar',
                      style: TextStyle(
                        color: Color(0xFF687182),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  double _proporcao(JornalPublicado atual) {
    if (atual.largura > 0 && atual.altura > 0) {
      return atual.largura / atual.altura;
    }
    return 4 / 5;
  }

  Widget _informacao(IconData icone, String texto) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: 17, color: AppTemaService.primaria),
        const SizedBox(width: 6),
        Text(
          texto,
          style: const TextStyle(
            color: Color(0xFF596273),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _estadoVazio({
    required IconData icone,
    required String titulo,
    required String mensagem,
    bool mostrarBotao = false,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      children: [
        Icon(
          icone,
          size: 72,
          color: AppTemaService.primaria.withValues(alpha: .55),
        ),
        const SizedBox(height: 18),
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF172033),
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          mensagem,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF687182),
            fontSize: 15,
            height: 1.35,
          ),
        ),
        if (mostrarBotao) ...[
          const SizedBox(height: 24),
          Center(
            child: FilledButton.icon(
              onPressed: carregar,
              style: FilledButton.styleFrom(
                backgroundColor: AppTemaService.primaria,
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ),
        ],
      ],
    );
  }
}

class _JornalImagemPage extends StatelessWidget {
  final JornalPublicado jornal;

  const _JornalImagemPage({required this.jornal});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          jornal.titulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(
            child: Hero(
              tag: 'jornal-publicado-atual',
              child: CachedNetworkImage(
                imageUrl: jornal.imagemUrl,
                fit: BoxFit.contain,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (context, url, error) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white70,
                  size: 64,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

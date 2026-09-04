import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

@JS('vuptPwaCanInstall')
external JSBoolean _vuptPwaCanInstall();

@JS('vuptPwaIsInstalled')
external JSBoolean _vuptPwaIsInstalled();

@JS('vuptPwaInstall')
external JSPromise<JSString> _vuptPwaInstall();

class PedidosWebBrowser {
  PedidosWebBrowser._();

  static const String _chaveSom = 'vupt_pedidos_som_novo_pedido';
  static const String _chaveVolume = 'vupt_pedidos_volume_novo_pedido';
  static const String _chaveSomAtivo = 'vupt_pedidos_som_novo_pedido_ativo';
  static const String _chaveAudioPersonalizado =
      'vupt_pedidos_audio_personalizado';
  static const String _chaveNomeAudioPersonalizado =
      'vupt_pedidos_nome_audio_personalizado';
  static const int _tamanhoMaximoAudioPersonalizado = 2 * 1024 * 1024;
  static const Set<String> _sonsDisponiveis = {
    'campainha',
    'urgente',
    'caixa',
    'suave',
    'personalizado',
  };

  static web.HTMLAudioElement? _audioAtual;
  static JSFunction? _listenerEstadoInstalacao;
  static final Set<void Function()> _ouvintesInstalacao = <void Function()>{};

  static bool get dispositivoIos {
    final agente = web.window.navigator.userAgent.toLowerCase();
    return agente.contains('iphone') ||
        agente.contains('ipad') ||
        agente.contains('ipod');
  }

  static bool get dispositivoAndroid {
    return web.window.navigator.userAgent.toLowerCase().contains('android');
  }

  static bool get pwaInstalado {
    try {
      return _vuptPwaIsInstalled().toDart;
    } catch (_) {
      return false;
    }
  }

  static bool get pwaPodeInstalar {
    if (pwaInstalado) return false;
    if (dispositivoIos) return true;

    try {
      return _vuptPwaCanInstall().toDart;
    } catch (_) {
      return false;
    }
  }

  static void adicionarOuvinteInstalacao(void Function() ouvinte) {
    _ouvintesInstalacao.add(ouvinte);
    if (_listenerEstadoInstalacao != null) return;

    _listenerEstadoInstalacao = ((web.Event _) {
      for (final callback in _ouvintesInstalacao.toList(growable: false)) {
        callback();
      }
    }).toJS;
    web.window.addEventListener(
      'vupt-install-state-changed',
      _listenerEstadoInstalacao,
    );
  }

  static void removerOuvinteInstalacao(void Function() ouvinte) {
    _ouvintesInstalacao.remove(ouvinte);
  }

  static Future<String> solicitarInstalacaoPwa() async {
    if (dispositivoIos) return 'ios';
    if (pwaInstalado) return 'installed';

    try {
      return (await _vuptPwaInstall().toDart).toDart;
    } catch (_) {
      return 'unavailable';
    }
  }

  static String get somNovoPedido {
    final valor = web.window.localStorage.getItem(_chaveSom)?.trim() ?? '';
    if (valor == 'personalizado' && !temAudioPersonalizado) {
      return 'campainha';
    }
    return _sonsDisponiveis.contains(valor) ? valor : 'campainha';
  }

  static double get volumeNovoPedido {
    final valor = double.tryParse(
      web.window.localStorage.getItem(_chaveVolume) ?? '',
    );
    return (valor ?? 1).clamp(0.0, 1.0).toDouble();
  }

  static bool get somNovoPedidoAtivo {
    return web.window.localStorage.getItem(_chaveSomAtivo) != 'false';
  }

  static String get nomeAudioPersonalizado {
    return web.window.localStorage
            .getItem(_chaveNomeAudioPersonalizado)
            ?.trim() ??
        '';
  }

  static bool get temAudioPersonalizado {
    return (web.window.localStorage.getItem(_chaveAudioPersonalizado)?.trim() ??
            '')
        .isNotEmpty;
  }

  static Future<String?> escolherAudioPersonalizado() async {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = 'audio/wav,audio/mpeg,audio/ogg,audio/mp4,.wav,.mp3,.ogg,.m4a'
      ..style.display = 'none';
    final escolha = Completer<web.File?>();

    late JSFunction aoAlterar;
    late JSFunction aoCancelar;
    aoAlterar = ((web.Event _) {
      final arquivos = input.files;
      final arquivo = arquivos == null || arquivos.length == 0
          ? null
          : arquivos.item(0);
      if (!escolha.isCompleted) escolha.complete(arquivo);
    }).toJS;
    aoCancelar = ((web.Event _) {
      if (!escolha.isCompleted) escolha.complete(null);
    }).toJS;

    input.addEventListener('change', aoAlterar);
    input.addEventListener('cancel', aoCancelar);
    web.document.body?.appendChild(input);
    input.click();

    try {
      final arquivo = await escolha.future;
      if (arquivo == null) return null;
      if (arquivo.size > _tamanhoMaximoAudioPersonalizado) {
        throw StateError('O arquivo deve ter no máximo 2 MB.');
      }

      final leitor = web.FileReader();
      final leitura = Completer<String>();
      late JSFunction aoCarregar;
      late JSFunction aoFalhar;

      aoCarregar = ((web.Event _) {
        final resultado = leitor.result;
        if (resultado == null) {
          leitura.completeError(StateError('Não foi possível ler o áudio.'));
          return;
        }
        leitura.complete((resultado as JSString).toDart);
      }).toJS;
      aoFalhar = ((web.Event _) {
        if (!leitura.isCompleted) {
          leitura.completeError(StateError('Não foi possível ler o áudio.'));
        }
      }).toJS;

      leitor.addEventListener('load', aoCarregar);
      leitor.addEventListener('error', aoFalhar);
      leitor.readAsDataURL(arquivo);
      final conteudo = await leitura.future;

      try {
        web.window.localStorage.setItem(_chaveAudioPersonalizado, conteudo);
        web.window.localStorage.setItem(
          _chaveNomeAudioPersonalizado,
          arquivo.name,
        );
      } catch (_) {
        throw StateError(
          'O navegador não possui espaço para salvar este áudio. Use um arquivo menor.',
        );
      }

      return arquivo.name;
    } finally {
      input.removeEventListener('change', aoAlterar);
      input.removeEventListener('cancel', aoCancelar);
      input.remove();
    }
  }

  static void removerAudioPersonalizado() {
    web.window.localStorage.removeItem(_chaveAudioPersonalizado);
    web.window.localStorage.removeItem(_chaveNomeAudioPersonalizado);
    if (somNovoPedido == 'personalizado') {
      web.window.localStorage.setItem(_chaveSom, 'campainha');
    }
  }

  static void salvarConfiguracaoSom({
    required bool ativo,
    required String som,
    required double volume,
  }) {
    final personalizadoValido = som == 'personalizado' && temAudioPersonalizado;
    final somValido =
        _sonsDisponiveis.contains(som) &&
            (som != 'personalizado' || personalizadoValido)
        ? som
        : 'campainha';
    web.window.localStorage.setItem(_chaveSomAtivo, ativo.toString());
    web.window.localStorage.setItem(_chaveSom, somValido);
    web.window.localStorage.setItem(
      _chaveVolume,
      volume.clamp(0.0, 1.0).toString(),
    );
  }

  static Future<void> tocarAlertaNovoPedido({
    String? som,
    double? volume,
    bool ignorarDesativado = false,
  }) async {
    if (!ignorarDesativado && !somNovoPedidoAtivo) return;

    String? url;

    try {
      final somEscolhido = _sonsDisponiveis.contains(som)
          ? som!
          : somNovoPedido;
      final volumeEscolhido = (volume ?? volumeNovoPedido)
          .clamp(0.0, 1.0)
          .toDouble();
      final audioPersonalizado = somEscolhido == 'personalizado'
          ? web.window.localStorage.getItem(_chaveAudioPersonalizado)?.trim()
          : null;

      if (audioPersonalizado != null && audioPersonalizado.isNotEmpty) {
        url = audioPersonalizado;
      } else {
        final bytes = _gerarToqueNovoPedido(somEscolhido);
        url = web.URL.createObjectURL(
          web.Blob(
            <web.BlobPart>[bytes.toJS].toJS,
            web.BlobPropertyBag(type: 'audio/wav'),
          ),
        );
      }

      _audioAtual?.pause();
      final audio = web.HTMLAudioElement()
        ..src = url
        ..volume = volumeEscolhido;
      _audioAtual = audio;
      await audio.play().toDart;
    } catch (_) {
      // O navegador pode bloquear audio antes da primeira interacao do usuario.
    } finally {
      if (url != null && !url.startsWith('data:')) {
        final urlTemporaria = url;
        Timer(
          const Duration(seconds: 4),
          () => web.URL.revokeObjectURL(urlTemporaria),
        );
      }
    }
  }

  static void imprimirHtml(String conteudo) {
    final url = web.URL.createObjectURL(
      web.Blob(
        <web.BlobPart>[conteudo.toJS].toJS,
        web.BlobPropertyBag(type: 'text/html;charset=utf-8'),
      ),
    );

    web.window.open(url, '_blank');
    Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  }

  static Uint8List _gerarToqueNovoPedido(String som) {
    const sampleRate = 44100;
    final duracaoSegundos = switch (som) {
      'urgente' => 1.15,
      'caixa' => 1.25,
      'suave' => 1.05,
      _ => 1.35,
    };
    final totalAmostras = (sampleRate * duracaoSegundos).round();
    final dados = ByteData(44 + totalAmostras * 2);

    _escreverTexto(dados, 0, 'RIFF');
    dados.setUint32(4, 36 + totalAmostras * 2, Endian.little);
    _escreverTexto(dados, 8, 'WAVE');
    _escreverTexto(dados, 12, 'fmt ');
    dados.setUint32(16, 16, Endian.little);
    dados.setUint16(20, 1, Endian.little);
    dados.setUint16(22, 1, Endian.little);
    dados.setUint32(24, sampleRate, Endian.little);
    dados.setUint32(28, sampleRate * 2, Endian.little);
    dados.setUint16(32, 2, Endian.little);
    dados.setUint16(34, 16, Endian.little);
    _escreverTexto(dados, 36, 'data');
    dados.setUint32(40, totalAmostras * 2, Endian.little);

    for (var indice = 0; indice < totalAmostras; indice++) {
      final tempo = indice / sampleRate;
      final amostra = _amostraSom(som, tempo).clamp(-1.0, 1.0);

      dados.setInt16(44 + indice * 2, (amostra * 32767).round(), Endian.little);
    }

    return dados.buffer.asUint8List();
  }

  static double _amostraSom(String som, double tempo) {
    switch (som) {
      case 'urgente':
        final pulso = tempo % 0.34;
        if (pulso >= 0.22) return 0;
        final frequencia = (tempo / 0.34).floor().isEven ? 1180.0 : 940.0;
        return math.sin(2 * math.pi * frequencia * tempo) *
            _envelopePulso(pulso, 0.22) *
            0.78;
      case 'caixa':
        if (tempo < 0.34) {
          return _sino(1046, tempo, 0.34, 0.70);
        }
        if (tempo < 0.92) {
          return _sino(784, tempo - 0.38, 0.54, 0.66);
        }
        return 0;
      case 'suave':
        return _sino(660, tempo, 0.95, 0.52);
      default:
        final pulso = tempo % 0.58;
        if (pulso < 0.18) {
          return math.sin(2 * math.pi * 880 * tempo) *
              _envelopePulso(pulso, 0.18) *
              0.72;
        }
        if (pulso >= 0.22 && pulso < 0.40) {
          return math.sin(2 * math.pi * 1174 * tempo) *
              _envelopePulso(pulso - 0.22, 0.18) *
              0.72;
        }
        return 0;
    }
  }

  static double _sino(
    double frequencia,
    double tempo,
    double duracao,
    double volume,
  ) {
    if (tempo < 0 || tempo > duracao) return 0;
    final queda = math.pow(1 - (tempo / duracao), 2).toDouble();
    final fundamental = math.sin(2 * math.pi * frequencia * tempo);
    final harmonico = math.sin(2 * math.pi * frequencia * 2.01 * tempo) * 0.24;
    return (fundamental + harmonico) * queda * volume;
  }

  static double _envelopePulso(double tempo, double duracao) {
    if (tempo < 0 || tempo > duracao) return 0;
    return math.min(1.0, tempo / 0.018) *
        math.min(1.0, (duracao - tempo) / 0.055).clamp(0.0, 1.0);
  }

  static void _escreverTexto(ByteData dados, int inicio, String texto) {
    for (var indice = 0; indice < texto.length; indice++) {
      dados.setUint8(inicio + indice, texto.codeUnitAt(indice));
    }
  }
}

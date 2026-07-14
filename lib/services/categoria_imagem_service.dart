import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class CategoriaImagemService {
  static const String centralFunctionUrl =
      'https://pkrkeeupcvxnqhynfvbw.functions.supabase.co/buscar-imagens-categorias';

  static const Duration validadeCache = Duration(days: 7);

  static final Map<String, String?> _cacheMemoria = {};
  static final Set<String> _consultando = {};

  static String normalizarCategoria(String categoria) {
    var texto = categoria.trim().toUpperCase();

    const trocas = {
      'Á': 'A',
      'À': 'A',
      'Â': 'A',
      'Ã': 'A',
      'Ä': 'A',
      'É': 'E',
      'È': 'E',
      'Ê': 'E',
      'Ë': 'E',
      'Í': 'I',
      'Ì': 'I',
      'Î': 'I',
      'Ï': 'I',
      'Ó': 'O',
      'Ò': 'O',
      'Ô': 'O',
      'Õ': 'O',
      'Ö': 'O',
      'Ú': 'U',
      'Ù': 'U',
      'Û': 'U',
      'Ü': 'U',
      'Ç': 'C',
    };

    trocas.forEach((de, para) {
      texto = texto.replaceAll(de, para);
    });

    texto = texto.replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
    texto = texto.replaceAll(RegExp(r'_+'), '_');
    texto = texto.replaceAll(RegExp(r'^_|_$'), '');

    return texto;
  }

  static String _chaveUrl(String chave) {
    return 'categoria_img_${chave}_url';
  }

  static String _chaveData(String chave) {
    return 'categoria_img_${chave}_data';
  }

  static Future<String?> buscarImagemCategoria(String categoria) async {
    final chave = normalizarCategoria(categoria);

    if (chave.isEmpty) {
      return null;
    }

    if (_cacheMemoria.containsKey(chave)) {
      return _cacheMemoria[chave];
    }

    final cacheLocal = await _buscarNoCacheLocal(chave);

    if (cacheLocal != null) {
      _cacheMemoria[chave] = cacheLocal.url;
      return cacheLocal.url;
    }

    final retorno = await buscarImagensCategorias([categoria]);

    if (retorno.containsKey(chave)) {
      return retorno[chave];
    }

    return _cacheMemoria[chave];
  }

  static Future<Map<String, String?>> buscarImagensCategorias(
    List<String> categorias,
  ) async {
    final chavesOriginais = <String, String>{};

    for (final categoria in categorias) {
      final chave = normalizarCategoria(categoria);

      if (chave.isNotEmpty) {
        chavesOriginais[chave] = categoria;
      }
    }

    if (chavesOriginais.isEmpty) {
      return {};
    }

    final resultado = <String, String?>{};
    final faltando = <String>[];

    for (final chave in chavesOriginais.keys) {
      if (_cacheMemoria.containsKey(chave)) {
        resultado[chave] = _cacheMemoria[chave];
        continue;
      }

      final cacheLocal = await _buscarNoCacheLocal(chave);

      if (cacheLocal != null) {
        _cacheMemoria[chave] = cacheLocal.url;
        resultado[chave] = cacheLocal.url;
        continue;
      }

      if (!_consultando.contains(chave)) {
        faltando.add(chave);
      }
    }

    if (faltando.isEmpty) {
      return resultado;
    }

    for (final chave in faltando) {
      _consultando.add(chave);
    }

    try {
      final response = await http
          .post(
            Uri.parse(centralFunctionUrl),
            headers: const {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'categorias': faltando,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return resultado;
      }

      final body = jsonDecode(response.body);

      if (body is! Map) {
        return resultado;
      }

      final imagens = body['imagens'];

      if (imagens is! Map) {
        return resultado;
      }

      final prefs = await SharedPreferences.getInstance();
      final agora = DateTime.now().millisecondsSinceEpoch;

      for (final chave in faltando) {
        final urlTexto = imagens[chave]?.toString().trim();
        final url = urlTexto == null || urlTexto.isEmpty ? null : urlTexto;

        _cacheMemoria[chave] = url;
        resultado[chave] = url;

        await prefs.setString(_chaveUrl(chave), url ?? '');
        await prefs.setInt(_chaveData(chave), agora);
      }

      return resultado;
    } catch (_) {
      return resultado;
    } finally {
      for (final chave in faltando) {
        _consultando.remove(chave);
      }
    }
  }

  static Future<_CacheCategoria?> _buscarNoCacheLocal(String chave) async {
    final prefs = await SharedPreferences.getInstance();

    final url = prefs.getString(_chaveUrl(chave));
    final data = prefs.getInt(_chaveData(chave));

    if (data == null) {
      return null;
    }

    final criadoEm = DateTime.fromMillisecondsSinceEpoch(data);
    final expirado = DateTime.now().difference(criadoEm) > validadeCache;

    if (expirado) {
      await prefs.remove(_chaveUrl(chave));
      await prefs.remove(_chaveData(chave));
      return null;
    }

    final urlLimpa = url?.trim() ?? '';
    return _CacheCategoria(urlLimpa.isEmpty ? null : urlLimpa);
  }

  static Future<void> limparCache() async {
    _cacheMemoria.clear();

    final prefs = await SharedPreferences.getInstance();
    final chaves = prefs.getKeys().where(
          (key) => key.startsWith('categoria_img_'),
        );

    for (final chave in chaves) {
      await prefs.remove(chave);
    }
  }
}

class _CacheCategoria {
  final String? url;

  const _CacheCategoria(this.url);
}

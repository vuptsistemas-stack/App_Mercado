import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_mercado_config.dart';
import 'sessao_mercado_cliente.dart' as sessao;

class JornalPublicado {
  final String titulo;
  final String validade;
  final String imagemUrl;
  final String formato;
  final int largura;
  final int altura;
  final DateTime? publicadoEm;

  const JornalPublicado({
    required this.titulo,
    required this.validade,
    required this.imagemUrl,
    required this.formato,
    required this.largura,
    required this.altura,
    required this.publicadoEm,
  });

  factory JornalPublicado.fromMap(Map<String, dynamic> dados) {
    return JornalPublicado(
      titulo: dados['titulo']?.toString().trim().isNotEmpty == true
          ? dados['titulo'].toString().trim()
          : 'Ofertas da semana',
      validade: dados['validade']?.toString().trim() ?? '',
      imagemUrl: dados['imagem_url']?.toString().trim() ?? '',
      formato: dados['formato']?.toString().trim() ?? '',
      largura: int.tryParse('${dados['largura'] ?? 0}') ?? 0,
      altura: int.tryParse('${dados['altura'] ?? 0}') ?? 0,
      publicadoEm: DateTime.tryParse(dados['publicado_em']?.toString() ?? '')
          ?.toLocal(),
    );
  }
}

class JornalOfertasService {
  JornalOfertasService._();

  static final JornalOfertasService instance = JornalOfertasService._();

  final SupabaseClient central = SupabaseClient(
    AppMercadoConfig.centralSupabaseUrl,
    AppMercadoConfig.centralSupabaseAnonKey,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  Future<JornalPublicado?> buscarAtual() async {
    final resposta = await central.functions.invoke(
      'buscar-jornal-publicado',
      body: {
        'mercado_id': sessao.SessaoMercadoCliente.mercadoIdObrigatorio,
        'mercado_codigo': sessao.SessaoMercadoCliente.mercadoCodigoObrigatorio,
      },
    );
    final dados = resposta.data;

    if (resposta.status >= 400 || dados is! Map || dados['sucesso'] != true) {
      final mensagem = dados is Map
          ? dados['erro']?.toString()
          : 'Não foi possível carregar o jornal.';
      throw Exception(mensagem ?? 'Não foi possível carregar o jornal.');
    }

    final jornal = dados['jornal'];
    if (jornal == null) return null;
    if (jornal is! Map) {
      throw Exception('O jornal retornado está em formato inválido.');
    }

    final resultado = JornalPublicado.fromMap(
      Map<String, dynamic>.from(jornal),
    );
    if (resultado.imagemUrl.isEmpty) return null;
    return resultado;
  }
}

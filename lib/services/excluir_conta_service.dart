import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class ResultadoExclusaoConta {
  final bool usuarioAuthExcluido;
  final bool possuiOutrosMercados;
  final bool possuiVinculoFuncionario;
  final String mensagem;
  final String? aviso;
  final Map<String, dynamic> dados;

  const ResultadoExclusaoConta({
    required this.usuarioAuthExcluido,
    required this.possuiOutrosMercados,
    required this.possuiVinculoFuncionario,
    required this.mensagem,
    required this.aviso,
    required this.dados,
  });

  factory ResultadoExclusaoConta.fromMap(Map<String, dynamic> map) {
    return ResultadoExclusaoConta(
      usuarioAuthExcluido: map['usuario_auth_excluido'] == true,
      possuiOutrosMercados: map['possui_outros_mercados'] == true,
      possuiVinculoFuncionario:
          map['possui_vinculo_funcionario'] == true,
      mensagem: _texto(map['mensagem']).isEmpty
          ? 'Sua conta neste mercado foi excluída.'
          : _texto(map['mensagem']),
      aviso: _texto(map['aviso']).isEmpty ? null : _texto(map['aviso']),
      dados: map,
    );
  }
}

class ExcluirContaException implements Exception {
  final String mensagem;
  final String? codigo;

  const ExcluirContaException(this.mensagem, {this.codigo});

  @override
  String toString() => mensagem;
}

class ExcluirContaService {
  ExcluirContaService._();

  static const String _nomeFuncao = 'excluir-conta-cliente';

  static Future<ResultadoExclusaoConta> excluirConta({
    required String mercadoId,
  }) async {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    final mercadoIdLimpo = mercadoId.trim();

    if (session == null || session.accessToken.trim().isEmpty) {
      throw const ExcluirContaException(
        'Sua sessão expirou. Entre novamente antes de excluir a conta.',
        codigo: 'SESSAO_EXPIRADA',
      );
    }

    if (!_uuidValido(mercadoIdLimpo)) {
      throw const ExcluirContaException(
        'Não foi possível identificar o mercado atual.',
        codigo: 'MERCADO_INVALIDO',
      );
    }

    try {
      final resposta = await client.functions
          .invoke(
            _nomeFuncao,
            headers: {
              'Authorization': 'Bearer ${session.accessToken}',
            },
            body: {
              'mercado_id': mercadoIdLimpo,
              'confirmacao': 'EXCLUIR',
            },
          )
          .timeout(const Duration(seconds: 35));

      final dados = _mapaResposta(resposta.data);

      if (dados['sucesso'] != true) {
        throw ExcluirContaException(
          _mensagemErro(dados),
          codigo: _texto(dados['codigo']).isEmpty
              ? null
              : _texto(dados['codigo']),
        );
      }

      return ResultadoExclusaoConta.fromMap(dados);
    } on FunctionException catch (e) {
      final dynamic erroDinamico = e;
      final dados = _mapaResposta(erroDinamico.details);

      throw ExcluirContaException(
        _mensagemErro(
          dados,
          alternativa:
              'Não foi possível excluir a conta. Tente novamente mais tarde.',
        ),
        codigo: _texto(dados['codigo']).isEmpty
            ? null
            : _texto(dados['codigo']),
      );
    } on ExcluirContaException {
      rethrow;
    } on TimeoutException {
      throw const ExcluirContaException(
        'A solicitação demorou mais que o esperado. Verifique sua internet e tente novamente.',
        codigo: 'TIMEOUT',
      );
    } catch (e) {
      throw ExcluirContaException(
        'Não foi possível excluir a conta: $e',
        codigo: 'ERRO_INESPERADO',
      );
    }
  }

  static Map<String, dynamic> _mapaResposta(dynamic valor) {
    if (valor is Map<String, dynamic>) {
      return Map<String, dynamic>.from(valor);
    }

    if (valor is Map) {
      return Map<String, dynamic>.from(valor);
    }

    if (valor is String && valor.trim().isNotEmpty) {
      try {
        final decodificado = jsonDecode(valor);

        if (decodificado is Map) {
          return Map<String, dynamic>.from(decodificado);
        }
      } catch (_) {}
    }

    return <String, dynamic>{};
  }

  static String _mensagemErro(
    Map<String, dynamic> dados, {
    String alternativa = 'Não foi possível excluir a conta.',
  }) {
    final erro = _texto(dados['erro']);
    final mensagem = _texto(dados['mensagem']);

    if (erro.isNotEmpty) {
      return erro;
    }

    if (mensagem.isNotEmpty) {
      return mensagem;
    }

    return alternativa;
  }

  static bool _uuidValido(String valor) {
    return RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(valor);
  }
}

String _texto(dynamic valor) {
  return valor?.toString().trim() ?? '';
}

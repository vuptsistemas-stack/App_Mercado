import 'package:supabase_flutter/supabase_flutter.dart';

import 'central_service.dart';

class FinanceiroMasterService {
  FinanceiroMasterService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static String competenciaIso(DateTime data) {
    final ano = data.year.toString().padLeft(4, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$ano-$mes-01';
  }

  Future<Map<String, dynamic>> _functionMap(
    String acao, {
    Map<String, dynamic> parametros = const {},
  }) async {
    try {
      final resposta = await _supabase.functions.invoke(
        'financeiro-master',
        body: {'acao': acao, 'parametros': parametros},
      );
      final conteudo = resposta.data;

      if (conteudo is Map && conteudo['erro'] != null) {
        throw ErroUsuarioException(conteudo['erro'].toString());
      }

      if (conteudo is Map && conteudo['dados'] is Map) {
        final dados = Map<String, dynamic>.from(conteudo['dados'] as Map);
        if (conteudo['avisos'] is List) {
          dados['_avisos_sincronizacao'] = List<String>.from(
            (conteudo['avisos'] as List).map((item) => item.toString()),
          );
        }
        return dados;
      }

      throw const ErroUsuarioException(
        'O servidor retornou uma resposta inválida para o módulo financeiro.',
      );
    } catch (erro) {
      throw ErroUsuarioException(CentralService.mensagemErroUsuario(erro));
    }
  }

  Future<Map<String, dynamic>> carregarDashboard(DateTime competencia) {
    return _functionMap(
      'dashboard',
      parametros: {'p_competencia': competenciaIso(competencia)},
    );
  }

  Future<Map<String, dynamic>> carregarDetalheLoja({
    required String mercadoId,
    required DateTime competencia,
  }) {
    return _functionMap(
      'detalhe',
      parametros: {
        'p_mercado_id': mercadoId,
        'p_competencia': competenciaIso(competencia),
      },
    );
  }

  Future<Map<String, dynamic>> salvarContrato({
    required String mercadoId,
    required DateTime inicio,
    required String status,
    required String tipoImplantacao,
    required double valorImplantacao,
    required double descontoImplantacao,
    required String observacao,
  }) {
    return _functionMap(
      'salvar_contrato',
      parametros: {
        'p_mercado_id': mercadoId,
        'p_inicio': _dataIso(inicio),
        'p_status': status,
        'p_tipo_implantacao': tipoImplantacao,
        'p_valor_implantacao': valorImplantacao,
        'p_desconto_implantacao': descontoImplantacao,
        'p_observacao': observacao.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> salvarModuloCatalogo({
    String? id,
    required String codigo,
    required String nome,
    required String descricao,
    required double precoPadrao,
    required bool incluidoPlanoBase,
    required bool ativo,
  }) {
    return _functionMap(
      'salvar_modulo',
      parametros: {
        'p_id': id,
        'p_codigo': codigo.trim(),
        'p_nome': nome.trim(),
        'p_descricao': descricao.trim(),
        'p_preco_padrao': precoPadrao,
        'p_incluido_plano_base': incluidoPlanoBase,
        'p_ativo': ativo,
      },
    );
  }

  Future<Map<String, dynamic>> salvarModuloLoja({
    required String mercadoId,
    required String moduloId,
    required bool ativo,
    required double precoMensal,
    required DateTime vigenciaInicio,
    required String motivo,
  }) {
    return _functionMap(
      'salvar_modulo_loja',
      parametros: {
        'p_mercado_id': mercadoId,
        'p_modulo_id': moduloId,
        'p_ativo': ativo,
        'p_preco_mensal': precoMensal,
        'p_vigencia_inicio': _dataIso(vigenciaInicio),
        'p_motivo': motivo.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> fecharCompetencia(DateTime competencia) {
    return _functionMap(
      'fechar_competencia',
      parametros: {'p_competencia': competenciaIso(competencia)},
    );
  }

  Future<Map<String, dynamic>> atualizarCobranca({
    required String cobrancaId,
    required String status,
    required String referencia,
    DateTime? pagoEm,
    required String formaPagamento,
    required String observacao,
  }) {
    return _functionMap(
      'atualizar_cobranca',
      parametros: {
        'p_cobranca_id': cobrancaId,
        'p_status': status,
        'p_referencia': referencia.trim(),
        'p_pago_em': pagoEm?.toUtc().toIso8601String(),
        'p_forma_pagamento': formaPagamento.trim(),
        'p_observacao': observacao.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> cancelarLoja({
    required String mercadoId,
    required String motivo,
  }) {
    return _functionMap(
      'cancelar_loja',
      parametros: {'p_mercado_id': mercadoId, 'p_motivo': motivo.trim()},
    );
  }

  Future<Map<String, dynamic>> reativarLoja({
    required String mercadoId,
    required DateTime data,
    required String motivo,
    required List<String> modulosIds,
  }) {
    return _functionMap(
      'reativar_loja',
      parametros: {
        'p_mercado_id': mercadoId,
        'p_data': _dataIso(data),
        'p_motivo': motivo.trim(),
        'p_modulos_ids': modulosIds,
      },
    );
  }

  Future<Map<String, dynamic>> consultarAcessoLoja(String mercadoId) {
    return _consultarAcessoCentral(mercadoId);
  }

  Future<Map<String, dynamic>> _consultarAcessoCentral(String mercadoId) async {
    try {
      final resposta = await _supabase.functions.invoke(
        'validar-mercado-ativo',
        body: {'mercado_id': mercadoId},
      );
      final conteudo = resposta.data;

      if (conteudo is Map && conteudo['erro'] != null) {
        throw ErroUsuarioException(conteudo['erro'].toString());
      }
      if (conteudo is Map) {
        return Map<String, dynamic>.from(conteudo);
      }

      throw const ErroUsuarioException(
        'Não foi possível validar o acesso financeiro da loja.',
      );
    } catch (erro) {
      throw ErroUsuarioException(CentralService.mensagemErroUsuario(erro));
    }
  }

  static Map<String, double> simularPlano({
    required double faturamento,
    required int diasAtivos,
    required int diasNoMes,
    required double adicionais,
    required double implantacao,
  }) {
    final diasMes = diasNoMes <= 0 ? 30 : diasNoMes;
    final dias = diasAtivos.clamp(0, diasMes);
    final fracao = dias / diasMes;
    final faturamentoEquivalente = fracao > 0
        ? faturamento / fracao
        : faturamento;
    final mensalidadeCheia = calcularMensalidade(faturamentoEquivalente);
    final mensalidadeProporcional = mensalidadeCheia * fracao;
    final adicionaisProporcionais = adicionais * fracao;

    return {
      'fracao': fracao,
      'faturamento_equivalente': faturamentoEquivalente,
      'mensalidade_cheia': mensalidadeCheia,
      'mensalidade': mensalidadeProporcional,
      'adicionais': adicionaisProporcionais,
      'implantacao': implantacao,
      'total': mensalidadeProporcional + adicionaisProporcionais + implantacao,
    };
  }

  static double calcularMensalidade(double faturamento) {
    if (faturamento <= 15000) return 159.90;
    if (faturamento <= 30000) return 189.90;
    if (faturamento <= 45000) return 219.90;
    if (faturamento <= 60000) return 249.90;
    if (faturamento <= 75000) return 279.90;
    if (faturamento <= 90000) return 309.90;
    if (faturamento <= 100000) return 339.90;
    return 339.90 + ((faturamento - 100000) * 0.0025);
  }

  static String _dataIso(DateTime data) {
    final ano = data.year.toString().padLeft(4, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final dia = data.day.toString().padLeft(2, '0');
    return '$ano-$mes-$dia';
  }
}

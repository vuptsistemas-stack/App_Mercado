import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'central_service.dart';
import 'notificacao_pedidos_service.dart';
import 'sessao_loja.dart';

class MonitorAcoesValidadeService {
  MonitorAcoesValidadeService._();

  static final MonitorAcoesValidadeService instance =
      MonitorAcoesValidadeService._();

  final CentralService centralService = CentralService();

  Timer? _timer;
  bool _verificando = false;
  String? _mercadoMonitorado;
  FutureOr<void> Function()? _onAcoesEncerradas;

  Future<void> iniciar({FutureOr<void> Function()? onAcoesEncerradas}) async {
    final mercadoId = SessaoLoja.mercadoId?.trim();
    final api = _apiBaseUrl;

    _onAcoesEncerradas = onAcoesEncerradas;

    if (mercadoId == null || mercadoId.isEmpty || api == null) {
      return;
    }

    if (_timer != null && _mercadoMonitorado == mercadoId) {
      return;
    }

    await parar();

    _mercadoMonitorado = mercadoId;
    _timer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(verificarAgora());
    });

    unawaited(verificarAgora());
  }

  Future<void> parar() async {
    _timer?.cancel();
    _timer = null;
    _mercadoMonitorado = null;
    _onAcoesEncerradas = null;
  }

  String? get _apiBaseUrl {
    final url = SessaoLoja.apiBaseUrl?.trim();
    if (url == null || url.isEmpty) return null;
    return url.replaceAll(RegExp(r'/+$'), '');
  }

  String _texto(dynamic valor) {
    return valor?.toString().trim() ?? '';
  }

  double? _numero(dynamic valor) {
    if (valor == null) return null;
    if (valor is num) return valor.toDouble();

    final textoValor = valor
        .toString()
        .trim()
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll('.', '')
        .replaceAll(',', '.');

    if (textoValor.isEmpty) return null;
    return double.tryParse(textoValor);
  }

  String _somenteNumeros(String valor) {
    return valor.replaceAll(RegExp(r'\D'), '');
  }

  String _normalizarEan(String valor) {
    final numeros = _somenteNumeros(valor);
    if (numeros.isEmpty) return '';
    return numeros.length < 14 ? numeros.padLeft(14, '0') : numeros;
  }

  double _estoqueProduto(Map<String, dynamic> produto) {
    for (final campo in [
      'estoque_atual',
      'estoque',
      'quantidade',
      'saldo_estoque',
      'qtd_estoque',
      'saldo',
    ]) {
      final valor = _numero(produto[campo]);
      if (valor != null) return valor;
    }
    return 0;
  }

  List<Map<String, dynamic>> _extrairProdutos(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (data is Map) {
      for (final campo in ['produtos', 'data', 'resultado', 'results']) {
        if (data[campo] is List) {
          return List<Map<String, dynamic>>.from(data[campo]);
        }
      }

      if (data['produto'] is Map) {
        return [Map<String, dynamic>.from(data['produto'])];
      }

      if (data['produto_id'] != null ||
          data['ean_principal'] != null ||
          data['nome_produto'] != null) {
        return [Map<String, dynamic>.from(data)];
      }
    }

    return [];
  }

  Future<double?> _buscarEstoqueAtual(String ean) async {
    final api = _apiBaseUrl;
    if (api == null) return null;

    final codigo = _normalizarEan(ean);
    if (codigo.isEmpty) return null;

    final url = Uri.parse('$api/produto/ean/$codigo');
    final resposta = await http.get(url).timeout(const Duration(seconds: 20));

    if (resposta.statusCode != 200) return null;

    final produtos = _extrairProdutos(jsonDecode(resposta.body));
    if (produtos.isEmpty) return null;

    return _estoqueProduto(produtos.first);
  }

  Future<void> verificarAgora() async {
    if (_verificando) return;

    final mercadoId = SessaoLoja.mercadoId?.trim();
    if (mercadoId == null || mercadoId.isEmpty) return;

    _verificando = true;

    try {
      final dados = await centralService.listarAcoesValidade(
        mercadoId: mercadoId,
      );

      final acoes = dados['acoes'] as List<Map<String, dynamic>>;
      final ativas = acoes.where((acao) {
        return acao['ativo'] == true &&
            _texto(acao['status']).toUpperCase() == 'ATIVA';
      });

      final estoques = <Map<String, dynamic>>[];

      for (final acao in ativas) {
        final ean = _texto(acao['ean']);
        if (ean.isEmpty) continue;

        final estoqueAtual = await _buscarEstoqueAtual(ean);
        if (estoqueAtual == null) continue;

        estoques.add({
          'acao_id': acao['id'],
          'ean': ean,
          'estoque_atual': estoqueAtual,
        });
      }

      final resposta = await centralService.monitorarAcoesValidade(
        mercadoId: mercadoId,
        estoques: estoques,
      );

      final encerradas = resposta['encerradas'] as List<Map<String, dynamic>>;

      for (final encerrada in encerradas) {
        final mensagem = _texto(encerrada['alerta_mensagem']);

        await NotificacaoPedidosService.instance.alertaValidade(
          titulo: 'Alerta de validade',
          mensagem: mensagem.isEmpty
              ? 'Uma acao de validade foi encerrada.'
              : mensagem,
        );
      }

      if (encerradas.isNotEmpty) {
        await _onAcoesEncerradas?.call();
      }
    } catch (_) {
      // Monitoramento nao deve interromper o uso do app.
    } finally {
      _verificando = false;
    }
  }
}

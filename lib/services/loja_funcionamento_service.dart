import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../controllers/carrinho_controller.dart';
import 'sessao_mercado_cliente.dart' as sessao;

class ResultadoFuncionamentoLoja {
  final bool aberto;
  final String mensagem;
  final String? horarioAbertura;
  final String? horarioFechamento;
  final String? motivoFechamento;

  const ResultadoFuncionamentoLoja({
    required this.aberto,
    required this.mensagem,
    this.horarioAbertura,
    this.horarioFechamento,
    this.motivoFechamento,
  });
}

class LojaConfiguracoesCliente {
  final bool exibirEstoque;
  final bool exibirProdutosSemEstoque;
  final bool bloquearVendaSemEstoque;
  final bool alertarEstoqueBaixoCarrinho;
  final double limiteAlertaEstoqueBaixoCarrinho;
  final bool exibirBotaoFinalizarCompra;
  final bool bloquearCarrinhoLojaFechada;
  final bool cobrarFrete;
  final double pedidoMinimo;
  final double taxaEntrega;
  final double valorFreteGratis;
  final double freteTaxaBase;
  final double fretePorKm;
  final double freteKmMaximo;
  final double freteGratisAcima;
  final bool bloquearEntregaForaRaio;
  final String mensagemFechado;
  final String mensagemForaAreaEntrega;
  final Map<String, dynamic> dados;

  const LojaConfiguracoesCliente({
    required this.exibirEstoque,
    required this.exibirProdutosSemEstoque,
    required this.bloquearVendaSemEstoque,
    required this.alertarEstoqueBaixoCarrinho,
    required this.limiteAlertaEstoqueBaixoCarrinho,
    required this.exibirBotaoFinalizarCompra,
    required this.bloquearCarrinhoLojaFechada,
    required this.cobrarFrete,
    required this.pedidoMinimo,
    required this.taxaEntrega,
    required this.valorFreteGratis,
    required this.freteTaxaBase,
    required this.fretePorKm,
    required this.freteKmMaximo,
    required this.freteGratisAcima,
    required this.bloquearEntregaForaRaio,
    required this.mensagemFechado,
    required this.mensagemForaAreaEntrega,
    required this.dados,
  });

  factory LojaConfiguracoesCliente.padrao() {
    return const LojaConfiguracoesCliente(
      exibirEstoque: true,
      exibirProdutosSemEstoque: true,
      bloquearVendaSemEstoque: true,
      alertarEstoqueBaixoCarrinho: false,
      limiteAlertaEstoqueBaixoCarrinho: 5,
      exibirBotaoFinalizarCompra: false,
      bloquearCarrinhoLojaFechada: true,
      cobrarFrete: true,
      pedidoMinimo: 0,
      taxaEntrega: 0,
      valorFreteGratis: 0,
      freteTaxaBase: 0,
      fretePorKm: 0,
      freteKmMaximo: 0,
      freteGratisAcima: 0,
      bloquearEntregaForaRaio: true,
      mensagemFechado:
          'A loja está fechada no momento. Tente novamente dentro do horário de atendimento.',
      mensagemForaAreaEntrega: 'Endereço fora da área de entrega.',
      dados: {},
    );
  }

  factory LojaConfiguracoesCliente.fromMap(Map<String, dynamic> dados) {
    final padrao = LojaConfiguracoesCliente.padrao();

    final mensagemFechado =
        LojaFuncionamentoService._texto(dados['mensagem_fechado']).isNotEmpty
        ? LojaFuncionamentoService._texto(dados['mensagem_fechado'])
        : padrao.mensagemFechado;

    final mensagemForaArea =
        LojaFuncionamentoService._texto(
          dados['mensagem_fora_area_entrega'],
        ).isNotEmpty
        ? LojaFuncionamentoService._texto(dados['mensagem_fora_area_entrega'])
        : padrao.mensagemForaAreaEntrega;

    return LojaConfiguracoesCliente(
      exibirEstoque: LojaFuncionamentoService._booleano(
        dados['exibir_estoque'],
        true,
      ),
      exibirProdutosSemEstoque: LojaFuncionamentoService._booleano(
        dados['exibir_produtos_sem_estoque'],
        true,
      ),
      bloquearVendaSemEstoque: LojaFuncionamentoService._booleano(
        dados['bloquear_venda_sem_estoque'],
        true,
      ),
      alertarEstoqueBaixoCarrinho: LojaFuncionamentoService._booleano(
        dados['alertar_estoque_baixo_carrinho'],
        false,
      ),
      limiteAlertaEstoqueBaixoCarrinho: LojaFuncionamentoService._numero(
        dados['limite_alerta_estoque_baixo_carrinho'],
      ),
      exibirBotaoFinalizarCompra: LojaFuncionamentoService._booleano(
        dados['exibir_botao_finalizar_compra'],
        false,
      ),
      bloquearCarrinhoLojaFechada: LojaFuncionamentoService._booleano(
        dados['bloquear_carrinho_loja_fechada'],
        true,
      ),
      cobrarFrete: LojaFuncionamentoService._booleano(
        dados['cobrar_frete'],
        true,
      ),
      pedidoMinimo: LojaFuncionamentoService._numero(dados['pedido_minimo']),
      taxaEntrega: LojaFuncionamentoService._numero(dados['taxa_entrega']),
      valorFreteGratis: LojaFuncionamentoService._numero(
        dados['valor_frete_gratis'],
      ),
      freteTaxaBase: LojaFuncionamentoService._numero(
        dados['frete_taxa_base'] ?? dados['taxa_entrega'],
      ),
      fretePorKm: LojaFuncionamentoService._numero(dados['frete_por_km']),
      freteKmMaximo: LojaFuncionamentoService._numero(dados['frete_km_maximo']),
      freteGratisAcima: LojaFuncionamentoService._numero(
        dados['frete_gratis_acima'] ?? dados['valor_frete_gratis'],
      ),
      bloquearEntregaForaRaio: LojaFuncionamentoService._booleano(
        dados['bloquear_entrega_fora_raio'],
        true,
      ),
      mensagemFechado: mensagemFechado,
      mensagemForaAreaEntrega: mensagemForaArea,
      dados: dados,
    );
  }
}

class LojaFuncionamentoService {
  static ResultadoFuncionamentoLoja? _cache;
  static DateTime? _cacheEm;

  static LojaConfiguracoesCliente? _cacheConfiguracoes;
  static DateTime? _cacheConfiguracoesEm;
  static List<String> _categoriasBloqueadasCliente = [];
  static DateTime? _categoriasBloqueadasClienteEm;
  static String? _categoriasBloqueadasClienteUserId;

  static const Duration _duracaoCache = Duration(seconds: 30);

  static List<String> _listaTextos(dynamic valor) {
    Iterable<dynamic> itens = const [];

    if (valor is List) {
      itens = valor;
    } else if (valor is String && valor.trim().isNotEmpty) {
      itens = valor.split(',');
    }

    final resultado = <String>[];
    final chaves = <String>{};

    for (final item in itens) {
      final nome = item.toString().trim();
      final chave = normalizarCategoria(nome);

      if (nome.isEmpty || chave.isEmpty || chaves.contains(chave)) continue;

      resultado.add(nome);
      chaves.add(chave);
    }

    return resultado;
  }

  static String normalizarCategoria(String valor) {
    return valor
        .trim()
        .toUpperCase()
        .replaceAll('Á', 'A')
        .replaceAll('À', 'A')
        .replaceAll('Â', 'A')
        .replaceAll('Ã', 'A')
        .replaceAll('Ä', 'A')
        .replaceAll('É', 'E')
        .replaceAll('È', 'E')
        .replaceAll('Ê', 'E')
        .replaceAll('Ë', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ì', 'I')
        .replaceAll('Î', 'I')
        .replaceAll('Ï', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ò', 'O')
        .replaceAll('Ô', 'O')
        .replaceAll('Õ', 'O')
        .replaceAll('Ö', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('Ù', 'U')
        .replaceAll('Û', 'U')
        .replaceAll('Ü', 'U')
        .replaceAll('Ç', 'C')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static List<String> get categoriasBloqueadasCliente =>
      List<String>.unmodifiable(_categoriasBloqueadasCliente);

  static void configurarCategoriasBloqueadasCliente(dynamic valor) {
    _categoriasBloqueadasCliente = _listaTextos(valor);
    _categoriasBloqueadasClienteUserId =
        Supabase.instance.client.auth.currentUser?.id;
    _categoriasBloqueadasClienteEm = DateTime.now();
  }

  static void limparCategoriasBloqueadasCliente() {
    _categoriasBloqueadasCliente = [];
    _categoriasBloqueadasClienteUserId = null;
    _categoriasBloqueadasClienteEm = null;
  }

  static bool categoriaBloqueadaParaCliente(String categoria) {
    final chave = normalizarCategoria(categoria);

    if (chave.isEmpty) return false;

    return _categoriasBloqueadasCliente.any(
      (item) => normalizarCategoria(item) == chave,
    );
  }

  static Future<void> _atualizarCategoriasBloqueadasCliente({
    bool forcarAtualizacao = false,
  }) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;

    if (userId == null || userId.isEmpty) {
      limparCategoriasBloqueadasCliente();
      return;
    }

    final agora = DateTime.now();
    final mesmoUsuario = _categoriasBloqueadasClienteUserId == userId;
    final cacheValido = _categoriasBloqueadasClienteEm != null &&
        agora.difference(_categoriasBloqueadasClienteEm!) <= _duracaoCache;

    if (!forcarAtualizacao && mesmoUsuario && cacheValido) return;

    try {
      final resposta = await client
          .from('clientes')
          .select('categorias_bloqueadas')
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .eq('user_id', userId)
          .maybeSingle();

      configurarCategoriasBloqueadasCliente(
        resposta?['categorias_bloqueadas'],
      );
    } catch (_) {
      _categoriasBloqueadasCliente = [];
      _categoriasBloqueadasClienteUserId = userId;
      _categoriasBloqueadasClienteEm = agora;
    }
  }

  static void limparCache() {
    _cache = null;
    _cacheEm = null;
    _cacheConfiguracoes = null;
    _cacheConfiguracoesEm = null;
    limparCategoriasBloqueadasCliente();
  }

  static Future<LojaConfiguracoesCliente> buscarConfiguracoes({
    bool forcarAtualizacao = false,
  }) async {
    await _atualizarCategoriasBloqueadasCliente(
      forcarAtualizacao: forcarAtualizacao,
    );

    final agora = DateTime.now();

    if (!forcarAtualizacao &&
        _cacheConfiguracoes != null &&
        _cacheConfiguracoesEm != null) {
      final idade = agora.difference(_cacheConfiguracoesEm!);

      if (idade <= _duracaoCache) {
        return _cacheConfiguracoes!;
      }
    }

    try {
      final resposta = await Supabase.instance.client
          .from('loja_configuracoes')
          .select()
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .limit(1)
          .maybeSingle();

      final configuracoes = resposta == null
          ? LojaConfiguracoesCliente.padrao()
          : LojaConfiguracoesCliente.fromMap(
              Map<String, dynamic>.from(resposta),
            );

      _cacheConfiguracoes = configuracoes;
      _cacheConfiguracoesEm = DateTime.now();

      return configuracoes;
    } catch (_) {
      final configuracoes = LojaConfiguracoesCliente.padrao();

      _cacheConfiguracoes = configuracoes;
      _cacheConfiguracoesEm = DateTime.now();

      return configuracoes;
    }
  }

  static Future<void> aplicarConfiguracoesNoCarrinho(
    BuildContext context, {
    bool forcarAtualizacao = false,
  }) async {
    final configuracoes = await buscarConfiguracoes(
      forcarAtualizacao: forcarAtualizacao,
    );

    if (!context.mounted) {
      return;
    }

    try {
      context.read<CarrinhoController>().atualizarBloqueioVendaSemEstoque(
        configuracoes.bloquearVendaSemEstoque,
      );
    } catch (_) {}
  }

  static Future<bool> alertarEstoqueBaixoAoAdicionar(
    BuildContext context, {
    required double estoqueAtual,
    required String unidade,
  }) async {
    final configuracoes = await buscarConfiguracoes();

    if (!context.mounted ||
        !configuracoes.exibirEstoque ||
        !configuracoes.alertarEstoqueBaixoCarrinho ||
        estoqueAtual <= 0 ||
        configuracoes.limiteAlertaEstoqueBaixoCarrinho <= 0 ||
        estoqueAtual > configuracoes.limiteAlertaEstoqueBaixoCarrinho) {
      return false;
    }

    final quantidade = _formatarQuantidadeEstoque(estoqueAtual);
    final unidadeNormalizada = unidade.trim().toUpperCase();
    final sufixo = unidadeNormalizada.isEmpty ? '' : ' $unidadeNormalizada';

    final retirarItem = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.inventory_2_outlined,
          color: Color(0xFFF59E0B),
          size: 34,
        ),
        title: const Text('Estoque baixo'),
        content: Text(
          'Restam apenas $quantidade$sufixo deste produto. Deseja continuar com o item no carrinho?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Retirar item'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Continuar comprando'),
          ),
        ],
      ),
    );

    return retirarItem ?? false;
  }

  static String _formatarQuantidadeEstoque(double valor) {
    if ((valor - valor.roundToDouble()).abs() < 0.0001) {
      return valor.round().toString();
    }

    var texto = valor.toStringAsFixed(3).replaceAll('.', ',');

    while (texto.endsWith('0')) {
      texto = texto.substring(0, texto.length - 1);
    }

    if (texto.endsWith(',')) {
      texto = texto.substring(0, texto.length - 1);
    }

    return texto;
  }

  static Future<bool> podeAdicionarAoCarrinho(
    BuildContext context, {
    bool forcarAtualizacao = false,
  }) async {
    final configuracoes = await buscarConfiguracoes(
      forcarAtualizacao: forcarAtualizacao,
    );

    if (context.mounted) {
      try {
        context.read<CarrinhoController>().atualizarBloqueioVendaSemEstoque(
          configuracoes.bloquearVendaSemEstoque,
        );
      } catch (_) {}
    }

    if (!configuracoes.bloquearCarrinhoLojaFechada) {
      return true;
    }

    final resultado = await verificarLojaAberta(
      forcarAtualizacao: forcarAtualizacao,
    );

    if (resultado.aberto) {
      return true;
    }

    if (!context.mounted) {
      return false;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(resultado.mensagem),
        backgroundColor: const Color(0xFFE30613),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );

    return false;
  }

  static Future<ResultadoFuncionamentoLoja> verificarLojaAberta({
    bool forcarAtualizacao = false,
  }) async {
    final agora = DateTime.now();

    if (!forcarAtualizacao && _cache != null && _cacheEm != null) {
      final idade = agora.difference(_cacheEm!);

      if (idade <= _duracaoCache) {
        return _cache!;
      }
    }

    try {
      final supabase = Supabase.instance.client;

      final mensagemFechado = await _buscarMensagemFechado(supabase);

      final fechamento = await _buscarFechamentoAtual(supabase, agora);
      if (fechamento != null) {
        final motivo = _texto(fechamento['motivo']);

        return _salvarCache(
          ResultadoFuncionamentoLoja(
            aberto: false,
            mensagem: motivo.isNotEmpty
                ? 'A loja está fechada no momento: $motivo.'
                : mensagemFechado,
            motivoFechamento: motivo,
          ),
        );
      }

      final tipoHorario = _tipoHorarioDoDia(agora);
      final horario = await _buscarHorarioDoDia(supabase, tipoHorario);

      final aberto = _booleano(
        horario?['aberto'],
        _abertoPadraoPorTipo(tipoHorario),
      );

      final abertura = _horarioOuPadrao(
        horario?['horario_abertura'],
        _aberturaPadraoPorTipo(tipoHorario),
      );

      final fechamentoHora = _horarioOuPadrao(
        horario?['horario_fechamento'],
        _fechamentoPadraoPorTipo(tipoHorario),
      );

      if (!aberto) {
        return _salvarCache(
          ResultadoFuncionamentoLoja(
            aberto: false,
            mensagem: mensagemFechado,
            horarioAbertura: abertura,
            horarioFechamento: fechamentoHora,
          ),
        );
      }

      if (abertura.isEmpty || fechamentoHora.isEmpty) {
        return _salvarCache(
          ResultadoFuncionamentoLoja(
            aberto: false,
            mensagem: mensagemFechado,
            horarioAbertura: abertura,
            horarioFechamento: fechamentoHora,
          ),
        );
      }

      final minutoAgora = agora.hour * 60 + agora.minute;
      final minutoAbertura = _horarioParaMinutos(abertura);
      final minutoFechamento = _horarioParaMinutos(fechamentoHora);

      if (minutoAbertura == null || minutoFechamento == null) {
        return _salvarCache(
          ResultadoFuncionamentoLoja(
            aberto: false,
            mensagem: mensagemFechado,
            horarioAbertura: abertura,
            horarioFechamento: fechamentoHora,
          ),
        );
      }

      final dentroDoHorario = _estaDentroDoHorario(
        minutoAgora: minutoAgora,
        minutoAbertura: minutoAbertura,
        minutoFechamento: minutoFechamento,
      );

      if (!dentroDoHorario) {
        return _salvarCache(
          ResultadoFuncionamentoLoja(
            aberto: false,
            mensagem:
                '$mensagemFechado Horário de atendimento: $abertura às $fechamentoHora.',
            horarioAbertura: abertura,
            horarioFechamento: fechamentoHora,
          ),
        );
      }

      return _salvarCache(
        ResultadoFuncionamentoLoja(
          aberto: true,
          mensagem: 'Loja aberta',
          horarioAbertura: abertura,
          horarioFechamento: fechamentoHora,
        ),
      );
    } catch (_) {
      return _salvarCache(
        const ResultadoFuncionamentoLoja(aberto: true, mensagem: 'Loja aberta'),
      );
    }
  }

  static ResultadoFuncionamentoLoja _salvarCache(
    ResultadoFuncionamentoLoja resultado,
  ) {
    _cache = resultado;
    _cacheEm = DateTime.now();
    return resultado;
  }

  static Future<String> _buscarMensagemFechado(SupabaseClient supabase) async {
    try {
      final configuracoes = await buscarConfiguracoes();

      if (configuracoes.mensagemFechado.isNotEmpty) {
        return configuracoes.mensagemFechado;
      }
    } catch (_) {}

    try {
      final resposta = await supabase
          .from('loja_configuracoes')
          .select('mensagem_fechado')
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .limit(1)
          .maybeSingle();

      final mensagem = _texto(resposta?['mensagem_fechado']);

      if (mensagem.isNotEmpty) {
        return mensagem;
      }
    } catch (_) {}

    return 'A loja está fechada no momento. Tente novamente dentro do horário de atendimento.';
  }

  static Future<Map<String, dynamic>?> _buscarFechamentoAtual(
    SupabaseClient supabase,
    DateTime data,
  ) async {
    final hoje = _dataBanco(data);

    try {
      final resposta = await supabase
          .from('loja_fechamentos')
          .select('data_inicio, data_fim, motivo, ativo')
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .lte('data_inicio', hoje)
          .gte('data_fim', hoje);

      final lista = List<Map<String, dynamic>>.from(resposta);

      for (final item in lista) {
        if (_booleano(item['ativo'], true)) {
          return item;
        }
      }
    } catch (_) {}

    return null;
  }

  static Future<Map<String, dynamic>?> _buscarHorarioDoDia(
    SupabaseClient supabase,
    String tipo,
  ) async {
    try {
      final resposta = await supabase
          .from('loja_horarios')
          .select('tipo, aberto, horario_abertura, horario_fechamento')
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .eq('tipo', tipo)
          .maybeSingle();

      if (resposta == null) {
        return null;
      }

      return Map<String, dynamic>.from(resposta);
    } catch (_) {
      return null;
    }
  }

  static String _tipoHorarioDoDia(DateTime data) {
    if (data.weekday == DateTime.saturday) {
      return 'sabado';
    }

    if (data.weekday == DateTime.sunday) {
      return 'domingo';
    }

    return 'segunda_sexta';
  }

  static bool _abertoPadraoPorTipo(String tipo) {
    if (tipo == 'domingo') {
      return false;
    }

    return true;
  }

  static String _aberturaPadraoPorTipo(String tipo) {
    return '08:00';
  }

  static String _fechamentoPadraoPorTipo(String tipo) {
    if (tipo == 'sabado') {
      return '18:00';
    }

    if (tipo == 'domingo') {
      return '12:00';
    }

    return '19:00';
  }

  static String _horarioOuPadrao(dynamic valor, String padrao) {
    final texto = _texto(valor);

    if (texto.isEmpty) {
      return padrao;
    }

    if (texto.length >= 5) {
      return texto.substring(0, 5);
    }

    return texto;
  }

  static int? _horarioParaMinutos(String horario) {
    final partes = horario.split(':');

    if (partes.length < 2) {
      return null;
    }

    final hora = int.tryParse(partes[0]);
    final minuto = int.tryParse(partes[1]);

    if (hora == null || minuto == null) {
      return null;
    }

    return hora * 60 + minuto;
  }

  static bool _estaDentroDoHorario({
    required int minutoAgora,
    required int minutoAbertura,
    required int minutoFechamento,
  }) {
    if (minutoAbertura == minutoFechamento) {
      return false;
    }

    if (minutoAbertura < minutoFechamento) {
      return minutoAgora >= minutoAbertura && minutoAgora <= minutoFechamento;
    }

    return minutoAgora >= minutoAbertura || minutoAgora <= minutoFechamento;
  }

  static bool _booleano(dynamic valor, bool padrao) {
    if (valor is bool) {
      return valor;
    }

    if (valor is num) {
      return valor != 0;
    }

    final texto = _texto(valor).toLowerCase();

    if (texto == 'true' || texto == '1' || texto == 'sim' || texto == 's') {
      return true;
    }

    if (texto == 'false' ||
        texto == '0' ||
        texto == 'nao' ||
        texto == 'não' ||
        texto == 'n') {
      return false;
    }

    return padrao;
  }

  static double _numero(dynamic valor) {
    if (valor == null) {
      return 0;
    }

    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor.toString().replaceAll(',', '.').trim()) ?? 0;
  }

  static String _texto(dynamic valor) {
    if (valor == null) {
      return '';
    }

    return valor.toString().trim();
  }

  static String _dataBanco(DateTime data) {
    final ano = data.year.toString().padLeft(4, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final dia = data.day.toString().padLeft(2, '0');

    return '$ano-$mes-$dia';
  }
}

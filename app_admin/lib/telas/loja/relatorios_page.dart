import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:excel/excel.dart' as ex;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/central_service.dart';
import '../../services/sessao_loja.dart';

class RelatoriosPage extends StatefulWidget {
  const RelatoriosPage({super.key});

  @override
  State<RelatoriosPage> createState() => _RelatoriosPageState();
}

class _RelatorioOpcao {
  final String id;
  final String titulo;
  final String descricao;
  final IconData icone;

  const _RelatorioOpcao({
    required this.id,
    required this.titulo,
    required this.descricao,
    required this.icone,
  });
}

class _RelatoriosPageState extends State<RelatoriosPage> {
  static Color get azul => SessaoLoja.corPrimaria;
  static Color get azulEscuro => SessaoLoja.corSecundaria;
  static Color get fundo => SessaoLoja.corFundo;

  final CentralService centralService = CentralService();
  bool verificandoPermissao = true;
  bool usuarioMasterCentral = false;
  bool usuarioTemRelatorios = false;
  bool carregando = false;
  bool exportando = false;

  String relatorioSelecionado = 'vendas_resumo';
  String periodoSelecionado = 'mes_atual';
  String? erro;
  String? aviso;

  DateTime dataInicio = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime dataFim = DateTime.now();

  Map<String, dynamic> metricas = {};
  List<Map<String, dynamic>> registros = [];

  final List<_RelatorioOpcao> relatorios = const [
    _RelatorioOpcao(
      id: 'vendas_resumo',
      titulo: 'Resumo de Vendas',
      descricao:
          'Visualize faturamento, quantidade de pedidos e ticket médio do período.',
      icone: Icons.shopping_cart_outlined,
    ),
    _RelatorioOpcao(
      id: 'pedidos_status',
      titulo: 'Pedidos por Status',
      descricao:
          'Acompanhe quantos pedidos estão novos, em preparo, entrega e finalizados.',
      icone: Icons.assignment_outlined,
    ),
    _RelatorioOpcao(
      id: 'produtos_mais_vendidos',
      titulo: 'Produtos Mais Vendidos',
      descricao:
          'Veja os produtos com melhor saída por quantidade vendida e valor faturado.',
      icone: Icons.emoji_events_outlined,
    ),
    _RelatorioOpcao(
      id: 'clientes',
      titulo: 'Clientes',
      descricao:
          'Consulte clientes ativos, frequência de pedidos e ticket médio.',
      icone: Icons.people_alt_outlined,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        inicializarPermissao();
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  dynamic queryMercado(dynamic consulta) {
    return consulta.eq('mercado_id', SessaoLoja.mercadoIdObrigatorio);
  }

  bool podeAcessarRelatorios() {
    return usuarioMasterCentral ||
        usuarioTemRelatorios ||
        SessaoLoja.temPermissao('relatorios');
  }

  Future<void> inicializarPermissao() async {
    SessaoLoja.sincronizarSessaoAtual();

    bool masterCentral = false;
    try {
      masterCentral = await centralService.usuarioEhMaster();
    } catch (_) {
      masterCentral = false;
    }

    if (!mounted) return;

    setState(() {
      usuarioMasterCentral = masterCentral;
      usuarioTemRelatorios =
          masterCentral || SessaoLoja.temPermissao('relatorios');
      verificandoPermissao = false;
    });

    if (podeAcessarRelatorios()) {
      aplicarPeriodo('mes_atual', recarregar: true);
    } else {
      setState(() {
        erro = 'Seu usuário não tem permissão para acessar relatórios.';
      });
    }
  }

  String dois(int valor) => valor.toString().padLeft(2, '0');

  String dataTela(DateTime data) =>
      '${dois(data.day)}/${dois(data.month)}/${data.year}';

  String dataSqlInicio(DateTime data) =>
      '${data.year}-${dois(data.month)}-${dois(data.day)}T00:00:00.000Z';

  String dataSqlFim(DateTime data) =>
      '${data.year}-${dois(data.month)}-${dois(data.day)}T23:59:59.999Z';

  String texto(dynamic valor) {
    if (valor == null) return '-';
    final t = valor.toString().trim();
    return t.isEmpty ? '-' : t;
  }

  String numero(dynamic valor) {
    final n = double.tryParse(valor?.toString() ?? '') ?? 0;
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(2).replaceAll('.', ',');
  }

  String moeda(dynamic valor) {
    final numero = double.tryParse(valor?.toString() ?? '') ?? 0;
    final partes = numero.toStringAsFixed(2).split('.');
    final inteiro = partes[0];
    final decimal = partes[1];
    final buffer = StringBuffer();
    for (int i = 0; i < inteiro.length; i++) {
      final posicao = inteiro.length - i;
      buffer.write(inteiro[i]);
      if (posicao > 1 && posicao % 3 == 1) {
        buffer.write('.');
      }
    }
    return 'R\$ ${buffer.toString()},$decimal';
  }

  String dataHoraTela(dynamic valor) {
    if (valor == null) return '-';
    final data = DateTime.tryParse(valor.toString());
    if (data == null) return valor.toString();
    final local = data.toLocal();
    return '${dois(local.day)}/${dois(local.month)}/${local.year} ${dois(local.hour)}:${dois(local.minute)}';
  }

  String? get apiBaseUrl {
    final url = SessaoLoja.apiBaseUrl?.trim();

    if (url == null || url.isEmpty || url.toLowerCase() == 'null') {
      return null;
    }

    return url.replaceAll(RegExp(r'/+$'), '');
  }

  double numeroDecimal(dynamic valor) {
    if (valor is num) return valor.toDouble();

    var texto = valor?.toString().trim() ?? '';
    if (texto.isEmpty || texto == '-') return 0;

    texto = texto.replaceAll('R\$', '').replaceAll(RegExp(r'[^0-9,.\-]'), '');

    if (texto.contains(',') && texto.contains('.')) {
      if (texto.lastIndexOf(',') > texto.lastIndexOf('.')) {
        texto = texto.replaceAll('.', '').replaceAll(',', '.');
      } else {
        texto = texto.replaceAll(',', '');
      }
    } else if (texto.contains(',')) {
      texto = texto.replaceAll(',', '.');
    }

    return double.tryParse(texto) ?? 0;
  }

  String campoTexto(Map<String, dynamic> item, List<String> campos) {
    for (final campo in campos) {
      final valor = texto(item[campo]);
      if (valor != '-') return valor;
    }

    return '-';
  }

  double campoNumero(Map<String, dynamic> item, List<String> campos) {
    for (final campo in campos) {
      if (!item.containsKey(campo) || item[campo] == null) continue;
      return numeroDecimal(item[campo]);
    }

    return 0;
  }

  bool campoBooleano(Map<String, dynamic> item, List<String> campos) {
    for (final campo in campos) {
      if (!item.containsKey(campo) || item[campo] == null) continue;
      return SessaoLoja.booleanoDinamico(item[campo], padrao: true);
    }

    return true;
  }

  bool produtoTemEstoqueMinimo(Map<String, dynamic> item) {
    const campos = [
      'estoque_minimo',
      'estoqueMinimo',
      'estoque_min',
      'minimo',
      'qtd_minima',
      'quantidade_minima',
      'minimo_estoque',
    ];

    return campos.any((campo) => item[campo] != null);
  }

  List<Map<String, dynamic>> extrairProdutosRelatorio(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (data is Map) {
      if (data['erro'] != null) throw Exception(data['erro'].toString());

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

  void aplicarPeriodo(String periodo, {bool recarregar = true}) {
    final agora = DateTime.now();
    DateTime inicio;
    DateTime fim = agora;

    switch (periodo) {
      case 'hoje':
        inicio = DateTime(agora.year, agora.month, agora.day);
        break;
      case '7_dias':
        inicio = DateTime(
          agora.year,
          agora.month,
          agora.day,
        ).subtract(const Duration(days: 6));
        break;
      case '30_dias':
        inicio = DateTime(
          agora.year,
          agora.month,
          agora.day,
        ).subtract(const Duration(days: 29));
        break;
      case 'mes_atual':
      default:
        inicio = DateTime(agora.year, agora.month, 1);
        fim = DateTime(agora.year, agora.month + 1, 0);
        break;
    }

    setState(() {
      periodoSelecionado = periodo;
      dataInicio = inicio;
      dataFim = fim;
    });

    if (recarregar) {
      carregarRelatorio();
    }
  }

  Future<void> escolherPeriodoPersonalizado() async {
    final inicio = await showDatePicker(
      context: context,
      initialDate: dataInicio,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (inicio == null || !mounted) return;

    final fim = await showDatePicker(
      context: context,
      initialDate: dataFim.isBefore(inicio) ? inicio : dataFim,
      firstDate: inicio,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (fim == null) return;

    setState(() {
      periodoSelecionado = 'personalizado';
      dataInicio = inicio;
      dataFim = fim;
    });

    await carregarRelatorio();
  }

  SupabaseClient get supabaseConsulta =>
      SessaoLoja.supabaseLoja ?? Supabase.instance.client;

  Future<List<Map<String, dynamic>>> _buscarTabelaComData({
    required String tabela,
    required String select,
    List<String> colunasData = const ['created_at', 'criado_em'],
    String? orderBy,
  }) async {
    PostgrestException? ultimoErro;

    // Primeiro tenta filtrar por data. Algumas tabelas antigas não possuem
    // created_at nem criado_em. Se nenhuma coluna existir, faz fallback sem data.
    for (final colunaData in colunasData) {
      try {
        dynamic consulta =
            queryMercado(supabaseConsulta.from(tabela).select(select))
                .gte(colunaData, dataSqlInicio(dataInicio))
                .lte(colunaData, dataSqlFim(dataFim));

        consulta = consulta.order(orderBy ?? colunaData, ascending: false);

        final resposta = await consulta;
        return List<Map<String, dynamic>>.from(resposta as List);
      } on PostgrestException catch (e) {
        ultimoErro = e;
        final textoErro = '${e.message} ${e.details ?? ''} ${e.hint ?? ''}'
            .toLowerCase();

        final erroColunaInexistente =
            textoErro.contains(colunaData.toLowerCase()) ||
            textoErro.contains('does not exist') ||
            e.code == '42703';

        if (!erroColunaInexistente) {
          rethrow;
        }
      }
    }

    // Fallback para tabelas que não têm coluna de data.
    try {
      dynamic consulta = queryMercado(
        supabaseConsulta.from(tabela).select(select),
      );

      final resposta = await consulta;
      return List<Map<String, dynamic>>.from(resposta as List);
    } on PostgrestException catch (e) {
      throw ultimoErro ?? e;
    }
  }

  Future<void> carregarRelatorio() async {
    if (!podeAcessarRelatorios()) {
      setState(() {
        erro = 'Seu usuário não tem permissão para acessar relatórios.';
      });
      return;
    }

    setState(() {
      carregando = true;
      erro = null;
      aviso = null;
      registros = [];
      metricas = {};
    });

    try {
      switch (relatorioSelecionado) {
        case 'pedidos_status':
          await carregarPedidosPorStatus();
          break;
        case 'produtos_mais_vendidos':
          await carregarProdutosMaisVendidos();
          break;
        case 'estoque_baixo':
          await carregarEstoqueBaixo();
          break;
        case 'clientes':
          await carregarClientes();
          break;
        case 'mais':
          await carregarConsumoInterno();
          break;
        case 'vendas_resumo':
        default:
          await carregarResumoVendas();
      }
    } catch (e) {
      erro = CentralService.mensagemErroUsuario(e);
    }

    if (!mounted) return;
    setState(() {
      carregando = false;
    });
  }

  Future<void> carregarResumoVendas() async {
    List<Map<String, dynamic>> pedidos = [];
    String colunaDataUsada = '';

    PostgrestException? ultimoErro;

    final tentativas = <Map<String, String>>[
      {
        'select':
            'id,total,taxa_entrega,forma_pagamento,status,user_id,created_at',
        'data': 'created_at',
      },
      {
        'select':
            'id,total,taxa_entrega,forma_pagamento,status,user_id,criado_em',
        'data': 'criado_em',
      },
      {
        'select': 'id,total,forma_pagamento,status,user_id,created_at',
        'data': 'created_at',
      },
      {
        'select': 'id,total,forma_pagamento,status,user_id,criado_em',
        'data': 'criado_em',
      },
      {
        'select': 'id,total,forma_pagamento,status,created_at',
        'data': 'created_at',
      },
      {
        'select': 'id,total,forma_pagamento,status,criado_em',
        'data': 'criado_em',
      },
      {'select': 'id,total,forma_pagamento,status', 'data': ''},
    ];

    for (final tentativa in tentativas) {
      try {
        dynamic consulta = supabaseConsulta
            .from('pedidos')
            .select(tentativa['select']!)
            .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio);

        final colunaData = tentativa['data'] ?? '';

        if (colunaData.isNotEmpty) {
          consulta = consulta
              .gte(colunaData, dataSqlInicio(dataInicio))
              .lte(colunaData, dataSqlFim(dataFim))
              .order(colunaData, ascending: false);
        }

        final resposta = await consulta;
        pedidos = List<Map<String, dynamic>>.from(resposta as List);
        colunaDataUsada = colunaData;
        ultimoErro = null;
        break;
      } on PostgrestException catch (e) {
        ultimoErro = e;
        continue;
      }
    }

    if (ultimoErro != null && pedidos.isEmpty) {
      throw ultimoErro;
    }

    double faturamento = 0;
    double frete = 0;
    int cancelados = 0;
    final clientes = <String>{};
    final formasPagamento = <String>{};
    final Map<String, double> faturamentoPorDia = {};
    final Map<String, int> pedidosPorDia = {};

    for (final pedido in pedidos) {
      final status = texto(pedido['status']).toLowerCase();
      final total = double.tryParse(pedido['total']?.toString() ?? '') ?? 0;
      final taxa =
          double.tryParse(
            pedido['taxa_entrega']?.toString() ??
                pedido['frete']?.toString() ??
                pedido['valor_frete']?.toString() ??
                '0',
          ) ??
          0;

      if (texto(pedido['user_id']) != '-') {
        clientes.add(texto(pedido['user_id']));
      }

      if (texto(pedido['forma_pagamento']) != '-') {
        formasPagamento.add(texto(pedido['forma_pagamento']));
      }

      if (status.contains('cancel')) {
        cancelados++;
        continue;
      }

      faturamento += total;
      frete += taxa;

      final data = DateTime.tryParse(
        pedido['created_at']?.toString() ??
            pedido['criado_em']?.toString() ??
            '',
      );

      if (data != null) {
        final local = data.toLocal();
        final chave = '${dois(local.day)}/${dois(local.month)}';
        faturamentoPorDia[chave] = (faturamentoPorDia[chave] ?? 0) + total;
        pedidosPorDia[chave] = (pedidosPorDia[chave] ?? 0) + 1;
      }
    }

    final totalPedidos = pedidos.length;
    final ticketMedio = totalPedidos == 0 ? 0 : faturamento / totalPedidos;

    metricas = {
      'Faturamento Total': moeda(faturamento),
      'Pedidos': totalPedidos.toString(),
      'Ticket Médio': moeda(ticketMedio),
      'Frete Recebido': moeda(frete),
      'Cancelamentos': cancelados.toString(),
      'Formas de Pagamento': formasPagamento.isEmpty
          ? '-'
          : formasPagamento.length.toString(),
      'Clientes': clientes.isEmpty ? '-' : clientes.length.toString(),
      'Período': '${dataTela(dataInicio)} até ${dataTela(dataFim)}',
    };

    if (faturamentoPorDia.isEmpty) {
      registros = pedidos.take(8).map((pedido) {
        return {
          'Data': colunaDataUsada.isEmpty
              ? '-'
              : texto(pedido[colunaDataUsada]),
          'Faturamento': moeda(pedido['total']),
          'Pedidos': '1',
          'Clientes': texto(pedido['user_id']),
          'Ticket Médio': moeda(pedido['total']),
          'Forma Pgto': texto(pedido['forma_pagamento']),
          '_valor_grafico':
              double.tryParse(pedido['total']?.toString() ?? '') ?? 0,
        };
      }).toList();
    } else {
      registros = faturamentoPorDia.entries.map((e) {
        final qtdPedidosDia = pedidosPorDia[e.key] ?? 0;
        return {
          'Data': e.key,
          'Faturamento': moeda(e.value),
          'Pedidos': qtdPedidosDia.toString(),
          'Clientes': '-',
          'Ticket Médio': qtdPedidosDia == 0
              ? '-'
              : moeda(e.value / qtdPedidosDia),
          'Itens Vendidos': '-',
          '_valor_grafico': e.value,
        };
      }).toList();
    }
  }

  Future<void> carregarPedidosPorStatus() async {
    final pedidos = await _buscarTabelaComData(
      tabela: 'pedidos',
      select: 'id,status,total,forma_pagamento',
      colunasData: const ['criado_em', 'created_at'],
    );

    final Map<String, int> porStatus = {};
    final Map<String, double> valorPorStatus = {};

    for (final pedido in pedidos) {
      final status = texto(pedido['status']);
      final total = double.tryParse(pedido['total']?.toString() ?? '') ?? 0;

      porStatus[status] = (porStatus[status] ?? 0) + 1;
      valorPorStatus[status] = (valorPorStatus[status] ?? 0) + total;
    }

    final cancelados = porStatus.entries
        .where((e) => e.key.toLowerCase().contains('cancel'))
        .fold<int>(0, (a, b) => a + b.value);

    metricas = {
      'Total de Pedidos': pedidos.length.toString(),
      'Status Diferentes': porStatus.length.toString(),
      'Finalizados': (porStatus['finalizado'] ?? porStatus['Finalizado'] ?? 0)
          .toString(),
      'Cancelados': cancelados.toString(),
      'Em Preparo': (porStatus['preparo'] ?? porStatus['em preparo'] ?? 0)
          .toString(),
      'Entrega': (porStatus['saiu para entrega'] ?? 0).toString(),
    };

    registros = porStatus.entries.map((e) {
      return {
        'Status': e.key,
        'Pedidos': e.value.toString(),
        'Faturamento': moeda(valorPorStatus[e.key] ?? 0),
        'Clientes': '-',
        'Ticket Médio': e.value == 0
            ? '-'
            : moeda((valorPorStatus[e.key] ?? 0) / e.value),
        '_valor_grafico': e.value.toDouble(),
      };
    }).toList();
  }

  Future<void> carregarProdutosMaisVendidos() async {
    const selectItens =
        'pedido_id,produto_id,nome_produto,ean,quantidade,preco_unitario,total,total_final,total_estimado';

    List<Map<String, dynamic>> itens = [];

    // Primeiro tenta respeitar o período selecionado.
    try {
      itens = await _buscarTabelaComData(
        tabela: 'pedido_itens',
        select: selectItens,
        colunasData: const ['criado_em', 'conferido_em'],
        orderBy: 'criado_em',
      );
    } catch (_) {
      itens = [];
    }

    // Se não vier nada no período, carrega sem período para não deixar
    // o relatório vazio. Isso ajuda quando os dados antigos receberam data
    // retroativa, horário UTC diferente ou quando o filtro ainda não bate.
    if (itens.isEmpty) {
      final resposta = await supabaseConsulta
          .from('pedido_itens')
          .select(selectItens)
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
          .limit(5000);

      itens = List<Map<String, dynamic>>.from(resposta as List);
    }

    final Map<String, Map<String, dynamic>> agrupado = {};

    for (final item in itens) {
      final nome = texto(item['nome_produto']);
      final qtd = double.tryParse(item['quantidade']?.toString() ?? '') ?? 0;

      final totalItem =
          double.tryParse(
            item['total_final']?.toString() ??
                item['total']?.toString() ??
                item['total_estimado']?.toString() ??
                '',
          ) ??
          0;

      final preco =
          double.tryParse(item['preco_unitario']?.toString() ?? '') ?? 0;
      final totalCalculado = totalItem > 0 ? totalItem : qtd * preco;

      if (nome == '-' && qtd == 0 && totalCalculado == 0) {
        continue;
      }

      agrupado.putIfAbsent(nome, () {
        return {
          'nome': nome,
          'qtd': 0.0,
          'total': 0.0,
          'ean': texto(item['ean']),
        };
      });

      agrupado[nome]!['qtd'] = (agrupado[nome]!['qtd'] as double) + qtd;
      agrupado[nome]!['total'] =
          (agrupado[nome]!['total'] as double) + totalCalculado;
    }

    final lista = agrupado.values.toList()
      ..sort((a, b) => (b['qtd'] as double).compareTo(a['qtd'] as double));

    final totalItens = lista.fold<double>(
      0,
      (soma, item) => soma + (item['qtd'] as double),
    );
    final faturamento = lista.fold<double>(
      0,
      (soma, item) => soma + (item['total'] as double),
    );

    metricas = {
      'Produtos Vendidos': numero(totalItens),
      'Produtos Diferentes': lista.length.toString(),
      'Mais Vendido': lista.isEmpty ? '-' : texto(lista.first['nome']),
      'Faturamento': moeda(faturamento),
      'Top 5': lista.take(5).length.toString(),
      'Registros Lidos': itens.length.toString(),
    };

    registros = lista.take(20).map((item) {
      return {
        'Produto': texto(item['nome']),
        'EAN': texto(item['ean']),
        'Quantidade': numero(item['qtd']),
        'Faturamento': moeda(item['total']),
        'Ticket Médio': (item['qtd'] as double) == 0
            ? '-'
            : moeda((item['total'] as double) / (item['qtd'] as double)),
        '_valor_grafico': item['qtd'],
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> buscarProdutosEstoqueApi() async {
    final api = apiBaseUrl;
    if (api == null) {
      throw Exception('API da loja não configurada.');
    }

    const limite = 300;
    final produtos = <Map<String, dynamic>>[];
    final chavesVistas = <String>{};

    for (final caminho in ['produtos', 'produto']) {
      var encontrouEndpoint = false;

      for (var pagina = 1; pagina <= 20; pagina++) {
        final uri = Uri.parse('$api/$caminho').replace(
          queryParameters: {
            'pagina': pagina.toString(),
            'limite': limite.toString(),
          },
        );

        final resposta = await http
            .get(uri)
            .timeout(const Duration(seconds: 20));

        if (resposta.statusCode == 404) {
          if (!encontrouEndpoint && pagina == 1) break;
          break;
        }

        if (resposta.statusCode != 200) {
          throw Exception(
            'Erro na API ${resposta.statusCode}: ${resposta.body}',
          );
        }

        encontrouEndpoint = true;
        final lista = extrairProdutosRelatorio(jsonDecode(resposta.body));
        if (lista.isEmpty) break;

        var novos = 0;
        for (final produto in lista) {
          final ean = campoTexto(produto, const [
            'ean_principal',
            'ean',
            'codigo_barras',
            'codigo',
          ]);
          final nome = campoTexto(produto, const [
            'nome_produto',
            'descricao',
            'produto',
            'nome',
          ]);
          final chave = '$ean|$nome';

          if (chavesVistas.add(chave)) {
            produtos.add(produto);
            novos++;
          }
        }

        if (lista.length < limite || novos == 0) break;
      }

      if (produtos.isNotEmpty || encontrouEndpoint) break;
    }

    return produtos;
  }

  Future<List<Map<String, dynamic>>> buscarProdutosEstoqueSupabase() async {
    return centralService.listarProdutosAppEstoque(
      mercadoId: SessaoLoja.mercadoIdObrigatorio,
      mercadoCodigo: SessaoLoja.mercadoCodigo,
      limite: 2000,
    );
  }

  bool get usaProdutosSupabase =>
      SessaoLoja.fonteProdutos == 'BANCO_LOJA' || apiBaseUrl == null;

  Future<List<Map<String, dynamic>>> buscarProdutosEstoque() async {
    if (usaProdutosSupabase) {
      return buscarProdutosEstoqueSupabase();
    }

    return buscarProdutosEstoqueApi();
  }

  Future<void> carregarEstoqueBaixo() async {
    final produtos = await buscarProdutosEstoque();

    final baixos = <Map<String, dynamic>>[];
    var comMinimo = 0;
    var semEstoque = 0;
    var estoqueNegativo = 0;
    var estoqueTotal = 0.0;

    for (final produto in produtos) {
      if (!campoBooleano(produto, const ['ativo'])) {
        continue;
      }

      final estoque = campoNumero(produto, const [
        'estoque',
        'estoque_atual',
        'estoque_total_app',
        'estoque_total',
        'saldo',
        'quantidade',
      ]);
      final minimo = campoNumero(produto, const [
        'estoque_minimo',
        'estoqueMinimo',
        'estoque_min',
        'minimo',
        'qtd_minima',
        'quantidade_minima',
        'minimo_estoque',
      ]);
      final temMinimo = produtoTemEstoqueMinimo(produto);

      estoqueTotal += estoque;
      if (estoque <= 0) semEstoque++;
      if (estoque < 0) estoqueNegativo++;
      if (temMinimo) comMinimo++;

      final baixo = temMinimo ? estoque <= minimo : estoque <= 0;
      if (!baixo) continue;

      baixos.add({
        'produto': campoTexto(produto, const [
          'nome_produto',
          'descricao',
          'produto',
          'nome',
        ]),
        'ean': campoTexto(produto, const [
          'ean_principal',
          'ean',
          'codigo_barras',
          'codigo',
        ]),
        'estoque': estoque,
        'minimo': temMinimo ? minimo : null,
        'preco': campoNumero(produto, const [
          'preco_venda',
          'preco',
          'valor',
          'valor_venda',
        ]),
        'diferenca': temMinimo ? estoque - minimo : estoque,
      });
    }

    baixos.sort((a, b) {
      final difA = numeroDecimal(a['diferenca']);
      final difB = numeroDecimal(b['diferenca']);
      return difA.compareTo(difB);
    });

    metricas = {
      'Produtos Lidos': produtos.length.toString(),
      'Estoque Baixo': baixos.length.toString(),
      'Sem Estoque': semEstoque.toString(),
      'Estoque Negativo': estoqueNegativo.toString(),
      'Com Mínimo': comMinimo.toString(),
      'Fonte': usaProdutosSupabase ? 'Supabase' : 'API',
      'Estoque Total': numero(estoqueTotal),
    };

    registros = baixos.take(80).map((item) {
      final minimo = item['minimo'];

      return {
        'Produto': texto(item['produto']),
        'EAN': texto(item['ean']),
        'Estoque': numero(item['estoque']),
        'Mínimo': minimo == null ? '-' : numero(minimo),
        'Diferença': numero(item['diferenca']),
        'Preço': moeda(item['preco']),
        '_valor_grafico': math.max(0, -numeroDecimal(item['diferenca'])),
      };
    }).toList();
  }

  Future<void> carregarClientes() async {
    final clientes = await _buscarTabelaComData(
      tabela: 'clientes',
      select: 'id,user_id,nome,email,telefone,bairro,cidade,estado,criado_em',
      colunasData: const ['criado_em'],
      orderBy: 'criado_em',
    );

    final bairros = <String, int>{};
    final cidades = <String, int>{};
    int comTelefone = 0;
    int comEmail = 0;
    int comEndereco = 0;

    for (final cliente in clientes) {
      final bairro = texto(cliente['bairro']);
      final cidade = texto(cliente['cidade']);

      if (bairro != '-') {
        bairros[bairro] = (bairros[bairro] ?? 0) + 1;
      }

      if (cidade != '-') {
        cidades[cidade] = (cidades[cidade] ?? 0) + 1;
      }

      if (texto(cliente['telefone']) != '-') {
        comTelefone++;
      }

      if (texto(cliente['email']) != '-') {
        comEmail++;
      }

      if (bairro != '-' || cidade != '-') {
        comEndereco++;
      }
    }

    final bairroTop = bairros.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final cidadeTop = cidades.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    metricas = {
      'Clientes': clientes.length.toString(),
      'Com Telefone': comTelefone.toString(),
      'Com E-mail': comEmail.toString(),
      'Com Endereço': comEndereco.toString(),
      'Bairro Top': bairroTop.isEmpty ? '-' : bairroTop.first.key,
      'Cidade Top': cidadeTop.isEmpty ? '-' : cidadeTop.first.key,
    };

    registros = clientes.take(10).map((cliente) {
      return {
        'Cliente': texto(cliente['nome']),
        'Telefone': texto(cliente['telefone']),
        'E-mail': texto(cliente['email']),
        'Bairro': texto(cliente['bairro']),
        'Cidade': texto(cliente['cidade']),
        'Cadastro': dataHoraTela(cliente['criado_em']),
        '_valor_grafico': 1,
      };
    }).toList();
  }

  Map<String, String> headersLoja() {
    SessaoLoja.sincronizarSessaoAtual();
    final tokenLoja =
        SessaoLoja.lojaAccessToken?.trim() ??
        SessaoLoja.supabaseLoja?.auth.currentSession?.accessToken.trim() ??
        '';
    if (tokenLoja.isNotEmpty) {
      return {'Authorization': 'Bearer $tokenLoja'};
    }
    final tokenCentral =
        Supabase.instance.client.auth.currentSession?.accessToken.trim() ?? '';
    if (tokenCentral.isNotEmpty) {
      return {'Authorization': 'Bearer $tokenCentral'};
    }
    throw Exception('Token vazio. Saia e entre novamente.');
  }

  Future<void> carregarConsumoInterno() async {
    await SessaoLoja.renovarSessaoLojaSePossivel();

    final mercadoId = SessaoLoja.mercadoId;
    final resposta = await Supabase.instance.client.functions.invoke(
      'listar-consumo-interno',
      headers: headersLoja(),
      body: {
        'mercado_id': mercadoId,
        'data_inicio': dataSqlInicio(dataInicio),
        'data_fim': dataSqlFim(dataFim),
        'motivo': null,
      },
    );

    final data = resposta.data;
    if (data == null) throw Exception('Resposta vazia da Edge Function');
    if (data is Map && data['erro'] != null) {
      throw Exception(data['erro'].toString());
    }

    final lista = data['registros'];
    final consumo = lista is List
        ? List<Map<String, dynamic>>.from(lista)
        : <Map<String, dynamic>>[];

    double totalQtd = 0;
    for (final item in consumo) {
      totalQtd += double.tryParse(item['quantidade']?.toString() ?? '') ?? 0;
    }

    metricas = {
      'Registros': consumo.length.toString(),
      'Quantidade': numero(totalQtd),
      'Período': '${dataTela(dataInicio)} até ${dataTela(dataFim)}',
      'Tipo': 'Consumo interno',
      'Usuários': '-',
      'Motivos': '-',
    };

    registros = consumo.take(8).map((item) {
      return {
        'Data': dataHoraTela(item['criado_em']),
        'Faturamento': '-',
        'Pedidos': '-',
        'Clientes': texto(item['usuario_email']),
        'Ticket Médio': texto(item['motivo']),
        'Itens Vendidos': numero(item['quantidade']),
        '_valor_grafico':
            double.tryParse(item['quantidade']?.toString() ?? '') ?? 0,
      };
    }).toList();
  }

  void carregarEstruturaPronta(String mensagem) {
    aviso = mensagem;
    metricas = {
      'Faturamento Total': '-',
      'Pedidos': '-',
      'Ticket Médio': '-',
      'Clientes': '-',
      'Produtos Vendidos': '-',
      'Itens por Pedido': '-',
      'Cancelamentos': '-',
      'Frete Recebido': '-',
    };
    registros = [];
  }

  Future<void> exportarExcel() async {
    if (registros.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não há dados para exportar'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => exportando = true);
    try {
      final excel = ex.Excel.createExcel();
      final sheet = excel[relatorioAtual.titulo];
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      final colunas = registros.first.keys
          .where((key) => !key.startsWith('_'))
          .toList();
      sheet.appendRow(colunas.map((c) => ex.TextCellValue(c)).toList());
      for (final item in registros) {
        sheet.appendRow(
          colunas.map((c) => ex.TextCellValue(texto(item[c]))).toList(),
        );
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Não foi possível gerar o Excel.');
      final dir = await getTemporaryDirectory();
      final nomeArquivo =
          'relatorio_${relatorioSelecionado}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final arquivo = File('${dir.path}/$nomeArquivo');
      await arquivo.writeAsBytes(bytes);

      await SharePlus.instance.share(
        ShareParams(text: relatorioAtual.titulo, files: [XFile(arquivo.path)]),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao exportar Excel: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
    if (!mounted) return;
    setState(() => exportando = false);
  }

  _RelatorioOpcao get relatorioAtual => relatorios.firstWhere(
    (item) => item.id == relatorioSelecionado,
    orElse: () => relatorios.first,
  );

  Widget _cardContainer({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _topo() {
    final nomeLoja = SessaoLoja.mercadoNome ?? 'Loja';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [SessaoLoja.corPrimaria, SessaoLoja.corSecundaria],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            const SizedBox(width: 2),
            const Expanded(
              child: Text(
                'Relatórios',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.store_mall_directory_outlined,
                    color: azulEscuro,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 118),
                    child: Text(
                      nomeLoja,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: azulEscuro,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.keyboard_arrow_down, color: azulEscuro),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                onPressed: exportando || carregando ? null : exportarExcel,
                icon: exportando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.file_download_outlined,
                        color: Colors.white,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tituloBloco(String titulo, String subtitulo) {
    final textoSubtitulo = subtitulo.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: azulEscuro,
          ),
        ),
        if (textoSubtitulo.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            textoSubtitulo,
            style: TextStyle(
              color: azulEscuro.withValues(alpha: 0.58),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _secaoRelatorios() {
    return _cardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloBloco('Relatórios', ''),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              const espacamento = 8.0;
              final larguraItem = (constraints.maxWidth - espacamento) / 2;

              return Wrap(
                spacing: espacamento,
                runSpacing: espacamento,
                children: relatorios.map((item) {
                  final selecionado = item.id == relatorioSelecionado;
                  return SizedBox(
                    width: larguraItem,
                    child: _cardRelatorio(item, selecionado),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _cardRelatorio(_RelatorioOpcao item, bool selecionado) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: carregando
          ? null
          : () {
              setState(() {
                relatorioSelecionado = item.id;
              });
              carregarRelatorio();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          gradient: selecionado
              ? LinearGradient(
                  colors: [SessaoLoja.corPrimaria, SessaoLoja.corSecundaria],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selecionado ? null : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selecionado ? Colors.transparent : const Color(0xFFD8DFEC),
          ),
          boxShadow: selecionado
              ? [
                  BoxShadow(
                    color: azul.withValues(alpha: 0.14),
                    blurRadius: 7,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: selecionado
                    ? Colors.white.withValues(alpha: 0.16)
                    : azul.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                item.icone,
                color: selecionado ? Colors.white : azul,
                size: 17,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                item.titulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selecionado ? Colors.white : azulEscuro,
                  fontSize: 12.2,
                  fontWeight: FontWeight.w900,
                  height: 1.03,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secaoPeriodo() {
    return _cardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloBloco('Período de análise', ''),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _botaoPeriodo(
                  'Hoje',
                  'hoje',
                  Icons.calendar_today_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _botaoPeriodo('7 dias', '7_dias', null)),
              const SizedBox(width: 8),
              Expanded(child: _botaoPeriodo('30 dias', '30_dias', null)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _botaoPeriodo('Mês atual', 'mes_atual', null)),
              const SizedBox(width: 8),
              Expanded(
                child: _botaoPeriodo(
                  'Personalizado',
                  'personalizado',
                  Icons.calendar_month_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _botaoPeriodo(String label, String id, IconData? icone) {
    final selecionado = periodoSelecionado == id;
    return SizedBox(
      height: 40,
      child: OutlinedButton(
        onPressed: carregando
            ? null
            : () {
                if (id == 'personalizado') {
                  escolherPeriodoPersonalizado();
                } else {
                  aplicarPeriodo(id);
                }
              },
        style: OutlinedButton.styleFrom(
          foregroundColor: selecionado ? Colors.white : azulEscuro,
          backgroundColor: selecionado ? azul : Colors.white,
          side: BorderSide(color: selecionado ? azul : const Color(0xFFD8DFEC)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icone != null) ...[
              Icon(icone, size: 15),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resumoPeriodo() {
    final entradas = metricas.entries.toList();
    final principal = entradas.isEmpty
        ? const MapEntry('Faturamento Total', 'R\$ 0,00')
        : entradas.first;
    final pequenos = entradas.length > 1
        ? entradas.sublist(1)
        : <MapEntry<String, dynamic>>[];

    return _cardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _tituloBloco(
                  'Resumo do período',
                  '${dataTela(dataInicio)} até ${dataTela(dataFim)}',
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: azul.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'ATUALIZADO',
                  style: TextStyle(
                    color: azul,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _cardPrincipal(principal.key, texto(principal.value)),
          if (pequenos.isNotEmpty) const SizedBox(height: 5),
          LayoutBuilder(
            builder: (context, constraints) {
              final duasColunas = constraints.maxWidth >= 520;

              if (!duasColunas) {
                return Column(
                  children: pequenos
                      .asMap()
                      .entries
                      .map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: _cardMetricas(
                            entry.key,
                            entry.value.key,
                            texto(entry.value.value),
                          ),
                        ),
                      )
                      .toList(),
                );
              }

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: pequenos.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 6.6,
                ),
                itemBuilder: (_, index) {
                  final item = pequenos[index];
                  return _cardMetricas(index, item.key, texto(item.value));
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _cardPrincipal(String titulo, String valor) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [SessaoLoja.corPrimaria, SessaoLoja.corSecundaria],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.bar_chart_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 0,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                valor,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardMetricas(int index, String titulo, String valor) {
    const cores = [
      Color(0xFF5B8CFF),
      Color(0xFF8B5CF6),
      Color(0xFF16A34A),
      Color(0xFFF97316),
      Color(0xFF06B6D4),
      Color(0xFFEF4444),
      Color(0xFF0EA5E9),
    ];
    const icones = [
      Icons.shopping_bag_outlined,
      Icons.groups_outlined,
      Icons.receipt_long_outlined,
      Icons.inventory_2_outlined,
      Icons.local_shipping_outlined,
      Icons.sell_outlined,
      Icons.paid_outlined,
    ];
    final cor = cores[index % cores.length];
    final icone = icones[index % icones.length];

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE5F2)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icone, color: cor, size: 16),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: azulEscuro.withValues(alpha: 0.62),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 0,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                valor,
                maxLines: 1,
                style: TextStyle(
                  color: azulEscuro,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grafico() {
    final valores = registros
        .map((e) => double.tryParse(e['_valor_grafico']?.toString() ?? '') ?? 0)
        .where((v) => v > 0)
        .toList();
    final labels = registros
        .where(
          (e) =>
              (double.tryParse(e['_valor_grafico']?.toString() ?? '') ?? 0) > 0,
        )
        .map(
          (e) => campoTexto(e, const ['Data', 'Produto', 'Status', 'Cliente']),
        )
        .toList();

    return _cardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Faturamento diário',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: azulEscuro,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 280,
            child: valores.isEmpty
                ? Center(
                    child: Text(
                      'Sem dados para exibir no gráfico',
                      style: TextStyle(
                        color: azulEscuro.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : CustomPaint(
                    painter: _LinhaGraficoPainter(
                      valores: valores,
                      labels: labels,
                      cor: azul,
                    ),
                    child: const SizedBox.expand(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _detalhamento() {
    return _cardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Detalhamento',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: azulEscuro,
            ),
          ),
          const SizedBox(height: 18),
          if (registros.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Center(
                child: Text(
                  carregando
                      ? 'Carregando...'
                      : 'Nenhum dado encontrado neste período.',
                  style: TextStyle(
                    color: azulEscuro.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else
            _tabelaDetalhes(),
        ],
      ),
    );
  }

  Widget _tabelaDetalhes() {
    final colunas = registros.first.keys
        .where((key) => !key.startsWith('_'))
        .take(6)
        .toList();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE5F2)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          horizontalMargin: 16,
          columnSpacing: 18,
          dataRowMinHeight: 46,
          dataRowMaxHeight: 56,
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFE)),
          headingTextStyle: TextStyle(
            color: azulEscuro.withValues(alpha: 0.70),
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
          dataTextStyle: TextStyle(
            color: azulEscuro,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          columns: colunas.map((c) => DataColumn(label: Text(c))).toList(),
          rows: registros.take(8).map((item) {
            return DataRow(
              cells: colunas.map((c) {
                return DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(
                      texto(item[c]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              }).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _avisoErroOuInfo() {
    if (erro != null && erro!.trim().isNotEmpty) {
      return _cardContainer(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                erro!,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (aviso != null && aviso!.trim().isNotEmpty) {
      return _cardContainer(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: Colors.orange),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                aviso!,
                style: const TextStyle(
                  color: Color(0xFF7C4A03),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _conteudo() {
    return RefreshIndicator(
      onRefresh: carregarRelatorio,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 26),
        children: [
          _secaoRelatorios(),
          const SizedBox(height: 16),
          _secaoPeriodo(),
          if (erro != null || aviso != null) ...[
            const SizedBox(height: 16),
            _avisoErroOuInfo(),
          ] else ...[
            const SizedBox(height: 16),
            _resumoPeriodo(),
            const SizedBox(height: 16),
            _grafico(),
            const SizedBox(height: 16),
            _detalhamento(),
          ],
        ],
      ),
    );
  }

  Widget _acessoNegado() {
    return Scaffold(
      backgroundColor: fundo,
      body: Column(
        children: [
          _topo(),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _cardContainer(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 46, color: Colors.black38),
                      SizedBox(height: 12),
                      Text(
                        'Acesso não permitido',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: azulEscuro,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Seu usuário não tem permissão para acessar relatórios.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (verificandoPermissao) {
      return Scaffold(
        backgroundColor: fundo,
        body: Column(
          children: [
            _topo(),
            const Expanded(child: Center(child: CircularProgressIndicator())),
          ],
        ),
      );
    }

    if (!podeAcessarRelatorios()) {
      return _acessoNegado();
    }

    return Scaffold(
      backgroundColor: fundo,
      body: Column(
        children: [
          _topo(),
          Expanded(
            child: carregando && metricas.isEmpty && erro == null
                ? const Center(child: CircularProgressIndicator())
                : _conteudo(),
          ),
        ],
      ),
    );
  }
}

class _LinhaGraficoPainter extends CustomPainter {
  final List<double> valores;
  final List<String> labels;
  final Color cor;

  _LinhaGraficoPainter({
    required this.valores,
    required this.labels,
    required this.cor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (valores.isEmpty) return;

    final area = Rect.fromLTWH(46, 12, size.width - 58, size.height - 42);
    final gridPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    final eixoPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = area.top + (area.height / 4) * i;
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), gridPaint);
    }

    canvas.drawLine(
      Offset(area.left, area.bottom),
      Offset(area.right, area.bottom),
      eixoPaint,
    );

    final maxValor = valores.reduce(math.max);
    final intervalo = math.max(1.0, maxValor);

    final pontos = <Offset>[];
    for (int i = 0; i < valores.length; i++) {
      final x = valores.length == 1
          ? area.center.dx
          : area.left + (area.width / (valores.length - 1)) * i;
      final y = area.bottom - ((valores[i]) / intervalo) * area.height;
      pontos.add(Offset(x, y));
    }

    final path = Path()..moveTo(pontos.first.dx, pontos.first.dy);
    for (int i = 1; i < pontos.length; i++) {
      path.lineTo(pontos[i].dx, pontos[i].dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(pontos.last.dx, area.bottom)
      ..lineTo(pontos.first.dx, area.bottom)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [cor.withValues(alpha: 0.20), cor.withValues(alpha: 0.02)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(area);

    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = cor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    final pointPaint = Paint()..color = cor;
    final pointBorder = Paint()..color = Colors.white;
    for (final ponto in pontos) {
      canvas.drawCircle(ponto, 4.8, pointBorder);
      canvas.drawCircle(ponto, 3.2, pointPaint);
    }

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final labelIndices = <int>{0, valores.length - 1};
    if (valores.length > 4) {
      labelIndices.add((valores.length / 3).floor());
      labelIndices.add((valores.length * 2 / 3).floor());
    }

    for (final idx in labelIndices) {
      if (idx < 0 || idx >= labels.length || idx >= pontos.length) continue;
      textPainter.text = TextSpan(
        text: labels[idx],
        style: TextStyle(
          color: const Color(0xFF0B1B4D).withValues(alpha: 0.58),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      );
      textPainter.layout(maxWidth: 64);
      textPainter.paint(
        canvas,
        Offset(
          (pontos[idx].dx - textPainter.width / 2).clamp(
            area.left - 20,
            area.right - textPainter.width + 20,
          ),
          area.bottom + 10,
        ),
      );
    }

    for (int i = 0; i <= 4; i++) {
      final valor = maxValor - (maxValor / 4) * i;
      textPainter.text = TextSpan(
        text: valor <= 0
            ? 'R\$ 0'
            : 'R\$ ${(valor / 1000).toStringAsFixed(0)}k',
        style: TextStyle(
          color: const Color(0xFF0B1B4D).withValues(alpha: 0.58),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      );
      textPainter.layout(maxWidth: 42);
      final y = area.top + (area.height / 4) * i - textPainter.height / 2;
      textPainter.paint(canvas, Offset(0, y));
    }
  }

  @override
  bool shouldRepaint(covariant _LinhaGraficoPainter oldDelegate) {
    return oldDelegate.valores != valores ||
        oldDelegate.labels != labels ||
        oldDelegate.cor != cor;
  }
}

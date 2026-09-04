import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/central_service.dart';
import '../../services/etiqueta_balanca_service.dart';
import '../../services/monitor_pedidos_service.dart';
import '../../services/preferencias_interface_service.dart';
import '../../services/sessao_loja.dart';
import 'loja_horarios_page.dart';

class TelefoneBrasilInputFormatter extends TextInputFormatter {
  String somenteNumeros(String valor) {
    return valor.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String formatar(String valor) {
    var numeros = somenteNumeros(valor);

    if (numeros.length > 11) {
      numeros = numeros.substring(0, 11);
    }

    if (numeros.isEmpty) {
      return '';
    }

    if (numeros.length <= 2) {
      return '($numeros';
    }

    final ddd = numeros.substring(0, 2);
    final restante = numeros.substring(2);

    if (restante.length <= 4) {
      return '($ddd) $restante';
    }

    if (numeros.length <= 10) {
      final parte1 = restante.substring(0, 4);
      final parte2 = restante.substring(4);

      return '($ddd) $parte1-$parte2';
    }

    final parte1 = restante.substring(0, 5);
    final parte2 = restante.substring(5);

    return '($ddd) $parte1-$parte2';
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatado = formatar(newValue.text);

    return TextEditingValue(
      text: formatado,
      selection: TextSelection.collapsed(offset: formatado.length),
    );
  }
}

class LojaConfiguracoesPage extends StatefulWidget {
  const LojaConfiguracoesPage({super.key});

  @override
  State<LojaConfiguracoesPage> createState() => _LojaConfiguracoesPageState();
}

class _LojaConfiguracoesPageState extends State<LojaConfiguracoesPage> {
  final nomeController = TextEditingController();
  final whatsappController = TextEditingController();
  final pedidoMinimoController = TextEditingController();
  final taxaEntregaController = TextEditingController();
  final freteGratisController = TextEditingController();
  final mensagemFechadoController = TextEditingController();
  final instagramController = TextEditingController();
  final facebookController = TextEditingController();
  final logoUrlController = TextEditingController();
  final adminLogoUrlController = TextEditingController();
  final adminCorPrimariaController = TextEditingController();
  final adminCorSecundariaController = TextEditingController();
  final adminCorFundoController = TextEditingController();
  final clienteCorPrimariaController = TextEditingController();
  final clienteCorSecundariaController = TextEditingController();
  final clienteCorFundoController = TextEditingController();

  final cepLojaController = TextEditingController();
  final enderecoLojaController = TextEditingController();
  final numeroLojaController = TextEditingController();
  final bairroLojaController = TextEditingController();
  final cidadeLojaController = TextEditingController();
  final estadoLojaController = TextEditingController();
  final referenciaLojaController = TextEditingController();

  final fretePorKmController = TextEditingController();
  final freteKmMaximoController = TextEditingController();
  final mensagemForaAreaEntregaController = TextEditingController();
  final limiteAlertaEstoqueBaixoController = TextEditingController(text: '5');
  final meioPagamentoController = TextEditingController();
  final etiquetaBalancaPrefixoController = TextEditingController(text: '2');
  final etiquetaBalancaTamanhoCodigoController = TextEditingController(
    text: '6',
  );
  final etiquetaBalancaTamanhoValorController = TextEditingController(
    text: '5',
  );
  final etiquetaBalancaCasasDecimaisController = TextEditingController(
    text: '2',
  );
  final etiquetaBalancaTesteController = TextEditingController();

  final TelefoneBrasilInputFormatter telefoneFormatter =
      TelefoneBrasilInputFormatter();
  final ImagePicker imagePicker = ImagePicker();
  final CentralService centralService = CentralService();

  bool carregando = true;
  bool salvando = false;
  bool enviandoLogo = false;
  bool buscandoLocalizacaoLoja = false;
  bool exibirEstoque = true;
  bool exibirProdutosSemEstoque = true;
  bool bloquearVendaSemEstoque = true;
  bool alertarEstoqueBaixoCarrinho = false;
  bool exibirBotaoFinalizarCompra = false;
  bool bloquearCarrinhoLojaFechada = true;
  bool cobrarFrete = true;
  bool bloquearEntregaForaRaio = true;
  bool permitirConferenciaManualItens = true;
  bool etiquetaBalancaHabilitada = false;
  bool etiquetaBalancaValidarDv = true;
  String etiquetaBalancaTipoValor = 'PRECO';
  String testeEtiquetaBalancaResultado = '';
  bool testeEtiquetaBalancaOk = false;
  String prioridadeEntrega = 'endereco_cadastrado';
  LayoutConsultaItem layoutConsultaItem = LayoutConsultaItem.compacto;

  List<String> meiosPagamento = const ['Pix', 'Dinheiro', 'Cartão na entrega'];

  double? latitudeLoja;
  double? longitudeLoja;
  String enderecoLocalizacaoAtualKey = '';

  String? idConfiguracao;

  static Color get vermelho => SessaoLoja.corPrimaria;
  static Color get vermelhoEscuro => SessaoLoja.corSecundaria;
  static Color get fundo => SessaoLoja.corFundo;
  static const Color textoPrincipal = Color(0xFF111827);
  static const List<Map<String, String>> paletasCores = [
    {
      'nome': 'Vermelho',
      'primaria': '#E30613',
      'secundaria': '#B8000D',
      'fundo': '#FFF7F7',
    },
    {
      'nome': 'Verde mercado',
      'primaria': '#07883D',
      'secundaria': '#05652F',
      'fundo': '#F0FFF6',
    },
    {
      'nome': 'Azul noite',
      'primaria': '#1D4ED8',
      'secundaria': '#1E3A8A',
      'fundo': '#EFF6FF',
    },
    {
      'nome': 'Azul claro',
      'primaria': '#0284C7',
      'secundaria': '#0369A1',
      'fundo': '#F0F9FF',
    },
    {
      'nome': 'Turquesa',
      'primaria': '#0F766E',
      'secundaria': '#115E59',
      'fundo': '#F0FDFA',
    },
    {
      'nome': 'Esmeralda',
      'primaria': '#059669',
      'secundaria': '#047857',
      'fundo': '#ECFDF5',
    },
    {
      'nome': 'Laranja',
      'primaria': '#EA580C',
      'secundaria': '#C2410C',
      'fundo': '#FFF7ED',
    },
    {
      'nome': 'Âmbar',
      'primaria': '#D97706',
      'secundaria': '#B45309',
      'fundo': '#FFFBEB',
    },
    {
      'nome': 'Roxo',
      'primaria': '#7C3AED',
      'secundaria': '#5B21B6',
      'fundo': '#F5F3FF',
    },
    {
      'nome': 'Violeta',
      'primaria': '#6D28D9',
      'secundaria': '#4C1D95',
      'fundo': '#F5F3FF',
    },
    {
      'nome': 'Rosa',
      'primaria': '#DB2777',
      'secundaria': '#BE185D',
      'fundo': '#FDF2F8',
    },
    {
      'nome': 'Pink',
      'primaria': '#E11D48',
      'secundaria': '#BE123C',
      'fundo': '#FFF1F2',
    },
    {
      'nome': 'Índigo',
      'primaria': '#4338CA',
      'secundaria': '#3730A3',
      'fundo': '#EEF2FF',
    },
    {
      'nome': 'Grafite',
      'primaria': '#374151',
      'secundaria': '#111827',
      'fundo': '#F3F4F6',
    },
    {
      'nome': 'Preto premium',
      'primaria': '#111827',
      'secundaria': '#030712',
      'fundo': '#F9FAFB',
    },
    {
      'nome': 'Marinho',
      'primaria': '#0F172A',
      'secundaria': '#020617',
      'fundo': '#F8FAFC',
    },
    {
      'nome': 'Ciano',
      'primaria': '#0891B2',
      'secundaria': '#0E7490',
      'fundo': '#ECFEFF',
    },
    {
      'nome': 'Lima',
      'primaria': '#65A30D',
      'secundaria': '#4D7C0F',
      'fundo': '#F7FEE7',
    },
    {
      'nome': 'Chocolate',
      'primaria': '#92400E',
      'secundaria': '#78350F',
      'fundo': '#FFFBEB',
    },
    {
      'nome': 'Vinho',
      'primaria': '#9F1239',
      'secundaria': '#881337',
      'fundo': '#FFF1F2',
    },
    {
      'nome': 'Safira',
      'primaria': '#2563EB',
      'secundaria': '#1D4ED8',
      'fundo': '#F8FAFC',
    },
    {
      'nome': 'Hortelã',
      'primaria': '#10B981',
      'secundaria': '#059669',
      'fundo': '#F0FDF4',
    },
    {
      'nome': 'Coral',
      'primaria': '#F97316',
      'secundaria': '#EA580C',
      'fundo': '#FFF7ED',
    },
    {
      'nome': 'Uva',
      'primaria': '#9333EA',
      'secundaria': '#7E22CE',
      'fundo': '#FAF5FF',
    },
  ];

  static const List<Map<String, String>> coresDisponiveis = [
    {'nome': 'Vermelho', 'hex': '#E30613'},
    {'nome': 'Vermelho escuro', 'hex': '#B8000D'},
    {'nome': 'Rubi', 'hex': '#DC2626'},
    {'nome': 'Vinho', 'hex': '#9F1239'},
    {'nome': 'Rose', 'hex': '#E11D48'},
    {'nome': 'Pink', 'hex': '#DB2777'},
    {'nome': 'Magenta', 'hex': '#C026D3'},
    {'nome': 'Roxo', 'hex': '#7C3AED'},
    {'nome': 'Uva', 'hex': '#9333EA'},
    {'nome': 'Violeta', 'hex': '#6D28D9'},
    {'nome': 'Indigo', 'hex': '#4338CA'},
    {'nome': 'Azul royal', 'hex': '#2563EB'},
    {'nome': 'Azul noite', 'hex': '#1D4ED8'},
    {'nome': 'Azul marinho', 'hex': '#0F172A'},
    {'nome': 'Azul claro', 'hex': '#0284C7'},
    {'nome': 'Ciano', 'hex': '#0891B2'},
    {'nome': 'Turquesa', 'hex': '#0F766E'},
    {'nome': 'Verde agua', 'hex': '#14B8A6'},
    {'nome': 'Esmeralda', 'hex': '#059669'},
    {'nome': 'Verde mercado', 'hex': '#07883D'},
    {'nome': 'Verde folha', 'hex': '#16A34A'},
    {'nome': 'Lima', 'hex': '#65A30D'},
    {'nome': 'Oliva', 'hex': '#4D7C0F'},
    {'nome': 'Amarelo', 'hex': '#EAB308'},
    {'nome': 'Ouro', 'hex': '#D97706'},
    {'nome': 'Ambar', 'hex': '#F59E0B'},
    {'nome': 'Laranja', 'hex': '#EA580C'},
    {'nome': 'Coral', 'hex': '#F97316'},
    {'nome': 'Terracota', 'hex': '#C2410C'},
    {'nome': 'Chocolate', 'hex': '#92400E'},
    {'nome': 'Cafe', 'hex': '#78350F'},
    {'nome': 'Grafite', 'hex': '#374151'},
    {'nome': 'Chumbo', 'hex': '#1F2937'},
    {'nome': 'Preto premium', 'hex': '#111827'},
    {'nome': 'Preto', 'hex': '#030712'},
    {'nome': 'Cinza', 'hex': '#6B7280'},
    {'nome': 'Cinza claro', 'hex': '#D1D5DB'},
    {'nome': 'Branco', 'hex': '#FFFFFF'},
    {'nome': 'Fundo vermelho', 'hex': '#FFF7F7'},
    {'nome': 'Fundo rose', 'hex': '#FFF1F2'},
    {'nome': 'Fundo rosa', 'hex': '#FDF2F8'},
    {'nome': 'Fundo roxo', 'hex': '#F5F3FF'},
    {'nome': 'Fundo indigo', 'hex': '#EEF2FF'},
    {'nome': 'Fundo azul', 'hex': '#EFF6FF'},
    {'nome': 'Fundo ceu', 'hex': '#F0F9FF'},
    {'nome': 'Fundo ciano', 'hex': '#ECFEFF'},
    {'nome': 'Fundo verde agua', 'hex': '#F0FDFA'},
    {'nome': 'Fundo verde', 'hex': '#ECFDF5'},
    {'nome': 'Fundo lima', 'hex': '#F7FEE7'},
    {'nome': 'Fundo amarelo', 'hex': '#FEFCE8'},
    {'nome': 'Fundo ambar', 'hex': '#FFFBEB'},
    {'nome': 'Fundo laranja', 'hex': '#FFF7ED'},
    {'nome': 'Fundo cinza', 'hex': '#F3F4F6'},
    {'nome': 'Fundo gelo', 'hex': '#F8FAFC'},
    {'nome': 'Fundo branco', 'hex': '#FFFFFF'},
  ];

  @override
  void initState() {
    super.initState();
    iniciarMonitorPedidos();
    carregarConfiguracoes();
    carregarLayoutConsultaItem();
  }

  Future<void> carregarLayoutConsultaItem() async {
    final layout =
        await PreferenciasInterfaceService.carregarLayoutConsultaItem();

    if (!mounted) return;

    setState(() {
      layoutConsultaItem = layout;
    });
  }

  Future<void> alterarLayoutConsultaItem(LayoutConsultaItem layout) async {
    final layoutAnterior = layoutConsultaItem;

    setState(() {
      layoutConsultaItem = layout;
    });

    try {
      await PreferenciasInterfaceService.salvarLayoutConsultaItem(layout);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        layoutConsultaItem = layoutAnterior;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível salvar o layout da consulta.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> iniciarMonitorPedidos() async {
    try {
      await MonitorPedidosService.instance.iniciar(
        onNovoPedido: () async {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Novo pedido recebido'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 5),
            ),
          );
        },
      );
    } catch (_) {
      // Não trava a tela de configurações caso o monitor não consiga iniciar.
    }
  }

  @override
  void dispose() {
    nomeController.dispose();
    whatsappController.dispose();
    pedidoMinimoController.dispose();
    taxaEntregaController.dispose();
    freteGratisController.dispose();
    mensagemFechadoController.dispose();
    instagramController.dispose();
    facebookController.dispose();
    logoUrlController.dispose();
    adminLogoUrlController.dispose();
    adminCorPrimariaController.dispose();
    adminCorSecundariaController.dispose();
    adminCorFundoController.dispose();
    clienteCorPrimariaController.dispose();
    clienteCorSecundariaController.dispose();
    clienteCorFundoController.dispose();
    cepLojaController.dispose();
    enderecoLojaController.dispose();
    numeroLojaController.dispose();
    bairroLojaController.dispose();
    cidadeLojaController.dispose();
    estadoLojaController.dispose();
    referenciaLojaController.dispose();
    fretePorKmController.dispose();
    freteKmMaximoController.dispose();
    mensagemForaAreaEntregaController.dispose();
    limiteAlertaEstoqueBaixoController.dispose();
    meioPagamentoController.dispose();
    etiquetaBalancaPrefixoController.dispose();
    etiquetaBalancaTamanhoCodigoController.dispose();
    etiquetaBalancaTamanhoValorController.dispose();
    etiquetaBalancaCasasDecimaisController.dispose();
    etiquetaBalancaTesteController.dispose();
    super.dispose();
  }

  String somenteNumeros(String valor) {
    return valor.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String formatarTelefone(String valor) {
    return telefoneFormatter.formatar(valor);
  }

  double converterValor(String texto) {
    final valor = texto
        .replaceAll(r'R$', '')
        .replaceAll(' ', '')
        .replaceAll('.', '')
        .replaceAll(',', '.')
        .trim();

    return double.tryParse(valor) ?? 0;
  }

  String textoValor(dynamic valor) {
    final numero = double.tryParse((valor ?? 0).toString()) ?? 0;
    return numero.toStringAsFixed(2).replaceAll('.', ',');
  }

  String textoQuantidade(dynamic valor, {double fallback = 5}) {
    final numero = double.tryParse((valor ?? fallback).toString()) ?? fallback;

    if ((numero - numero.roundToDouble()).abs() < 0.0001) {
      return numero.round().toString();
    }

    var texto = numero.toStringAsFixed(3).replaceAll('.', ',');

    while (texto.endsWith('0')) {
      texto = texto.substring(0, texto.length - 1);
    }

    return texto.endsWith(',') ? texto.substring(0, texto.length - 1) : texto;
  }

  double? converterDecimalOpcional(String texto) {
    final valor = texto.replaceAll(',', '.').trim();

    if (valor.isEmpty) {
      return null;
    }

    return double.tryParse(valor);
  }

  double? valorDoubleOpcional(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor.toString().replaceAll(',', '.').trim());
  }

  bool get lojaTemLocalizacao {
    return latitudeLoja != null && longitudeLoja != null;
  }

  String chaveEnderecoLocalizacao() {
    return enderecoLojaParaBusca().trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
  }

  bool get enderecoMudouDepoisDaLocalizacao {
    if (!lojaTemLocalizacao) {
      return false;
    }

    final atual = chaveEnderecoLocalizacao();

    return atual.isNotEmpty && atual != enderecoLocalizacaoAtualKey;
  }

  bool get precisaRecalcularLocalizacaoLoja {
    return precisaLocalizacaoParaFrete &&
        (!lojaTemLocalizacao || enderecoMudouDepoisDaLocalizacao);
  }

  bool get precisaLocalizacaoParaFrete {
    final fretePorKm = converterValor(fretePorKmController.text);
    final kmMaximo = converterValor(freteKmMaximoController.text);

    return cobrarFrete && (fretePorKm > 0 || kmMaximo > 0);
  }

  String enderecoLojaParaBusca() {
    final partes = [
      enderecoLojaController.text.trim(),
      numeroLojaController.text.trim(),
      bairroLojaController.text.trim(),
      cidadeLojaController.text.trim(),
      estadoLojaController.text.trim().toUpperCase(),
      cepLojaController.text.trim(),
    ].where((item) => item.isNotEmpty).toList();

    if (partes.isEmpty) {
      return '';
    }

    return '${partes.join(', ')}, Brasil';
  }

  String textoStatusLocalizacaoLoja() {
    if (enderecoMudouDepoisDaLocalizacao) {
      return 'Endereço alterado: localização precisa ser recalculada';
    }

    if (lojaTemLocalizacao) {
      return 'Localização da loja cadastrada';
    }

    if (enderecoLojaParaBusca().isNotEmpty) {
      return 'Endereço informado, localização ainda não buscada';
    }

    return 'Localização da loja ainda não definida';
  }

  String montarEnderecoLojaFormatado() {
    final linha1 = [
      enderecoLojaController.text.trim(),
      numeroLojaController.text.trim(),
    ].where((item) => item.isNotEmpty).join(', ');

    final linha2 = [
      bairroLojaController.text.trim(),
      cidadeLojaController.text.trim(),
      estadoLojaController.text.trim().toUpperCase(),
    ].where((item) => item.isNotEmpty).join(' - ');

    final partes = [
      linha1,
      linha2,
      referenciaLojaController.text.trim(),
      cepLojaController.text.trim(),
    ].where((item) => item.isNotEmpty).toList();

    return partes.join(' | ');
  }

  bool valorBool(dynamic valor, bool padrao) {
    if (valor is bool) return valor;

    if (valor is num) {
      return valor == 1;
    }

    if (valor is String) {
      final texto = valor.trim().toLowerCase();

      if (texto == 'true' || texto == '1' || texto == 'sim') {
        return true;
      }

      if (texto == 'false' ||
          texto == '0' ||
          texto == 'nao' ||
          texto == 'não') {
        return false;
      }
    }

    return padrao;
  }

  List<String> normalizarMeiosPagamento(dynamic valor) {
    Iterable<dynamic> itens = const [];

    if (valor is List) {
      itens = valor;
    } else if (valor is String && valor.trim().isNotEmpty) {
      itens = valor.split(',');
    }

    final nomes = <String>[];
    final nomesNormalizados = <String>{};

    for (final item in itens) {
      final nome = item.toString().trim();
      final chave = nome.toLowerCase();

      if (nome.isEmpty || nomesNormalizados.contains(chave)) continue;

      nomes.add(nome);
      nomesNormalizados.add(chave);
    }

    return nomes.isEmpty ? ['Pix', 'Dinheiro', 'Cartão na entrega'] : nomes;
  }

  String normalizarPrioridadeEntrega(dynamic valor) {
    const opcoesValidas = {
      'endereco_cadastrado',
      'localizacao_atual',
      'retirada_loja',
      'outro_endereco',
    };
    final prioridade = valor?.toString().trim().toLowerCase() ?? '';

    return opcoesValidas.contains(prioridade)
        ? prioridade
        : 'endereco_cadastrado';
  }

  void adicionarMeioPagamento() {
    final nome = meioPagamentoController.text.trim();

    if (nome.isEmpty) return;

    final jaExiste = meiosPagamento.any(
      (item) => item.toLowerCase() == nome.toLowerCase(),
    );

    if (jaExiste) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esse meio de pagamento já foi adicionado.'),
        ),
      );
      return;
    }

    setState(() {
      meiosPagamento = [...meiosPagamento, nome];
      meioPagamentoController.clear();
    });
  }

  String primeiroTexto(List<dynamic> valores, {String fallback = ''}) {
    for (final valor in valores) {
      final texto = valor?.toString().trim() ?? '';

      if (texto.isNotEmpty && texto.toLowerCase() != 'null') {
        return texto;
      }
    }

    return fallback;
  }

  String normalizarCorHex(String? valor, String fallback) {
    final texto = valor?.trim() ?? '';
    final hexadecimal = texto.startsWith('#') ? texto.substring(1) : texto;

    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hexadecimal)) {
      return '#${hexadecimal.toUpperCase()}';
    }

    return fallback;
  }

  Color corHexParaColor(String valor, Color fallback) {
    final normalizada = normalizarCorHex(valor, '');

    if (normalizada.isEmpty) {
      return fallback;
    }

    final numero = int.tryParse(normalizada.substring(1), radix: 16);

    if (numero == null) {
      return fallback;
    }

    return Color(0xFF000000 | numero);
  }

  bool corHexValida(String valor) {
    final texto = valor.trim();

    if (texto.isEmpty) {
      return false;
    }

    final hexadecimal = texto.startsWith('#') ? texto.substring(1) : texto;
    return RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hexadecimal);
  }

  bool urlHttpValida(String valor) {
    final texto = valor.trim();

    if (texto.isEmpty) {
      return true;
    }

    final uri = Uri.tryParse(texto);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  bool urlPerfilValida(String valor, List<String> dominios) {
    final texto = valor.trim();

    if (texto.isEmpty) {
      return true;
    }

    final uri = Uri.tryParse(texto);

    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      return false;
    }

    final host = uri.host.toLowerCase();
    return dominios.any(
      (dominio) => host == dominio || host.endsWith('.$dominio'),
    );
  }

  void preencherTela(Map<String, dynamic> dados) {
    idConfiguracao = dados['id']?.toString();

    nomeController.text = dados['nome_loja']?.toString() ?? '';
    whatsappController.text = formatarTelefone(
      dados['whatsapp']?.toString() ?? '',
    );
    instagramController.text = dados['instagram']?.toString() ?? '';
    facebookController.text = dados['facebook']?.toString() ?? '';
    logoUrlController.text = primeiroTexto([dados['logo_url']]);
    adminLogoUrlController.text = primeiroTexto([
      dados['admin_logo_url'],
      dados['logo_admin_url'],
    ]);
    adminCorPrimariaController.text = normalizarCorHex(
      dados['admin_cor_primaria']?.toString(),
      SessaoLoja.corPrimariaHex,
    );
    adminCorSecundariaController.text = normalizarCorHex(
      dados['admin_cor_secundaria']?.toString(),
      SessaoLoja.corSecundariaHex,
    );
    adminCorFundoController.text = normalizarCorHex(
      dados['admin_cor_fundo']?.toString(),
      SessaoLoja.corFundoHex,
    );
    clienteCorPrimariaController.text = normalizarCorHex(
      dados['cliente_cor_primaria']?.toString(),
      '#E30613',
    );
    clienteCorSecundariaController.text = normalizarCorHex(
      dados['cliente_cor_secundaria']?.toString(),
      '#C90010',
    );
    clienteCorFundoController.text = normalizarCorHex(
      dados['cliente_cor_fundo']?.toString(),
      '#FFF7F7',
    );

    cepLojaController.text = dados['cep_loja']?.toString() ?? '';
    enderecoLojaController.text = dados['endereco_loja']?.toString() ?? '';
    numeroLojaController.text = dados['numero_loja']?.toString() ?? '';
    bairroLojaController.text = dados['bairro_loja']?.toString() ?? '';
    cidadeLojaController.text = dados['cidade_loja']?.toString() ?? '';
    estadoLojaController.text = dados['estado_loja']?.toString() ?? '';
    referenciaLojaController.text = dados['referencia_loja']?.toString() ?? '';

    pedidoMinimoController.text = textoValor(dados['pedido_minimo']);
    taxaEntregaController.text = textoValor(
      dados['frete_taxa_base'] ?? dados['taxa_entrega'],
    );
    freteGratisController.text = textoValor(
      dados['frete_gratis_acima'] ?? dados['valor_frete_gratis'],
    );
    fretePorKmController.text = textoValor(dados['frete_por_km']);
    freteKmMaximoController.text = textoValor(dados['frete_km_maximo']);

    latitudeLoja = valorDoubleOpcional(dados['latitude_loja']);
    longitudeLoja = valorDoubleOpcional(dados['longitude_loja']);
    enderecoLocalizacaoAtualKey = chaveEnderecoLocalizacao();

    mensagemFechadoController.text =
        dados['mensagem_fechado']?.toString() ?? '';

    mensagemForaAreaEntregaController.text =
        dados['mensagem_fora_area_entrega']?.toString() ??
        'Endereço fora da área de entrega.';

    exibirEstoque = valorBool(dados['exibir_estoque'], true);
    exibirProdutosSemEstoque = valorBool(
      dados['exibir_produtos_sem_estoque'],
      true,
    );
    bloquearVendaSemEstoque = valorBool(
      dados['bloquear_venda_sem_estoque'],
      true,
    );
    alertarEstoqueBaixoCarrinho = valorBool(
      dados['alertar_estoque_baixo_carrinho'],
      false,
    );
    exibirBotaoFinalizarCompra = valorBool(
      dados['exibir_botao_finalizar_compra'],
      false,
    );
    limiteAlertaEstoqueBaixoController.text = textoQuantidade(
      dados['limite_alerta_estoque_baixo_carrinho'],
    );
    bloquearCarrinhoLojaFechada = valorBool(
      dados['bloquear_carrinho_loja_fechada'],
      true,
    );
    cobrarFrete = valorBool(dados['cobrar_frete'], true);
    bloquearEntregaForaRaio = valorBool(
      dados['bloquear_entrega_fora_raio'],
      true,
    );
    permitirConferenciaManualItens = valorBool(
      dados['permitir_conferencia_manual_itens'],
      true,
    );
    etiquetaBalancaHabilitada = valorBool(
      dados['etiqueta_balanca_habilitada'],
      false,
    );
    etiquetaBalancaPrefixoController.text =
        dados['etiqueta_balanca_prefixo']?.toString().trim().isNotEmpty == true
        ? dados['etiqueta_balanca_prefixo'].toString().trim()
        : '2';
    etiquetaBalancaTipoValor =
        dados['etiqueta_balanca_tipo_valor']?.toString().trim().toUpperCase() ==
            'PESO'
        ? 'PESO'
        : 'PRECO';
    etiquetaBalancaTamanhoCodigoController.text =
        (int.tryParse(
                  dados['etiqueta_balanca_tamanho_codigo']?.toString() ?? '',
                ) ??
                6)
            .toString();
    etiquetaBalancaTamanhoValorController.text =
        (int.tryParse(
                  dados['etiqueta_balanca_tamanho_valor']?.toString() ?? '',
                ) ??
                5)
            .toString();
    etiquetaBalancaCasasDecimaisController.text =
        (int.tryParse(
                  dados['etiqueta_balanca_casas_decimais']?.toString() ?? '',
                ) ??
                (etiquetaBalancaTipoValor == 'PESO' ? 3 : 2))
            .toString();
    etiquetaBalancaValidarDv = valorBool(
      dados['etiqueta_balanca_validar_dv'],
      true,
    );
    testeEtiquetaBalancaResultado = '';
    prioridadeEntrega = normalizarPrioridadeEntrega(
      dados['prioridade_entrega'],
    );
    meiosPagamento = normalizarMeiosPagamento(dados['meios_pagamento']);
  }

  Map<String, dynamic> montarDadosConfiguracao() {
    final taxaBase = cobrarFrete
        ? converterValor(taxaEntregaController.text)
        : 0.0;
    final freteGratis = cobrarFrete
        ? converterValor(freteGratisController.text)
        : 0.0;

    return {
      'nome_loja': nomeController.text.trim(),
      'whatsapp': whatsappController.text.trim(),
      'instagram': instagramController.text.trim(),
      'facebook': facebookController.text.trim(),
      'logo_url': logoUrlController.text.trim(),
      'admin_logo_url': adminLogoUrlController.text.trim(),
      'admin_cor_primaria': normalizarCorHex(
        adminCorPrimariaController.text,
        '#E30613',
      ),
      'admin_cor_secundaria': normalizarCorHex(
        adminCorSecundariaController.text,
        '#B8000D',
      ),
      'admin_cor_fundo': normalizarCorHex(
        adminCorFundoController.text,
        '#F5F7FA',
      ),
      'cliente_cor_primaria': normalizarCorHex(
        clienteCorPrimariaController.text,
        '#E30613',
      ),
      'cliente_cor_secundaria': normalizarCorHex(
        clienteCorSecundariaController.text,
        '#C90010',
      ),
      'cliente_cor_fundo': normalizarCorHex(
        clienteCorFundoController.text,
        '#FFF7F7',
      ),

      // Endereço da loja exibido/organizado.
      'cep_loja': cepLojaController.text.trim(),
      'endereco_loja': enderecoLojaController.text.trim(),
      'numero_loja': numeroLojaController.text.trim(),
      'bairro_loja': bairroLojaController.text.trim(),
      'cidade_loja': cidadeLojaController.text.trim(),
      'estado_loja': estadoLojaController.text.trim().toUpperCase(),
      'referencia_loja': referenciaLojaController.text.trim(),
      'endereco_loja_formatado': montarEnderecoLojaFormatado(),

      'pedido_minimo': converterValor(pedidoMinimoController.text),
      'cobrar_frete': cobrarFrete,

      // Campos antigos mantidos por compatibilidade.
      'taxa_entrega': taxaBase,
      'valor_frete_gratis': freteGratis,

      // Frete por KM.
      // Latitude/longitude ficam escondidas na tela e são preenchidas pelo botão
      // "Usar localização atual da loja".
      'latitude_loja': latitudeLoja,
      'longitude_loja': longitudeLoja,
      'frete_taxa_base': taxaBase,
      'frete_por_km': cobrarFrete
          ? converterValor(fretePorKmController.text)
          : 0,
      'frete_km_maximo': cobrarFrete
          ? converterValor(freteKmMaximoController.text)
          : 0,
      'frete_gratis_acima': freteGratis,
      'bloquear_entrega_fora_raio': bloquearEntregaForaRaio,
      'mensagem_fora_area_entrega':
          mensagemForaAreaEntregaController.text.trim().isEmpty
          ? 'Endereço fora da área de entrega.'
          : mensagemForaAreaEntregaController.text.trim(),

      'mensagem_fechado': mensagemFechadoController.text.trim(),
      'exibir_estoque': exibirEstoque,
      'exibir_produtos_sem_estoque': exibirProdutosSemEstoque,
      'bloquear_venda_sem_estoque': bloquearVendaSemEstoque,
      'alertar_estoque_baixo_carrinho': alertarEstoqueBaixoCarrinho,
      'exibir_botao_finalizar_compra': exibirBotaoFinalizarCompra,
      'limite_alerta_estoque_baixo_carrinho':
          converterDecimalOpcional(limiteAlertaEstoqueBaixoController.text) ??
          5,
      'bloquear_carrinho_loja_fechada': bloquearCarrinhoLojaFechada,
      'permitir_conferencia_manual_itens': permitirConferenciaManualItens,
      'etiqueta_balanca_habilitada': etiquetaBalancaHabilitada,
      'etiqueta_balanca_prefixo': etiquetaBalancaPrefixoController.text.trim(),
      'etiqueta_balanca_tipo_valor': etiquetaBalancaTipoValor,
      'etiqueta_balanca_tamanho_codigo':
          int.tryParse(etiquetaBalancaTamanhoCodigoController.text.trim()) ?? 6,
      'etiqueta_balanca_tamanho_valor':
          int.tryParse(etiquetaBalancaTamanhoValorController.text.trim()) ?? 5,
      'etiqueta_balanca_casas_decimais':
          int.tryParse(etiquetaBalancaCasasDecimaisController.text.trim()) ??
          (etiquetaBalancaTipoValor == 'PESO' ? 3 : 2),
      'etiqueta_balanca_validar_dv': etiquetaBalancaValidarDv,
      'prioridade_entrega': prioridadeEntrega,
      'meios_pagamento': meiosPagamento,
      'atualizado_em': DateTime.now().toIso8601String(),
    };
  }

  String? validarCampos({bool validarLocalizacao = true}) {
    final nome = nomeController.text.trim();
    final whatsappNumeros = somenteNumeros(whatsappController.text);

    if (nome.isEmpty) {
      return 'Informe o nome da loja.';
    }

    if (whatsappNumeros.isNotEmpty &&
        whatsappNumeros.length != 10 &&
        whatsappNumeros.length != 11) {
      return 'Informe um WhatsApp válido com DDD. Ex: (77) 98126-7706';
    }

    if (!urlPerfilValida(instagramController.text, ['instagram.com'])) {
      return 'Informe a URL completa do perfil do Instagram. Ex: https://instagram.com/sualoja';
    }

    if (!urlPerfilValida(facebookController.text, ['facebook.com', 'fb.com'])) {
      return 'Informe a URL completa do perfil do Facebook. Ex: https://facebook.com/sualoja';
    }

    if (!urlHttpValida(logoUrlController.text)) {
      return 'Informe uma URL válida para a logo do app Mercado.';
    }

    if (!urlHttpValida(adminLogoUrlController.text)) {
      return 'Informe uma URL válida para a logo do app Admin.';
    }

    final cores = {
      'cor principal do app Admin': adminCorPrimariaController.text,
      'cor secundária do app Admin': adminCorSecundariaController.text,
      'cor de fundo do app Admin': adminCorFundoController.text,
      'cor principal do app Mercado': clienteCorPrimariaController.text,
      'cor secundária do app Mercado': clienteCorSecundariaController.text,
      'cor de fundo do app Mercado': clienteCorFundoController.text,
    };

    for (final entrada in cores.entries) {
      if (!corHexValida(entrada.value)) {
        return 'Informe a ${entrada.key} em hexadecimal. Ex: #E30613';
      }
    }

    final estadoLoja = estadoLojaController.text.trim();

    if (estadoLoja.isNotEmpty && estadoLoja.length != 2) {
      return 'Informe o estado da loja com 2 letras. Ex: BA';
    }

    if (alertarEstoqueBaixoCarrinho) {
      final limite = converterDecimalOpcional(
        limiteAlertaEstoqueBaixoController.text,
      );

      if (limite == null || limite <= 0) {
        return 'Informe uma quantidade maior que zero para o alerta de estoque baixo.';
      }
    }

    if (meiosPagamento.isEmpty) {
      return 'Cadastre pelo menos um meio de pagamento.';
    }

    if (etiquetaBalancaHabilitada) {
      final erroEtiqueta = configuracaoEtiquetaBalancaTela().validar();
      if (erroEtiqueta != null) {
        return 'Configuração da etiqueta de balança: $erroEtiqueta';
      }
    }

    if (validarLocalizacao && precisaLocalizacaoParaFrete) {
      if (!lojaTemLocalizacao) {
        return 'Busque a localização pelo endereço da loja ou use o GPS do aparelho para calcular frete por KM.';
      }
    }

    return null;
  }

  Future<bool> localizarLojaPeloEndereco({bool exibirMensagens = true}) async {
    if (!SessaoLoja.lojaSelecionada || SessaoLoja.supabaseLoja == null) {
      if (exibirMensagens && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhuma loja selecionada'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    final endereco = enderecoLojaController.text.trim();
    final cidade = cidadeLojaController.text.trim();
    final estado = estadoLojaController.text.trim();
    final enderecoBusca = enderecoLojaParaBusca();

    if (endereco.isEmpty || cidade.isEmpty || estado.isEmpty) {
      if (exibirMensagens && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Preencha rua/endereço, cidade e UF antes de buscar a localização.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    if (mounted) {
      setState(() {
        buscandoLocalizacaoLoja = true;
      });
    }

    try {
      final locais = await geocoding.locationFromAddress(enderecoBusca);

      if (locais.isEmpty) {
        throw Exception(
          'Endereço não encontrado. Confira rua, número, cidade e UF.',
        );
      }

      final local = locais.first;

      if (!mounted) return false;

      setState(() {
        latitudeLoja = local.latitude;
        longitudeLoja = local.longitude;
        enderecoLocalizacaoAtualKey = chaveEnderecoLocalizacao();
      });

      if (exibirMensagens) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Localização encontrada pelo endereço. Toque em Salvar.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      return true;
    } catch (e) {
      if (exibirMensagens && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao buscar localização pelo endereço: ${CentralService.mensagemErroUsuario(e)}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          buscandoLocalizacaoLoja = false;
        });
      }
    }
  }

  Future<void> buscarLocalizacaoPeloEnderecoDaLoja() async {
    await localizarLojaPeloEndereco();
  }

  Future<void> usarLocalizacaoAtualDaLoja() async {
    if (!SessaoLoja.lojaSelecionada || SessaoLoja.supabaseLoja == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma loja selecionada'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      buscandoLocalizacaoLoja = true;
    });

    try {
      final servicoAtivo = await Geolocator.isLocationServiceEnabled();

      if (!servicoAtivo) {
        throw Exception('Ative a localização do aparelho.');
      }

      var permissao = await Geolocator.checkPermission();

      if (permissao == LocationPermission.denied) {
        permissao = await Geolocator.requestPermission();
      }

      if (permissao == LocationPermission.denied ||
          permissao == LocationPermission.deniedForever) {
        throw Exception('Permissão de localização negada.');
      }

      final posicao = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;

      setState(() {
        latitudeLoja = posicao.latitude;
        longitudeLoja = posicao.longitude;
        enderecoLocalizacaoAtualKey = chaveEnderecoLocalizacao();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Localização da loja capturada. Toque em Salvar.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao capturar localização da loja: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          buscandoLocalizacaoLoja = false;
        });
      }
    }
  }

  Future<void> carregarConfiguracoes() async {
    if (!SessaoLoja.lojaSelecionada || SessaoLoja.supabaseLoja == null) {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma loja selecionada'),
          backgroundColor: Colors.red,
        ),
      );

      return;
    }

    try {
      final resposta = await SessaoLoja.supabaseLoja!
          .from('loja_configuracoes')
          .select()
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
          .limit(1)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        if (resposta != null) {
          preencherTela(Map<String, dynamic>.from(resposta));
        } else {
          idConfiguracao = null;
          preencherTela(<String, dynamic>{});
        }

        carregando = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao carregar configurações: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> selecionarEEnviarLogoLoja({
    required String tipoLogo,
    required TextEditingController controller,
  }) async {
    if (enviandoLogo || salvando) return;

    final mercadoId = SessaoLoja.mercadoId?.trim();

    if (mercadoId == null || mercadoId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loja atual não identificada.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final imagem = await imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 90,
      );

      if (imagem == null) return;

      setState(() {
        enviandoLogo = true;
      });

      final resposta = await centralService.uploadLogoConfiguracaoLoja(
        mercadoId: mercadoId,
        mercadoCodigo: SessaoLoja.mercadoCodigo,
        tipoLogo: tipoLogo,
        logoFile: File(imagem.path),
      );

      final logoUrl = tipoLogo == 'admin'
          ? primeiroTexto([
              resposta['admin_logo_url'],
              resposta['logo_admin_url'],
              resposta['imagem_url'],
            ])
          : primeiroTexto([resposta['logo_url'], resposta['imagem_url']]);

      if (logoUrl.isEmpty) {
        throw Exception('Upload concluído, mas a URL não retornou.');
      }

      if (!mounted) return;

      setState(() {
        controller.text = logoUrl;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logo carregada. Clique em Salvar para aplicar.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao carregar logo: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          enviandoLogo = false;
        });
      }
    }
  }

  Future<void> salvarConfiguracoes() async {
    var erroValidacao = validarCampos(validarLocalizacao: false);

    if (erroValidacao != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erroValidacao), backgroundColor: Colors.red),
      );
      return;
    }

    if (precisaRecalcularLocalizacaoLoja) {
      final localizado = await localizarLojaPeloEndereco(
        exibirMensagens: false,
      );

      if (!localizado) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível encontrar a localização pelo endereço. Confira o endereço ou use o GPS do aparelho.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    erroValidacao = validarCampos();

    if (erroValidacao != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erroValidacao), backgroundColor: Colors.red),
      );
      return;
    }

    if (!SessaoLoja.lojaSelecionada || SessaoLoja.supabaseLoja == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma loja selecionada'),
          backgroundColor: Colors.red,
        ),
      );

      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      salvando = true;
    });

    try {
      final dados = montarDadosConfiguracao();

      Map<String, dynamic>? registroSalvo;

      if (idConfiguracao != null && idConfiguracao!.trim().isNotEmpty) {
        final respostaUpdate = await SessaoLoja.supabaseLoja!
            .from('loja_configuracoes')
            .update(dados)
            .eq('id', idConfiguracao!)
            .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
            .select()
            .maybeSingle();

        if (respostaUpdate != null) {
          registroSalvo = Map<String, dynamic>.from(respostaUpdate);
        }
      }

      if (registroSalvo == null) {
        final respostaInsert = await SessaoLoja.supabaseLoja!
            .from('loja_configuracoes')
            .insert(SessaoLoja.dadosComMercado(dados))
            .select()
            .single();

        registroSalvo = Map<String, dynamic>.from(respostaInsert);
      }

      if (!mounted) return;

      setState(() {
        preencherTela(registroSalvo!);
      });

      SessaoLoja.configurarCores(
        primaria: adminCorPrimariaController.text,
        secundaria: adminCorSecundariaController.text,
        fundo: adminCorFundoController.text,
      );
      SessaoLoja.logoUrl = adminLogoUrlController.text.trim().isEmpty
          ? null
          : adminLogoUrlController.text.trim();
      await SessaoLoja.salvarSessaoLojaPersistida();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configurações salvas com sucesso'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao salvar configurações: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          salvando = false;
        });
      }
    }
  }

  Widget topo() {
    final nomeLoja = SessaoLoja.mercadoNome ?? 'Loja';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [vermelho, vermelhoEscuro],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: vermelho.withOpacity(0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(19),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(Icons.storefront, color: vermelho, size: 34),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Configurações da loja',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  nomeLoja,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget tituloSecao({
    required String titulo,
    required String subtitulo,
    required IconData icone,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 2, bottom: 10, top: 8),
      child: Row(
        children: [
          Icon(icone, color: vermelho, size: 20),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: textoPrincipal,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitulo,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget blocoSecao({
    required String titulo,
    required String subtitulo,
    required IconData icone,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tituloSecao(titulo: titulo, subtitulo: subtitulo, icone: icone),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.black.withOpacity(0.05)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget campoTexto({
    required String label,
    required TextEditingController controller,
    IconData? icon,
    TextInputType tipo = TextInputType.text,
    int maxLines = 1,
    bool enabled = true,
    List<TextInputFormatter>? inputFormatters,
    String? hint,
    String? helper,
  }) {
    final preenchido = controller.text.trim().isNotEmpty;

    final corBorda = preenchido
        ? vermelho.withOpacity(0.28)
        : const Color(0xFFCBD5E1);

    final corFundo = enabled ? Colors.white : const Color(0xFFF3F4F6);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: maxLines > 1 ? TextInputType.multiline : tipo,
        maxLines: maxLines,
        enabled: enabled,
        inputFormatters: inputFormatters,
        onChanged: (_) {
          if (mounted) {
            setState(() {});
          }
        },
        textInputAction: maxLines > 1
            ? TextInputAction.newline
            : TextInputAction.next,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          labelStyle: TextStyle(
            color: preenchido ? vermelho : const Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
          floatingLabelStyle: TextStyle(
            color: vermelho,
            fontWeight: FontWeight.w800,
          ),
          helperStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          prefixIcon: icon == null
              ? null
              : Padding(
                  padding: const EdgeInsets.all(9),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: enabled
                          ? vermelho.withOpacity(0.10)
                          : Colors.grey.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      icon,
                      color: enabled ? vermelho : Colors.grey,
                      size: 21,
                    ),
                  ),
                ),
          filled: true,
          fillColor: corFundo,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: BorderSide(color: corBorda, width: 1.4),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: BorderSide(color: corBorda, width: 1.4),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: BorderSide(color: vermelho, width: 1.8),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1.2),
          ),
        ),
      ),
    );
  }

  Widget campoPrioridadeEntrega() {
    const opcoes = <String, String>{
      'endereco_cadastrado': 'Entregar no endereço cadastrado',
      'localizacao_atual': 'Entregar na localização atual',
      'retirada_loja': 'Retirar na loja',
      'outro_endereco': 'Digitar outro endereço',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: prioridadeEntrega,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Opção de entrega prioritária',
          helperText:
              'Esta opção ficará marcada inicialmente no fechamento do pedido.',
          labelStyle: const TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
          floatingLabelStyle: TextStyle(
            color: vermelho,
            fontWeight: FontWeight.w800,
          ),
          helperStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(9),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: vermelho.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.flag_outlined, color: vermelho, size: 21),
            ),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 16,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: vermelho, width: 1.5),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
        ),
        items: opcoes.entries
            .map(
              (opcao) => DropdownMenuItem<String>(
                value: opcao.key,
                child: Text(
                  opcao.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: salvando
            ? null
            : (value) {
                if (value == null) return;
                setState(() {
                  prioridadeEntrega = value;
                });
              },
      ),
    );
  }

  Widget paletaCores({
    required String titulo,
    required TextEditingController primariaController,
    required TextEditingController secundariaController,
    required TextEditingController fundoController,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.color_lens_outlined, color: vermelho, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: textoPrincipal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: paletasCores.map((paleta) {
              final primaria = paleta['primaria']!;
              final secundaria = paleta['secundaria']!;
              final fundoPaleta = paleta['fundo']!;
              final selecionada =
                  normalizarCorHex(primariaController.text, '') == primaria &&
                  normalizarCorHex(secundariaController.text, '') ==
                      secundaria &&
                  normalizarCorHex(fundoController.text, '') == fundoPaleta;

              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  setState(() {
                    primariaController.text = primaria;
                    secundariaController.text = secundaria;
                    fundoController.text = fundoPaleta;
                  });
                },
                child: Container(
                  width: 98,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selecionada
                          ? corHexParaColor(primaria, vermelho)
                          : Colors.black.withOpacity(0.08),
                      width: selecionada ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _amostraCor(primaria, 22),
                          const SizedBox(width: 3),
                          _amostraCor(secundaria, 18),
                          const SizedBox(width: 3),
                          _amostraCor(fundoPaleta, 18),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        paleta['nome']!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selecionada
                              ? corHexParaColor(primaria, vermelho)
                              : textoPrincipal,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _amostraCor(String hex, double tamanho) {
    return Container(
      width: tamanho,
      height: tamanho,
      decoration: BoxDecoration(
        color: corHexParaColor(hex, vermelho),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.black.withOpacity(0.10)),
      ),
    );
  }

  Future<void> escolherCor({
    required String titulo,
    required TextEditingController controller,
  }) async {
    final corAtual = normalizarCorHex(controller.text, '');

    final selecionada = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 8, 10),
                  child: Row(
                    children: [
                      Icon(Icons.format_color_fill, color: vermelho),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          titulo,
                          style: const TextStyle(
                            color: textoPrincipal,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(14),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          mainAxisExtent: 96,
                        ),
                    itemCount: coresDisponiveis.length,
                    itemBuilder: (context, index) {
                      final item = coresDisponiveis[index];
                      final nome = item['nome']!;
                      final hex = item['hex']!;
                      final selecionado = corAtual == hex;
                      final cor = corHexParaColor(hex, vermelho);

                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(context, hex),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selecionado
                                  ? cor
                                  : Colors.black.withOpacity(0.08),
                              width: selecionado ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: cor,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.black.withOpacity(0.12),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                nome,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: textoPrincipal,
                                  fontSize: 10,
                                  height: 1.05,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                hex,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 9,
                                  height: 1.05,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selecionada == null || !mounted) {
      return;
    }

    setState(() {
      controller.text = selecionada;
    });
  }

  Widget campoCor({
    required String label,
    required TextEditingController controller,
    String? hint,
  }) {
    final corAtual = corHexParaColor(
      controller.text,
      corHexParaColor(hint ?? '#E30613', vermelho),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.text,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
          LengthLimitingTextInputFormatter(7),
        ],
        onChanged: (_) {
          if (mounted) {
            setState(() {});
          }
        },
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(
            color: corHexValida(controller.text)
                ? vermelho
                : const Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
          floatingLabelStyle: TextStyle(
            color: vermelho,
            fontWeight: FontWeight.w800,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(9),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: corAtual,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Colors.black.withOpacity(0.10)),
              ),
            ),
          ),
          suffixIcon: IconButton(
            tooltip: 'Escolher cor',
            icon: Icon(Icons.format_color_fill, color: vermelho),
            onPressed: () => escolherCor(titulo: label, controller: controller),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.4),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: BorderSide(
              color: corHexValida(controller.text)
                  ? vermelho.withOpacity(0.28)
                  : const Color(0xFFCBD5E1),
              width: 1.4,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: BorderSide(color: vermelho, width: 1.8),
          ),
        ),
      ),
    );
  }

  Widget campoLogoLoja({
    required String label,
    required String descricao,
    required String tipoLogo,
    required TextEditingController controller,
  }) {
    final logoUrl = controller.text.trim();
    final podeExibirPreview = urlHttpValida(logoUrl);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (podeExibirPreview)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: vermelho.withOpacity(0.12)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    logoUrl,
                    width: 74,
                    height: 58,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 74,
                        height: 58,
                        color: Colors.white,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: vermelho,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    descricao,
                    style: const TextStyle(
                      color: textoPrincipal,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        campoTexto(
          label: label,
          controller: controller,
          icon: Icons.image,
          tipo: TextInputType.url,
          hint: 'https://...',
        ),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: enviandoLogo || salvando
                ? null
                : () => selecionarEEnviarLogoLoja(
                    tipoLogo: tipoLogo,
                    controller: controller,
                  ),
            style: OutlinedButton.styleFrom(
              foregroundColor: vermelho,
              backgroundColor: vermelho.withOpacity(0.06),
              side: BorderSide(color: vermelho.withOpacity(0.28), width: 1.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: enviandoLogo
                ? SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: vermelho,
                    ),
                  )
                : const Icon(Icons.upload_file),
            label: Text(
              enviandoLogo ? 'Enviando logo...' : 'Carregar imagem',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget cardHorarios() {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LojaHorariosPage()),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [vermelho.withOpacity(0.08), Colors.white],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: vermelho.withOpacity(0.10)),
        ),
        child: Row(
          children: [
            Container(
              width: 47,
              height: 47,
              decoration: BoxDecoration(
                color: const Color(0xFFFFE5E8),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(Icons.access_time, color: vermelho),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Horários e fechamentos',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: textoPrincipal,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Funcionamento, sábado, domingo e feriados',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black45),
          ],
        ),
      ),
    );
  }

  Widget cardLocalizacaoLoja() {
    final definida = lojaTemLocalizacao;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: definida
            ? Colors.green.withOpacity(0.06)
            : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: definida
              ? Colors.green.withOpacity(0.20)
              : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: definida
                      ? Colors.green.withOpacity(0.12)
                      : vermelho.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  definida ? Icons.location_on : Icons.location_searching,
                  color: definida ? Colors.green : vermelho,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      textoStatusLocalizacaoLoja(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: textoPrincipal,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Use o endereço cadastrado para encontrar a latitude/longitude da loja. Se mudar rua, número, bairro, cidade ou UF, a localização será recalculada ao salvar.',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: buscandoLocalizacaoLoja
                  ? null
                  : buscarLocalizacaoPeloEnderecoDaLoja,
              icon: buscandoLocalizacaoLoja
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.manage_search),
              label: Text(
                buscandoLocalizacaoLoja
                    ? 'Buscando localização...'
                    : definida
                    ? 'Atualizar pelo endereço da loja'
                    : 'Buscar localização pelo endereço',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: vermelho,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: buscandoLocalizacaoLoja
                  ? null
                  : usarLocalizacaoAtualDaLoja,
              icon: const Icon(Icons.my_location),
              label: Text(
                definida
                    ? 'Atualizar usando GPS do aparelho'
                    : 'Usar GPS do aparelho',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: vermelho,
                side: BorderSide(color: vermelho.withOpacity(0.35)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
          if (definida) ...[
            const SizedBox(height: 10),
            Text(
              'Lat: ${latitudeLoja!.toStringAsFixed(6)} | Long: ${longitudeLoja!.toStringAsFixed(6)}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget editorMeiosPagamento() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: meioPagamentoController,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => adicionarMeioPagamento(),
                decoration: InputDecoration(
                  labelText: 'Nome do meio de pagamento',
                  hintText: 'Ex: Cartão de crédito',
                  prefixIcon: Icon(Icons.payments_outlined, color: vermelho),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(17),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(17),
                    borderSide: BorderSide(color: vermelho, width: 1.8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 52,
              height: 56,
              child: IconButton.filled(
                onPressed: adicionarMeioPagamento,
                tooltip: 'Adicionar meio de pagamento',
                style: IconButton.styleFrom(backgroundColor: vermelho),
                icon: const Icon(Icons.add),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Os clientes verão estas opções ao finalizar o pedido.',
          style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
        ),
        const SizedBox(height: 10),
        ...List.generate(meiosPagamento.length, (index) {
          final nome = meiosPagamento[index];

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.only(left: 12, right: 4),
            decoration: BoxDecoration(
              color: vermelho.withOpacity(0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: vermelho.withOpacity(0.16)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, color: vermelho, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    nome,
                    style: const TextStyle(
                      color: textoPrincipal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      meiosPagamento = [
                        ...meiosPagamento.take(index),
                        ...meiosPagamento.skip(index + 1),
                      ];
                    });
                  },
                  tooltip: 'Remover $nome',
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red,
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  ConfiguracaoEtiquetaBalanca configuracaoEtiquetaBalancaTela() {
    return ConfiguracaoEtiquetaBalanca(
      habilitada: etiquetaBalancaHabilitada,
      prefixo: etiquetaBalancaPrefixoController.text.trim(),
      tipoValor: etiquetaBalancaTipoValor,
      tamanhoCodigo:
          int.tryParse(etiquetaBalancaTamanhoCodigoController.text.trim()) ?? 0,
      tamanhoValor:
          int.tryParse(etiquetaBalancaTamanhoValorController.text.trim()) ?? 0,
      casasDecimais:
          int.tryParse(etiquetaBalancaCasasDecimaisController.text.trim()) ??
          -1,
      validarDigitoVerificador: etiquetaBalancaValidarDv,
    );
  }

  void testarEtiquetaBalanca() {
    try {
      final resultado = EtiquetaBalancaService.interpretar(
        etiquetaBalancaTesteController.text,
        configuracaoEtiquetaBalancaTela(),
      );
      final valor = resultado.tipoValor == 'PESO'
          ? '${resultado.valorInterpretado.toStringAsFixed(3).replaceAll('.', ',')} kg'
          : 'R\$ ${resultado.valorInterpretado.toStringAsFixed(2).replaceAll('.', ',')}';

      setState(() {
        testeEtiquetaBalancaOk = true;
        testeEtiquetaBalancaResultado =
            'Código do produto: ${resultado.codigoProduto} | $valor';
      });
    } catch (e) {
      setState(() {
        testeEtiquetaBalancaOk = false;
        testeEtiquetaBalancaResultado = e.toString();
      });
    }
  }

  Widget editorEtiquetaBalanca() {
    final somenteDigitos = <TextInputFormatter>[
      FilteringTextInputFormatter.digitsOnly,
    ];

    return Column(
      children: [
        switchCard(
          value: etiquetaBalancaHabilitada,
          titulo: 'Ler etiqueta de balança na conferência',
          subtituloAtivo:
              'O código será interpretado conforme o formato abaixo',
          subtituloInativo:
              'A conferência aceitará somente o EAN normal do produto',
          icone: Icons.scale_outlined,
          onChanged: (value) {
            setState(() {
              etiquetaBalancaHabilitada = value;
              testeEtiquetaBalancaResultado = '';
            });
          },
        ),
        if (etiquetaBalancaHabilitada) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              key: ValueKey(etiquetaBalancaTipoValor),
              initialValue: etiquetaBalancaTipoValor,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Informação gravada na etiqueta',
                helperText:
                    'Preço: calcula o peso pelo preço/kg. Peso: calcula o total.',
                prefixIcon: Icon(Icons.qr_code_2, color: vermelho),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'PRECO',
                  child: Text('Valor total a pagar'),
                ),
                DropdownMenuItem(value: 'PESO', child: Text('Peso do produto')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  etiquetaBalancaTipoValor = value;
                  etiquetaBalancaCasasDecimaisController.text = value == 'PESO'
                      ? '3'
                      : '2';
                  testeEtiquetaBalancaResultado = '';
                });
              },
            ),
          ),
          campoTexto(
            label: 'Prefixo da etiqueta',
            controller: etiquetaBalancaPrefixoController,
            icon: Icons.first_page,
            tipo: TextInputType.number,
            hint: 'Ex: 2',
            helper: 'Primeiros dígitos que identificam etiqueta de balança.',
            inputFormatters: somenteDigitos,
          ),
          Row(
            children: [
              Expanded(
                child: campoTexto(
                  label: 'Dígitos do produto',
                  controller: etiquetaBalancaTamanhoCodigoController,
                  icon: Icons.numbers,
                  tipo: TextInputType.number,
                  hint: '6',
                  inputFormatters: somenteDigitos,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: campoTexto(
                  label: 'Dígitos do valor',
                  controller: etiquetaBalancaTamanhoValorController,
                  icon: Icons.pin_outlined,
                  tipo: TextInputType.number,
                  hint: '5',
                  inputFormatters: somenteDigitos,
                ),
              ),
            ],
          ),
          campoTexto(
            label: 'Casas decimais',
            controller: etiquetaBalancaCasasDecimaisController,
            icon: Icons.exposure_zero,
            tipo: TextInputType.number,
            hint: etiquetaBalancaTipoValor == 'PESO' ? '3' : '2',
            helper: etiquetaBalancaTipoValor == 'PESO'
                ? 'Normalmente 3 casas para quilogramas.'
                : 'Normalmente 2 casas para reais e centavos.',
            inputFormatters: somenteDigitos,
          ),
          switchCard(
            value: etiquetaBalancaValidarDv,
            titulo: 'Validar dígito verificador',
            subtituloAtivo:
                'Leituras incompletas ou incorretas serão recusadas',
            subtituloInativo: 'O último dígito da etiqueta não será conferido',
            icone: Icons.verified_outlined,
            onChanged: (value) {
              setState(() => etiquetaBalancaValidarDv = value);
            },
          ),
          campoTexto(
            label: 'Testar uma etiqueta',
            controller: etiquetaBalancaTesteController,
            icon: Icons.qr_code_scanner,
            tipo: TextInputType.number,
            hint: 'Digite ou escaneie os 13 dígitos',
            inputFormatters: somenteDigitos,
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: testarEtiquetaBalanca,
              icon: const Icon(Icons.science_outlined),
              label: const Text('Testar formato'),
              style: OutlinedButton.styleFrom(
                foregroundColor: vermelho,
                side: BorderSide(color: vermelho),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          if (testeEtiquetaBalancaResultado.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: testeEtiquetaBalancaOk
                    ? Colors.green.withValues(alpha: 0.08)
                    : Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: testeEtiquetaBalancaOk
                      ? Colors.green.withValues(alpha: 0.35)
                      : Colors.red.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                testeEtiquetaBalancaResultado,
                style: TextStyle(
                  color: testeEtiquetaBalancaOk
                      ? Colors.green.shade800
                      : Colors.red.shade800,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget switchCard({
    required bool value,
    required String titulo,
    required String subtituloAtivo,
    required String subtituloInativo,
    required IconData icone,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.only(left: 12, right: 4, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: value ? vermelho.withOpacity(0.06) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: value
              ? vermelho.withOpacity(0.18)
              : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Row(
        children: [
          Icon(icone, color: value ? vermelho : Colors.black38),
          const SizedBox(width: 10),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: value,
                title: Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textoPrincipal,
                  ),
                ),
                subtitle: Text(
                  value ? subtituloAtivo : subtituloInativo,
                  style: const TextStyle(fontSize: 12),
                ),
                activeColor: vermelho,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nomeLoja = SessaoLoja.mercadoNome;

    return Scaffold(
      backgroundColor: fundo,
      appBar: AppBar(
        title: Text(
          nomeLoja == null
              ? 'Configurações da Loja'
              : 'Configurações - $nomeLoja',
        ),
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: salvando ? null : salvarConfiguracoes,
            child: Text(
              salvando ? 'Salvando...' : 'Salvar',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  topo(),
                  const SizedBox(height: 20),

                  blocoSecao(
                    titulo: 'Dados da loja',
                    subtitulo: 'Nome e canal principal de atendimento',
                    icone: Icons.storefront,
                    children: [
                      campoTexto(
                        label: 'Nome da loja',
                        controller: nomeController,
                        icon: Icons.store,
                      ),
                      campoTexto(
                        label: 'WhatsApp',
                        controller: whatsappController,
                        icon: Icons.phone,
                        tipo: TextInputType.phone,
                        inputFormatters: [telefoneFormatter],
                        hint: '(77) 98126-7706',
                        helper:
                            'Informe o DDD e o número. O campo será formatado automaticamente.',
                      ),
                    ],
                  ),

                  blocoSecao(
                    titulo: 'Redes sociais',
                    subtitulo: 'Informe sempre a URL completa do perfil',
                    icone: Icons.public,
                    children: [
                      campoTexto(
                        label: 'URL do Instagram',
                        controller: instagramController,
                        icon: Icons.camera_alt,
                        tipo: TextInputType.url,
                        hint: 'https://instagram.com/sualoja',
                        helper:
                            'Use o link do perfil. Não use apenas @nomedaloja.',
                      ),
                      campoTexto(
                        label: 'URL do Facebook',
                        controller: facebookController,
                        icon: Icons.facebook,
                        tipo: TextInputType.url,
                        hint: 'https://facebook.com/sualoja',
                      ),
                    ],
                  ),

                  blocoSecao(
                    titulo: 'Aparência do app Mercado',
                    subtitulo: 'Logo da loja e cores vistas pelos clientes',
                    icone: Icons.shopping_basket,
                    children: [
                      campoLogoLoja(
                        label: 'URL da logo do app Mercado',
                        descricao:
                            'Logo usada no app Mercado para os clientes.',
                        tipoLogo: 'mercado',
                        controller: logoUrlController,
                      ),
                      campoCor(
                        label: 'Cor principal',
                        controller: clienteCorPrimariaController,
                        hint: '#E30613',
                      ),
                      campoCor(
                        label: 'Cor secundária',
                        controller: clienteCorSecundariaController,
                        hint: '#C90010',
                      ),
                      campoCor(
                        label: 'Cor de fundo',
                        controller: clienteCorFundoController,
                        hint: '#FFF7F7',
                      ),
                    ],
                  ),

                  blocoSecao(
                    titulo: 'Aparência do app Admin',
                    subtitulo: 'Logo e cores usadas no app de gestão',
                    icone: Icons.admin_panel_settings,
                    children: [
                      campoLogoLoja(
                        label: 'URL da logo do app Admin',
                        descricao: 'Logo usada no app Admin/app_preço.',
                        tipoLogo: 'admin',
                        controller: adminLogoUrlController,
                      ),
                      campoCor(
                        label: 'Cor principal',
                        controller: adminCorPrimariaController,
                        hint: '#E30613',
                      ),
                      campoCor(
                        label: 'Cor secundária',
                        controller: adminCorSecundariaController,
                        hint: '#B8000D',
                      ),
                      campoCor(
                        label: 'Cor de fundo',
                        controller: adminCorFundoController,
                        hint: '#F5F7FA',
                      ),
                    ],
                  ),

                  blocoSecao(
                    titulo: 'Consulta Item',
                    subtitulo: 'Organização dos indicadores',
                    icone: Icons.dashboard_customize_outlined,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<LayoutConsultaItem>(
                          segments: const [
                            ButtonSegment(
                              value: LayoutConsultaItem.compacto,
                              icon: Icon(Icons.view_week_outlined),
                              label: Text('Moderno'),
                            ),
                            ButtonSegment(
                              value: LayoutConsultaItem.classico,
                              icon: Icon(Icons.grid_view_outlined),
                              label: Text('Clássico'),
                            ),
                          ],
                          selected: {layoutConsultaItem},
                          showSelectedIcon: false,
                          expandedInsets: EdgeInsets.zero,
                          onSelectionChanged: (selecionados) {
                            alterarLayoutConsultaItem(selecionados.first);
                          },
                        ),
                      ),
                    ],
                  ),

                  blocoSecao(
                    titulo: 'Funcionamento',
                    subtitulo: 'Horários de abertura, fechamento e feriados',
                    icone: Icons.schedule,
                    children: [cardHorarios()],
                  ),

                  blocoSecao(
                    titulo: 'Endereço da loja',
                    subtitulo:
                        'Cadastre o endereço normal e capture a localização para o frete por KM',
                    icone: Icons.location_on,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: campoTexto(
                              label: 'CEP',
                              controller: cepLojaController,
                              icon: Icons.local_post_office,
                              tipo: TextInputType.number,
                              hint: 'Ex: 45260-000',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: campoTexto(
                              label: 'UF',
                              controller: estadoLojaController,
                              icon: Icons.flag,
                              hint: 'BA',
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(2),
                              ],
                            ),
                          ),
                        ],
                      ),
                      campoTexto(
                        label: 'Rua / Endereço',
                        controller: enderecoLojaController,
                        icon: Icons.home_work,
                        hint: 'Ex: Rua São José',
                      ),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: campoTexto(
                              label: 'Número',
                              controller: numeroLojaController,
                              icon: Icons.pin,
                              tipo: TextInputType.number,
                              hint: 'Ex: 123',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 7,
                            child: campoTexto(
                              label: 'Bairro',
                              controller: bairroLojaController,
                              icon: Icons.location_city,
                              hint: 'Ex: Centro',
                            ),
                          ),
                        ],
                      ),
                      campoTexto(
                        label: 'Cidade',
                        controller: cidadeLojaController,
                        icon: Icons.map,
                        hint: 'Ex: Poções',
                      ),
                      campoTexto(
                        label: 'Referência / Complemento',
                        controller: referenciaLojaController,
                        icon: Icons.info_outline,
                        maxLines: 2,
                        hint: 'Ex: próximo à praça',
                      ),
                      cardLocalizacaoLoja(),
                    ],
                  ),

                  blocoSecao(
                    titulo: 'Pedidos e frete',
                    subtitulo: 'Pedido mínimo, taxa base, valor por KM e raio',
                    icone: Icons.delivery_dining,
                    children: [
                      campoTexto(
                        label: 'Pedido mínimo',
                        controller: pedidoMinimoController,
                        icon: Icons.shopping_cart,
                        tipo: TextInputType.number,
                        hint: 'Ex: 50,00',
                      ),
                      campoPrioridadeEntrega(),
                      switchCard(
                        value: cobrarFrete,
                        titulo: 'Cobrar frete',
                        subtituloAtivo: 'Taxa de entrega habilitada',
                        subtituloInativo:
                            'Entrega grátis para todos os pedidos',
                        icone: Icons.local_shipping,
                        onChanged: (value) {
                          setState(() {
                            cobrarFrete = value;

                            if (!cobrarFrete) {
                              taxaEntregaController.text = '0';
                              fretePorKmController.text = '0';
                              freteKmMaximoController.text = '0';
                              freteGratisController.text = '0';
                            }
                          });
                        },
                      ),
                      campoTexto(
                        label: 'Taxa base de entrega',
                        controller: taxaEntregaController,
                        icon: Icons.payments,
                        tipo: TextInputType.number,
                        enabled: cobrarFrete,
                        hint: 'Ex: 5,00',
                        helper:
                            'Valor inicial do frete. Se o valor por KM ficar zerado, funciona como taxa fixa.',
                      ),
                      campoTexto(
                        label: 'Valor por KM',
                        controller: fretePorKmController,
                        icon: Icons.route,
                        tipo: TextInputType.number,
                        enabled: cobrarFrete,
                        hint: 'Ex: 2,00',
                      ),
                      campoTexto(
                        label: 'KM máximo para entrega',
                        controller: freteKmMaximoController,
                        icon: Icons.social_distance,
                        tipo: TextInputType.number,
                        enabled: cobrarFrete,
                        hint: 'Ex: 8',
                      ),
                      campoTexto(
                        label: 'Frete grátis acima de',
                        controller: freteGratisController,
                        icon: Icons.card_giftcard,
                        tipo: TextInputType.number,
                        enabled: cobrarFrete,
                        hint: 'Ex: 100,00',
                      ),
                      switchCard(
                        value: bloquearEntregaForaRaio,
                        titulo: 'Bloquear entrega fora do raio',
                        subtituloAtivo:
                            'Cliente não finaliza pedido fora do KM máximo',
                        subtituloInativo:
                            'Sistema avisa, mas permite finalizar pedido',
                        icone: Icons.block,
                        onChanged: cobrarFrete
                            ? (value) {
                                setState(() {
                                  bloquearEntregaForaRaio = value;
                                });
                              }
                            : (_) {},
                      ),
                      campoTexto(
                        label: 'Mensagem fora da área de entrega',
                        controller: mensagemForaAreaEntregaController,
                        icon: Icons.warning_amber,
                        maxLines: 2,
                        enabled: cobrarFrete,
                        hint: 'Ex: Endereço fora da área de entrega.',
                      ),
                    ],
                  ),

                  blocoSecao(
                    titulo: 'Meios de pagamento',
                    subtitulo: 'Opções exibidas ao cliente no fechamento',
                    icone: Icons.account_balance_wallet_outlined,
                    children: [editorMeiosPagamento()],
                  ),

                  blocoSecao(
                    titulo: 'Etiqueta de balança',
                    subtitulo: 'Regra usada para conferir produtos pesados',
                    icone: Icons.scale_outlined,
                    children: [editorEtiquetaBalanca()],
                  ),

                  blocoSecao(
                    titulo: 'Exibição no app',
                    subtitulo: 'Mensagem para loja fechada e estoque',
                    icone: Icons.mobile_friendly,
                    children: [
                      campoTexto(
                        label: 'Mensagem quando fechado',
                        controller: mensagemFechadoController,
                        icon: Icons.message,
                        maxLines: 3,
                      ),
                      switchCard(
                        value: exibirEstoque,
                        titulo: 'Exibir estoque no app',
                        subtituloAtivo:
                            'Cliente poderá visualizar disponibilidade',
                        subtituloInativo:
                            'Cliente não verá disponibilidade do estoque',
                        icone: Icons.inventory_2,
                        onChanged: (value) {
                          setState(() {
                            exibirEstoque = value;
                          });
                        },
                      ),
                      switchCard(
                        value: exibirProdutosSemEstoque,
                        titulo: 'Mostrar produtos sem estoque',
                        subtituloAtivo: 'Produtos sem estoque aparecem no app',
                        subtituloInativo:
                            'Produtos sem estoque ficam ocultos no app',
                        icone: Icons.visibility_outlined,
                        onChanged: (value) {
                          setState(() {
                            exibirProdutosSemEstoque = value;
                          });
                        },
                      ),
                      switchCard(
                        value: bloquearVendaSemEstoque,
                        titulo: 'Bloquear venda sem estoque',
                        subtituloAtivo:
                            'Cliente não compra produto sem estoque disponível',
                        subtituloInativo:
                            'Cliente consegue comprar mesmo sem estoque',
                        icone: Icons.production_quantity_limits,
                        onChanged: (value) {
                          setState(() {
                            bloquearVendaSemEstoque = value;
                          });
                        },
                      ),
                      switchCard(
                        value: alertarEstoqueBaixoCarrinho,
                        titulo: 'Alertar cliente sobre estoque baixo',
                        subtituloAtivo:
                            'Exibe um aviso ao adicionar o primeiro item ao carrinho',
                        subtituloInativo:
                            'O cliente não recebe aviso de estoque baixo',
                        icone: Icons.inventory_outlined,
                        onChanged: (value) {
                          setState(() {
                            alertarEstoqueBaixoCarrinho = value;
                          });
                        },
                      ),
                      if (alertarEstoqueBaixoCarrinho)
                        campoTexto(
                          label:
                              'Alertar quando o estoque for igual ou menor a',
                          controller: limiteAlertaEstoqueBaixoController,
                          icon: Icons.low_priority,
                          tipo: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          hint: 'Ex: 5',
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9,.]'),
                            ),
                          ],
                        ),
                      switchCard(
                        value: exibirBotaoFinalizarCompra,
                        titulo: 'Botão finalizar compra',
                        subtituloAtivo:
                            'Aparece no início e nas categorias quando houver itens no carrinho',
                        subtituloInativo:
                            'A finalização fica disponível somente pelo carrinho',
                        icone: Icons.shopping_cart_checkout,
                        onChanged: (value) {
                          setState(() {
                            exibirBotaoFinalizarCompra = value;
                          });
                        },
                      ),
                      switchCard(
                        value: bloquearCarrinhoLojaFechada,
                        titulo: 'Bloquear carrinho com loja fechada',
                        subtituloAtivo:
                            'Cliente não monta carrinho fora do horário',
                        subtituloInativo:
                            'Cliente consegue montar carrinho mesmo com a loja fechada',
                        icone: Icons.lock_clock,
                        onChanged: (value) {
                          setState(() {
                            bloquearCarrinhoLojaFechada = value;
                          });
                        },
                      ),
                      switchCard(
                        value: permitirConferenciaManualItens,
                        titulo: 'Permitir conferência manual no item',
                        subtituloAtivo:
                            'Toque no item abre a conferência manual',
                        subtituloInativo:
                            'Item só pode ser conferido pela bipagem',
                        icone: Icons.touch_app,
                        onChanged: (value) {
                          setState(() {
                            permitirConferenciaManualItens = value;
                          });
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: salvando ? null : salvarConfiguracoes,
                      icon: salvando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: Text(
                        salvando ? 'Salvando...' : 'Salvar configurações',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: vermelho,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

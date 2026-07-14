import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/carrinho_controller.dart';
import '../services/app_tema_service.dart';
import '../services/loja_funcionamento_service.dart';
import 'main_navigation_page.dart';
import '../services/sessao_mercado_cliente.dart' as sessao;

class FinalizarPedidoPage extends StatefulWidget {
  final VoidCallback? onVoltar;
  final VoidCallback? onPedidoFinalizado;

  const FinalizarPedidoPage({
    super.key,
    this.onVoltar,
    this.onPedidoFinalizado,
  });

  @override
  State<FinalizarPedidoPage> createState() => _FinalizarPedidoPageState();
}

class _FinalizarPedidoPageState extends State<FinalizarPedidoPage> {
  static const String urlGeocodificarEndereco =
      'https://pkrkeeupcvxnqhynfvbw.functions.supabase.co/geocodificar-endereco';

  final observacaoController = TextEditingController();
  final trocoController = TextEditingController();
  final cupomController = TextEditingController();

  final outroEnderecoController = TextEditingController();
  final outroNumeroController = TextEditingController();
  final outroBairroController = TextEditingController();
  final outroCidadeController = TextEditingController();
  final outroReferenciaController = TextEditingController();

  String formaPagamento = 'Pix';
  String tipoEntrega = 'localizacao_atual';

  bool salvando = false;
  bool buscandoLocalizacao = false;
  bool buscandoEndereco = false;
  bool carregandoConfiguracoes = true;
  bool validandoCupom = false;

  double? latitude;
  double? longitude;
  String? mapaUrl;

  // Mantém a localização separada por tipo de entrega.
  // Isso evita usar um KM antigo quando o cliente muda o endereço.
  double? latitudeLocalizacaoAtual;
  double? longitudeLocalizacaoAtual;
  String? mapaUrlLocalizacaoAtual;

  double? latitudeEnderecoCadastrado;
  double? longitudeEnderecoCadastrado;
  String? mapaUrlEnderecoCadastrado;

  double? latitudeOutroEndereco;
  double? longitudeOutroEndereco;
  String? mapaUrlOutroEndereco;
  String? assinaturaOutroEnderecoLocalizado;

  Map<String, dynamic>? configuracoesLoja;
  Map<String, dynamic>? cupomAplicado;
  String? mensagemCupom;

  Color get corPrimaria => AppTemaService.primaria;
  Color get corSecundaria => AppTemaService.secundaria;
  Color get corFundo => AppTemaService.fundo;

  Color get corPrimariaSuave => corPrimaria.withValues(alpha: 0.07);
  Color get corPrimariaMuitoSuave => corPrimaria.withValues(alpha: 0.035);
  Color get corPrimariaBorda => corPrimaria.withValues(alpha: 0.22);

  @override
  void initState() {
    super.initState();
    carregarConfiguracoesLoja();
  }

  @override
  void dispose() {
    observacaoController.dispose();
    trocoController.dispose();
    cupomController.dispose();
    outroEnderecoController.dispose();
    outroNumeroController.dispose();
    outroBairroController.dispose();
    outroCidadeController.dispose();
    outroReferenciaController.dispose();
    super.dispose();
  }

  Future<void> carregarConfiguracoesLoja() async {
    try {
      final resposta = await Supabase.instance.client
          .from('loja_configuracoes')
          .select()
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .limit(1)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        configuracoesLoja = resposta == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(resposta);
        carregandoConfiguracoes = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        configuracoesLoja = <String, dynamic>{};
        carregandoConfiguracoes = false;
      });
    }
  }

  void voltarTela() {
    if (widget.onVoltar != null) {
      widget.onVoltar!();
      return;
    }

    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  void abrirPedidosAposFinalizar() {
    if (widget.onPedidoFinalizado != null) {
      widget.onPedidoFinalizado!();
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const MainNavigationPage(indexInicial: 3),
      ),
      (route) => false,
    );
  }

  String formatarMoeda(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  double? valorTroco() {
    final texto = trocoController.text
        .replaceAll('R\$', '')
        .replaceAll('.', '')
        .replaceAll(',', '.')
        .trim();

    if (texto.isEmpty) return null;

    return double.tryParse(texto);
  }

  double numero(dynamic valor) {
    if (valor == null) {
      return 0;
    }

    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor.toString().replaceAll(',', '.').trim()) ?? 0;
  }

  bool valorBool(dynamic valor, bool padrao) {
    if (valor is bool) return valor;

    if (valor is num) return valor == 1;

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

  String normalizarCupom(String valor) {
    return valor.trim().toUpperCase();
  }

  DateTime? converterData(dynamic valor) {
    if (valor == null) return null;

    if (valor is DateTime) {
      return valor;
    }

    return DateTime.tryParse(valor.toString());
  }

  bool cupomDentroDoPeriodo(Map<String, dynamic> cupom) {
    final agora = DateTime.now();
    final inicio = converterData(cupom['data_inicio']);
    final fim = converterData(cupom['data_fim']);

    if (inicio != null && agora.isBefore(inicio)) {
      return false;
    }

    if (fim != null && agora.isAfter(fim)) {
      return false;
    }

    return true;
  }

  double calcularDescontoCupom(double subtotal) {
    if (cupomAplicado == null) {
      return 0;
    }

    final tipo = (cupomAplicado!['tipo'] ?? 'valor')
        .toString()
        .trim()
        .toLowerCase();

    final valorCupom = numero(cupomAplicado!['valor']);

    if (valorCupom <= 0) {
      return 0;
    }

    double desconto;

    if (tipo == 'percentual' || tipo == 'porcentagem') {
      desconto = subtotal * (valorCupom / 100);
    } else {
      desconto = valorCupom;
    }

    if (desconto < 0) {
      return 0;
    }

    if (desconto > subtotal) {
      return subtotal;
    }

    return desconto;
  }

  String textoDescontoCupom(double subtotal) {
    if (cupomAplicado == null) {
      return '';
    }

    final codigo = cupomAplicado!['codigo']?.toString() ?? '';
    final desconto = calcularDescontoCupom(subtotal);

    return 'Cupom $codigo aplicado: -${formatarMoeda(desconto)}';
  }

  void removerCupom() {
    setState(() {
      cupomAplicado = null;
      mensagemCupom = null;
      cupomController.clear();
    });
  }

  Future<void> aplicarCupom(double subtotal) async {
    final codigo = normalizarCupom(cupomController.text);

    if (codigo.isEmpty) {
      setState(() {
        cupomAplicado = null;
        mensagemCupom = 'Digite um cupom.';
      });
      return;
    }

    setState(() {
      validandoCupom = true;
      mensagemCupom = null;
    });

    try {
      final resposta = await Supabase.instance.client
          .from('cupons_desconto')
          .select()
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .eq('codigo', codigo)
          .maybeSingle();

      if (resposta == null) {
        throw Exception('Cupom não encontrado.');
      }

      final cupom = Map<String, dynamic>.from(resposta);

      if (!valorBool(cupom['ativo'], true)) {
        throw Exception('Este cupom está inativo.');
      }

      if (!cupomDentroDoPeriodo(cupom)) {
        throw Exception('Este cupom não está disponível no momento.');
      }

      final valorMinimo = numero(cupom['valor_minimo']);

      if (valorMinimo > 0 && subtotal < valorMinimo) {
        throw Exception(
          'Este cupom é válido para pedidos acima de ${formatarMoeda(valorMinimo)}.',
        );
      }

      final limiteUso = numero(cupom['limite_uso']).round();
      final quantidadeUsada = numero(cupom['quantidade_usada']).round();

      if (limiteUso > 0 && quantidadeUsada >= limiteUso) {
        throw Exception('Este cupom atingiu o limite de uso.');
      }

      if (!mounted) return;

      setState(() {
        cupomAplicado = cupom;
        cupomAplicado!['codigo'] = codigo;
        mensagemCupom = textoDescontoCupom(subtotal);
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        cupomAplicado = null;
        mensagemCupom = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          validandoCupom = false;
        });
      }
    }
  }

  String textoLocalEntrega() {
    if (tipoEntrega == 'retirada_loja') {
      return 'Retirar na loja';
    }

    if (tipoEntrega == 'localizacao_atual') {
      return 'Localização Atual';
    }

    if (tipoEntrega == 'outro_endereco') {
      return 'Outro Endereço';
    }

    return 'Endereço Cadastrado';
  }

  String enderecoFormatado({
    required String? endereco,
    required String? numero,
    required String? bairro,
    required String? cidade,
    required String? referencia,
  }) {
    final linha1 = [
      endereco?.trim() ?? '',
      numero?.trim() ?? '',
    ].where((item) => item.isNotEmpty).join(', ');

    final linha2 = [
      bairro?.trim() ?? '',
      cidade?.trim() ?? '',
    ].where((item) => item.isNotEmpty).join(' - ');

    final partes = [
      linha1,
      linha2,
      referencia?.trim() ?? '',
    ].where((item) => item.isNotEmpty).toList();

    return partes.join(' | ');
  }

  String? urlGoogleMapsPorCoordenadas(double? lat, double? lng) {
    if (lat == null || lng == null) {
      return null;
    }

    return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
  }

  String? urlGoogleMapsPorEndereco(String endereco) {
    final texto = endereco
        .replaceAll('|', ',')
        .replaceAll('\n', ',')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (texto.isEmpty) {
      return null;
    }

    return 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(texto)}';
  }

  String textoEnderecoAlternativoResumo() {
    final endereco = outroEnderecoController.text.trim();
    final numero = outroNumeroController.text.trim();
    final bairro = outroBairroController.text.trim();
    final cidade = outroCidadeController.text.trim();

    if (endereco.isEmpty &&
        numero.isEmpty &&
        bairro.isEmpty &&
        cidade.isEmpty) {
      return 'Adicionar endereço para esta entrega';
    }

    final linha1 = numero.isEmpty ? endereco : '$endereco, $numero';
    final linha2 = [
      bairro,
      cidade,
    ].where((item) => item.isNotEmpty).join(' - ');

    if (linha2.isEmpty) {
      return linha1;
    }

    return '$linha1\n$linha2';
  }

  bool enderecoAlternativoValido() {
    return outroEnderecoController.text.trim().isNotEmpty &&
        outroNumeroController.text.trim().isNotEmpty &&
        outroBairroController.text.trim().isNotEmpty &&
        outroCidadeController.text.trim().isNotEmpty;
  }

  double distanciaKm({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    const raioTerraKm = 6371.0;

    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) *
            cos(lat2 * pi / 180.0) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return raioTerraKm * c;
  }

  bool usaFretePorKm() {
    final cfg = configuracoesLoja ?? {};

    return valorBool(cfg['cobrar_frete'], true) &&
        numero(cfg['frete_por_km']) > 0;
  }

  String assinaturaEnderecoAlternativo() {
    return [
      outroEnderecoController.text.trim().toLowerCase(),
      outroNumeroController.text.trim().toLowerCase(),
      outroBairroController.text.trim().toLowerCase(),
      outroCidadeController.text.trim().toLowerCase(),
      outroReferenciaController.text.trim().toLowerCase(),
    ].join('|');
  }

  bool localizacaoAtualEnviadaParaTipo() {
    if (tipoEntrega == 'retirada_loja') {
      return true;
    }

    if (tipoEntrega == 'localizacao_atual') {
      return latitudeLocalizacaoAtual != null &&
          longitudeLocalizacaoAtual != null;
    }

    if (tipoEntrega == 'endereco_cadastrado') {
      return latitudeEnderecoCadastrado != null &&
          longitudeEnderecoCadastrado != null;
    }

    if (tipoEntrega == 'outro_endereco') {
      return latitudeOutroEndereco != null &&
          longitudeOutroEndereco != null &&
          assinaturaOutroEnderecoLocalizado == assinaturaEnderecoAlternativo();
    }

    return false;
  }

  String? mapaUrlParaTipoAtual() {
    if (tipoEntrega == 'retirada_loja') {
      return null;
    }

    if (tipoEntrega == 'localizacao_atual') {
      return mapaUrlLocalizacaoAtual;
    }

    if (tipoEntrega == 'endereco_cadastrado') {
      return mapaUrlEnderecoCadastrado;
    }

    if (tipoEntrega == 'outro_endereco') {
      if (assinaturaOutroEnderecoLocalizado ==
          assinaturaEnderecoAlternativo()) {
        return mapaUrlOutroEndereco;
      }
      return null;
    }

    return null;
  }

  void enderecoAlternativoAlterado() {
    final assinaturaAtual = assinaturaEnderecoAlternativo();

    setState(() {
      if (assinaturaOutroEnderecoLocalizado != null &&
          assinaturaOutroEnderecoLocalizado != assinaturaAtual) {
        latitudeOutroEndereco = null;
        longitudeOutroEndereco = null;
        mapaUrlOutroEndereco = null;
        assinaturaOutroEnderecoLocalizado = null;

        if (tipoEntrega == 'outro_endereco') {
          latitude = null;
          longitude = null;
          mapaUrl = null;
        }
      }
    });
  }

  void selecionarTipoEntrega(String novoTipo) {
    setState(() {
      tipoEntrega = novoTipo;

      if (novoTipo == 'localizacao_atual') {
        latitude = latitudeLocalizacaoAtual;
        longitude = longitudeLocalizacaoAtual;
        mapaUrl = mapaUrlLocalizacaoAtual;
      } else if (novoTipo == 'retirada_loja') {
        latitude = null;
        longitude = null;
        mapaUrl = null;
      } else if (novoTipo == 'endereco_cadastrado') {
        latitude = latitudeEnderecoCadastrado;
        longitude = longitudeEnderecoCadastrado;
        mapaUrl = mapaUrlEnderecoCadastrado;
      } else if (novoTipo == 'outro_endereco' &&
          assinaturaOutroEnderecoLocalizado ==
              assinaturaEnderecoAlternativo()) {
        latitude = latitudeOutroEndereco;
        longitude = longitudeOutroEndereco;
        mapaUrl = mapaUrlOutroEndereco;
      } else {
        latitude = null;
        longitude = null;
        mapaUrl = null;
      }
    });
  }

  Map<String, dynamic> coordenadasEntrega(
    Map<String, dynamic>? cliente, {
    bool validar = false,
  }) {
    double? latEntrega;
    double? lngEntrega;

    if (tipoEntrega == 'retirada_loja') {
      return {'latitude': null, 'longitude': null};
    } else if (tipoEntrega == 'localizacao_atual') {
      latEntrega = latitudeLocalizacaoAtual;
      lngEntrega = longitudeLocalizacaoAtual;
    } else if (tipoEntrega == 'outro_endereco') {
      if (assinaturaOutroEnderecoLocalizado ==
          assinaturaEnderecoAlternativo()) {
        latEntrega = latitudeOutroEndereco;
        lngEntrega = longitudeOutroEndereco;
      }
    } else {
      final latCliente = numero(cliente?['latitude']);
      final lngCliente = numero(cliente?['longitude']);

      if (latCliente != 0 && lngCliente != 0) {
        latEntrega = latCliente;
        lngEntrega = lngCliente;
      } else {
        latEntrega = latitudeEnderecoCadastrado;
        lngEntrega = longitudeEnderecoCadastrado;
      }
    }

    if (validar && usaFretePorKm()) {
      if (latEntrega == null || lngEntrega == null) {
        if (tipoEntrega == 'endereco_cadastrado') {
          throw Exception(
            'Para calcular o frete por KM, calcule a distância pelo endereço cadastrado.',
          );
        }

        if (tipoEntrega == 'outro_endereco') {
          throw Exception(
            'Para calcular o frete por KM, calcule a distância desse endereço.',
          );
        }

        throw Exception('Envie sua localização atual antes de finalizar.');
      }
    }

    return {'latitude': latEntrega, 'longitude': lngEntrega};
  }

  Map<String, dynamic> calcularFrete(
    Map<String, dynamic>? cliente,
    double subtotal, {
    bool validar = false,
  }) {
    final cfg = configuracoesLoja ?? {};

    if (tipoEntrega == 'retirada_loja') {
      return {
        'taxa': 0.0,
        'distancia_km': null,
        'latitude': null,
        'longitude': null,
        'fora_area': false,
        'mensagem': '',
      };
    }

    final cobrarFrete = valorBool(cfg['cobrar_frete'], true);

    if (!cobrarFrete) {
      return {
        'taxa': 0.0,
        'distancia_km': null,
        'latitude': null,
        'longitude': null,
        'fora_area': false,
        'mensagem': '',
      };
    }

    final freteGratisAcima = numero(
      cfg['frete_gratis_acima'] ?? cfg['valor_frete_gratis'],
    );

    final taxaBase = numero(cfg['frete_taxa_base'] ?? cfg['taxa_entrega']);

    final fretePorKm = numero(cfg['frete_por_km']);
    final kmMaximo = numero(cfg['frete_km_maximo']);
    final bloquearForaRaio = valorBool(cfg['bloquear_entrega_fora_raio'], true);

    final mensagemForaArea =
        (cfg['mensagem_fora_area_entrega']?.toString().trim().isNotEmpty ??
            false)
        ? cfg['mensagem_fora_area_entrega'].toString()
        : 'Endereço fora da área de entrega.';

    final temFreteGratis = freteGratisAcima > 0 && subtotal >= freteGratisAcima;

    if (fretePorKm <= 0) {
      return {
        'taxa': temFreteGratis ? 0.0 : taxaBase,
        'distancia_km': null,
        'latitude': null,
        'longitude': null,
        'fora_area': false,
        'mensagem': '',
      };
    }

    final latLoja = numero(cfg['latitude_loja']);
    final lngLoja = numero(cfg['longitude_loja']);

    if ((latLoja == 0 || lngLoja == 0) && validar) {
      throw Exception(
        'A loja ainda não tem latitude e longitude cadastradas para calcular o frete.',
      );
    }

    if (latLoja == 0 || lngLoja == 0) {
      return {
        'taxa': temFreteGratis ? 0.0 : taxaBase,
        'distancia_km': null,
        'latitude': null,
        'longitude': null,
        'fora_area': false,
        'mensagem': 'Loja sem localização configurada.',
      };
    }

    final coords = coordenadasEntrega(cliente, validar: validar);

    final latEntrega = coords['latitude'] as double?;
    final lngEntrega = coords['longitude'] as double?;

    if (latEntrega == null || lngEntrega == null) {
      return {
        'taxa': 0.0,
        'distancia_km': null,
        'latitude': null,
        'longitude': null,
        'fora_area': false,
        'mensagem': 'Envie a localização para calcular o frete.',
      };
    }

    final distancia = distanciaKm(
      lat1: latLoja,
      lon1: lngLoja,
      lat2: latEntrega,
      lon2: lngEntrega,
    );

    final foraArea = kmMaximo > 0 && distancia > kmMaximo;

    if (foraArea && bloquearForaRaio && validar) {
      throw Exception(
        '$mensagemForaArea Distância aproximada: ${distancia.toStringAsFixed(2).replaceAll('.', ',')} km.',
      );
    }

    final taxaCalculada = temFreteGratis
        ? 0.0
        : taxaBase + (distancia * fretePorKm);

    return {
      'taxa': taxaCalculada,
      'distancia_km': distancia,
      'latitude': latEntrega,
      'longitude': lngEntrega,
      'fora_area': foraArea,
      'mensagem': foraArea ? mensagemForaArea : '',
    };
  }

  String primeiroTextoNaoVazio(List<dynamic> valores) {
    for (final valor in valores) {
      final texto = valor?.toString().trim() ?? '';

      if (texto.isNotEmpty && texto.toLowerCase() != 'null') {
        return texto;
      }
    }

    return '';
  }

  String estadoPadrao(Map<String, dynamic>? cliente) {
    final cfg = configuracoesLoja ?? {};

    return primeiroTextoNaoVazio([
      cliente?['estado'],
      cliente?['uf'],
      cfg['estado'],
      cfg['uf'],
      cfg['loja_estado'],
      cfg['estado_loja'],
    ]);
  }

  String cepPadrao(Map<String, dynamic>? cliente) {
    final cfg = configuracoesLoja ?? {};

    return primeiroTextoNaoVazio([
      cliente?['cep'],
      cliente?['codigo_postal'],
      cfg['cep'],
      cfg['loja_cep'],
    ]);
  }

  Future<Map<String, dynamic>> geocodificarEndereco({
    required String rua,
    required String numeroEndereco,
    required String bairro,
    required String cidade,
    String? estado,
    String? cep,
  }) async {
    final payload = <String, dynamic>{
      'rua': rua.trim(),
      'numero': numeroEndereco.trim(),
      'bairro': bairro.trim(),
      'cidade': cidade.trim(),
      'estado': estado?.trim() ?? '',
      'cep': cep?.trim() ?? '',
    };

    final resposta = await http.post(
      Uri.parse(urlGeocodificarEndereco),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    Map<String, dynamic> dados;

    try {
      dados = Map<String, dynamic>.from(jsonDecode(resposta.body));
    } catch (_) {
      throw Exception(
        'Não foi possível ler a resposta da geocodificação. HTTP ${resposta.statusCode}.',
      );
    }

    if (resposta.statusCode < 200 || resposta.statusCode >= 300) {
      final erro = dados['erro']?.toString().trim();
      final detalhes = dados['detalhes'];

      if (erro != null && erro.isNotEmpty) {
        if (detalhes is List && detalhes.isNotEmpty) {
          throw Exception('$erro Detalhes: ${detalhes.take(3).join(' | ')}');
        }

        throw Exception(erro);
      }

      throw Exception('Endereço não localizado. HTTP ${resposta.statusCode}.');
    }

    if (dados['sucesso'] != true) {
      throw Exception(
        dados['erro']?.toString() ?? 'Endereço não localizado com segurança.',
      );
    }

    final lat = numero(dados['latitude']);
    final lng = numero(dados['longitude']);

    if (lat == 0 || lng == 0) {
      throw Exception(
        'A API localizou o endereço, mas retornou coordenadas inválidas.',
      );
    }

    return dados;
  }

  Future<void> salvarCoordenadasCliente(
    Map<String, dynamic>? cliente,
    double lat,
    double lng,
  ) async {
    if (cliente == null) return;

    try {
      final id = cliente['id']?.toString();
      final userId = cliente['user_id']?.toString();
      final dados = {'latitude': lat, 'longitude': lng};

      if (id != null && id.isNotEmpty) {
        await Supabase.instance.client
            .from('clientes')
            .update(dados)
            .eq('id', id)
            .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio);
        return;
      }

      if (userId != null && userId.isNotEmpty) {
        await Supabase.instance.client
            .from('clientes')
            .update(dados)
            .eq('user_id', userId)
            .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio);
      }
    } catch (_) {
      // Não bloqueia o pedido se o banco não permitir atualizar latitude/longitude do cliente.
    }
  }

  Future<void> calcularEnderecoCadastrado(
    Map<String, dynamic>? cliente, {
    bool mostrarMensagem = true,
  }) async {
    if (cliente == null) {
      throw Exception('Cadastro do cliente não encontrado.');
    }

    final rua = cliente['endereco']?.toString().trim() ?? '';
    final numeroEndereco = cliente['numero']?.toString().trim() ?? '';
    final bairro = cliente['bairro']?.toString().trim() ?? '';
    final cidade = cliente['cidade']?.toString().trim() ?? '';
    final estado = estadoPadrao(cliente);
    final cep = cepPadrao(cliente);

    if (rua.isEmpty ||
        numeroEndereco.isEmpty ||
        bairro.isEmpty ||
        cidade.isEmpty) {
      throw Exception(
        'Complete endereço, número, bairro e cidade no cadastro antes de calcular a entrega.',
      );
    }

    if (mounted) {
      setState(() {
        buscandoEndereco = true;
      });
    }

    try {
      final dados = await geocodificarEndereco(
        rua: rua,
        numeroEndereco: numeroEndereco,
        bairro: bairro,
        cidade: cidade,
        estado: estado,
        cep: cep,
      );

      final lat = numero(dados['latitude']);
      final lng = numero(dados['longitude']);
      final urlMapa = urlGoogleMapsPorCoordenadas(lat, lng);

      await salvarCoordenadasCliente(cliente, lat, lng);

      if (!mounted) return;

      setState(() {
        latitudeEnderecoCadastrado = lat;
        longitudeEnderecoCadastrado = lng;
        mapaUrlEnderecoCadastrado = urlMapa;

        if (tipoEntrega == 'endereco_cadastrado') {
          latitude = lat;
          longitude = lng;
          mapaUrl = urlMapa;
        }
      });

      if (mostrarMensagem) {
        final origem = dados['origem']?.toString() ?? 'API';
        final aproximado = dados['aproximado'] == true;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              aproximado
                  ? 'Endereço localizado de forma aproximada por $origem. Confira a distância antes de finalizar.'
                  : 'Endereço localizado com sucesso por $origem.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          buscandoEndereco = false;
        });
      }
    }
  }

  Future<void> calcularOutroEndereco(
    Map<String, dynamic>? cliente, {
    bool mostrarMensagem = true,
  }) async {
    if (!enderecoAlternativoValido()) {
      throw Exception('Preencha endereço, número, bairro e cidade.');
    }

    if (mounted) {
      setState(() {
        buscandoEndereco = true;
      });
    }

    try {
      final dados = await geocodificarEndereco(
        rua: outroEnderecoController.text,
        numeroEndereco: outroNumeroController.text,
        bairro: outroBairroController.text,
        cidade: outroCidadeController.text,
        estado: estadoPadrao(cliente),
        cep: '',
      );

      final lat = numero(dados['latitude']);
      final lng = numero(dados['longitude']);
      final urlMapa = urlGoogleMapsPorCoordenadas(lat, lng);

      if (!mounted) return;

      setState(() {
        latitudeOutroEndereco = lat;
        longitudeOutroEndereco = lng;
        mapaUrlOutroEndereco = urlMapa;
        assinaturaOutroEnderecoLocalizado = assinaturaEnderecoAlternativo();

        if (tipoEntrega == 'outro_endereco') {
          latitude = lat;
          longitude = lng;
          mapaUrl = urlMapa;
        }
      });

      if (mostrarMensagem) {
        final origem = dados['origem']?.toString() ?? 'API';
        final aproximado = dados['aproximado'] == true;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              aproximado
                  ? 'Outro endereço localizado de forma aproximada por $origem. Confira a distância antes de finalizar.'
                  : 'Outro endereço localizado com sucesso por $origem.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          buscandoEndereco = false;
        });
      }
    }
  }

  Future<void> calcularEnderecoParaEntrega(
    Map<String, dynamic>? cliente,
  ) async {
    try {
      if (tipoEntrega == 'endereco_cadastrado') {
        await calcularEnderecoCadastrado(cliente);
        return;
      }

      if (tipoEntrega == 'outro_endereco') {
        await calcularOutroEndereco(cliente);
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao calcular endereço: $e')));
    }
  }

  Future<void> garantirCoordenadasEntrega(Map<String, dynamic>? cliente) async {
    if (tipoEntrega == 'retirada_loja') {
      return;
    }

    if (!usaFretePorKm()) {
      return;
    }

    if (tipoEntrega == 'endereco_cadastrado') {
      final latCliente = numero(cliente?['latitude']);
      final lngCliente = numero(cliente?['longitude']);

      if (latCliente != 0 && lngCliente != 0) {
        latitudeEnderecoCadastrado = latCliente;
        longitudeEnderecoCadastrado = lngCliente;
        mapaUrlEnderecoCadastrado = urlGoogleMapsPorCoordenadas(
          latCliente,
          lngCliente,
        );
        return;
      }

      if (latitudeEnderecoCadastrado != null &&
          longitudeEnderecoCadastrado != null) {
        return;
      }

      await calcularEnderecoCadastrado(cliente, mostrarMensagem: false);
      return;
    }

    if (tipoEntrega == 'outro_endereco') {
      final assinaturaAtual = assinaturaEnderecoAlternativo();

      if (latitudeOutroEndereco != null &&
          longitudeOutroEndereco != null &&
          assinaturaOutroEnderecoLocalizado == assinaturaAtual) {
        return;
      }

      await calcularOutroEndereco(cliente, mostrarMensagem: false);
    }
  }

  Future<void> pegarLocalizacao() async {
    setState(() {
      buscandoLocalizacao = true;
    });

    try {
      bool servicoAtivo = await Geolocator.isLocationServiceEnabled();

      if (!servicoAtivo) {
        throw Exception('Ative a localização do celular');
      }

      LocationPermission permissao = await Geolocator.checkPermission();

      if (permissao == LocationPermission.denied) {
        permissao = await Geolocator.requestPermission();
      }

      if (permissao == LocationPermission.denied ||
          permissao == LocationPermission.deniedForever) {
        throw Exception('Permissão de localização negada');
      }

      final posicao = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final urlMapa =
          'https://www.google.com/maps?q=${posicao.latitude},${posicao.longitude}';

      setState(() {
        latitude = posicao.latitude;
        longitude = posicao.longitude;
        mapaUrl = urlMapa;

        if (tipoEntrega == 'localizacao_atual') {
          latitudeLocalizacaoAtual = posicao.latitude;
          longitudeLocalizacaoAtual = posicao.longitude;
          mapaUrlLocalizacaoAtual = urlMapa;
        } else if (tipoEntrega == 'endereco_cadastrado') {
          latitudeEnderecoCadastrado = posicao.latitude;
          longitudeEnderecoCadastrado = posicao.longitude;
          mapaUrlEnderecoCadastrado = urlMapa;
        } else if (tipoEntrega == 'outro_endereco') {
          latitudeOutroEndereco = posicao.latitude;
          longitudeOutroEndereco = posicao.longitude;
          mapaUrlOutroEndereco = urlMapa;
          assinaturaOutroEnderecoLocalizado = assinaturaEnderecoAlternativo();
        }
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Localização capturada com sucesso')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao pegar localização: $e')));
    } finally {
      if (mounted) {
        setState(() {
          buscandoLocalizacao = false;
        });
      }
    }
  }

  String gerarCodigoEntrega() {
    final random = Random.secure();
    final numero = random.nextInt(10000);

    return numero.toString().padLeft(4, '0');
  }

  Future<void> baixarEstoquePedidoSupabase(dynamic pedidoId) async {
    if (sessao.SessaoMercadoCliente.fonteProdutos != 'BANCO_LOJA') {
      return;
    }

    final id = pedidoId?.toString().trim() ?? '';

    if (id.isEmpty) {
      throw Exception('Pedido sem ID para baixa de estoque.');
    }

    try {
      await Supabase.instance.client.rpc(
        'baixar_estoque_pedido_app',
        params: {
          'p_pedido_id': id,
          'p_mercado_id': sessao.SessaoMercadoCliente.mercadoIdObrigatorio,
        },
      );
    } catch (e) {
      throw Exception(
        'Pedido criado, mas nao foi possivel baixar o estoque no Supabase. '
        'Verifique se o SQL de baixa de estoque foi executado. Detalhe: $e',
      );
    }
  }

  Future<void> finalizarPedido() async {
    final carrinho = context.read<CarrinhoController>();
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) return;

    if (carrinho.itens.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Seu carrinho está vazio')));
      return;
    }

    final podeFinalizar =
        await LojaFuncionamentoService.podeAdicionarAoCarrinho(
          context,
          forcarAtualizacao: true,
        );

    if (!podeFinalizar) {
      return;
    }

    if (tipoEntrega == 'localizacao_atual' &&
        (latitudeLocalizacaoAtual == null ||
            longitudeLocalizacaoAtual == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ative o GPS e toque em "Enviar minha localização atual" antes de finalizar.',
          ),
        ),
      );
      return;
    }

    if (tipoEntrega == 'outro_endereco' && !enderecoAlternativoValido()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha endereço, número, bairro e cidade'),
        ),
      );
      return;
    }

    if (cupomController.text.trim().isNotEmpty && cupomAplicado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Toque em "Aplicar cupom" antes de finalizar.'),
        ),
      );
      return;
    }

    if (formaPagamento == 'Dinheiro') {
      final troco = valorTroco();

      if (troco != null && troco < carrinho.valorTotal) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('O valor para troco não pode ser menor que o total'),
          ),
        );
        return;
      }
    }

    setState(() {
      salvando = true;
    });

    try {
      final clienteRaw = await Supabase.instance.client
          .from('clientes')
          .select()
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .eq('user_id', user.id)
          .maybeSingle();

      if (clienteRaw == null) {
        throw Exception('Cadastro do cliente não encontrado');
      }

      final cliente = Map<String, dynamic>.from(clienteRaw);

      await garantirCoordenadasEntrega(cliente);

      final calculoFrete = calcularFrete(
        cliente,
        carrinho.valorTotal,
        validar: true,
      );

      final taxaEntregaCalculada = calculoFrete['taxa'] as double;
      final distanciaEntregaKm = calculoFrete['distancia_km'] as double?;
      final entregaLatitude = calculoFrete['latitude'] as double?;
      final entregaLongitude = calculoFrete['longitude'] as double?;

      final descontoCupom = calcularDescontoCupom(carrinho.valorTotal);
      final totalPedido =
          carrinho.valorTotal + taxaEntregaCalculada - descontoCupom;

      if (formaPagamento == 'Dinheiro') {
        final troco = valorTroco();

        if (troco != null && troco < totalPedido) {
          throw Exception(
            'O valor para troco não pode ser menor que o total do pedido.',
          );
        }
      }

      final retiradaNaLoja = tipoEntrega == 'retirada_loja';
      final usandoOutroEndereco = tipoEntrega == 'outro_endereco';

      final enderecoPedido = retiradaNaLoja
          ? null
          : usandoOutroEndereco
          ? outroEnderecoController.text.trim()
          : cliente['endereco'];

      final numeroPedido = retiradaNaLoja
          ? null
          : usandoOutroEndereco
          ? outroNumeroController.text.trim()
          : cliente['numero'];

      final bairroPedido = retiradaNaLoja
          ? null
          : usandoOutroEndereco
          ? outroBairroController.text.trim()
          : cliente['bairro'];

      final cidadePedido = retiradaNaLoja
          ? null
          : usandoOutroEndereco
          ? outroCidadeController.text.trim()
          : cliente['cidade'];

      final referenciaPedido = retiradaNaLoja
          ? null
          : usandoOutroEndereco
          ? outroReferenciaController.text.trim()
          : cliente['referencia'];

      final enderecoEntregaFormatado = retiradaNaLoja
          ? 'Retirar na loja'
          : enderecoFormatado(
              endereco: enderecoPedido?.toString(),
              numero: numeroPedido?.toString(),
              bairro: bairroPedido?.toString(),
              cidade: cidadePedido?.toString(),
              referencia: referenciaPedido?.toString(),
            );

      final codigoEntrega = retiradaNaLoja ? null : gerarCodigoEntrega();

      final mapaEntregaUrl = retiradaNaLoja
          ? null
          : urlGoogleMapsPorCoordenadas(entregaLatitude, entregaLongitude) ??
                urlGoogleMapsPorEndereco(enderecoEntregaFormatado);

      final agoraPedido = DateTime.now().toIso8601String();

      final pedido = await Supabase.instance.client
          .from('pedidos')
          .insert({
            ...sessao.SessaoMercadoCliente.dadosMercadoRegistro,
            'user_id': user.id,
            'cliente_nome': cliente['nome'],
            'cliente_email': user.email,
            'cliente_telefone': cliente['telefone'],
            'endereco': enderecoPedido,
            'numero': numeroPedido,
            'bairro': bairroPedido,
            'cidade': cidadePedido,
            'referencia': referenciaPedido,
            'local_entrega': textoLocalEntrega(),
            'forma_pagamento': formaPagamento,
            'troco_para': formaPagamento == 'Dinheiro' ? valorTroco() : null,
            'observacao': observacaoController.text.trim(),
            'subtotal_produtos': carrinho.valorTotal,
            'subtotal': carrinho.valorTotal,
            'cupom_id': cupomAplicado?['id'],
            'cupom_codigo': cupomAplicado?['codigo'],
            'cupom_desconto': descontoCupom,
            'valor_desconto': descontoCupom,
            'desconto': descontoCupom,
            'codigo_entrega': codigoEntrega,
            'taxa_entrega': taxaEntregaCalculada,
            'total': totalPedido,
            'status': 'novo',
            'criado_em': agoraPedido,
            'atualizado_em': agoraPedido,

            // Campos antigos mantidos para compatibilidade.
            'latitude': entregaLatitude,
            'longitude': entregaLongitude,
            'mapa_url': mapaEntregaUrl,

            // Campos novos do frete por KM.
            'entrega_latitude': entregaLatitude,
            'entrega_longitude': entregaLongitude,
            'entrega_distancia_km': distanciaEntregaKm,
            'taxa_entrega_calculada': taxaEntregaCalculada,
            'endereco_entrega_formatado': enderecoEntregaFormatado,
          })
          .select('id, numero_pedido')
          .single();

      final pedidoId = pedido['id'];
      final origemProdutos = sessao.SessaoMercadoCliente.fonteProdutos;

      final itens = carrinho.itens.map((item) {
        final produto = item.produto;
        final pesoEstimadoKg = produto.ehKg ? item.pesoEstimadoKg : null;
        final totalFinal = produto.pesoVariavel ? null : item.total;
        final produtoAppId = produto.produtoAppId.trim();

        final dadosItem = {
          ...sessao.SessaoMercadoCliente.dadosMercadoRegistro,
          'pedido_id': pedidoId,
          'produto_id': produto.produtoId,
          'nome_produto': produto.nome,
          'ean': produto.ean,
          'quantidade': item.quantidade,
          'preco_unitario': produto.preco,
          'total': item.total,
          'criado_em': agoraPedido,

          // Campos para produtos KG, fracionados e peso variável.
          'unidade_medida': produto.unidadeNormalizada,
          'peso_variavel': produto.ehKg && produto.pesoVariavel,
          'quantidade_unidade': produto.ehKg && !produto.pesoVariavel
              ? null
              : item.quantidade,
          'peso_estimado_kg': pesoEstimadoKg,
          'peso_real_kg': null,
          'preco_kg': produto.ehKg ? produto.preco : null,
          'total_estimado': item.total,
          'total_final': totalFinal,
          'item_conferido': false,
          'conferido': false,
          'quantidade_conferida': 0,
          'conferido_em': null,
        };

        if (origemProdutos == 'BANCO_LOJA') {
          dadosItem['produto_app_id'] = produtoAppId.isEmpty
              ? null
              : produtoAppId;
          dadosItem['origem_produtos'] = origemProdutos;
        }

        return dadosItem;
      }).toList();

      await Supabase.instance.client.from('pedido_itens').insert(itens);
      await baixarEstoquePedidoSupabase(pedidoId);

      if (cupomAplicado != null && cupomAplicado?['id'] != null) {
        try {
          final quantidadeAtual = numero(
            cupomAplicado?['quantidade_usada'],
          ).round();

          await Supabase.instance.client
              .from('cupons_desconto')
              .update({'quantidade_usada': quantidadeAtual + 1})
              .eq('id', cupomAplicado!['id'])
              .eq(
                'mercado_id',
                sessao.SessaoMercadoCliente.mercadoIdObrigatorio,
              );
        } catch (_) {
          // Não bloqueia o pedido caso a política do banco não permita atualizar o cupom pelo app.
        }
      }

      carrinho.limparCarrinho();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pedido #${pedido['numero_pedido']} enviado com sucesso',
          ),
        ),
      );

      abrirPedidosAposFinalizar();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao finalizar pedido: $e')));
    } finally {
      if (mounted) {
        setState(() {
          salvando = false;
        });
      }
    }
  }

  Widget opcaoPagamento(String texto, IconData icon) {
    return RadioListTile<String>(
      value: texto,
      groupValue: formaPagamento,
      activeColor: corPrimaria,
      onChanged: salvando
          ? null
          : (value) {
              setState(() {
                formaPagamento = value!;
                if (formaPagamento != 'Dinheiro') {
                  trocoController.clear();
                }
              });
            },
      title: Text(texto),
      secondary: Icon(icon, color: corPrimaria),
    );
  }

  Widget campoEnderecoAlternativo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      enabled: !salvando,
      keyboardType: keyboardType,
      onChanged: (_) {
        if (mounted) {
          enderecoAlternativoAlterado();
        }
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: corPrimaria),
        filled: true,
        fillColor: corPrimariaMuitoSuave,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: corPrimariaBorda),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: corPrimaria, width: 1.4),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget botaoEnviarLocalizacao({required String texto}) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: buscandoLocalizacao || salvando ? null : pegarLocalizacao,
        icon: buscandoLocalizacao
            ? SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: corPrimaria,
                ),
              )
            : const Icon(Icons.my_location),
        label: Text(
          mapaUrlParaTipoAtual() == null
              ? texto
              : 'Localização enviada para cálculo',
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: corPrimaria,
          side: BorderSide(color: corPrimaria),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget botaoCalcularEndereco({
    required String texto,
    required Map<String, dynamic>? cliente,
  }) {
    final localizado = mapaUrlParaTipoAtual() != null;

    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: buscandoEndereco || salvando
            ? null
            : () => calcularEnderecoParaEntrega(cliente),
        icon: buscandoEndereco
            ? SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: corPrimaria,
                ),
              )
            : Icon(localizado ? Icons.check_circle : Icons.route),
        label: Text(
          buscandoEndereco
              ? 'Calculando endereço...'
              : localizado
              ? 'Distância calculada pelo endereço'
              : texto,
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: localizado ? Colors.green : corPrimaria,
          side: BorderSide(color: localizado ? Colors.green : corPrimaria),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget formularioOutroEndereco(Map<String, dynamic>? cliente) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: corPrimariaSuave,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: corPrimariaBorda),
      ),
      child: Column(
        children: [
          campoEnderecoAlternativo(
            controller: outroEnderecoController,
            label: 'Rua / Endereço',
            icon: Icons.location_on_outlined,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 4,
                child: campoEnderecoAlternativo(
                  controller: outroNumeroController,
                  label: 'Número',
                  icon: Icons.home_outlined,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 6,
                child: campoEnderecoAlternativo(
                  controller: outroBairroController,
                  label: 'Bairro',
                  icon: Icons.location_city,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          campoEnderecoAlternativo(
            controller: outroCidadeController,
            label: 'Cidade',
            icon: Icons.map_outlined,
          ),
          const SizedBox(height: 10),
          campoEnderecoAlternativo(
            controller: outroReferenciaController,
            label: 'Referência (opcional)',
            icon: Icons.info_outline,
          ),
          const SizedBox(height: 10),
          botaoCalcularEndereco(
            texto: 'Calcular distância pelo endereço',
            cliente: cliente,
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Este endereço será usado somente neste pedido. Para frete por KM, calcule a distância pelo endereço.',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String telefoneContatoLoja() {
    final numeros = telefoneContatoLojaNumeros();

    if (numeros.length == 13 && numeros.startsWith('55')) {
      final semPais = numeros.substring(2);

      return '(${semPais.substring(0, 2)}) '
          '${semPais.substring(2, 7)}-${semPais.substring(7)}';
    }

    if (numeros.length == 12 && numeros.startsWith('55')) {
      final semPais = numeros.substring(2);

      return '(${semPais.substring(0, 2)}) '
          '${semPais.substring(2, 6)}-${semPais.substring(6)}';
    }

    if (numeros.length == 11) {
      return '(${numeros.substring(0, 2)}) '
          '${numeros.substring(2, 7)}-${numeros.substring(7)}';
    }

    if (numeros.length == 10) {
      return '(${numeros.substring(0, 2)}) '
          '${numeros.substring(2, 6)}-${numeros.substring(6)}';
    }

    final cfg = configuracoesLoja ?? {};

    return (cfg['whatsapp'] ??
            cfg['telefone'] ??
            cfg['telefone_loja'] ??
            cfg['celular'] ??
            '')
        .toString()
        .trim();
  }

  String telefoneContatoLojaNumeros() {
    final cfg = configuracoesLoja ?? {};

    final bruto =
        (cfg['whatsapp'] ??
                cfg['telefone'] ??
                cfg['telefone_loja'] ??
                cfg['celular'] ??
                '')
            .toString();

    var numeros = bruto.replaceAll(RegExp(r'[^0-9]'), '');

    if (numeros.isEmpty) {
      return '';
    }

    if (!numeros.startsWith('55') &&
        (numeros.length == 10 || numeros.length == 11)) {
      numeros = '55$numeros';
    }

    return numeros;
  }

  Future<void> abrirWhatsAppLoja() async {
    final telefone = telefoneContatoLojaNumeros();

    if (telefone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Telefone da loja não encontrado.')),
      );
      return;
    }

    final mensagem = Uri.encodeComponent(
      'Olá! Tenho uma dúvida sobre a entrega no perímetro urbano.',
    );

    final appUrl = Uri.parse('whatsapp://send?phone=$telefone&text=$mensagem');
    final webUrl = Uri.parse('https://wa.me/$telefone?text=$mensagem');

    try {
      final abriuApp = await launchUrl(
        appUrl,
        mode: LaunchMode.externalApplication,
      );

      if (!abriuApp) {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  Widget avisoEntregaUrbana() {
    final telefone = telefoneContatoLoja();

    const verdeEntrega = Color(0xFF007D80);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF9ADADD), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: verdeEntrega.withOpacity(0.10),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.warning_amber_rounded, color: verdeEntrega, size: 23),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ATENÇÃO',
                  style: TextStyle(
                    color: verdeEntrega,
                    fontSize: 15,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'No momento só realizamos entrega no perímetro urbano.',
            style: TextStyle(
              color: Color(0xFF1B1F24),
              fontSize: 12.8,
              height: 1.25,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Em caso de dúvidas, entre em contato com a loja pelo WhatsApp.',
            style: TextStyle(
              color: Color(0xFF2D3436),
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (telefone.isNotEmpty) ...[
            const SizedBox(height: 9),
            SizedBox(
              width: double.infinity,
              height: 39,
              child: ElevatedButton.icon(
                onPressed: abrirWhatsAppLoja,
                icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 18),
                label: Text('Chamar no WhatsApp $telefone'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: verdeEntrega,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12.2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget cardEntrega(Map<String, dynamic>? cliente) {
    final latCliente = numero(cliente?['latitude']);
    final lngCliente = numero(cliente?['longitude']);
    final enderecoCadastradoLocalizado =
        (latCliente != 0 && lngCliente != 0) ||
        (latitudeEnderecoCadastrado != null &&
            longitudeEnderecoCadastrado != null);
    final enderecoCadastradoSelecionado = tipoEntrega == 'endereco_cadastrado';

    final retiradaSelecionada = tipoEntrega == 'retirada_loja';
    final localizacaoAtualSelecionada = tipoEntrega == 'localizacao_atual';
    final localizacaoAtualEnviada =
        latitudeLocalizacaoAtual != null && longitudeLocalizacaoAtual != null;

    return Card(
      elevation: 6,
      shadowColor: AppTemaService.primaria.withValues(alpha: 0.08),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: AppTemaService.primaria.withValues(alpha: 0.16),
          width: 1.6,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Entrega ou retirada',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: retiradaSelecionada
                    ? Colors.green.withValues(alpha: 0.09)
                    : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: retiradaSelecionada
                      ? Colors.green.withValues(alpha: 0.35)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: salvando
                    ? null
                    : () {
                        selecionarTipoEntrega('retirada_loja');
                      },
                child: Row(
                  children: [
                    Radio<String>(
                      value: 'retirada_loja',
                      groupValue: tipoEntrega,
                      activeColor: Colors.green,
                      onChanged: salvando
                          ? null
                          : (value) {
                              selecionarTipoEntrega(value!);
                            },
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Retirar na loja',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Sem taxa de entrega. O pedido fica separado para retirada.',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      retiradaSelecionada
                          ? Icons.check_circle
                          : Icons.storefront,
                      color: retiradaSelecionada ? Colors.green : corPrimaria,
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: localizacaoAtualSelecionada
                    ? corPrimariaSuave
                    : corPrimariaMuitoSuave,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: localizacaoAtualSelecionada
                      ? corPrimaria.withValues(alpha: 0.32)
                      : corPrimaria.withValues(alpha: 0.10),
                ),
              ),
              child: Column(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: salvando
                        ? null
                        : () {
                            selecionarTipoEntrega('localizacao_atual');
                          },
                    child: Row(
                      children: [
                        Radio<String>(
                          value: 'localizacao_atual',
                          groupValue: tipoEntrega,
                          activeColor: corPrimaria,
                          onChanged: salvando
                              ? null
                              : (value) {
                                  selecionarTipoEntrega(value!);
                                },
                        ),
                        const SizedBox(width: 4),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Entregar na minha localização atual',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Opção principal. O GPS precisa estar ativo para finalizar.',
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          localizacaoAtualEnviada
                              ? Icons.check_circle
                              : Icons.my_location,
                          color: localizacaoAtualEnviada
                              ? Colors.green
                              : corPrimaria,
                        ),
                      ],
                    ),
                  ),
                  if (localizacaoAtualSelecionada) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: buscandoLocalizacao || salvando
                            ? null
                            : pegarLocalizacao,
                        icon: buscandoLocalizacao
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                localizacaoAtualEnviada
                                    ? Icons.check_circle
                                    : Icons.location_on,
                              ),
                        label: Text(
                          buscandoLocalizacao
                              ? 'Capturando localização...'
                              : localizacaoAtualEnviada
                              ? 'Localização atual enviada'
                              : 'Enviar minha localização atual',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: corPrimaria,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      localizacaoAtualEnviada
                          ? 'Localização capturada com sucesso.'
                          : 'Sem a localização atual não será possível finalizar o pedido.',
                      style: TextStyle(
                        color: localizacaoAtualEnviada
                            ? Colors.green
                            : Colors.black54,
                        fontSize: 12,
                        fontWeight: localizacaoAtualEnviada
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                childrenPadding: EdgeInsets.zero,
                iconColor: corPrimaria,
                collapsedIconColor: corPrimaria,
                initiallyExpanded:
                    tipoEntrega == 'endereco_cadastrado' ||
                    tipoEntrega == 'outro_endereco',
                title: const Text(
                  'Outras opções de entrega',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                subtitle: const Text(
                  'Use apenas se não quiser enviar a localização atual',
                  style: TextStyle(fontSize: 12),
                ),
                children: [
                  RadioListTile<String>(
                    value: 'endereco_cadastrado',
                    groupValue: tipoEntrega,
                    activeColor: corPrimaria,
                    dense: true,
                    onChanged: salvando
                        ? null
                        : (value) {
                            selecionarTipoEntrega(value!);
                          },
                    title: const Text('Endereço cadastrado'),
                    subtitle: cliente == null
                        ? null
                        : Text(
                            '${cliente['endereco'] ?? ''}, ${cliente['numero'] ?? ''}\n'
                            '${cliente['bairro'] ?? ''} - ${cliente['cidade'] ?? ''}',
                          ),
                    secondary: Icon(Icons.home, color: corPrimaria),
                  ),
                  if (enderecoCadastradoSelecionado) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        enderecoCadastradoLocalizado
                            ? 'Endereço cadastrado localizado para cálculo do frete.'
                            : 'Para calcular o frete por KM, calcule a distância pelo endereço cadastrado.',
                        style: TextStyle(
                          color: enderecoCadastradoLocalizado
                              ? Colors.green
                              : Colors.black54,
                          fontSize: 12,
                          fontWeight: enderecoCadastradoLocalizado
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: botaoCalcularEndereco(
                        texto: 'Calcular distância pelo endereço cadastrado',
                        cliente: cliente,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  RadioListTile<String>(
                    value: 'outro_endereco',
                    groupValue: tipoEntrega,
                    activeColor: corPrimaria,
                    dense: true,
                    onChanged: salvando
                        ? null
                        : (value) {
                            selecionarTipoEntrega(value!);
                          },
                    title: const Text('Outro endereço'),
                    subtitle: Text(textoEnderecoAlternativoResumo()),
                    secondary: Icon(Icons.add_location_alt, color: corPrimaria),
                  ),
                  if (tipoEntrega == 'outro_endereco') ...[
                    const SizedBox(height: 8),
                    formularioOutroEndereco(cliente),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget cardCupomDesconto(double subtotal) {
    final cupomValido = cupomAplicado != null;
    final mensagem = mensagemCupom ?? '';

    return Card(
      elevation: 6,
      shadowColor: AppTemaService.primaria.withValues(alpha: 0.08),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: AppTemaService.primaria.withValues(alpha: 0.16),
          width: 1.6,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cupom de desconto',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: cupomController,
              enabled: !salvando && !validandoCupom && !cupomValido,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) {
                if (cupomAplicado != null || mensagemCupom != null) {
                  setState(() {
                    cupomAplicado = null;
                    mensagemCupom = null;
                  });
                }
              },
              decoration: InputDecoration(
                labelText: 'Digite seu cupom',
                hintText: 'Ex: PROMO10',
                prefixIcon: Icon(
                  Icons.local_offer_outlined,
                  color: corPrimaria,
                ),
                filled: true,
                fillColor: corPrimariaMuitoSuave,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: corPrimariaBorda),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: corPrimaria, width: 1.4),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: salvando || validandoCupom
                          ? null
                          : cupomValido
                          ? removerCupom
                          : () => aplicarCupom(subtotal),
                      icon: validandoCupom
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              cupomValido ? Icons.close : Icons.check_circle,
                            ),
                      label: Text(
                        validandoCupom
                            ? 'Validando...'
                            : cupomValido
                            ? 'Remover cupom'
                            : 'Aplicar cupom',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cupomValido
                            ? Colors.black54
                            : corPrimaria,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (mensagem.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                mensagem,
                style: TextStyle(
                  color: cupomValido ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget cardResumoPedido(
    CarrinhoController carrinho,
    Map<String, dynamic>? cliente,
  ) {
    final calculo = calcularFrete(cliente, carrinho.valorTotal, validar: false);

    final taxa = calculo['taxa'] as double;
    final distancia = calculo['distancia_km'] as double?;
    final foraArea = calculo['fora_area'] == true;
    final mensagem = calculo['mensagem']?.toString() ?? '';
    final descontoCupom = calcularDescontoCupom(carrinho.valorTotal);
    final total = carrinho.valorTotal + taxa - descontoCupom;
    final aguardandoCalculoFrete =
        usaFretePorKm() && distancia == null && mensagem.isNotEmpty;

    return Card(
      elevation: 6,
      shadowColor: AppTemaService.primaria.withValues(alpha: 0.08),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: AppTemaService.primaria.withValues(alpha: 0.16),
          width: 1.6,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Resumo do pedido',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
            const SizedBox(height: 10),
            ...carrinho.itens.map((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item.textoQuantidadeCurto} ${item.produto.nome}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(formatarMoeda(item.total)),
                  ],
                ),
              );
            }),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Produtos'),
                Text(formatarMoeda(carrinho.valorTotal)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Entrega'),
                Text(
                  aguardandoCalculoFrete
                      ? 'A calcular'
                      : taxa == 0
                      ? 'Grátis'
                      : formatarMoeda(taxa),
                  style: TextStyle(
                    color: aguardandoCalculoFrete
                        ? Colors.orange.shade900
                        : taxa == 0
                        ? Colors.green
                        : Colors.black87,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (descontoCupom > 0) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Cupom ${cupomAplicado?['codigo'] ?? ''}'),
                  Text(
                    '-${formatarMoeda(descontoCupom)}',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
            if (distancia != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Distância aprox.: ${distancia.toStringAsFixed(2).replaceAll('.', ',')} km',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ),
            ],
            if (mensagem.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: foraArea
                      ? const Color(0xFFFFEBEE)
                      : const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  mensagem,
                  style: TextStyle(
                    color: foraArea ? Colors.red : Colors.orange.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                Text(
                  formatarMoeda(total),
                  style: TextStyle(
                    color: corPrimaria,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> carregarCliente() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) return null;

    final resposta = await Supabase.instance.client
        .from('clientes')
        .select()
        .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
        .eq('user_id', user.id)
        .maybeSingle();

    if (resposta == null) {
      return null;
    }

    return Map<String, dynamic>.from(resposta);
  }

  @override
  Widget build(BuildContext context) {
    final carrinho = context.watch<CarrinhoController>();

    return Scaffold(
      backgroundColor: corFundo,
      appBar: AppBar(
        leading: IconButton(
          onPressed: salvando ? null : voltarTela,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Finalizar pedido'),
        backgroundColor: corPrimaria,
        foregroundColor: Colors.white,
      ),
      body: carregandoConfiguracoes
          ? Center(child: CircularProgressIndicator(color: corPrimaria))
          : FutureBuilder<Map<String, dynamic>?>(
              future: carregarCliente(),
              builder: (context, snapshot) {
                final cliente = snapshot.data;

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  child: Column(
                    children: [
                      avisoEntregaUrbana(),
                      cardEntrega(cliente),
                      const SizedBox(height: 12),
                      Card(
                        elevation: 6,
                        shadowColor: AppTemaService.primaria.withValues(
                          alpha: 0.08,
                        ),
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(
                            color: AppTemaService.primaria.withValues(
                              alpha: 0.16,
                            ),
                            width: 1.6,
                          ),
                        ),
                        child: Column(
                          children: [
                            const Padding(
                              padding: EdgeInsets.all(14),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Forma de pagamento',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                  ),
                                ),
                              ),
                            ),
                            opcaoPagamento('Pix', Icons.pix),
                            opcaoPagamento('Dinheiro', Icons.payments),
                            if (formaPagamento == 'Dinheiro')
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  14,
                                ),
                                child: TextField(
                                  controller: trocoController,
                                  enabled: !salvando,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: InputDecoration(
                                    labelText: 'Troco para quanto?',
                                    hintText: 'Ex: 100,00',
                                    prefixIcon: Icon(
                                      Icons.attach_money,
                                      color: corPrimaria,
                                    ),
                                    filled: true,
                                    fillColor: corPrimariaMuitoSuave,
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(
                                        color: corPrimariaBorda,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(
                                        color: corPrimaria,
                                        width: 1.4,
                                      ),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                            opcaoPagamento(
                              'Cartão na entrega',
                              Icons.credit_card,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      cardCupomDesconto(carrinho.valorTotal),
                      const SizedBox(height: 10),
                      TextField(
                        controller: observacaoController,
                        enabled: !salvando,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Observação',
                          hintText: 'Ex: entregar no portão azul',
                          filled: true,
                          fillColor: corPrimariaMuitoSuave,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: corPrimariaBorda),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: corPrimaria,
                              width: 1.4,
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      cardResumoPedido(carrinho, cliente),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: salvando ? null : finalizarPedido,
                          icon: salvando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_circle),
                          label: const Text(
                            'Finalizar pedido',
                            style: TextStyle(fontSize: 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: corPrimaria,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

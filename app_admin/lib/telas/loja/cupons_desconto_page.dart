import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/central_service.dart';
import '../../services/sessao_loja.dart';

class CuponsDescontoPage extends StatefulWidget {
  const CuponsDescontoPage({super.key});

  @override
  State<CuponsDescontoPage> createState() => _CuponsDescontoPageState();
}

class _CuponsDescontoPageState extends State<CuponsDescontoPage> {
  final CentralService centralService = CentralService();

  bool carregando = true;
  bool salvando = false;
  String? erroCarregamento;

  List<Map<String, dynamic>> cupons = [];

  @override
  void initState() {
    super.initState();
    carregarCupons();
  }

  Future<void> carregarCupons() async {
    setState(() {
      carregando = true;
      erroCarregamento = null;
    });

    try {
      final resposta = await centralService.listarCuponsDesconto(
        mercadoId: SessaoLoja.mercadoIdObrigatorio,
      );

      if (!mounted) return;

      setState(() {
        cupons = resposta;
        erroCarregamento = null;
      });
    } catch (e) {
      if (!mounted) return;

      final mensagem = CentralService.mensagemErroUsuario(e);

      setState(() {
        erroCarregamento = mensagem;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Erro ao carregar cupons: $mensagem'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          carregando = false;
        });
      }
    }
  }

  double numero(dynamic valor) {
    if (valor == null) return 0;

    if (valor is num) return valor.toDouble();

    var texto = valor.toString().trim();

    if (texto.isEmpty) return 0;

    texto = texto.replaceAll('R\$', '').replaceAll('%', '').trim();

    if (texto.contains(',') && texto.contains('.')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    } else if (texto.contains(',')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    }

    return double.tryParse(texto) ?? 0;
  }

  int inteiro(dynamic valor) {
    if (valor == null) return 0;

    if (valor is num) return valor.round();

    final texto = valor.toString().replaceAll(RegExp(r'[^0-9]'), '');

    if (texto.isEmpty) return 0;

    return int.tryParse(texto) ?? 0;
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

  DateTime? dataCupom(dynamic valor) {
    if (valor == null) return null;

    if (valor is DateTime) return valor;

    return DateTime.tryParse(valor.toString());
  }

  String formatarMoeda(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String formatarValorCupom(Map<String, dynamic> cupom) {
    final tipo = cupom['tipo']?.toString() ?? 'valor';
    final valor = numero(cupom['valor']);

    if (tipo == 'percentual') {
      return '${valor.toStringAsFixed(2).replaceAll('.', ',')}%';
    }

    return formatarMoeda(valor);
  }

  String escopoCupom(Map<String, dynamic>? cupom) {
    final escopo = cupom?['escopo']?.toString().trim().toUpperCase() ?? '';
    return const {
          'GERAL',
          'PRODUTO',
          'CATEGORIA',
          'SUBCATEGORIA',
        }.contains(escopo)
        ? escopo
        : 'GERAL';
  }

  String nomeEscopo(String escopo) {
    switch (escopo) {
      case 'PRODUTO':
        return 'Produto específico';
      case 'CATEGORIA':
        return 'Categoria';
      case 'SUBCATEGORIA':
        return 'Subcategoria';
      default:
        return 'Pedido inteiro';
    }
  }

  Map<String, dynamic>? primeiroAlvo(Map<String, dynamic>? cupom) {
    final alvos = cupom?['cupom_desconto_alvos'];
    if (alvos is! List || alvos.isEmpty || alvos.first is! Map) return null;
    return Map<String, dynamic>.from(alvos.first as Map);
  }

  String valorAlvo(String escopo, Map<String, dynamic>? alvo) {
    if (alvo == null) return '';
    switch (escopo) {
      case 'PRODUTO':
        return (alvo['ean'] ??
                alvo['produto_id'] ??
                alvo['produto_app_id'] ??
                '')
            .toString();
      case 'CATEGORIA':
        return alvo['categoria']?.toString() ?? '';
      case 'SUBCATEGORIA':
        return alvo['subcategoria']?.toString() ?? '';
      default:
        return '';
    }
  }

  String formatarData(DateTime? data) {
    if (data == null) return 'Não definido';

    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');

    return '$dia/$mes/${data.year}';
  }

  String formatarPeriodo(Map<String, dynamic> cupom) {
    final inicio = dataCupom(cupom['data_inicio']);
    final fim = dataCupom(cupom['data_fim']);

    if (inicio == null && fim == null) {
      return 'Sem período definido';
    }

    if (inicio != null && fim == null) {
      return 'A partir de ${formatarData(inicio)}';
    }

    if (inicio == null && fim != null) {
      return 'Até ${formatarData(fim)}';
    }

    return '${formatarData(inicio)} até ${formatarData(fim)}';
  }

  String isoInicioDia(DateTime? data) {
    if (data == null) return '';

    return DateTime(data.year, data.month, data.day).toIso8601String();
  }

  String isoFimDia(DateTime? data) {
    if (data == null) return '';

    return DateTime(
      data.year,
      data.month,
      data.day,
      23,
      59,
      59,
    ).toIso8601String();
  }

  Future<void> alternarAtivo(Map<String, dynamic> cupom, bool ativo) async {
    final id = cupom['id'];

    if (id == null) return;

    try {
      await centralService.alternarCupomDesconto(
        mercadoId: SessaoLoja.mercadoIdObrigatorio,
        cupomId: id.toString(),
        ativo: ativo,
      );

      await carregarCupons();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            'Erro ao alterar cupom: ${CentralService.mensagemErroUsuario(e)}',
          ),
        ),
      );
    }
  }

  Future<void> excluirCupom(Map<String, dynamic> cupom) async {
    final id = cupom['id'];

    if (id == null) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Excluir cupom'),
          content: Text('Deseja excluir o cupom ${cupom['codigo'] ?? ''}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    try {
      await centralService.excluirCupomDesconto(
        mercadoId: SessaoLoja.mercadoIdObrigatorio,
        cupomId: id.toString(),
      );

      await carregarCupons();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cupom excluído com sucesso.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            'Erro ao excluir cupom: ${CentralService.mensagemErroUsuario(e)}',
          ),
        ),
      );
    }
  }

  Future<void> abrirFormularioCupom({Map<String, dynamic>? cupom}) async {
    final editando = cupom != null;
    String escopo = escopoCupom(cupom);
    final alvoSalvo = primeiroAlvo(cupom);

    final codigoController = TextEditingController(
      text: cupom?['codigo']?.toString() ?? '',
    );
    final descricaoController = TextEditingController(
      text: cupom?['descricao']?.toString() ?? '',
    );
    final valorController = TextEditingController(
      text: cupom == null
          ? ''
          : numero(cupom['valor']).toStringAsFixed(2).replaceAll('.', ','),
    );
    final valorMinimoController = TextEditingController(
      text: cupom == null
          ? ''
          : numero(
              cupom['valor_minimo'],
            ).toStringAsFixed(2).replaceAll('.', ','),
    );
    final limiteUsoController = TextEditingController(
      text: cupom == null || inteiro(cupom['limite_uso']) == 0
          ? ''
          : inteiro(cupom['limite_uso']).toString(),
    );
    final quantidadeMinimaController = TextEditingController(
      text: cupom == null || numero(cupom['quantidade_minima']) == 0
          ? ''
          : numero(cupom['quantidade_minima'])
                .toStringAsFixed(3)
                .replaceFirst(RegExp(r'0+$'), '')
                .replaceFirst(RegExp(r'\.$'), '')
                .replaceAll('.', ','),
    );
    final alvoController = TextEditingController(
      text: valorAlvo(escopo, alvoSalvo),
    );
    final nomeProdutoController = TextEditingController(
      text: alvoSalvo?['nome_produto']?.toString() ?? '',
    );

    String tipo = cupom?['tipo']?.toString() == 'percentual'
        ? 'percentual'
        : 'valor';
    bool ativo = valorBool(cupom?['ativo'], true);
    bool usoUnicoPorCliente = valorBool(cupom?['uso_unico_por_cliente'], false);
    bool somentePrimeiraCompra = valorBool(
      cupom?['somente_primeira_compra'],
      false,
    );
    DateTime? dataInicio = dataCupom(cupom?['data_inicio']);
    DateTime? dataFim = dataCupom(cupom?['data_fim']);

    bool salvandoFormulario = false;
    String? erroFormulario;

    final salvou = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void mostrarErro(String mensagem) {
              setDialogState(() {
                erroFormulario = mensagem;
              });
            }

            Future<void> selecionarData({required bool inicio}) async {
              final atual = inicio ? dataInicio : dataFim;

              final selecionada = await showDatePicker(
                context: dialogContext,
                initialDate: atual ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );

              if (selecionada == null) return;

              setDialogState(() {
                if (inicio) {
                  dataInicio = selecionada;
                } else {
                  dataFim = selecionada;
                }

                erroFormulario = null;
              });
            }

            Future<void> salvarCupom() async {
              final codigo = codigoController.text.trim().toUpperCase();
              final descricao = descricaoController.text.trim();
              final valor = numero(valorController.text);
              final valorMinimo = numero(valorMinimoController.text);
              final limiteUso = inteiro(limiteUsoController.text);
              final quantidadeMinima = numero(quantidadeMinimaController.text);
              final alvoInformado = alvoController.text.trim();

              if (codigo.isEmpty) {
                mostrarErro('Informe o código do cupom.');
                return;
              }

              if (valor <= 0) {
                mostrarErro('Informe o valor do desconto.');
                return;
              }

              if (tipo == 'percentual' && valor > 100) {
                mostrarErro('O percentual não pode ser maior que 100%.');
                return;
              }

              if (dataInicio != null &&
                  dataFim != null &&
                  dataFim!.isBefore(dataInicio!)) {
                mostrarErro('A data final não pode ser menor que a inicial.');
                return;
              }

              if (escopo != 'GERAL' && alvoInformado.isEmpty) {
                mostrarErro(
                  escopo == 'PRODUTO'
                      ? 'Informe o EAN ou código do produto.'
                      : 'Informe a ${nomeEscopo(escopo).toLowerCase()}.',
                );
                return;
              }

              setDialogState(() {
                salvandoFormulario = true;
                erroFormulario = null;
              });

              final dados = <String, dynamic>{
                ...SessaoLoja.dadosMercadoRegistro,
                'codigo': codigo,
                'descricao': descricao.isEmpty ? null : descricao,
                'tipo': tipo,
                'valor': valor,
                'valor_minimo': valorMinimo,
                'quantidade_minima': quantidadeMinima,
                'escopo': escopo,
                'data_inicio': dataInicio == null
                    ? null
                    : isoInicioDia(dataInicio),
                'data_fim': dataFim == null ? null : isoFimDia(dataFim),
                'limite_uso': limiteUso,
                'uso_unico_por_cliente': usoUnicoPorCliente,
                'somente_primeira_compra': somentePrimeiraCompra,
                'ativo': ativo,
              };

              if (editando) dados['id'] = cupom['id'];

              final alvos = <Map<String, dynamic>>[];
              if (escopo == 'PRODUTO') {
                alvos.add({
                  'produto_id': alvoInformado,
                  'produto_app_id': alvoInformado,
                  'ean': alvoInformado,
                  'nome_produto': nomeProdutoController.text.trim(),
                });
              } else if (escopo == 'CATEGORIA') {
                alvos.add({'categoria': alvoInformado});
              } else if (escopo == 'SUBCATEGORIA') {
                alvos.add({'subcategoria': alvoInformado});
              }

              try {
                await centralService.salvarCupomDesconto(
                  mercadoId: SessaoLoja.mercadoIdObrigatorio,
                  cupom: dados,
                  alvos: alvos,
                );

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (e) {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    erroFormulario =
                        'Erro ao salvar cupom: ${CentralService.mensagemErroUsuario(e)}';
                  });
                }
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    salvandoFormulario = false;
                  });
                }
              }
            }

            return AlertDialog(
              title: Text(editando ? 'Editar cupom' : 'Novo cupom'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width > 520
                      ? 480
                      : double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: codigoController,
                        enabled: !salvandoFormulario,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9_-]'),
                          ),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Código do cupom',
                          hintText: 'Ex: PROMO10',
                          prefixIcon: const Icon(Icons.confirmation_number),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: descricaoController,
                        enabled: !salvandoFormulario,
                        decoration: InputDecoration(
                          labelText: 'Descrição',
                          hintText: 'Ex: Desconto de inauguração',
                          prefixIcon: const Icon(Icons.description_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: tipo,
                        decoration: InputDecoration(
                          labelText: 'Tipo de desconto',
                          prefixIcon: const Icon(Icons.discount_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'valor',
                            child: Text('Valor fixo em R\$'),
                          ),
                          DropdownMenuItem(
                            value: 'percentual',
                            child: Text('Porcentagem %'),
                          ),
                        ],
                        onChanged: salvandoFormulario
                            ? null
                            : (value) {
                                if (value == null) return;

                                setDialogState(() {
                                  tipo = value;
                                  erroFormulario = null;
                                });
                              },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: escopo,
                        decoration: InputDecoration(
                          labelText: 'Aplicar desconto em',
                          prefixIcon: const Icon(Icons.filter_alt_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'GERAL',
                            child: Text('Pedido inteiro'),
                          ),
                          DropdownMenuItem(
                            value: 'PRODUTO',
                            child: Text('Produto específico'),
                          ),
                          DropdownMenuItem(
                            value: 'CATEGORIA',
                            child: Text('Categoria'),
                          ),
                          DropdownMenuItem(
                            value: 'SUBCATEGORIA',
                            child: Text('Subcategoria'),
                          ),
                        ],
                        onChanged: salvandoFormulario
                            ? null
                            : (value) {
                                if (value == null) return;
                                setDialogState(() {
                                  escopo = value;
                                  alvoController.clear();
                                  nomeProdutoController.clear();
                                  erroFormulario = null;
                                });
                              },
                      ),
                      if (escopo != 'GERAL') ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: alvoController,
                          enabled: !salvandoFormulario,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: escopo == 'PRODUTO'
                                ? 'EAN ou código do produto'
                                : nomeEscopo(escopo),
                            hintText: escopo == 'PRODUTO'
                                ? 'Leia ou digite o código'
                                : escopo == 'CATEGORIA'
                                ? 'Ex: Bebidas'
                                : 'Ex: Refrigerantes',
                            prefixIcon: Icon(
                              escopo == 'PRODUTO'
                                  ? Icons.qr_code
                                  : Icons.category_outlined,
                            ),
                            helperText: escopo == 'PRODUTO'
                                ? 'O cupom valerá somente para este produto.'
                                : 'Use o mesmo nome recebido no cadastro do produto.',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        if (escopo == 'PRODUTO') ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: nomeProdutoController,
                            enabled: !salvandoFormulario,
                            decoration: InputDecoration(
                              labelText: 'Nome do produto (opcional)',
                              prefixIcon: const Icon(
                                Icons.shopping_basket_outlined,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 10),
                      TextField(
                        controller: valorController,
                        enabled: !salvandoFormulario,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                        ],
                        decoration: InputDecoration(
                          labelText: tipo == 'percentual'
                              ? 'Percentual do desconto'
                              : 'Valor do desconto',
                          hintText: tipo == 'percentual'
                              ? 'Ex: 10'
                              : 'Ex: 10,00',
                          prefixIcon: Icon(
                            tipo == 'percentual'
                                ? Icons.percent
                                : Icons.attach_money,
                          ),
                          suffixText: tipo == 'percentual' ? '%' : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: valorMinimoController,
                        enabled: !salvandoFormulario,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                        ],
                        decoration: InputDecoration(
                          labelText: escopo == 'GERAL'
                              ? 'Valor mínimo do pedido'
                              : 'Valor mínimo dos itens elegíveis',
                          hintText: 'Ex: 50,00',
                          prefixIcon: const Icon(Icons.shopping_cart_outlined),
                          helperText:
                              'Deixe vazio ou 0 para não exigir mínimo.',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: quantidadeMinimaController,
                        enabled: !salvandoFormulario,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Quantidade mínima elegível',
                          hintText: escopo == 'GERAL'
                              ? 'Ex: 3 itens'
                              : 'Ex: 3 da categoria ou produto',
                          prefixIcon: const Icon(
                            Icons.production_quantity_limits,
                          ),
                          helperText:
                              'Deixe vazio ou 0 para não exigir quantidade mínima.',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: limiteUsoController,
                        enabled: !salvandoFormulario,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: 'Limite de uso',
                          hintText: 'Ex: 100',
                          prefixIcon: const Icon(Icons.numbers),
                          helperText: 'Deixe vazio ou 0 para uso ilimitado.',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: usoUnicoPorCliente,
                        title: const Text('Uso único por cliente'),
                        subtitle: const Text(
                          'Cada cliente poderá usar este cupom somente uma vez.',
                        ),
                        onChanged: salvandoFormulario
                            ? null
                            : (value) {
                                setDialogState(() {
                                  usoUnicoPorCliente = value;
                                  erroFormulario = null;
                                });
                              },
                      ),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: somentePrimeiraCompra,
                        title: const Text('Somente na primeira compra'),
                        subtitle: const Text(
                          'O cliente não poderá usar este cupom após já ter feito um pedido.',
                        ),
                        onChanged: salvandoFormulario
                            ? null
                            : (value) {
                                setDialogState(() {
                                  somentePrimeiraCompra = value;
                                  erroFormulario = null;
                                });
                              },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: salvandoFormulario
                                  ? null
                                  : () => selecionarData(inicio: true),
                              icon: const Icon(Icons.event_available),
                              label: Text(
                                'Início: ${formatarData(dataInicio)}',
                              ),
                            ),
                          ),
                          if (dataInicio != null)
                            IconButton(
                              onPressed: salvandoFormulario
                                  ? null
                                  : () {
                                      setDialogState(() {
                                        dataInicio = null;
                                        erroFormulario = null;
                                      });
                                    },
                              icon: const Icon(Icons.close),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: salvandoFormulario
                                  ? null
                                  : () => selecionarData(inicio: false),
                              icon: const Icon(Icons.event_busy),
                              label: Text('Fim: ${formatarData(dataFim)}'),
                            ),
                          ),
                          if (dataFim != null)
                            IconButton(
                              onPressed: salvandoFormulario
                                  ? null
                                  : () {
                                      setDialogState(() {
                                        dataFim = null;
                                        erroFormulario = null;
                                      });
                                    },
                              icon: const Icon(Icons.close),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: ativo,
                        title: const Text('Cupom ativo'),
                        subtitle: const Text(
                          'Quando ativo, o cliente consegue usar no pedido.',
                        ),
                        onChanged: salvandoFormulario
                            ? null
                            : (value) {
                                setDialogState(() {
                                  ativo = value;
                                  erroFormulario = null;
                                });
                              },
                      ),
                      if (erroFormulario != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.red.withOpacity(0.25),
                            ),
                          ),
                          child: Text(
                            erroFormulario!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: salvandoFormulario
                      ? null
                      : () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: salvandoFormulario ? null : salvarCupom,
                  icon: salvandoFormulario
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(salvandoFormulario ? 'Salvando...' : 'Salvar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SessaoLoja.corPrimaria,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    codigoController.dispose();
    descricaoController.dispose();
    valorController.dispose();
    valorMinimoController.dispose();
    limiteUsoController.dispose();
    quantidadeMinimaController.dispose();
    alvoController.dispose();
    nomeProdutoController.dispose();

    if (salvou == true) {
      await carregarCupons();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            editando
                ? 'Cupom atualizado com sucesso.'
                : 'Cupom cadastrado com sucesso.',
          ),
        ),
      );
    }
  }

  Widget chipStatus(bool ativo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ativo ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        ativo ? 'Ativo' : 'Inativo',
        style: TextStyle(
          color: ativo ? Colors.green.shade800 : Colors.red.shade700,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget cardCupom(Map<String, dynamic> cupom) {
    final ativo = valorBool(cupom['ativo'], true);
    final escopo = escopoCupom(cupom);
    final alvo = primeiroAlvo(cupom);
    final alvoResumo = valorAlvo(escopo, alvo);
    final tipo = cupom['tipo']?.toString() == 'percentual'
        ? 'Porcentagem'
        : 'Valor fixo';
    final valorMinimo = numero(cupom['valor_minimo']);
    final quantidadeMinima = numero(cupom['quantidade_minima']);
    final limiteUso = inteiro(cupom['limite_uso']);
    final quantidadeUsada = inteiro(cupom['quantidade_usada']);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: SessaoLoja.corPrimaria.withValues(
                    alpha: 0.10,
                  ),
                  child: Icon(Icons.local_offer, color: SessaoLoja.corPrimaria),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    cupom['codigo']?.toString() ?? '',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                chipStatus(ativo),
              ],
            ),
            if ((cupom['descricao']?.toString().trim().isNotEmpty ??
                false)) ...[
              const SizedBox(height: 8),
              Text(
                cupom['descricao'].toString(),
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _miniInfo(
                  icon: Icons.discount_outlined,
                  label: tipo,
                  valor: formatarValorCupom(cupom),
                ),
                _miniInfo(
                  icon: Icons.filter_alt_outlined,
                  label: 'Aplicação',
                  valor: nomeEscopo(escopo),
                ),
                if (escopo != 'GERAL')
                  _miniInfo(
                    icon: escopo == 'PRODUTO'
                        ? Icons.qr_code
                        : Icons.category_outlined,
                    label: nomeEscopo(escopo),
                    valor: alvoResumo.isEmpty ? 'Não informado' : alvoResumo,
                  ),
                _miniInfo(
                  icon: Icons.shopping_basket_outlined,
                  label: escopo == 'GERAL'
                      ? 'Mínimo do pedido'
                      : 'Mínimo elegível',
                  valor: valorMinimo > 0
                      ? formatarMoeda(valorMinimo)
                      : 'Sem mínimo',
                ),
                if (quantidadeMinima > 0)
                  _miniInfo(
                    icon: Icons.production_quantity_limits,
                    label: 'Quantidade mínima',
                    valor: quantidadeMinima
                        .toStringAsFixed(3)
                        .replaceFirst(RegExp(r'0+$'), '')
                        .replaceFirst(RegExp(r'\.$'), ''),
                  ),
                _miniInfo(
                  icon: Icons.repeat,
                  label: 'Uso',
                  valor: limiteUso > 0
                      ? '$quantidadeUsada / $limiteUso'
                      : '$quantidadeUsada / ilimitado',
                ),
                if (valorBool(cupom['uso_unico_por_cliente'], false))
                  _miniInfo(
                    icon: Icons.person_outline,
                    label: 'Por cliente',
                    valor: 'Uma vez',
                  ),
                if (valorBool(cupom['somente_primeira_compra'], false))
                  _miniInfo(
                    icon: Icons.shopping_cart_checkout_outlined,
                    label: 'Disponível em',
                    valor: 'Primeira compra',
                  ),
                _miniInfo(
                  icon: Icons.calendar_month_outlined,
                  label: 'Período',
                  valor: formatarPeriodo(cupom),
                ),
              ],
            ),
            const Divider(height: 22),
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: ativo,
                    title: Text(
                      ativo ? 'Cupom liberado' : 'Cupom bloqueado',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    onChanged: salvando
                        ? null
                        : (value) => alternarAtivo(cupom, value),
                  ),
                ),
                IconButton(
                  tooltip: 'Editar',
                  onPressed: salvando
                      ? null
                      : () => abrirFormularioCupom(cupom: cupom),
                  icon: const Icon(Icons.edit),
                ),
                IconButton(
                  tooltip: 'Excluir',
                  onPressed: salvando ? null : () => excluirCupom(cupom),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniInfo({
    required IconData icon,
    required String label,
    required String valor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F9),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: Colors.black54),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.black54, fontSize: 11),
              ),
              Text(
                valor,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget estadoVazio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.local_offer_outlined,
              color: Colors.grey.shade400,
              size: 72,
            ),
            const SizedBox(height: 12),
            const Text(
              'Nenhum cupom cadastrado',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 6),
            const Text(
              'Toque no botão abaixo para criar um cupom de valor fixo ou porcentagem.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => abrirFormularioCupom(),
              icon: const Icon(Icons.add),
              label: const Text('Criar primeiro cupom'),
              style: ElevatedButton.styleFrom(
                backgroundColor: SessaoLoja.corPrimaria,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget estadoErro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              color: Colors.red.shade300,
              size: 68,
            ),
            const SizedBox(height: 14),
            const Text(
              'Nao foi possivel carregar os cupons',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 7),
            Text(
              erroCarregamento ?? 'Tente novamente.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: carregarCupons,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
              style: ElevatedButton.styleFrom(
                backgroundColor: SessaoLoja.corPrimaria,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SessaoLoja.corFundo,
      appBar: AppBar(
        title: const Text('Cupons de desconto'),
        backgroundColor: SessaoLoja.corPrimaria,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: carregarCupons,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : erroCarregamento != null && cupons.isEmpty
          ? estadoErro()
          : cupons.isEmpty
          ? estadoVazio()
          : RefreshIndicator(
              onRefresh: carregarCupons,
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 8, bottom: 90),
                itemCount: cupons.length,
                itemBuilder: (context, index) {
                  return cardCupom(cupons[index]);
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => abrirFormularioCupom(),
        backgroundColor: SessaoLoja.corPrimaria,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Novo cupom'),
      ),
    );
  }
}

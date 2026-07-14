import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main_navigation_page.dart';
import '../services/app_tema_service.dart';
import '../services/sessao_mercado_cliente.dart' as sessao;

class CompletarCadastroPage extends StatefulWidget {
  const CompletarCadastroPage({super.key});

  @override
  State<CompletarCadastroPage> createState() => _CompletarCadastroPageState();
}

class _CompletarCadastroPageState extends State<CompletarCadastroPage> {
  Color get corPrimaria => AppTemaService.primaria;
  Color get corSecundaria => AppTemaService.secundaria;
  Color get corFundo => AppTemaService.fundo;
  static const Color corTexto = Color(0xFF241F20);

  final nomeController = TextEditingController();
  final telefoneController = TextEditingController();
  final dataNascimentoController = TextEditingController();
  final enderecoController = TextEditingController();
  final numeroController = TextEditingController();
  final bairroController = TextEditingController();
  final cidadeController = TextEditingController();
  final referenciaController = TextEditingController();

  bool salvando = false;
  String? estadoSelecionado;

  static const List<Map<String, String>> estadosBrasil = [
    {'uf': 'AC', 'nome': 'Acre'},
    {'uf': 'AL', 'nome': 'Alagoas'},
    {'uf': 'AP', 'nome': 'Amapá'},
    {'uf': 'AM', 'nome': 'Amazonas'},
    {'uf': 'BA', 'nome': 'Bahia'},
    {'uf': 'CE', 'nome': 'Ceará'},
    {'uf': 'DF', 'nome': 'Distrito Federal'},
    {'uf': 'ES', 'nome': 'Espírito Santo'},
    {'uf': 'GO', 'nome': 'Goiás'},
    {'uf': 'MA', 'nome': 'Maranhão'},
    {'uf': 'MT', 'nome': 'Mato Grosso'},
    {'uf': 'MS', 'nome': 'Mato Grosso do Sul'},
    {'uf': 'MG', 'nome': 'Minas Gerais'},
    {'uf': 'PA', 'nome': 'Pará'},
    {'uf': 'PB', 'nome': 'Paraíba'},
    {'uf': 'PR', 'nome': 'Paraná'},
    {'uf': 'PE', 'nome': 'Pernambuco'},
    {'uf': 'PI', 'nome': 'Piauí'},
    {'uf': 'RJ', 'nome': 'Rio de Janeiro'},
    {'uf': 'RN', 'nome': 'Rio Grande do Norte'},
    {'uf': 'RS', 'nome': 'Rio Grande do Sul'},
    {'uf': 'RO', 'nome': 'Rondônia'},
    {'uf': 'RR', 'nome': 'Roraima'},
    {'uf': 'SC', 'nome': 'Santa Catarina'},
    {'uf': 'SP', 'nome': 'São Paulo'},
    {'uf': 'SE', 'nome': 'Sergipe'},
    {'uf': 'TO', 'nome': 'Tocantins'},
  ];

  @override
  void initState() {
    super.initState();

    final user = Supabase.instance.client.auth.currentUser;
    nomeController.text = user?.userMetadata?['full_name']?.toString() ?? '';
  }

  @override
  void dispose() {
    nomeController.dispose();
    telefoneController.dispose();
    dataNascimentoController.dispose();
    enderecoController.dispose();
    numeroController.dispose();
    bairroController.dispose();
    cidadeController.dispose();
    referenciaController.dispose();
    super.dispose();
  }

  String somenteNumeros(String valor) {
    return valor.replaceAll(RegExp(r'[^0-9]'), '');
  }

  DateTime? converterDataNascimento(String valor) {
    final numeros = somenteNumeros(valor);

    if (numeros.length != 8) return null;

    final dia = int.tryParse(numeros.substring(0, 2));
    final mes = int.tryParse(numeros.substring(2, 4));
    final ano = int.tryParse(numeros.substring(4, 8));

    if (dia == null || mes == null || ano == null) return null;

    try {
      final data = DateTime(ano, mes, dia);

      if (data.day != dia || data.month != mes || data.year != ano) {
        return null;
      }

      final hoje = DateTime.now();
      if (data.isAfter(DateTime(hoje.year, hoje.month, hoje.day))) {
        return null;
      }

      return data;
    } catch (_) {
      return null;
    }
  }

  String formatarDataParaBanco(DateTime data) {
    final mes = data.month.toString().padLeft(2, '0');
    final dia = data.day.toString().padLeft(2, '0');
    return '${data.year}-$mes-$dia';
  }

  Future<void> salvarCadastro() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) return;

    final dataNascimento = converterDataNascimento(
      dataNascimentoController.text,
    );

    if (nomeController.text.trim().isEmpty ||
        telefoneController.text.trim().isEmpty ||
        dataNascimentoController.text.trim().isEmpty ||
        dataNascimento == null ||
        enderecoController.text.trim().isEmpty ||
        numeroController.text.trim().isEmpty ||
        bairroController.text.trim().isEmpty ||
        cidadeController.text.trim().isEmpty ||
        estadoSelecionado == null ||
        estadoSelecionado!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Preencha todos os campos obrigatórios corretamente'),
        ),
      );
      return;
    }

    setState(() {
      salvando = true;
    });

    try {
      final clienteExistente = await Supabase.instance.client
          .from('clientes')
          .select('id')
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .eq('user_id', user.id)
          .maybeSingle();

      final dadosCliente = sessao.SessaoMercadoCliente.dadosComMercado({
        'user_id': user.id,
        'nome': nomeController.text.trim(),
        'email': user.email,
        'telefone': telefoneController.text.trim(),
        'data_nascimento': formatarDataParaBanco(dataNascimento),
        'endereco': enderecoController.text.trim(),
        'numero': numeroController.text.trim(),
        'bairro': bairroController.text.trim(),
        'cidade': cidadeController.text.trim(),
        'estado': estadoSelecionado,
        'referencia': referenciaController.text.trim(),
      });

      if (clienteExistente != null) {
        await Supabase.instance.client
            .from('clientes')
            .update(dadosCliente)
            .eq('id', clienteExistente['id'])
            .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio);
      } else {
        await Supabase.instance.client.from('clientes').insert(dadosCliente);
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const MainNavigationPage(),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar cadastro: $e'),
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

  InputDecoration decoracaoCampo({
    required String label,
    required IconData icon,
    bool obrigatorio = true,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: obrigatorio ? '$label *' : label,
      hintText: hintText,
      prefixIcon: Icon(icon, color: const Color(0xFF6D4C4C)),
      labelStyle: TextStyle(
        color: Color(0xFF7A6161),
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(color: Color(0xFFB5A6A6)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Color(0xFFE2D6D6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: corPrimaria, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.redAccent, width: 1.6),
      ),
    );
  }

  Widget campo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType tipo = TextInputType.text,
    bool obrigatorio = true,
    List<TextInputFormatter>? inputFormatters,
    String? hintText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        keyboardType: tipo,
        inputFormatters: inputFormatters,
        textInputAction: TextInputAction.next,
        style: TextStyle(
          color: corTexto,
          fontWeight: FontWeight.w600,
        ),
        decoration: decoracaoCampo(
          label: label,
          icon: icon,
          obrigatorio: obrigatorio,
          hintText: hintText,
        ),
      ),
    );
  }

  Future<void> abrirSeletorEstado() async {
    if (salvando) return;

    final selecionado = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppTemaService.primaria.withValues(alpha: 0.16), width: 1.6),
              boxShadow: [
                BoxShadow(
                  color: AppTemaService.primaria.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2D6D6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                SizedBox(height: 14),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Icon(Icons.public, color: corPrimaria),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Selecione o estado',
                          style: TextStyle(
                            color: corTexto,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 10),
                Divider(height: 1, color: Color(0xFFF0E8E8)),
                SizedBox(
                  height: 5 * 58,
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: estadosBrasil.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: Color(0xFFF4EEEE),
                      ),
                      itemBuilder: (context, index) {
                        final estado = estadosBrasil[index];
                        final uf = estado['uf']!;
                        final nome = estado['nome']!;
                        final ativo = estadoSelecionado == uf;

                        return ListTile(
                          dense: false,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 2,
                          ),
                          leading: Container(
                            width: 42,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: ativo ? corPrimaria : corFundo,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              uf,
                              style: TextStyle(
                                color: ativo ? Colors.white : corPrimaria,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          title: Text(
                            nome,
                            style: TextStyle(
                              color: corTexto,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          trailing: ativo
                              ? Icon(
                                  Icons.check_circle,
                                  color: corPrimaria,
                                )
                              : null,
                          onTap: () => Navigator.pop(context, uf),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selecionado == null || !mounted) return;

    setState(() {
      estadoSelecionado = selecionado;
    });
  }

  Widget campoEstado() {
    Map<String, String>? estado;
    for (final item in estadosBrasil) {
      if (item['uf'] == estadoSelecionado) {
        estado = item;
        break;
      }
    }

    final textoSelecionado = estado == null
        ? 'Selecione o estado'
        : '${estado['uf']} - ${estado['nome']}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: abrirSeletorEstado,
        child: InputDecorator(
          decoration: decoracaoCampo(
            label: 'Estado',
            icon: Icons.public,
          ).copyWith(
            suffixIcon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF7A6161),
            ),
          ),
          child: Text(
            textoSelecionado,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: estadoSelecionado == null ? const Color(0xFFB5A6A6) : corTexto,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }


  Future<void> voltarTelaAnterior() async {
    if (salvando) {
      return;
    }

    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      return;
    }

    await Supabase.instance.client.auth.signOut();
  }

  Widget cabecalho() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 34),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [corPrimaria, corSecundaria],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(34),
          bottomRight: Radius.circular(34),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InkWell(
                  onTap: salvando ? null : voltarTelaAnterior,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Icon(
                    Icons.person_add_alt_1,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Complete seu cadastro',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Precisamos desses dados para entregar seu pedido.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget formulario() {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 22),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dados pessoais',
            style: TextStyle(
              color: corTexto,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 14),
          campo(
            controller: nomeController,
            label: 'Nome',
            icon: Icons.person,
            tipo: TextInputType.name,
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'[0-9]')),
            ],
          ),
          campo(
            controller: telefoneController,
            label: 'Telefone',
            icon: Icons.phone,
            tipo: TextInputType.phone,
            hintText: '(00) 00000-0000',
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(11),
              TelefoneInputFormatter(),
            ],
          ),
          campo(
            controller: dataNascimentoController,
            label: 'Data de nascimento',
            icon: Icons.cake,
            tipo: TextInputType.number,
            hintText: 'dd/mm/aaaa',
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
              DataNascimentoInputFormatter(),
            ],
          ),
          SizedBox(height: 6),
          Text(
            'Endereço de entrega',
            style: TextStyle(
              color: corTexto,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 14),
          campo(
            controller: enderecoController,
            label: 'Endereço',
            icon: Icons.location_on,
          ),
          campo(
            controller: numeroController,
            label: 'Número',
            icon: Icons.home,
            tipo: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
          ),
          campo(
            controller: bairroController,
            label: 'Bairro',
            icon: Icons.map,
          ),
          campo(
            controller: cidadeController,
            label: 'Cidade',
            icon: Icons.location_city,
          ),
          campoEstado(),
          campo(
            controller: referenciaController,
            label: 'Referência',
            icon: Icons.info_outline,
            obrigatorio: false,
            hintText: 'Ponto de referência ou complemento',
          ),
          SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: salvando ? null : salvarCadastro,
              style: ElevatedButton.styleFrom(
                backgroundColor: corPrimaria,
                foregroundColor: Colors.white,
                elevation: 8,
                shadowColor: corPrimaria.withValues(alpha: 0.28),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: salvando
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      'Salvar cadastro',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
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
    return Scaffold(
      backgroundColor: corFundo,
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          children: [
            cabecalho(),
            Transform.translate(
              offset: const Offset(0, -22),
              child: formulario(),
            ),
          ],
        ),
      ),
    );
  }
}

class TelefoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final numeros = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buffer = StringBuffer();

    for (var i = 0; i < numeros.length && i < 11; i++) {
      if (i == 0) buffer.write('(');
      if (i == 2) buffer.write(') ');
      if (i == 7) buffer.write('-');
      buffer.write(numeros[i]);
    }

    final texto = buffer.toString();

    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

class DataNascimentoInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final numeros = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buffer = StringBuffer();

    for (var i = 0; i < numeros.length && i < 8; i++) {
      if (i == 2 || i == 4) buffer.write('/');
      buffer.write(numeros[i]);
    }

    final texto = buffer.toString();

    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

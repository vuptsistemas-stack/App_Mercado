import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/sessao_mercado_cliente.dart' as sessao;
import 'main_navigation_page.dart';
import '../services/app_tema_service.dart';

class CadastroClientePage extends StatefulWidget {
  const CadastroClientePage({super.key});

  @override
  State<CadastroClientePage> createState() => _CadastroClientePageState();
}

class _CadastroClientePageState extends State<CadastroClientePage> {
  static const Color vermelhoPadrao = Color(0xFFE30613);
  static const Color fundoPadrao = Color(0xFFFFF7F7);
  static const Color textoEscuro = Color(0xFF1F2937);

  final nomeController = TextEditingController();
  final emailController = TextEditingController();
  final senhaController = TextEditingController();
  final confirmarSenhaController = TextEditingController();
  final telefoneController = TextEditingController();
  final dataNascimentoController = TextEditingController();
  final enderecoController = TextEditingController();
  final numeroController = TextEditingController();
  final bairroController = TextEditingController();
  final cidadeController = TextEditingController();
  final referenciaController = TextEditingController();

  bool salvando = false;
  bool senhaVisivel = false;
  bool confirmarSenhaVisivel = false;
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

  Color corHex(String valor, Color padrao) {
    var texto = valor.trim();

    if (texto.isEmpty) {
      return padrao;
    }

    if (texto.startsWith('#')) {
      texto = texto.substring(1);
    }

    if (texto.length == 6) {
      texto = 'FF$texto';
    }

    final numero = int.tryParse(texto, radix: 16);

    if (numero == null) {
      return padrao;
    }

    return Color(numero);
  }

  Color get corPrimaria => corHex(
        sessao.SessaoMercadoCliente.clienteCorPrimaria,
        vermelhoPadrao,
      );

  Color get corFundo => corHex(
        sessao.SessaoMercadoCliente.clienteCorFundo,
        fundoPadrao,
      );

  String somenteNumeros(String valor) {
    return valor.replaceAll(RegExp(r'[^0-9]'), '');
  }

  DateTime? converterDataNascimento(String valor) {
    final numeros = somenteNumeros(valor);

    if (numeros.length != 8) {
      return null;
    }

    final dia = int.tryParse(numeros.substring(0, 2));
    final mes = int.tryParse(numeros.substring(2, 4));
    final ano = int.tryParse(numeros.substring(4, 8));

    if (dia == null || mes == null || ano == null) {
      return null;
    }

    if (ano < 1900 || ano > DateTime.now().year) {
      return null;
    }

    try {
      final data = DateTime(ano, mes, dia);

      if (data.day != dia || data.month != mes || data.year != ano) {
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

  @override
  void dispose() {
    nomeController.dispose();
    emailController.dispose();
    senhaController.dispose();
    confirmarSenhaController.dispose();
    telefoneController.dispose();
    dataNascimentoController.dispose();
    enderecoController.dispose();
    numeroController.dispose();
    bairroController.dispose();
    cidadeController.dispose();
    referenciaController.dispose();
    super.dispose();
  }

  void mostrarMensagem(String texto, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: erro ? Colors.red : const Color(0xFF0F9D58),
      ),
    );
  }

  Future<void> abrirSeletorEstado() async {
    if (salvando) {
      return;
    }

    final selecionado = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          constraints: const BoxConstraints(
            maxHeight: 430,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(28),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.13),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Selecione o estado',
                  style: TextStyle(
                    color: textoEscuro,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    itemCount: estadosBrasil.length,
                    itemBuilder: (context, index) {
                      final estado = estadosBrasil[index];
                      final uf = estado['uf']!;
                      final nome = estado['nome']!;
                      final ativo = estadoSelecionado == uf;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: ativo
                              ? corPrimaria.withOpacity(0.10)
                              : const Color(0xFFF8F8F8),
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.pop(context, uf),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: ativo
                                          ? corPrimaria
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: ativo
                                            ? corPrimaria
                                            : Colors.black.withOpacity(0.08),
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        uf,
                                        style: TextStyle(
                                          color: ativo
                                              ? Colors.white
                                              : corPrimaria,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      nome,
                                      style: const TextStyle(
                                        color: textoEscuro,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  if (ativo)
                                    Icon(
                                      Icons.check_circle,
                                      color: corPrimaria,
                                    ),
                                ],
                              ),
                            ),
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

    if (selecionado == null) {
      return;
    }

    setState(() {
      estadoSelecionado = selecionado;
    });
  }

  Future<void> cadastrarCliente() async {
    if (salvando) {
      return;
    }

    final nome = nomeController.text.trim();
    final email = emailController.text.trim();
    final senha = senhaController.text.trim();
    final confirmarSenha = confirmarSenhaController.text.trim();
    final telefone = telefoneController.text.trim();
    final dataNascimento = converterDataNascimento(
      dataNascimentoController.text,
    );
    final endereco = enderecoController.text.trim();
    final numero = numeroController.text.trim();
    final bairro = bairroController.text.trim();
    final cidade = cidadeController.text.trim();
    final estado = estadoSelecionado?.trim() ?? '';

    if (nome.isEmpty ||
        email.isEmpty ||
        !email.contains('@') ||
        senha.isEmpty ||
        confirmarSenha.isEmpty ||
        telefone.isEmpty ||
        dataNascimento == null ||
        endereco.isEmpty ||
        numero.isEmpty ||
        bairro.isEmpty ||
        cidade.isEmpty ||
        estado.isEmpty) {
      mostrarMensagem(
        'Preencha todos os campos obrigatórios corretamente.',
        erro: true,
      );
      return;
    }

    if (senha.length < 6) {
      mostrarMensagem(
        'A senha precisa ter pelo menos 6 caracteres.',
        erro: true,
      );
      return;
    }

    if (senha != confirmarSenha) {
      mostrarMensagem(
        'A confirmação de senha não confere.',
        erro: true,
      );
      return;
    }

    setState(() {
      salvando = true;
    });

    try {
      final resposta = await Supabase.instance.client.auth.signUp(
        email: email,
        password: senha,
        data: {
          'full_name': nome,
          'nome': nome,
          'telefone': telefone,
        },
      );

      final user = resposta.user ?? Supabase.instance.client.auth.currentUser;

      if (user == null) {
        if (!mounted) return;

        mostrarMensagem(
          'Cadastro criado. Verifique seu e-mail antes de fazer login.',
        );

        Navigator.pop(context);
        return;
      }

      final clienteExistente = await Supabase.instance.client
          .from('clientes')
          .select('id')
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .eq('user_id', user.id)
          .maybeSingle();

      final dadosCliente = sessao.SessaoMercadoCliente.dadosComMercado({
        'user_id': user.id,
        'nome': nome,
        'email': email,
        'telefone': telefone,
        'data_nascimento': formatarDataParaBanco(dataNascimento),
        'endereco': endereco,
        'numero': numero,
        'bairro': bairro,
        'cidade': cidade,
        'estado': estado,
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

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const MainNavigationPage(),
        ),
        (_) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      mostrarMensagem(e.message, erro: true);
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem('Erro ao cadastrar: $e', erro: true);
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
    String? hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: obrigatorio ? '$label *' : label,
      hintText: hint,
      prefixIcon: Icon(
        icon,
        color: corPrimaria,
      ),
      suffixIcon: suffixIcon,
      labelStyle: const TextStyle(
        color: Color(0xFF6B7280),
        fontWeight: FontWeight.w700,
      ),
      hintStyle: const TextStyle(
        color: Color(0xFFB3B6BD),
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 15,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Colors.black.withOpacity(0.10),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: corPrimaria,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: Colors.redAccent,
          width: 1.5,
        ),
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
    String? hint,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: tipo,
        obscureText: obscureText,
        enabled: !salvando,
        inputFormatters: inputFormatters,
        decoration: decoracaoCampo(
          label: label,
          icon: icon,
          obrigatorio: obrigatorio,
          hint: hint,
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }

  Widget campoEstado() {
    final texto = estadoSelecionado == null || estadoSelecionado!.isEmpty
        ? 'Selecione o estado'
        : estadoSelecionado!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: salvando ? null : abrirSeletorEstado,
        borderRadius: BorderRadius.circular(16),
        child: InputDecorator(
          decoration: decoracaoCampo(
            label: 'Estado',
            icon: Icons.map_outlined,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  texto,
                  style: TextStyle(
                    color: estadoSelecionado == null
                        ? Colors.black45
                        : textoEscuro,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.black45,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget secaoTitulo(String titulo, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 12),
      child: Row(
        children: [
          Icon(
            icon,
            color: corPrimaria,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            titulo,
            style: const TextStyle(
              color: textoEscuro,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget formulario() {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 24),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
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
        children: [
          secaoTitulo('Acesso', Icons.lock_person_outlined),
          campo(
            controller: nomeController,
            label: 'Nome completo',
            icon: Icons.person_outline,
            tipo: TextInputType.name,
            inputFormatters: [
              LengthLimitingTextInputFormatter(80),
            ],
          ),
          campo(
            controller: emailController,
            label: 'E-mail',
            icon: Icons.mail_outline,
            tipo: TextInputType.emailAddress,
            inputFormatters: [
              LengthLimitingTextInputFormatter(120),
            ],
          ),
          campo(
            controller: senhaController,
            label: 'Senha',
            icon: Icons.lock_outline,
            obscureText: !senhaVisivel,
            inputFormatters: [
              LengthLimitingTextInputFormatter(32),
            ],
            suffixIcon: IconButton(
              onPressed: salvando
                  ? null
                  : () {
                      setState(() {
                        senhaVisivel = !senhaVisivel;
                      });
                    },
              icon: Icon(
                senhaVisivel
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: Colors.black45,
              ),
            ),
          ),
          campo(
            controller: confirmarSenhaController,
            label: 'Confirmar senha',
            icon: Icons.verified_user_outlined,
            obscureText: !confirmarSenhaVisivel,
            inputFormatters: [
              LengthLimitingTextInputFormatter(32),
            ],
            suffixIcon: IconButton(
              onPressed: salvando
                  ? null
                  : () {
                      setState(() {
                        confirmarSenhaVisivel = !confirmarSenhaVisivel;
                      });
                    },
              icon: Icon(
                confirmarSenhaVisivel
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: Colors.black45,
              ),
            ),
          ),
          const SizedBox(height: 6),
          secaoTitulo('Dados pessoais', Icons.badge_outlined),
          campo(
            controller: telefoneController,
            label: 'Telefone',
            icon: Icons.phone_android,
            tipo: TextInputType.phone,
            inputFormatters: [
              TelefoneInputFormatter(),
              LengthLimitingTextInputFormatter(15),
            ],
            hint: '(77) 99999-9999',
          ),
          campo(
            controller: dataNascimentoController,
            label: 'Data de nascimento',
            icon: Icons.cake_outlined,
            tipo: TextInputType.number,
            inputFormatters: [
              DataNascimentoInputFormatter(),
              LengthLimitingTextInputFormatter(10),
            ],
            hint: 'dd/mm/aaaa',
          ),
          const SizedBox(height: 6),
          secaoTitulo('Endereço de entrega', Icons.location_on_outlined),
          campo(
            controller: enderecoController,
            label: 'Endereço',
            icon: Icons.home_outlined,
            inputFormatters: [
              LengthLimitingTextInputFormatter(120),
            ],
          ),
          Row(
            children: [
              Expanded(
                flex: 4,
                child: campo(
                  controller: numeroController,
                  label: 'Número',
                  icon: Icons.numbers,
                  tipo: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 7,
                child: campo(
                  controller: bairroController,
                  label: 'Bairro',
                  icon: Icons.location_city_outlined,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(80),
                  ],
                ),
              ),
            ],
          ),
          campo(
            controller: cidadeController,
            label: 'Cidade',
            icon: Icons.apartment_outlined,
            inputFormatters: [
              LengthLimitingTextInputFormatter(80),
            ],
          ),
          campoEstado(),
          campo(
            controller: referenciaController,
            label: 'Referência',
            icon: Icons.pin_drop_outlined,
            obrigatorio: false,
            inputFormatters: [
              LengthLimitingTextInputFormatter(140),
            ],
            hint: 'Ex: perto da praça',
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: salvando ? null : cadastrarCliente,
              style: ElevatedButton.styleFrom(
                backgroundColor: corPrimaria,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: salvando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.3,
                      ),
                    )
                  : const Text(
                      'Criar minha conta',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget cabecalho() {
    final nomeMercado = sessao.SessaoMercadoCliente.mercadoNome.trim().isEmpty
        ? 'Mercado Online'
        : sessao.SessaoMercadoCliente.mercadoNome.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 34),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            corPrimaria,
            corPrimaria.withOpacity(0.78),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(34),
          bottomRight: Radius.circular(34),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            InkWell(
              onTap: salvando ? null : () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.28),
                  ),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.28),
                ),
              ),
              child: const Icon(
                Icons.person_add_alt_1,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Criar cadastro',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    nomeMercado,
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

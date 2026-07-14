import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_page.dart';
import '../services/app_tema_service.dart';
import '../services/sessao_mercado_cliente.dart' as sessao;

class ContaPage extends StatefulWidget {
  final VoidCallback? onVoltar;

  const ContaPage({super.key, this.onVoltar});

  @override
  State<ContaPage> createState() => _ContaPageState();
}

class _ContaPageState extends State<ContaPage> {
  Color get vermelho => AppTemaService.primaria;
  Color get vermelhoEscuro => AppTemaService.secundaria;
  Color get fundo => AppTemaService.fundo;

  final nomeController = TextEditingController();
  final dataNascimentoController = TextEditingController();
  final telefoneController = TextEditingController();
  final enderecoController = TextEditingController();
  final numeroController = TextEditingController();
  final bairroController = TextEditingController();
  final cidadeController = TextEditingController();
  final estadoController = TextEditingController();
  final referenciaController = TextEditingController();

  Map<String, dynamic>? cliente;

  bool carregando = true;
  bool salvando = false;
  bool editando = false;

  final List<Map<String, String>> estados = const [
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
    carregarDados();
  }

  @override
  void dispose() {
    nomeController.dispose();
    dataNascimentoController.dispose();
    telefoneController.dispose();
    enderecoController.dispose();
    numeroController.dispose();
    bairroController.dispose();
    cidadeController.dispose();
    estadoController.dispose();
    referenciaController.dispose();
    super.dispose();
  }

  String formatarTelefoneParaTela(dynamic valor) {
    final digits = (valor?.toString() ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';

    if (digits.length <= 10) {
      final d = digits.padRight(10).substring(0, 10);
      final parte1 = d.substring(0, 2).trim();
      final parte2 = d.substring(2, 6).trim();
      final parte3 = d.substring(6, 10).trim();
      if (digits.length <= 2) return '($parte1';
      if (digits.length <= 6) return '($parte1) $parte2';
      return '($parte1) $parte2-$parte3'.trim();
    }

    final d = digits.padRight(11).substring(0, 11);
    final parte1 = d.substring(0, 2).trim();
    final parte2 = d.substring(2, 7).trim();
    final parte3 = d.substring(7, 11).trim();
    return '($parte1) $parte2-$parte3'.trim();
  }

  String formatarDataParaTela(dynamic valor) {
    final texto = valor?.toString() ?? '';
    if (texto.trim().isEmpty) return '';

    try {
      final data = DateTime.parse(texto);
      final dia = data.day.toString().padLeft(2, '0');
      final mes = data.month.toString().padLeft(2, '0');
      final ano = data.year.toString().padLeft(4, '0');
      return '$dia/$mes/$ano';
    } catch (_) {
      if (texto.length >= 10 && texto.contains('-')) {
        final partes = texto.substring(0, 10).split('-');
        if (partes.length == 3) {
          return '${partes[2]}/${partes[1]}/${partes[0]}';
        }
      }
      return texto;
    }
  }

  String? dataParaBanco(String texto) {
    final valor = texto.trim();
    if (valor.isEmpty) return null;

    final partes = valor.split('/');
    if (partes.length != 3) return null;

    final dia = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);
    final ano = int.tryParse(partes[2]);

    if (dia == null || mes == null || ano == null) return null;
    if (ano < 1900 || ano > DateTime.now().year) return null;
    if (mes < 1 || mes > 12) return null;
    if (dia < 1 || dia > 31) return null;

    try {
      final data = DateTime(ano, mes, dia);
      if (data.day != dia || data.month != mes || data.year != ano) {
        return null;
      }
      return '${ano.toString().padLeft(4, '0')}-${mes.toString().padLeft(2, '0')}-${dia.toString().padLeft(2, '0')}';
    } catch (_) {
      return null;
    }
  }

  Future<void> carregarDados() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      setState(() {
        carregando = false;
      });
      return;
    }

    final dados = await Supabase.instance.client
        .from('clientes')
        .select()
        .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
        .eq('user_id', user.id)
        .maybeSingle();

    final nomeGoogle = user.userMetadata?['full_name']?.toString() ?? '';

    nomeController.text = dados?['nome']?.toString() ?? nomeGoogle;
    dataNascimentoController.text = formatarDataParaTela(
      dados?['data_nascimento'],
    );
    telefoneController.text = formatarTelefoneParaTela(dados?['telefone']);
    enderecoController.text = dados?['endereco']?.toString() ?? '';
    numeroController.text = dados?['numero']?.toString() ?? '';
    bairroController.text = dados?['bairro']?.toString() ?? '';
    cidadeController.text = dados?['cidade']?.toString() ?? '';
    estadoController.text = dados?['estado']?.toString() ?? '';
    referenciaController.text = dados?['referencia']?.toString() ?? '';

    setState(() {
      cliente = dados;
      carregando = false;
    });
  }

  Future<void> salvarDados() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) return;

    final dataBanco = dataParaBanco(dataNascimentoController.text);

    if (nomeController.text.trim().isEmpty ||
        dataNascimentoController.text.trim().isEmpty ||
        dataBanco == null ||
        telefoneController.text.trim().isEmpty ||
        enderecoController.text.trim().isEmpty ||
        numeroController.text.trim().isEmpty ||
        bairroController.text.trim().isEmpty ||
        cidadeController.text.trim().isEmpty ||
        estadoController.text.trim().isEmpty) {
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
        'data_nascimento': dataBanco,
        'telefone': telefoneController.text.trim(),
        'endereco': enderecoController.text.trim(),
        'numero': numeroController.text.trim(),
        'bairro': bairroController.text.trim(),
        'cidade': cidadeController.text.trim(),
        'estado': estadoController.text.trim(),
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

      await carregarDados();

      if (!mounted) return;

      setState(() {
        editando = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Dados atualizados com sucesso')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao salvar dados: $e')));
    } finally {
      if (mounted) {
        setState(() {
          salvando = false;
        });
      }
    }
  }

  Future<void> sair() async {
    await Supabase.instance.client.auth.signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> abrirSeletorEstado() async {
    final selecionado = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.only(top: 14, bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: AppTemaService.primaria.withValues(alpha: 0.16),
                width: 1.6,
              ),
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
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  'Selecione o estado',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 5 * 52),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: estados.length,
                    separatorBuilder: (_, __) => Divider(height: 1),
                    itemBuilder: (context, index) {
                      final estado = estados[index];
                      final uf = estado['uf']!;
                      final nome = estado['nome']!;
                      final ativo = estadoController.text == uf;

                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 17,
                          backgroundColor: ativo
                              ? vermelho.withOpacity(0.12)
                              : const Color(0xFFF2F2F2),
                          child: Text(
                            uf,
                            style: TextStyle(
                              color: ativo ? vermelho : Colors.black87,
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text('$uf - $nome'),
                        trailing: ativo
                            ? Icon(Icons.check, color: vermelho)
                            : null,
                        onTap: () => Navigator.pop(context, uf),
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

    if (selecionado != null) {
      setState(() {
        estadoController.text = selecionado;
      });
    }
  }

  Widget item({
    required IconData icon,
    required String titulo,
    required String valor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: AppTemaService.primaria.withValues(alpha: 0.16),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTemaService.primaria.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 31,
            height: 31,
            decoration: BoxDecoration(
              color: vermelho.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: vermelho, size: 17),
          ),
          SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.black45,
                    height: 1.0,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  valor.trim().isEmpty ? '-' : valor.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.8,
                    height: 1.08,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF222222),
                  ),
                ),
              ],
            ),
          ),
        ],
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
    bool readOnly = false,
    VoidCallback? onTap,
    Widget? suffixIcon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: tipo,
        inputFormatters: inputFormatters,
        readOnly: readOnly,
        onTap: onTap,
        decoration: InputDecoration(
          labelText: obrigatorio ? '$label *' : label,
          prefixIcon: Icon(icon, color: vermelho),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Color(0xFFE3E3E3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: vermelho, width: 1.4),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
    );
  }

  Widget cabecalhoUsuario() {
    final user = Supabase.instance.client.auth.currentUser;
    final fotoGoogle = user?.userMetadata?['avatar_url']?.toString() ?? '';
    final email = user?.email ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: AppTemaService.primaria.withValues(alpha: 0.16),
          width: 1.6,
        ),
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
          CircleAvatar(
            radius: 25,
            backgroundColor: vermelho,
            backgroundImage: fotoGoogle.isNotEmpty
                ? NetworkImage(fotoGoogle)
                : null,
            child: fotoGoogle.isEmpty
                ? Icon(Icons.person, color: Colors.white, size: 27)
                : null,
          ),
          SizedBox(height: 8),
          Text(
            nomeController.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              height: 1.15,
            ),
          ),
          SizedBox(height: 2),
          Text(
            email,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  Widget visualizarDados() {
    return Column(
      children: [
        item(
          icon: Icons.cake,
          titulo: 'Data de nascimento',
          valor: dataNascimentoController.text,
        ),
        item(
          icon: Icons.phone,
          titulo: 'Telefone',
          valor: telefoneController.text,
        ),
        item(
          icon: Icons.location_on,
          titulo: 'Endereço',
          valor: enderecoController.text,
        ),
        item(icon: Icons.home, titulo: 'Número', valor: numeroController.text),
        item(icon: Icons.map, titulo: 'Bairro', valor: bairroController.text),
        item(
          icon: Icons.location_city,
          titulo: 'Cidade',
          valor: cidadeController.text,
        ),
        item(icon: Icons.flag, titulo: 'Estado', valor: estadoController.text),
        item(
          icon: Icons.info_outline,
          titulo: 'Referência',
          valor: referenciaController.text,
        ),
        SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          height: 43,
          child: ElevatedButton.icon(
            icon: Icon(Icons.edit, size: 19),
            label: Text('Editar meus dados'),
            style: ElevatedButton.styleFrom(
              backgroundColor: vermelho,
              foregroundColor: Colors.white,
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            onPressed: () {
              setState(() {
                editando = true;
              });
            },
          ),
        ),
        SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          height: 43,
          child: OutlinedButton.icon(
            icon: Icon(Icons.logout, size: 19),
            label: Text('Sair da conta'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF8A4A4A),
              side: BorderSide(color: Color(0xFF8A4A4A)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            onPressed: sair,
          ),
        ),
      ],
    );
  }

  Widget editarDados() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: AppTemaService.primaria.withValues(alpha: 0.16),
          width: 1.6,
        ),
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
          campo(controller: nomeController, label: 'Nome', icon: Icons.person),
          campo(
            controller: dataNascimentoController,
            label: 'Data de nascimento',
            icon: Icons.cake,
            tipo: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              DataNascimentoInputFormatter(),
            ],
          ),
          campo(
            controller: telefoneController,
            label: 'Telefone',
            icon: Icons.phone,
            tipo: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              TelefoneInputFormatter(),
            ],
          ),
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
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          campo(controller: bairroController, label: 'Bairro', icon: Icons.map),
          campo(
            controller: cidadeController,
            label: 'Cidade',
            icon: Icons.location_city,
          ),
          campo(
            controller: estadoController,
            label: 'Estado',
            icon: Icons.flag,
            readOnly: true,
            onTap: abrirSeletorEstado,
            suffixIcon: Icon(Icons.keyboard_arrow_down),
          ),
          campo(
            controller: referenciaController,
            label: 'Referência',
            icon: Icons.info_outline,
            obrigatorio: false,
          ),
          SizedBox(height: 5),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              icon: salvando
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(Icons.save, size: 19),
              label: Text('Salvar alterações'),
              style: ElevatedButton.styleFrom(
                backgroundColor: vermelho,
                foregroundColor: Colors.white,
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onPressed: salvando ? null : salvarDados,
            ),
          ),
          SizedBox(height: 5),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              icon: Icon(Icons.close, size: 19),
              label: Text('Cancelar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF8A4A4A),
                side: BorderSide(color: Color(0xFF8A4A4A)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onPressed: salvando
                  ? null
                  : () {
                      setState(() {
                        editando = false;
                      });
                      carregarDados();
                    },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: fundo,
      appBar: AppBar(
        title: Text('Minha conta'),
        leading: widget.onVoltar != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onVoltar,
              )
            : null,
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: carregando
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 112),
              child: Column(
                children: [
                  cabecalhoUsuario(),
                  SizedBox(height: 7),
                  editando ? editarDados() : visualizarDados(),
                ],
              ),
            ),
    );

    return scaffold;
  }
}

class TelefoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 11 ? digits.substring(0, 11) : digits;
    final buffer = StringBuffer();

    for (int i = 0; i < limited.length; i++) {
      if (i == 0) buffer.write('(');
      if (i == 2) buffer.write(') ');
      if (limited.length <= 10 && i == 6) buffer.write('-');
      if (limited.length > 10 && i == 7) buffer.write('-');
      buffer.write(limited[i]);
    }

    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class DataNascimentoInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();

    for (int i = 0; i < digits.length && i < 8; i++) {
      if (i == 2 || i == 4) buffer.write('/');
      buffer.write(digits[i]);
    }

    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

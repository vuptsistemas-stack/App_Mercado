import 'package:flutter/material.dart';

import '../../services/central_service.dart';
import '../../services/sessao_loja.dart';

class LojaHorariosPage extends StatefulWidget {
  const LojaHorariosPage({super.key});

  @override
  State<LojaHorariosPage> createState() => _LojaHorariosPageState();
}

class _LojaHorariosPageState extends State<LojaHorariosPage> {
  static Color get vermelho => SessaoLoja.corPrimaria;
  static Color get fundo => SessaoLoja.corFundo;

  bool carregando = true;
  bool salvando = false;

  bool segundaSextaAberto = true;
  bool sabadoAberto = true;
  bool domingoAberto = false;

  final segundaSextaAberturaController = TextEditingController();
  final segundaSextaFechamentoController = TextEditingController();

  final sabadoAberturaController = TextEditingController();
  final sabadoFechamentoController = TextEditingController();

  final domingoAberturaController = TextEditingController();
  final domingoFechamentoController = TextEditingController();

  List<Map<String, dynamic>> fechamentos = [];

  @override
  void initState() {
    super.initState();
    carregarTudo();
  }

  @override
  void dispose() {
    segundaSextaAberturaController.dispose();
    segundaSextaFechamentoController.dispose();
    sabadoAberturaController.dispose();
    sabadoFechamentoController.dispose();
    domingoAberturaController.dispose();
    domingoFechamentoController.dispose();
    super.dispose();
  }

  bool get lojaSelecionada {
    return SessaoLoja.lojaSelecionada && SessaoLoja.supabaseLoja != null;
  }

  void mostrarMensagemSemLoja() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Nenhuma loja selecionada'),
        backgroundColor: Colors.red,
      ),
    );
  }

  String limparHorario(dynamic valor) {
    if (valor == null) return '';

    final texto = valor.toString();

    if (texto.length >= 5) {
      return texto.substring(0, 5);
    }

    return texto;
  }

  String? horarioParaSalvar(String texto) {
    final valor = texto.trim();

    if (valor.isEmpty) {
      return null;
    }

    return valor;
  }

  String formatarDataBr(dynamic valor) {
    if (valor == null) return '';

    final texto = valor.toString();

    try {
      final data = DateTime.parse(texto);
      final dia = data.day.toString().padLeft(2, '0');
      final mes = data.month.toString().padLeft(2, '0');
      final ano = data.year.toString();

      return '$dia/$mes/$ano';
    } catch (_) {
      return texto;
    }
  }

  String dataParaBanco(DateTime data) {
    final ano = data.year.toString();
    final mes = data.month.toString().padLeft(2, '0');
    final dia = data.day.toString().padLeft(2, '0');

    return '$ano-$mes-$dia';
  }

  Future<void> carregarTudo() async {
    if (!lojaSelecionada) {
      setState(() {
        carregando = false;
      });

      mostrarMensagemSemLoja();
      return;
    }

    setState(() {
      carregando = true;
    });

    await criarHorariosPadraoSeNecessario();
    await carregarHorarios();
    await carregarFechamentos();

    if (!mounted) return;

    setState(() {
      carregando = false;
    });
  }

  Future<void> criarHorariosPadraoSeNecessario() async {
    if (!lojaSelecionada) {
      mostrarMensagemSemLoja();
      return;
    }

    try {
      final resposta = await SessaoLoja.supabaseLoja!
          .from('loja_horarios')
          .select()
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio);

      if (resposta.isNotEmpty) return;

      await SessaoLoja.supabaseLoja!.from('loja_horarios').insert([
        {
          ...SessaoLoja.dadosMercadoRegistro,
          'tipo': 'segunda_sexta',
          'titulo': 'Segunda a sexta',
          'aberto': true,
          'horario_abertura': '08:00',
          'horario_fechamento': '19:00',
        },
        {
          ...SessaoLoja.dadosMercadoRegistro,
          'tipo': 'sabado',
          'titulo': 'Sábado',
          'aberto': true,
          'horario_abertura': '08:00',
          'horario_fechamento': '18:00',
        },
        {
          ...SessaoLoja.dadosMercadoRegistro,
          'tipo': 'domingo',
          'titulo': 'Domingo',
          'aberto': false,
          'horario_abertura': null,
          'horario_fechamento': null,
        },
      ]);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao criar horários padrão: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> carregarHorarios() async {
    if (!lojaSelecionada) {
      mostrarMensagemSemLoja();
      return;
    }

    try {
      final resposta = await SessaoLoja.supabaseLoja!
          .from('loja_horarios')
          .select()
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio);

      for (final item in resposta) {
        final tipo = item['tipo']?.toString();

        if (tipo == 'segunda_sexta') {
          segundaSextaAberto = item['aberto'] ?? true;
          segundaSextaAberturaController.text = limparHorario(
            item['horario_abertura'],
          );
          segundaSextaFechamentoController.text = limparHorario(
            item['horario_fechamento'],
          );
        }

        if (tipo == 'sabado') {
          sabadoAberto = item['aberto'] ?? true;
          sabadoAberturaController.text = limparHorario(
            item['horario_abertura'],
          );
          sabadoFechamentoController.text = limparHorario(
            item['horario_fechamento'],
          );
        }

        if (tipo == 'domingo') {
          domingoAberto = item['aberto'] ?? false;
          domingoAberturaController.text = limparHorario(
            item['horario_abertura'],
          );
          domingoFechamentoController.text = limparHorario(
            item['horario_fechamento'],
          );
        }
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao carregar horários: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> carregarFechamentos() async {
    if (!lojaSelecionada) {
      mostrarMensagemSemLoja();
      return;
    }

    try {
      final resposta = await SessaoLoja.supabaseLoja!
          .from('loja_fechamentos')
          .select()
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
          .order('data_inicio', ascending: true);

      fechamentos = List<Map<String, dynamic>>.from(resposta);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao carregar fechamentos: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> salvarHorarios() async {
    if (!lojaSelecionada) {
      mostrarMensagemSemLoja();
      return;
    }

    setState(() {
      salvando = true;
    });

    try {
      await SessaoLoja.supabaseLoja!
          .from('loja_horarios')
          .update({
            'aberto': segundaSextaAberto,
            'horario_abertura': segundaSextaAberto
                ? horarioParaSalvar(segundaSextaAberturaController.text)
                : null,
            'horario_fechamento': segundaSextaAberto
                ? horarioParaSalvar(segundaSextaFechamentoController.text)
                : null,
            'atualizado_em': DateTime.now().toIso8601String(),
          })
          .eq('tipo', 'segunda_sexta')
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio);

      await SessaoLoja.supabaseLoja!
          .from('loja_horarios')
          .update({
            'aberto': sabadoAberto,
            'horario_abertura': sabadoAberto
                ? horarioParaSalvar(sabadoAberturaController.text)
                : null,
            'horario_fechamento': sabadoAberto
                ? horarioParaSalvar(sabadoFechamentoController.text)
                : null,
            'atualizado_em': DateTime.now().toIso8601String(),
          })
          .eq('tipo', 'sabado')
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio);

      await SessaoLoja.supabaseLoja!
          .from('loja_horarios')
          .update({
            'aberto': domingoAberto,
            'horario_abertura': domingoAberto
                ? horarioParaSalvar(domingoAberturaController.text)
                : null,
            'horario_fechamento': domingoAberto
                ? horarioParaSalvar(domingoFechamentoController.text)
                : null,
            'atualizado_em': DateTime.now().toIso8601String(),
          })
          .eq('tipo', 'domingo')
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Horários salvos com sucesso')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao salvar horários: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }

    if (!mounted) return;

    setState(() {
      salvando = false;
    });
  }

  Future<void> selecionarHorario(TextEditingController controller) async {
    int hora = 8;
    int minuto = 0;

    if (controller.text.contains(':')) {
      final partes = controller.text.split(':');
      hora = int.tryParse(partes[0]) ?? 8;
      minuto = int.tryParse(partes[1]) ?? 0;
    }

    final selecionado = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hora, minute: minuto),
    );

    if (selecionado == null) return;

    final horaFormatada = selecionado.hour.toString().padLeft(2, '0');
    final minutoFormatado = selecionado.minute.toString().padLeft(2, '0');

    controller.text = '$horaFormatada:$minutoFormatado';
  }

  void aplicarHorarioPadraoSeLigar({
    required bool ativo,
    required TextEditingController abertura,
    required TextEditingController fechamento,
    required String horaAberturaPadrao,
    required String horaFechamentoPadrao,
  }) {
    if (!ativo) return;

    if (abertura.text.trim().isEmpty) {
      abertura.text = horaAberturaPadrao;
    }

    if (fechamento.text.trim().isEmpty) {
      fechamento.text = horaFechamentoPadrao;
    }
  }

  Future<void> adicionarFechamento() async {
    if (!lojaSelecionada) {
      mostrarMensagemSemLoja();
      return;
    }

    DateTime dataInicio = DateTime.now();
    DateTime dataFim = DateTime.now();

    final motivoController = TextEditingController();
    bool ativo = true;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Adicionar fechamento'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today),
                      title: const Text('Data inicial'),
                      subtitle: Text(formatarDataBr(dataInicio)),
                      onTap: () async {
                        final selecionada = await showDatePicker(
                          context: context,
                          initialDate: dataInicio,
                          firstDate: DateTime(2024),
                          lastDate: DateTime(2100),
                        );

                        if (selecionada == null) return;

                        setModalState(() {
                          dataInicio = selecionada;

                          if (dataFim.isBefore(dataInicio)) {
                            dataFim = dataInicio;
                          }
                        });
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event),
                      title: const Text('Data final'),
                      subtitle: Text(formatarDataBr(dataFim)),
                      onTap: () async {
                        final selecionada = await showDatePicker(
                          context: context,
                          initialDate: dataFim,
                          firstDate: dataInicio,
                          lastDate: DateTime(2100),
                        );

                        if (selecionada == null) return;

                        setModalState(() {
                          dataFim = selecionada;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: motivoController,
                      decoration: InputDecoration(
                        labelText: 'Motivo',
                        hintText: 'Ex: Feriado, Natal, reforma...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: ativo,
                      title: const Text('Ativo'),
                      activeColor: vermelho,
                      onChanged: (value) {
                        setModalState(() {
                          ativo = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: vermelho,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmou != true) return;

    try {
      await SessaoLoja.supabaseLoja!.from('loja_fechamentos').insert({
        ...SessaoLoja.dadosMercadoRegistro,
        'data_inicio': dataParaBanco(dataInicio),
        'data_fim': dataParaBanco(dataFim),
        'motivo': motivoController.text.trim(),
        'ativo': ativo,
        'atualizado_em': DateTime.now().toIso8601String(),
      });

      motivoController.dispose();

      await carregarFechamentos();

      if (!mounted) return;

      setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fechamento adicionado com sucesso')),
      );
    } catch (e) {
      motivoController.dispose();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao adicionar fechamento: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> alterarStatusFechamento({
    required String id,
    required bool ativo,
  }) async {
    if (!lojaSelecionada) {
      mostrarMensagemSemLoja();
      return;
    }

    try {
      await SessaoLoja.supabaseLoja!
          .from('loja_fechamentos')
          .update({
            'ativo': ativo,
            'atualizado_em': DateTime.now().toIso8601String(),
          })
          .eq('id', id)
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio);

      await carregarFechamentos();

      if (!mounted) return;

      setState(() {});
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao alterar fechamento: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> excluirFechamento(String id) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir fechamento'),
          content: const Text(
            'Deseja realmente excluir este feriado ou bloqueio?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    if (!lojaSelecionada) {
      mostrarMensagemSemLoja();
      return;
    }

    try {
      await SessaoLoja.supabaseLoja!
          .from('loja_fechamentos')
          .delete()
          .eq('id', id)
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio);

      await carregarFechamentos();

      if (!mounted) return;

      setState(() {});

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Fechamento excluído')));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao excluir fechamento: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget tituloSecao(String texto) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          texto,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
      ),
    );
  }

  Widget campoHorario({
    required String label,
    required TextEditingController controller,
    required bool enabled,
  }) {
    return Expanded(
      child: TextField(
        controller: controller,
        readOnly: true,
        enabled: enabled,
        onTap: enabled ? () => selecionarHorario(controller) : null,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.access_time),
          filled: true,
          fillColor: enabled ? Colors.white : Colors.grey.shade200,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget cardHorario({
    required String titulo,
    required String subtitulo,
    required bool aberto,
    required ValueChanged<bool> onChanged,
    required TextEditingController aberturaController,
    required TextEditingController fechamentoController,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: aberto,
            title: Text(
              titulo,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(subtitulo),
            activeColor: vermelho,
            onChanged: onChanged,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              campoHorario(
                label: 'Abre',
                controller: aberturaController,
                enabled: aberto,
              ),
              const SizedBox(width: 12),
              campoHorario(
                label: 'Fecha',
                controller: fechamentoController,
                enabled: aberto,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget listaFechamentos() {
    if (fechamentos.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withOpacity(0.05)),
        ),
        child: const Column(
          children: [
            Icon(Icons.event_available, color: Colors.black38, size: 36),
            SizedBox(height: 8),
            Text(
              'Nenhum feriado ou bloqueio cadastrado',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      );
    }

    return Column(
      children: fechamentos.map((item) {
        final id = item['id'].toString();
        final motivo = item['motivo']?.toString() ?? 'Sem motivo';
        final dataInicio = formatarDataBr(item['data_inicio']);
        final dataFim = formatarDataBr(item['data_fim']);
        final ativo = item['ativo'] ?? true;

        final periodo = dataInicio == dataFim
            ? dataInicio
            : '$dataInicio até $dataFim';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withOpacity(0.05)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: ativo
                    ? const Color(0xFFFFE5E8)
                    : Colors.grey.shade200,
                child: Icon(
                  Icons.event_busy,
                  color: ativo ? vermelho : Colors.black38,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      motivo.isEmpty ? 'Sem motivo' : motivo,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      periodo,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              Switch(
                value: ativo,
                activeColor: vermelho,
                onChanged: (value) {
                  alterarStatusFechamento(id: id, ativo: value);
                },
              ),
              IconButton(
                onPressed: () => excluirFechamento(id),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fundo,
      appBar: AppBar(
        title: const Text('Horários e fechamentos'),
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: salvando ? null : salvarHorarios,
            child: const Text('Salvar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  tituloSecao('Horário de funcionamento'),
                  cardHorario(
                    titulo: 'Segunda a sexta',
                    subtitulo: 'Horário usado de segunda até sexta-feira',
                    aberto: segundaSextaAberto,
                    aberturaController: segundaSextaAberturaController,
                    fechamentoController: segundaSextaFechamentoController,
                    onChanged: (value) {
                      setState(() {
                        segundaSextaAberto = value;

                        aplicarHorarioPadraoSeLigar(
                          ativo: value,
                          abertura: segundaSextaAberturaController,
                          fechamento: segundaSextaFechamentoController,
                          horaAberturaPadrao: '08:00',
                          horaFechamentoPadrao: '19:00',
                        );
                      });
                    },
                  ),
                  cardHorario(
                    titulo: 'Sábado',
                    subtitulo: 'Horário especial para sábado',
                    aberto: sabadoAberto,
                    aberturaController: sabadoAberturaController,
                    fechamentoController: sabadoFechamentoController,
                    onChanged: (value) {
                      setState(() {
                        sabadoAberto = value;

                        aplicarHorarioPadraoSeLigar(
                          ativo: value,
                          abertura: sabadoAberturaController,
                          fechamento: sabadoFechamentoController,
                          horaAberturaPadrao: '08:00',
                          horaFechamentoPadrao: '18:00',
                        );
                      });
                    },
                  ),
                  cardHorario(
                    titulo: 'Domingo',
                    subtitulo: 'Ative somente se a loja atender aos domingos',
                    aberto: domingoAberto,
                    aberturaController: domingoAberturaController,
                    fechamentoController: domingoFechamentoController,
                    onChanged: (value) {
                      setState(() {
                        domingoAberto = value;

                        aplicarHorarioPadraoSeLigar(
                          ativo: value,
                          abertura: domingoAberturaController,
                          fechamento: domingoFechamentoController,
                          horaAberturaPadrao: '08:00',
                          horaFechamentoPadrao: '12:00',
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: salvando ? null : salvarHorarios,
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
                      label: const Text('Salvar horários'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: vermelho,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Feriados e bloqueios',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: adicionarFechamento,
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: vermelho,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  listaFechamentos(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}

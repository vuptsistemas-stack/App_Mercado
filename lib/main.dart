import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_mercado_config.dart' as app_config;
import 'controllers/carrinho_controller.dart';
import 'pages/auth_gate.dart';
import 'services/sessao_mercado_cliente.dart' as sessao;

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        debugPrint('ERRO FLUTTER: ${details.exception}');
        debugPrint(details.stack.toString());
      };

      debugPrint('APP_MERCADO: main iniciou');
      runApp(const AppMercadoInicial());
    },
    (error, stack) {
      debugPrint('ERRO ZONA APP_MERCADO: $error');
      debugPrint(stack.toString());
    },
  );
}

class AppMercadoInicial extends StatelessWidget {
  const AppMercadoInicial({super.key});

  static const Color vermelho = Color(0xFFE30613);

  @override
  Widget build(BuildContext context) {
    debugPrint('APP_MERCADO: AppMercadoInicial build');

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'App Mercado',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: vermelho,
        ),
        useMaterial3: true,
      ),
      home: const InicializarMercadoPage(),
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (_) => const InicializarMercadoPage(),
          settings: settings,
        );
      },
      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (_) => const InicializarMercadoPage(),
          settings: settings,
        );
      },
    );
  }
}

class InicializarMercadoPage extends StatefulWidget {
  const InicializarMercadoPage({super.key});

  @override
  State<InicializarMercadoPage> createState() => _InicializarMercadoPageState();
}

class _InicializarMercadoPageState extends State<InicializarMercadoPage> {
  static const Color vermelho = Color(0xFFE30613);

  bool carregando = true;
  String titulo = 'Iniciando loja';
  String mensagem = 'Abrindo aplicativo...';
  String detalheErro = '';

  @override
  void initState() {
    super.initState();

    debugPrint('APP_MERCADO: InicializarMercadoPage initState');

    // IMPORTANTE:
    // Não iniciar Hive/Central/Supabase em microtask antes do primeiro frame.
    // Primeiro deixamos a tela "Iniciando loja" aparecer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('APP_MERCADO: primeiro frame renderizado');
      if (!mounted) return;
      iniciar();
    });
  }

  Future<void> iniciar() async {
    if (!mounted) return;

    debugPrint('APP_MERCADO: iniciar()');

    setState(() {
      carregando = true;
      titulo = 'Iniciando loja';
      mensagem = 'Preparando aplicativo...';
      detalheErro = '';
    });

    // Pequena pausa para garantir que a tela inicial seja desenhada
    // antes de iniciar chamadas mais pesadas.
    await Future<void>.delayed(const Duration(milliseconds: 250));

    try {
      final resultado = await inicializarMercadoCliente(
        onStatus: (texto) {
          debugPrint('APP_MERCADO STATUS: $texto');

          if (!mounted) return;

          setState(() {
            mensagem = texto;
          });
        },
      );

      if (!mounted) return;

      if (!resultado.sucesso) {
        debugPrint('APP_MERCADO ERRO INICIALIZACAO: ${resultado.detalhe}');

        setState(() {
          carregando = false;
          titulo = resultado.titulo;
          mensagem = resultado.mensagem;
          detalheErro = resultado.detalhe;
        });
        return;
      }

      debugPrint('APP_MERCADO: inicialização concluída, abrindo app');

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const AppMercado(),
        ),
      );
    } catch (e, stack) {
      debugPrint('APP_MERCADO EXCEPTION iniciar(): $e');
      debugPrint(stack.toString());

      if (!mounted) return;

      setState(() {
        carregando = false;
        titulo = 'Erro ao iniciar loja';
        mensagem =
            'Não foi possível concluir a conexão inicial com a base Central.';
        detalheErro = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mercadoCodigo = app_config.AppMercadoConfig.mercadoCodigo;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: vermelho.withOpacity(0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.storefront,
                      color: vermelho,
                      size: 42,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    mensagem,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Loja: ${mercadoCodigo.isEmpty ? 'não informada' : mercadoCodigo}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (carregando) ...[
                    const SizedBox(height: 22),
                    const CircularProgressIndicator(
                      color: vermelho,
                    ),
                  ] else ...[
                    if (detalheErro.trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.red.withOpacity(0.18),
                          ),
                        ),
                        child: SelectableText(
                          detalheErro,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: iniciar,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar novamente'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: vermelho,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<ResultadoInicializacaoMercado> inicializarMercadoCliente({
  void Function(String texto)? onStatus,
}) async {
  try {
    final mercadoCodigo =
        app_config.AppMercadoConfig.mercadoCodigoObrigatorio;
    final mercadoId = app_config.AppMercadoConfig.mercadoIdObrigatorio;

    debugPrint('APP_MERCADO: mercadoId=$mercadoId');
    debugPrint('APP_MERCADO: mercadoCodigo=$mercadoCodigo');

    onStatus?.call('Preparando carrinho local...');

    await Hive.initFlutter().timeout(
      const Duration(seconds: 10),
    );

    debugPrint('APP_MERCADO: Hive.initFlutter OK');

    await Hive.openBox('carrinho').timeout(
      const Duration(seconds: 10),
    );

    debugPrint('APP_MERCADO: Hive.openBox carrinho OK');

    if (app_config.AppMercadoConfig.centralSupabaseAnonKey
        .contains('COLOQUE_A_ANON')) {
      return const ResultadoInicializacaoMercado.erro(
        titulo: 'Configuração pendente',
        mensagem:
            'Informe a anon key da Central no arquivo app_mercado_config.dart.',
        detalhe:
            'Arquivo: lib/config/app_mercado_config.dart\nCampo: centralSupabaseAnonKey',
      );
    }

    onStatus?.call('Conectando na base Central...');

    final central = SupabaseClient(
      app_config.AppMercadoConfig.centralSupabaseUrl,
      app_config.AppMercadoConfig.centralSupabaseAnonKey,
    );

    debugPrint('APP_MERCADO: SupabaseClient Central criado');

    onStatus?.call('Buscando conexão da loja na Central...');

    final resposta = await central.functions
        .invoke(
          'buscar-conexao-mercado-cliente',
          body: {
            'mercado_id': mercadoId,
            'mercado_codigo': mercadoCodigo,
          },
        )
        .timeout(
          const Duration(seconds: 20),
        );

    debugPrint('APP_MERCADO: Central respondeu');

    final dados = normalizarRespostaCentral(resposta.data);

    if (dados['erro'] != null) {
      return ResultadoInicializacaoMercado.erro(
        titulo: 'Loja não encontrada',
        mensagem: 'A Central retornou erro ao buscar a loja.',
        detalhe: dados['erro'].toString(),
      );
    }

    onStatus?.call('Carregando conexão da loja...');

    sessao.SessaoMercadoCliente.carregarDaCentral(dados);

    debugPrint(
      'APP_MERCADO: Loja carregada: ${sessao.SessaoMercadoCliente.mercadoNome}',
    );
    debugPrint(
      'APP_MERCADO: API: ${sessao.SessaoMercadoCliente.apiBaseUrl}',
    );

    if (!sessao.SessaoMercadoCliente.ativo) {
      return const ResultadoInicializacaoMercado.erro(
        titulo: 'Loja indisponível',
        mensagem:
            'Esta loja está indisponível no momento. Entre em contato com o mercado.',
        detalhe: '',
      );
    }

    if (sessao.SessaoMercadoCliente.supabaseUrl.isEmpty ||
        sessao.SessaoMercadoCliente.supabaseAnonKey.isEmpty) {
      return ResultadoInicializacaoMercado.erro(
        titulo: 'Conexão incompleta',
        mensagem:
            'A Central não retornou a URL ou a anon key do Supabase da loja.',
        detalhe:
            'supabaseUrl: ${sessao.SessaoMercadoCliente.supabaseUrl}\nsupabaseAnonKey vazia: ${sessao.SessaoMercadoCliente.supabaseAnonKey.isEmpty}',
      );
    }

    onStatus?.call('Conectando no Supabase da loja...');

    await Supabase.initialize(
      url: sessao.SessaoMercadoCliente.supabaseUrl,
      anonKey: sessao.SessaoMercadoCliente.supabaseAnonKey,
    ).timeout(
      const Duration(seconds: 20),
    );

    debugPrint('APP_MERCADO: Supabase loja inicializado');

    onStatus?.call('Loja carregada com sucesso.');

    return const ResultadoInicializacaoMercado.sucesso();
  } on TimeoutException catch (e) {
    return ResultadoInicializacaoMercado.erro(
      titulo: 'Tempo esgotado',
      mensagem:
          'A conexão demorou demais para responder. Veja o detalhe abaixo.',
      detalhe: e.toString(),
    );
  } catch (e, stack) {
    debugPrint('APP_MERCADO EXCEPTION inicializarMercadoCliente(): $e');
    debugPrint(stack.toString());

    return ResultadoInicializacaoMercado.erro(
      titulo: 'Erro ao iniciar loja',
      mensagem: 'Não foi possível iniciar o app conectado na Central.',
      detalhe: e.toString(),
    );
  }
}

Map<String, dynamic> normalizarRespostaCentral(dynamic data) {
  if (data == null) {
    return {
      'erro': 'Resposta vazia da Central',
    };
  }

  if (data is Map<String, dynamic>) {
    if (data['data'] is Map) {
      return Map<String, dynamic>.from(data['data'] as Map);
    }

    if (data['mercado'] is Map) {
      return Map<String, dynamic>.from(data['mercado'] as Map);
    }

    return data;
  }

  if (data is Map) {
    final convertido = Map<String, dynamic>.from(data);

    if (convertido['data'] is Map) {
      return Map<String, dynamic>.from(convertido['data'] as Map);
    }

    if (convertido['mercado'] is Map) {
      return Map<String, dynamic>.from(convertido['mercado'] as Map);
    }

    return convertido;
  }

  return {
    'erro': 'Formato inválido retornado pela Central',
  };
}

class ResultadoInicializacaoMercado {
  final bool sucesso;
  final String titulo;
  final String mensagem;
  final String detalhe;

  const ResultadoInicializacaoMercado._({
    required this.sucesso,
    required this.titulo,
    required this.mensagem,
    required this.detalhe,
  });

  const ResultadoInicializacaoMercado.sucesso()
      : this._(
          sucesso: true,
          titulo: '',
          mensagem: '',
          detalhe: '',
        );

  const ResultadoInicializacaoMercado.erro({
    required String titulo,
    required String mensagem,
    required String detalhe,
  }) : this._(
          sucesso: false,
          titulo: titulo,
          mensagem: mensagem,
          detalhe: detalhe,
        );
}

Color _corHex(String valor, Color padrao) {
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

class AppMercado extends StatelessWidget {
  const AppMercado({super.key});

  @override
  Widget build(BuildContext context) {
    final nomeApp = sessao.SessaoMercadoCliente.mercadoNome.isEmpty
        ? 'Mercado Online'
        : sessao.SessaoMercadoCliente.mercadoNome;

    debugPrint('APP_MERCADO: AppMercado build - $nomeApp');

    return ChangeNotifierProvider(
      create: (_) => CarrinhoController(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: nomeApp,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: _corHex(sessao.SessaoMercadoCliente.clienteCorPrimaria, const Color(0xFFE30613)),
          ),
          useMaterial3: true,
        ),
        home: const AuthGate(),
        onGenerateRoute: (settings) {
          return MaterialPageRoute(
            builder: (_) => const AuthGate(),
            settings: settings,
          );
        },
        onUnknownRoute: (settings) {
          return MaterialPageRoute(
            builder: (_) => const AuthGate(),
            settings: settings,
          );
        },
      ),
    );
  }
}

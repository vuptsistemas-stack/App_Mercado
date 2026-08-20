import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_mercado_config.dart' as app_config;
import 'controllers/carrinho_controller.dart';
import 'pages/auth_gate.dart';
import 'services/push_notification_service.dart';
import 'services/sessao_mercado_cliente.dart' as sessao;

void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        debugPrint('ERRO FLUTTER: ${details.exception}');
        debugPrint(details.stack.toString());
      };

      debugPrint('APP_MERCADO: inicialização começou no splash nativo');

      try {
        final resultado = await inicializarMercadoCliente();

        if (resultado.sucesso) {
          debugPrint(
            'APP_MERCADO: inicialização concluída; liberando primeira tela',
          );

          runApp(const AppMercado());
          return;
        }

        debugPrint('APP_MERCADO ERRO INICIALIZAÇÃO: ${resultado.detalhe}');

        runApp(AppMercadoErroInicializacao(resultado: resultado));
      } catch (e, stack) {
        debugPrint('APP_MERCADO EXCEPTION NO STARTUP: $e');
        debugPrint(stack.toString());

        runApp(
          AppMercadoErroInicializacao(
            resultado: ResultadoInicializacaoMercado.erro(
              titulo: 'Erro ao iniciar loja',
              mensagem:
                  'Não foi possível concluir a conexão inicial do aplicativo.',
              detalhe: e.toString(),
            ),
          ),
        );
      }
    },
    (error, stack) {
      debugPrint('ERRO ZONA APP_MERCADO: $error');
      debugPrint(stack.toString());
    },
  );
}

class AppMercadoErroInicializacao extends StatefulWidget {
  final ResultadoInicializacaoMercado resultado;

  const AppMercadoErroInicializacao({super.key, required this.resultado});

  @override
  State<AppMercadoErroInicializacao> createState() =>
      _AppMercadoErroInicializacaoState();
}

class _AppMercadoErroInicializacaoState
    extends State<AppMercadoErroInicializacao> {
  bool tentandoNovamente = false;
  late ResultadoInicializacaoMercado resultado;

  @override
  void initState() {
    super.initState();
    resultado = widget.resultado;
  }

  Future<void> tentarNovamente() async {
    if (tentandoNovamente) {
      return;
    }

    setState(() {
      tentandoNovamente = true;
    });

    try {
      final novoResultado = await inicializarMercadoCliente();

      if (novoResultado.sucesso) {
        runApp(const AppMercado());
        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        resultado = novoResultado;
        tentandoNovamente = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        resultado = ResultadoInicializacaoMercado.erro(
          titulo: 'Erro ao iniciar loja',
          mensagem:
              'Não foi possível concluir a conexão inicial do aplicativo.',
          detalhe: e.toString(),
        );
        tentandoNovamente = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tentandoNovamente)
                      const SizedBox(
                        width: 38,
                        height: 38,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Color(0xFFE30613),
                        ),
                      )
                    else
                      const Icon(
                        Icons.cloud_off_rounded,
                        color: Color(0xFFE30613),
                        size: 52,
                      ),
                    const SizedBox(height: 18),
                    Text(
                      tentandoNovamente
                          ? 'Tentando conectar novamente'
                          : resultado.titulo,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      tentandoNovamente
                          ? 'Aguarde enquanto reconectamos à loja.'
                          : resultado.mensagem,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 14.5,
                        height: 1.4,
                      ),
                    ),
                    if (!tentandoNovamente &&
                        resultado.detalhe.trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 130),
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F2),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            resultado.detalhe,
                            style: const TextStyle(
                              color: Color(0xFFB91C1C),
                              fontSize: 11.5,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (!tentandoNovamente) ...[
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: tentarNovamente,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text(
                            'Tentar novamente',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE30613),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
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
      ),
    );
  }
}

Future<ResultadoInicializacaoMercado> inicializarMercadoCliente({
  void Function(String texto)? onStatus,
}) async {
  try {
    final mercadoCodigo = app_config.AppMercadoConfig.mercadoCodigoObrigatorio;
    final mercadoId = app_config.AppMercadoConfig.mercadoIdObrigatorio;

    debugPrint('APP_MERCADO: mercadoId=$mercadoId');
    debugPrint('APP_MERCADO: mercadoCodigo=$mercadoCodigo');

    onStatus?.call('Preparando carrinho local...');

    await Hive.initFlutter().timeout(const Duration(seconds: 10));

    debugPrint('APP_MERCADO: Hive.initFlutter OK');

    await Hive.openBox('carrinho').timeout(const Duration(seconds: 10));

    debugPrint('APP_MERCADO: Hive.openBox carrinho OK');

    if (app_config.AppMercadoConfig.centralSupabaseAnonKey.contains(
      'COLOQUE_A_ANON',
    )) {
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
          body: {'mercado_id': mercadoId, 'mercado_codigo': mercadoCodigo},
        )
        .timeout(const Duration(seconds: 20));

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
    debugPrint('APP_MERCADO: API: ${sessao.SessaoMercadoCliente.apiBaseUrl}');

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
    ).timeout(const Duration(seconds: 20));

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
    return {'erro': 'Resposta vazia da Central'};
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

  return {'erro': 'Formato inválido retornado pela Central'};
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
    : this._(sucesso: true, titulo: '', mensagem: '', detalhe: '');

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
            seedColor: _corHex(
              sessao.SessaoMercadoCliente.clienteCorPrimaria,
              const Color(0xFFE30613),
            ),
          ),
          useMaterial3: true,
        ),
        builder: (context, child) {
          return ZoomPinchGlobal(child: child ?? const SizedBox.shrink());
        },
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

class ZoomPinchGlobal extends StatefulWidget {
  final Widget child;

  const ZoomPinchGlobal({super.key, required this.child});

  @override
  State<ZoomPinchGlobal> createState() => _ZoomPinchGlobalState();
}

class _ZoomPinchGlobalState extends State<ZoomPinchGlobal> {
  final TransformationController controller = TransformationController();

  bool ampliado = false;

  @override
  void initState() {
    super.initState();
    controller.addListener(atualizarEstadoZoom);
  }

  @override
  void dispose() {
    controller.removeListener(atualizarEstadoZoom);
    controller.dispose();
    super.dispose();
  }

  void atualizarEstadoZoom() {
    final escala = controller.value.getMaxScaleOnAxis();
    final novoAmpliado = escala > 1.01;

    if (novoAmpliado == ampliado || !mounted) {
      return;
    }

    setState(() {
      ampliado = novoAmpliado;
    });
  }

  void resetarZoom() {
    controller.value = Matrix4.identity();

    if (!mounted) {
      return;
    }

    setState(() {
      ampliado = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 10;

    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onDoubleTap: resetarZoom,
          child: InteractiveViewer(
            transformationController: controller,
            minScale: 1,
            maxScale: 2.6,
            panEnabled: ampliado,
            scaleEnabled: true,
            clipBehavior: Clip.hardEdge,
            boundaryMargin: const EdgeInsets.all(220),
            child: widget.child,
          ),
        ),
        if (ampliado)
          Positioned(
            top: top,
            right: 12,
            child: Material(
              color: Colors.black.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: resetarZoom,
                borderRadius: BorderRadius.circular(18),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.zoom_in_map, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

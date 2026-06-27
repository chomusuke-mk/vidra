import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/core/isolate/backend_isolate.dart';
import 'package:serious_python/serious_python.dart';

class SystemController extends ChangeNotifier {
  SystemState _state = SystemState.initializing;
  SystemState get state => _state;

  // Credenciales dinámicas para el Backend
  int? _backendPort;
  String? _backendToken;
  String? _serverLogsFilePath;

  int? get backendPort => _backendPort;
  String? get backendToken => _backendToken;
  String? get serverLogsFilePath => _serverLogsFilePath; // Getter para la UI

  // Comunicación con el Isolate
  Isolate? _backendIsolate;
  SendPort? _isolateSendPort;
  final ReceivePort _receivePort = ReceivePort();
  Completer<void>? _pauseCompleter;

  SystemController() {
    _bootIsolate();
  }

  /// Cambia el estado y avisa a la UI solo si el estado es diferente
  void _setState(SystemState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  Future<void> _bootIsolate() async {
    debugPrint(
      '🚀 [UI-Controller] Preparando entorno para lanzar el Isolate...',
    );

    // 1. Conseguir un puerto libre y token
    final serverSocket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    _backendPort = serverSocket.port;
    await serverSocket.close();

    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    _backendToken = base64UrlEncode(values);

    // 2. Resolver directorios
    final supportDir = await getApplicationSupportDirectory();
    final tempDir = await getApplicationCacheDirectory();
    _serverLogsFilePath = p.join(tempDir.path, 'logs', 'server.log');

    // 4. Escuchar respuestas del Isolate
    _receivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        if (message['event'] == 'port') {
          _isolateSendPort = message['value'];
          debugPrint(
            '🤝 [UI-Controller] Conectado al puerto de escucha del Isolate.',
          );
        } else if (message['event'] == 'state') {
          final String stateStr = message['value'];
          switch (stateStr) {
            case 'initializing':
            case 'unpacking':
              _setState(SystemState.initializing);
              break;
            case 'missingPermissions':
              _setState(SystemState.missingPermissions);
              break;
            case 'missingResources':
              _setState(SystemState.missingResources);
              break;
            case 'startingBackend':
              _setState(SystemState.startingBackend);
              break;
            case 'retrying':
              _setState(SystemState.retrying);
              break;
            case 'fatalError':
              _setState(SystemState.fatalError);
              break;
            case 'ready':
              _setState(SystemState.ready);
              break;
          }
        } else if (message['event'] == 'paused_ack') {
          _pauseCompleter?.complete();
        }
      }
    });

    // 4. Lanzar el Isolate
    debugPrint('🚀 [UI-Controller] Haciendo spawn del Isolate...');
    _backendIsolate = await Isolate.spawn(backendIsolateMain, {
      'rootToken': RootIsolateToken.instance,
      'sendPort': _receivePort.sendPort,
      'backendPort': _backendPort,
      'backendToken': _backendToken,
      'supportDirPath': supportDir.path,
      'tempDirPath': tempDir.path,
      'serverLogsFilePath': _serverLogsFilePath,
      'isAndroid': Platform.isAndroid,
    }, debugName: 'VidraBackendIsolate');
    _preparePythonAsync();
  }

  /// Extrae el binario de Python en el hilo principal y avisa al Isolate cuando termine
  Future<void> _preparePythonAsync() async {
    debugPrint(
      '🚀 [UI-Controller] Extrayendo binarios de Python (Esto puede tardar)...',
    );

    // Esto puede demorar hasta 20s en Android la primera vez
    final String pythonAppPath = await SeriousPython.prepareApp();
    debugPrint('✅ [UI-Controller] Python extraído en: $pythonAppPath');

    // Nos aseguramos de que el Isolate ya nos haya enviado su puerto de escucha
    while (_isolateSendPort == null) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Le enviamos la ruta al Isolate
    _isolateSendPort!.send({'cmd': 'python_prepared', 'path': pythonAppPath});
  }

  // ==========================================================================
  // MÉTODOS PUENTE (Comandos hacia el Isolate)
  // ==========================================================================

  /// Ordena al isolate procesar o encolar una descarga
  void enqueueDownload(String url, Map<String, dynamic> options) {
    if (_isolateSendPort != null) {
      _isolateSendPort!.send({
        'cmd': 'download',
        'url': url,
        'options': options,
      });
    }
  }

  /// Continúa el arranque si la UI resolvió un bloqueo
  Future<void> resumeInitialization() async {
    _setState(SystemState.initializing);
    _isolateSendPort?.send({'cmd': 'revalidate'});
  }

  /// Detiene el motor temporalmente para instalar actualizaciones OTA
  Future<void> stopBackendForUpdate() async {
    debugPrint('🛑 [UI-Controller] Ordenando pausa al Isolate para OTA...');
    _pauseCompleter = Completer<void>();
    _isolateSendPort?.send({'cmd': 'pause_for_update'});
    await _pauseCompleter!
        .future; // Esperamos a que el isolate confirme que pausó todo
    debugPrint('🛑 [UI-Controller] Isolate pausado.');
  }

  @override
  void dispose() {
    _receivePort.close();
    _backendIsolate?.kill(priority: Isolate.immediate);
    super.dispose();
  }
}

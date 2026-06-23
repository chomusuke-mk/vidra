import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:vidra/features/system/domain/system_state.dart';

class SystemController extends ChangeNotifier {
  SystemState _state = SystemState.initializing;
  SystemState get state => _state;

  Timer? _healthCheckTimer;

  // Credenciales dinámicas para el Backend
  int? _backendPort;
  String? _backendToken;

  int? get backendPort => _backendPort;
  String? get backendToken => _backendToken;

  // Bandera para evitar que el Watchdog pelee con las actualizaciones OTA
  bool _isUpdating = false;

  SystemController() {
    _initSequence();
  }

  /// Cambia el estado y avisa a la UI solo si el estado es diferente
  void _setState(SystemState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  // ==========================================================================
  // LA SECUENCIA MAESTRA DE ARRANQUE
  // ==========================================================================
  /// El flujo maestro de vida de la aplicación
  Future<void> _initSequence() async {
    if (_isUpdating) return;
    _setState(SystemState.initializing);

    // 1. Validar Permisos (Overlay, Notificaciones, etc.)
    final hasPermissions = await _checkPermissions();
    if (!hasPermissions) {
      _setState(SystemState.missingPermissions);
      return;
    }

    // 2. Validar Recursos en el disco (yt-dlp y ejs)
    final hasResources = await _checkResources();
    if (!hasResources) {
      _setState(SystemState.missingResources);
      return;
    }

    // 3. Levantar el Backend (Busca puerto, genera token y lanza Python)
    _setState(SystemState.startingBackend);
    final backendStarted = await _startPythonBackend();

    if (!backendStarted) {
      _setState(SystemState.fatalError);
      return;
    }

    if (!backendStarted) {
      _setState(SystemState.fatalError);
      return;
    }

    // 4. Iniciar el "Perro Guardián" (Ping)
    _startHealthCheck();
  }

  // ==========================================================================
  // EL WATCHDOG (PERRO GUARDIÁN)
  // ==========================================================================
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();

    _healthCheckTimer = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      if (_isUpdating || _backendPort == null || _backendToken == null) return;

      final isAlive = await _pingBackend();

      if (isAlive) {
        _setState(SystemState.ready);
      } else {
        // Python no responde. Podríamos implementar un contador aquí y
        // si falla 3 veces seguidas, llamar a _startPythonBackend() de nuevo.
        _setState(SystemState.retrying);
      }
    });
  }

  Future<bool> _pingBackend() async {
    try {
      final uri = Uri.parse('http://127.0.0.1:$_backendPort/');
      final response = await http
          .get(uri, headers: {'Authorization': 'Bearer $_backendToken'})
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == 'ok';
      }
    } catch (_) {
      // Fallo de red local = Python está colgado o muerto
    }
    return false;
  }

  // ==========================================================================
  // MÉTODOS DE SOPORTE: PERMISOS Y RECURSOS
  // ==========================================================================
  Future<bool> _checkPermissions() async {
    if (!Platform.isAndroid) return true; // Si en un futuro compilas para PC

    final androidInfo = await DeviceInfoPlugin().androidInfo;

    // 1. Almacenamiento (Depende de la versión de Android)
    bool storageGranted = false;
    if (androidInfo.version.sdkInt >= 30) {
      storageGranted = await Permission.manageExternalStorage.isGranted;
    } else {
      storageGranted = await Permission.storage.isGranted;
    }

    // 2. Overlay
    bool overlayGranted = await FlutterOverlayWindow.isPermissionGranted();

    // 3. Notificaciones (Android 13+)
    bool notifGranted = true;
    if (androidInfo.version.sdkInt >= 33) {
      notifGranted = await Permission.notification.isGranted;
    }

    // El permiso de Instalar Paquetes lo dejaremos opcional para el arranque,
    // pero lo pediremos en la pantalla para dejarlo listo.

    return storageGranted && overlayGranted && notifGranted;
  }

  Future<bool> _checkResources() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final ytDlpDir = Directory(
        p.join(supportDir.path, 'core_modules', 'yt-dlp'),
      );
      final ejsDir = Directory(
        p.join(supportDir.path, 'core_modules', 'yt_dlp_ejs'),
      );

      // Comprobamos que las carpetas existan y no estén vacías
      if (!ytDlpDir.existsSync() || ytDlpDir.listSync().isEmpty) return false;
      if (!ejsDir.existsSync() || ejsDir.listSync().isEmpty) return false;

      return true;
    } catch (e) {
      debugPrint('Error comprobando recursos: $e');
      return false;
    }
  }

  // ==========================================================================
  // INYECCIÓN DEL MOTOR PYTHON (SERIOUS PYTHON)
  // ==========================================================================
  Future<bool> _startPythonBackend() async {
    try {
      // 1. Conseguir un puerto libre nativo del Sistema Operativo
      final serverSocket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      _backendPort = serverSocket.port;
      await serverSocket
          .close(); // Liberamos el puerto inmediatamente para Python

      // 2. Generar un Token Aleatorio Criptográficamente Seguro
      final random = Random.secure();
      final values = List<int>.generate(32, (i) => random.nextInt(256));
      _backendToken = base64UrlEncode(values);

      // 3. Preparar las rutas de los recursos adicionales (yt-dlp y ejs)
      final supportDir = await getApplicationSupportDirectory();
      final modulesPath = p.join(supportDir.path, 'core_modules');

      debugPrint(
        '🔥 Levantando Python en Puerto: $_backendPort con Token: $_backendToken',
      );

      // TODO: Aquí va la llamada real a serious_python.
      // Quedará estructuralmente así:
      /*
      SeriousPython.run(
        'ruta/a/tu/main.pyc', 
        environmentVariables: {
          'VIDRA_PORT': _backendPort.toString(),
          'VIDRA_TOKEN': _backendToken!,
        },
        sync: false, // Debe correr en segundo plano
        extraPaths: [
          p.join(modulesPath, 'yt-dlp'),
          p.join(modulesPath, 'yt_dlp_ejs'),
        ]
      );
      */

      return true;
    } catch (e) {
      debugPrint('Error fatal levantando Python: $e');
      return false;
    }
  }

  // ==========================================================================
  // MÉTODOS PÚBLICOS (Para la UI y el UpdateController)
  // ==========================================================================
  /// Continúa el arranque si la UI resolvió un bloqueo (ej. usuario dio permisos)
  Future<void> resumeInitialization() async {
    _isUpdating = false;
    await _initSequence();
  }

  /// Detiene el motor y el watchdog temporalmente para instalar actualizaciones OTA
  Future<void> stopBackendForUpdate() async {
    debugPrint('🛑 Deteniendo motor Python para actualización OTA...');
    _isUpdating = true;
    _healthCheckTimer?.cancel();

    // TODO: Si tu backend Python soporta una ruta de apagado seguro, llámala aquí.
    // Ej: await http.post(Uri.parse('http://127.0.0.1:$_backendPort/shutdown'), ...);

    _setState(SystemState.initializing); // Ponemos la app en modo espera
  }

  @override
  void dispose() {
    _healthCheckTimer?.cancel();
    super.dispose();
  }
}

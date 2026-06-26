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
import 'package:serious_python/serious_python.dart';

class SystemController extends ChangeNotifier {
  SystemState _state = SystemState.initializing;
  SystemState get state => _state;

  Timer? _healthCheckTimer;

  // Credenciales dinámicas para el Backend
  int? _backendPort;
  String? _backendToken;
  String? _serverLogsPath;

  int? get backendPort => _backendPort;
  String? get backendToken => _backendToken;
  String? get serverLogsPath => _serverLogsPath; // Getter para la UI

  // Bandera para evitar que el Watchdog pelee con las actualizaciones OTA
  bool _isUpdating = false;
  int _failedPings = 0;

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
    debugPrint('🚀 Iniciando secuencia de arranque...');
    if (_isUpdating) return;
    _setState(SystemState.initializing);
    debugPrint('🔎 Evaluando permisos...');
    // 1. Validar Permisos (Overlay, Notificaciones, etc.)
    final hasPermissions = await _checkPermissions();
    if (!hasPermissions) {
      debugPrint('❌ Faltan permisos críticos. Bloqueando arranque...');
      _setState(SystemState.missingPermissions);
      return;
    }
    debugPrint('✅ Permisos críticos OK. Evaluando recursos...');
    // 2. Validar Recursos en el disco (yt-dlp y ejs)
    final hasResources = await _checkResources();
    if (!hasResources) {
      debugPrint('❌ Faltan recursos críticos. Bloqueando arranque...');
      _setState(SystemState.missingResources);
      return;
    }
    debugPrint('✅ Permisos y recursos críticos OK. Iniciando Backend...');
    // 3. Levantar el Backend (Busca puerto, genera token y lanza Python)
    _setState(SystemState.startingBackend);
    final backendStarted = await _startPythonBackend();

    if (!backendStarted) {
      debugPrint('❌ No se pudo iniciar el Backend. Bloqueando arranque...');
      _setState(SystemState.fatalError);
      return;
    }
    debugPrint('✅ Backend iniciado correctamente. Iniciando Watchdog...');

    if (!backendStarted) {
      _setState(SystemState.fatalError);
      return;
    }

    // 4. Iniciar el "Perro Guardián" (Ping)
    _startHealthCheck();
  }

  // ==========================================================================
  // EL WATCHDOG (PERRO GUARDIÁN) INMORTAL
  // ==========================================================================
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _failedPings = 0; // Reseteamos al iniciar el watchdog

    _healthCheckTimer = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      // Si estamos actualizando OTA o no hay credenciales, no hacemos nada
      if (_isUpdating || _backendPort == null || _backendToken == null) return;

      final isAlive = await _pingBackend();
      final maxRetries = 10; // 10 intentos fallidos = 20 segundos offline

      if (isAlive) {
        _failedPings = 0; // Si responde, ponemos el contador a 0
        _setState(SystemState.ready);
      } else {
        _failedPings++;
        debugPrint(
          '⚠️ El Backend no responde. Intento fallido ($_failedPings/$maxRetries)',
        );
        _setState(SystemState.retrying);

        // Si falla $maxRetries veces seguidas, lo revivimos
        if (_failedPings >= maxRetries) {
          debugPrint(
            '🔄 Backend muerto detectado. Intentando auto-resurrección...',
          );
          _failedPings =
              0; // Reseteamos para que no lance 20 arranques a la vez
          _setState(SystemState.startingBackend);

          final revived = await _startPythonBackend();
          if (!revived) {
            _setState(SystemState.fatalError);
          }
        }
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

    // 4. Optimización de batería
    bool batteryGranted = true;
    if (Platform.isAndroid) {
      batteryGranted = await Permission.ignoreBatteryOptimizations.isGranted;
    }

    // El permiso de Instalar Paquetes lo dejaremos opcional para el arranque,
    // pero lo pediremos en la pantalla para dejarlo listo.

    return storageGranted && overlayGranted && notifGranted && batteryGranted;
  }

  Future<bool> _checkResources() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final ytDlpDir = Directory(
        p.join(supportDir.path, 'core_modules', 'yt_dlp'),
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
      // Liberamos el puerto inmediatamente para Python
      await serverSocket.close();

      // 2. Generar un Token Aleatorio Criptográficamente Seguro
      final random = Random.secure();
      final values = List<int>.generate(32, (i) => random.nextInt(256));
      _backendToken = base64UrlEncode(values);

      // 3. Preparar las rutas de los recursos adicionales (yt-dlp y ejs)
      final supportDir = await getApplicationSupportDirectory();
      final modulesPath = p.join(supportDir.path, 'core_modules');

      // 4. Preparar la ruta de logs del servidor para que la UI pueda leerlo
      _serverLogsPath = p.join(supportDir.path, 'logs', 'server.log');

      debugPrint(
        '🔥 Levantando Python en Puerto: $_backendPort con Token: $_backendToken',
      );

      SeriousPython.run(
        appFileName: 'main.py',
        environmentVariables: {
          'APP_ENV': 'production',
          'API_TOKEN': _backendToken!,
          'LOGS_PATH': p.join(supportDir.path, 'logs'),
          'DATA_PATH': p.join(supportDir.path, 'data'),
          'TEMP_PATH': p.join(supportDir.path, 'temp'),
          'HOST': '127.0.0.1',
          'PORT': _backendPort.toString(),
          'SERVER_LOGS_FILE_PATH': _serverLogsPath!,
        },
        sync: false, // Debe correr en segundo plano
        modulePaths: [modulesPath],
      );

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

    if (_backendPort != null && _backendToken != null) {
      try {
        final uri = Uri.parse('http://127.0.0.1:$_backendPort/shutdown');
        await http
            .post(uri, headers: {'Authorization': 'Bearer $_backendToken'})
            .timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint(
          'Aviso: Fallo de red en shutdown, probablemente ya cerró. $e',
        );
      }
    }

    _setState(SystemState.initializing); // Ponemos la app en modo espera
  }

  @override
  void dispose() {
    _healthCheckTimer?.cancel();
    super.dispose();
  }
}

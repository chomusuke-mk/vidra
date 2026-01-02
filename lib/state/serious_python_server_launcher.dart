import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:serious_python/serious_python.dart';

enum BackendState { unknown, unpacking, starting, running, stopped }

enum _ExistingBackendResult { none, reused, conflict }

class BackendLaunchInfo {
  BackendLaunchInfo({
    required this.phase,
    this.message,
    this.traceback,
    this.logPath,
    this.token,
    this.source,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String phase;
  final String? message;
  final String? traceback;
  final String? logPath;
  final String? token;
  final String? source;
  final DateTime timestamp;

  static const String phaseStarting = 'starting';
  static const String phaseSuccess = 'success';
  static const String phaseError = 'error';
  static const String phaseReused = 'reused';

  BackendLaunchInfo copyWith({
    String? phase,
    String? message,
    String? traceback,
    String? logPath,
    String? token,
    String? source,
    DateTime? timestamp,
  }) {
    return BackendLaunchInfo(
      phase: phase ?? this.phase,
      message: message ?? this.message,
      traceback: traceback ?? this.traceback,
      logPath: logPath ?? this.logPath,
      token: token ?? this.token,
      source: source ?? this.source,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'status': phase,
      'message': message,
      'traceback': traceback,
      'log_path': logPath,
      'token': token,
      'source': source,
      'timestamp': timestamp.toIso8601String(),
    }..removeWhere((_, value) => value == null);
  }

  static BackendLaunchInfo? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    final status = json['status'] as String?;
    if (status == null) {
      return null;
    }
    return BackendLaunchInfo(
      phase: status,
      message: json['message'] as String?,
      traceback: json['traceback'] as String?,
      logPath: json['log_path'] as String?,
      token: json['token'] as String?,
      source: json['source'] as String?,
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Boots the embedded Serious Python package once per app lifetime.
class SeriousPythonServerLauncher {
  SeriousPythonServerLauncher._();

  static final SeriousPythonServerLauncher instance =
      SeriousPythonServerLauncher._();

  static const _assetArchivePath = 'app/app.zip';
  static const _assetHashAssetPath = 'app/app.zip.hash';
  static const _backendFolderName = 'backend';
  static const _backendHashFileName = 'app.zip.hash';
  static const _statusFileName = 'startup_status.json';
  static const _lockFileName = 'vidra.start.lock';
  static const _logFileName = 'release_logs.txt';
  static const _mainScript = 'main.py';
  static const Duration _primaryPingTimeout = Duration(minutes: 10);
  static const Duration _reusePingTimeout = Duration(seconds: 5);

  final ValueNotifier<BackendState> _stateNotifier =
      ValueNotifier<BackendState>(BackendState.unknown);
  final ValueNotifier<BackendLaunchInfo?> _launchInfoNotifier =
      ValueNotifier<BackendLaunchInfo?>(null);

  String? _pendingHashValue;
  File? _pendingHashFile;
  File? _statusFile;
  File? _lockFile;
  File? _logFile;
  RandomAccessFile? _activeLockHandle;
  Completer<void>? _backendRunExitCompleter;

  ValueListenable<BackendState> get state => _stateNotifier;
  ValueListenable<BackendLaunchInfo?> get launchInfo => _launchInfoNotifier;

  Future<void>? _launchFuture;
  Timer? _portMonitorTimer;

  /// Ensures the Python backend is running. Subsequent calls reuse the same
  /// launch future to avoid relaunching due to rebuilds.
  Future<void> ensureStarted({Map<String, String>? extraEnvironment}) {
    return _launchFuture ??= _launch(extraEnvironment: extraEnvironment);
  }

  Future<void> _launch({Map<String, String>? extraEnvironment}) async {
    _log(
      'Requested backend launch. extraEnvironment keys: '
      '${extraEnvironment?.keys.join(', ') ?? '<none>'}',
    );
    _updateState(BackendState.unknown);
    final env = _buildEnvironment(extraEnvironment);
    final backendPaths = await _prepareBackendPaths();

    env.putIfAbsent(
      'VIDRA_SERVER_STATUS_FILE',
      () => backendPaths.statusFile.path,
    );
    env.putIfAbsent('VIDRA_SERVER_LOCK_FILE', () => backendPaths.lockFile.path);
    env.putIfAbsent('VIDRA_SERVER_LOG_FILE', () => backendPaths.logFile.path);

    _statusFile = backendPaths.statusFile;
    _lockFile = backendPaths.lockFile;
    _logFile = backendPaths.logFile;

    final existingBackendState = await _checkExistingBackend(env);
    if (existingBackendState == _ExistingBackendResult.reused) {
      final existingInfo = await _readStatus();
      await _writeStatus(
        BackendLaunchInfo(
          phase: BackendLaunchInfo.phaseReused,
          message: 'Se reutilizó una instancia existente.',
          logPath: _logFile?.path,
          token: existingInfo?.token,
          source: 'flutter',
        ),
      );
      return;
    }
    if (existingBackendState == _ExistingBackendResult.conflict) {
      throw StateError('Port already in use by another service.');
    }

    final backendHashFile = File(
      p.join(backendPaths.backendDir.path, _backendHashFileName),
    );

    final lockHandle = await _tryAcquireLaunchLock();
    if (lockHandle != null) {
      await _launchWithAcquiredLock(
        env: env,
        supportDir: backendPaths.supportDir,
        backendHashFile: backendHashFile,
        lockHandle: lockHandle,
      );
      return;
    }

    await _handlePeerLaunch(
      env: env,
      backendHashFile: backendHashFile,
      supportDir: backendPaths.supportDir,
    );
  }

  Map<String, String> _buildEnvironment(Map<String, String>? extraEnvironment) {
    final merged = <String, String>{
      ...dotenv.env,
      if (extraEnvironment != null) ...extraEnvironment,
    };
    _log(
      'Environment prepared with ${merged.length} entries. Keys: '
      '${merged.keys.join(', ')}',
    );
    return merged;
  }

  Future<_ExistingBackendResult> _checkExistingBackend(
    Map<String, String> env,
  ) async {
    final expectedService = env['VIDRA_SERVER_NAME']?.trim();
    if (expectedService == null || expectedService.isEmpty) {
      return _ExistingBackendResult.none;
    }
    final host = env['VIDRA_SERVER_HOST']?.trim().isNotEmpty == true
        ? env['VIDRA_SERVER_HOST']!.trim()
        : '127.0.0.1';
    final port = int.tryParse(env['VIDRA_SERVER_PORT'] ?? '') ?? 5000;
    final portOpen = await _isPortOpen(host, port);
    if (!portOpen) {
      return _ExistingBackendResult.none;
    }
    final uri = _buildHealthCheckUri(env, host, port);
    try {
      final health = await _fetchHealthSnapshot(uri);
      final serviceValue = health['service'];
      if (serviceValue is String && serviceValue == expectedService) {
        _log('Backend ya en ejecucion en ${uri.toString()}');
        _startPortMonitor(host, port);
        _updateState(BackendState.running);
        return _ExistingBackendResult.reused;
      }
      final conflictingService = serviceValue is String
          ? serviceValue
          : 'desconocido';
      _handleBackendStopped(
        'Puerto ocupado por "$conflictingService" en $host:$port',
      );
      return _ExistingBackendResult.conflict;
    } catch (error, stackTrace) {
      _log(
        'No se pudo validar el backend existente en ${uri.toString()}: '
        '$error',
      );
      debugPrint(stackTrace.toString());
      _handleBackendStopped(
        'Puerto ocupado o sin respuesta valida en $host:$port',
      );
      return _ExistingBackendResult.conflict;
    }
  }

  Uri _buildHealthCheckUri(Map<String, String> env, String host, int port) {
    final rawScheme = env['VIDRA_SERVER_SCHEME']?.trim().toLowerCase();
    final scheme = rawScheme == 'https' ? 'https' : 'http';
    final basePath = env['VIDRA_SERVER_BASE_PATH'] ?? '/';
    final healthPath = env['VIDRA_SERVER_HEALTH_PATH'] ?? '/';
    final normalizedPath = _combinePaths(basePath, healthPath);
    return Uri(scheme: scheme, host: host, port: port, path: normalizedPath);
  }

  String _combinePaths(String base, String path) {
    String normalize(String raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || trimmed == '/') {
        return '';
      }
      return trimmed
          .replaceAll(RegExp(r'^/+'), '')
          .replaceAll(RegExp(r'/+'), '/');
    }

    final segments = <String>[];
    final baseNormalized = normalize(base);
    final pathNormalized = normalize(path);
    if (baseNormalized.isNotEmpty) {
      segments.addAll(baseNormalized.split('/'));
    }
    if (pathNormalized.isNotEmpty) {
      segments.addAll(pathNormalized.split('/'));
    }
    if (segments.isEmpty) {
      return '/';
    }
    return '/${segments.join('/')}';
  }

  Future<Map<String, dynamic>> _fetchHealthSnapshot(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Estado inesperado ${response.statusCode} para ${uri.toString()}',
        );
      }
      final body = await response.transform(utf8.decoder).join();
      final decoded = json.decode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw const FormatException('La respuesta del health no es un objeto');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _launchWithAcquiredLock({
    required Map<String, String> env,
    required Directory supportDir,
    required File backendHashFile,
    required RandomAccessFile lockHandle,
  }) async {
    _activeLockHandle = lockHandle;
    await _writeStatus(
      BackendLaunchInfo(
        phase: BackendLaunchInfo.phaseStarting,
        message: 'Inicializando backend embebido...',
        logPath: _logFile?.path,
        source: 'flutter',
      ),
    );

    final assetHash = await _readAssetHash();
    final storedHash = await _readStoredHash(backendHashFile);
    final extractedDir = Directory(_extractedAppDirPath(supportDir.path));
    final needsUnpack =
        !await extractedDir.exists() ||
        assetHash == null ||
        assetHash != storedHash;

    _log(
      'Launcher context: extractedDir=${extractedDir.path}, '
      'exists=${await extractedDir.exists()}, assetHash=${assetHash ?? '<none>'}, '
      'storedHash=${storedHash ?? '<none>'}, needsUnpack=$needsUnpack',
    );

    _pendingHashValue = null;
    _pendingHashFile = null;

    if (needsUnpack) {
      _updateState(BackendState.unpacking);
      if (assetHash != null) {
        _pendingHashValue = assetHash;
        _pendingHashFile = backendHashFile;
      } else if (await backendHashFile.exists()) {
        await backendHashFile.delete();
      }
    } else {
      _updateState(BackendState.starting);
    }

    try {
      _log('Launching main backend script...');
      await _runMainScript(env: env, maxWait: _primaryPingTimeout);
      await _writeStatus(
        BackendLaunchInfo(
          phase: BackendLaunchInfo.phaseSuccess,
          message: 'Backend disponible y respondiendo.',
          logPath: _logFile?.path,
          token: env['VIDRA_SERVER_TOKEN'],
          source: 'flutter',
        ),
      );
      await _releaseLaunchLock();
    } catch (error, stackTrace) {
      await _writeStatus(
        BackendLaunchInfo(
          phase: BackendLaunchInfo.phaseError,
          message: 'Fallo al iniciar backend: $error',
          traceback: stackTrace.toString(),
          logPath: _logFile?.path,
          source: 'flutter',
        ),
      );
      await _releaseLaunchLock();
      rethrow;
    }
  }

  Future<void> _handlePeerLaunch({
    required Map<String, String> env,
    required File backendHashFile,
    required Directory supportDir,
  }) async {
    if (_lockFile == null) {
      throw StateError('Launch lock file not prepared.');
    }
    _log('Launch lock busy. Waiting for existing startup sequence.');
    await _waitForLockRelease();
    final info = await _readStatus();
    if (info != null) {
      _log('Observed backend status: ${info.phase} (${info.message ?? ''}).');
    }

    final host = env['VIDRA_SERVER_HOST'] ?? '127.0.0.1';
    final port = int.tryParse(env['VIDRA_SERVER_PORT'] ?? '') ?? 5000;
    final reuseSucceeded = await _waitForBackendPing(
      host,
      port,
      _reusePingTimeout,
    );
    if (reuseSucceeded) {
      _log('Backend responded after waiting for peer launch.');
      await _writeStatus(
        BackendLaunchInfo(
          phase: BackendLaunchInfo.phaseReused,
          message: 'Se reutilizó una instancia existente (lock liberado).',
          logPath: _logFile?.path,
          token: info?.token,
          source: 'flutter',
        ),
      );
      _startPortMonitor(host, port);
      _updateState(BackendState.running);
      return;
    }

    _log('Peer launch did not reach ready state. Retrying startup.');
    final newLock = await _waitForLaunchLock();
    await _writeStatus(
      BackendLaunchInfo(
        phase: BackendLaunchInfo.phaseStarting,
        message: 'Intentando reiniciar backend tras lock liberado.',
        logPath: _logFile?.path,
        source: 'flutter',
      ),
    );
    await _launchWithAcquiredLock(
      env: env,
      supportDir: supportDir,
      backendHashFile: backendHashFile,
      lockHandle: newLock,
    );
  }

  Future<void> _runMainScript({
    required Map<String, String> env,
    required Duration maxWait,
  }) async {
    _log(
      'Starting Serious Python run for $_mainScript '
      '(env=${env.length} vars).',
    );

    final runFuture = SeriousPython.run(
      _assetArchivePath,
      appFileName: _mainScript,
      environmentVariables: env.isEmpty ? null : env,
      sync: false,
    );
    _trackRunFuture(runFuture);
    final host = env['VIDRA_SERVER_HOST'] ?? '127.0.0.1';
    final port = int.tryParse(env['VIDRA_SERVER_PORT'] ?? '') ?? 5000;
    _updateState(BackendState.starting);
    try {
      await _waitForBackendReady(host, port, maxWait);
    } on TimeoutException catch (error) {
      _handleBackendStopped('Timed out waiting for $host:$port: $error');
      rethrow;
    }
    _startPortMonitor(host, port);
    _updateState(BackendState.running);
  }

  void _trackRunFuture(Future<String?> runFuture) {
    final exitCompleter = Completer<void>();
    _backendRunExitCompleter = exitCompleter;
    runFuture
        .then((result) {
          final scriptInfo = result?.isNotEmpty == true ? result : _mainScript;
          _log('SeriousPython.run started background task ($scriptInfo).');
        })
        .catchError((error, stackTrace) async {
          if (!exitCompleter.isCompleted) {
            exitCompleter.completeError(
              error,
              stackTrace is StackTrace ? stackTrace : StackTrace.current,
            );
          }
          await _handleUnexpectedBackendExit(
            'SeriousPython.run future error: $error',
            stackTrace: stackTrace is StackTrace ? stackTrace : null,
          );
        })
        .whenComplete(() {
          if (identical(_backendRunExitCompleter, exitCompleter)) {
            _backendRunExitCompleter = null;
          }
        });
  }

  Future<void> _waitForBackendReady(
    String host,
    int port,
    Duration maxWait,
  ) async {
    var attempt = 1;
    final deadline = DateTime.now().add(maxWait);
    while (true) {
      if (await _isPortOpen(host, port)) {
        _log(
          'Backend accepted TCP connection on attempt $attempt for '
          '$host:$port',
        );
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Backend did not open $host:$port in time.');
      }
      final delay = _retryDelayForAttempt(attempt);
      final delayFuture = Future<void>.delayed(delay);
      if (_backendRunExitCompleter != null) {
        await Future.any(<Future<void>>[
          delayFuture,
          _backendRunExitCompleter!.future,
        ]);
      } else {
        await delayFuture;
      }
      attempt += 1;
    }
  }

  Duration _retryDelayForAttempt(int attempt) {
    if (attempt <= 40) {
      return const Duration(milliseconds: 250);
    }
    if (attempt <= 100) {
      return const Duration(seconds: 1);
    }
    return const Duration(seconds: 2);
  }

  Future<bool> _isPortOpen(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 250),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _startPortMonitor(String host, int port) {
    _portMonitorTimer?.cancel();
    _portMonitorTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final alive = await _isPortOpen(host, port);
      if (!alive) {
        _log(
          'Health monitor lost connection to $host:$port; '
          'marking backend stopped.',
        );
        _handleBackendStopped('Port monitor detected failure on $host:$port');
      }
    });
  }

  void _handleBackendStopped(String reason) {
    _log(reason);
    _portMonitorTimer?.cancel();
    _portMonitorTimer = null;
    _launchFuture = null;
    _updateState(BackendState.stopped);
  }

  Future<void> _handleUnexpectedBackendExit(
    String message, {
    StackTrace? stackTrace,
  }) async {
    if (!(_backendRunExitCompleter?.isCompleted ?? true)) {
      _backendRunExitCompleter!.completeError(StateError(message), stackTrace);
    }
    _log(message);
    debugPrint(stackTrace?.toString());
    await _writeStatus(
      BackendLaunchInfo(
        phase: BackendLaunchInfo.phaseError,
        message: message,
        traceback: stackTrace?.toString(),
        logPath: _logFile?.path,
        source: 'flutter',
      ),
    );
    await _releaseLaunchLock();
    _handleBackendStopped(message);
  }

  Future<String?> _readAssetHash() async {
    try {
      final value = await rootBundle.loadString(_assetHashAssetPath);
      return value.trim();
    } catch (error) {
      debugPrint('Could not read asset hash: $error');
      return null;
    }
  }

  Future<String?> _readStoredHash(File backendHashFile) async {
    if (!await backendHashFile.exists()) {
      return null;
    }
    try {
      return (await backendHashFile.readAsString()).trim();
    } catch (error) {
      debugPrint('Could not read backend hash file: $error');
      return null;
    }
  }

  String _extractedAppDirPath(String supportDirPath) {
    final archiveDirName = p.dirname(_assetArchivePath);
    return p.join(supportDirPath, 'flet', archiveDirName);
  }

  void _updateState(BackendState state) {
    final previous = _stateNotifier.value;
    if (previous == state) {
      return;
    }
    _log('Backend state transition: ${_stateNotifier.value} -> $state');
    _stateNotifier.value = state;
    if (previous == BackendState.unpacking && state == BackendState.running) {
      _persistPendingHash();
    }
  }

  void _log(String message) {
    debugPrint('[SeriousPythonLauncher] $message');
  }

  void _persistPendingHash() {
    final hash = _pendingHashValue;
    final file = _pendingHashFile;
    _pendingHashValue = null;
    _pendingHashFile = null;
    if (hash == null || file == null) {
      return;
    }
    unawaited(_writeHashAsync(file, hash));
  }

  Future<void> _writeHashAsync(File file, String hash) async {
    try {
      await file.writeAsString(hash);
    } catch (error) {
      debugPrint('Could not write backend hash file: $error');
    }
  }

  Future<_BackendPaths> _prepareBackendPaths() async {
    final supportDir = await getApplicationSupportDirectory();
    final backendDir = Directory(p.join(supportDir.path, _backendFolderName));
    await backendDir.create(recursive: true);
    final statusFile = File(p.join(backendDir.path, _statusFileName));
    final lockFile = File(p.join(backendDir.path, _lockFileName));
    final logFile = File(p.join(backendDir.path, _logFileName));
    return _BackendPaths(
      supportDir: supportDir,
      backendDir: backendDir,
      statusFile: statusFile,
      lockFile: lockFile,
      logFile: logFile,
    );
  }

  Future<RandomAccessFile?> _tryAcquireLaunchLock() async {
    final file = _lockFile;
    if (file == null) {
      return null;
    }
    try {
      await file.create(recursive: true);
      final handle = await file.open(mode: FileMode.writeOnlyAppend);
      try {
        await handle
            .lock(FileLock.exclusive)
            .timeout(const Duration(milliseconds: 150));
        return handle;
      } on TimeoutException {
        await handle.close();
        return null;
      }
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _waitForLockRelease() async {
    while (true) {
      final probe = await _tryAcquireLaunchLock();
      if (probe != null) {
        await _releaseLockHandle(probe);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<RandomAccessFile> _waitForLaunchLock() async {
    while (true) {
      final handle = await _tryAcquireLaunchLock();
      if (handle != null) {
        return handle;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<void> _releaseLaunchLock() async {
    final handle = _activeLockHandle;
    if (handle != null) {
      await _releaseLockHandle(handle);
      _activeLockHandle = null;
    }
  }

  Future<void> _releaseLockHandle(RandomAccessFile handle) async {
    try {
      await handle.unlock();
    } catch (_) {
      // ignored
    }
    try {
      await handle.close();
    } catch (_) {
      // ignored
    }
  }

  Future<void> _writeStatus(BackendLaunchInfo info) async {
    final file = _statusFile;
    if (file == null) {
      return;
    }
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(info.toJson()));
      _launchInfoNotifier.value = info;
    } catch (error) {
      debugPrint('Could not write backend status file: $error');
    }
  }

  Future<BackendLaunchInfo?> _readStatus() async {
    final file = _statusFile;
    if (file == null || !await file.exists()) {
      return null;
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final info = BackendLaunchInfo.fromJson(decoded);
      if (info != null) {
        _launchInfoNotifier.value = info;
      }
      return info;
    } catch (error) {
      debugPrint('Could not read backend status file: $error');
      return null;
    }
  }

  Future<bool> _waitForBackendPing(
    String host,
    int port,
    Duration timeout,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _isPortOpen(host, port)) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }
}

class _BackendPaths {
  _BackendPaths({
    required this.supportDir,
    required this.backendDir,
    required this.statusFile,
    required this.lockFile,
    required this.logFile,
  });

  final Directory supportDir;
  final Directory backendDir;
  final File statusFile;
  final File lockFile;
  final File logFile;
}

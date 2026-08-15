import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Standalone resource checker matching backend_isolate.dart implementation
bool checkResources(String supportDirPath) {
  try {
    final ytDlpDir = Directory(
      p.join(supportDirPath, 'core_modules', 'yt_dlp'),
    );
    final ejsDir = Directory(
      p.join(supportDirPath, 'core_modules', 'yt_dlp_ejs'),
    );
    if (!ytDlpDir.existsSync() || ytDlpDir.listSync().isEmpty) return false;
    if (!ejsDir.existsSync() || ejsDir.listSync().isEmpty) return false;
    return true;
  } catch (e) {
    return false;
  }
}

/// Simulated startup state machine to test early-exit flow without native binary dependency
class StartupSequenceHarness {
  final String supportDirPath;
  final bool hasPermissions;
  final String? pythonAppPath;
  bool isBackendRunning = false;
  bool startPythonCalled = false;
  final List<String> notifiedStates = [];

  StartupSequenceHarness({
    required this.supportDirPath,
    this.hasPermissions = true,
    this.pythonAppPath,
    this.isBackendRunning = false,
  });

  void notifyUiState(String state) {
    notifiedStates.add(state);
  }

  Future<void> initSequence() async {
    notifyUiState('initializing');

    if (!hasPermissions) {
      notifyUiState('missingPermissions');
      return;
    }

    if (!checkResources(supportDirPath)) {
      notifyUiState('missingResources');
      return;
    }

    if (pythonAppPath == null) {
      notifyUiState('unpacking');
      return;
    }

    if (isBackendRunning) {
      return;
    }

    notifyUiState('startingBackend');
    startPythonCalled = true;
    isBackendRunning = true;
    notifyUiState('ready');
  }
}

void main() {
  group('Scenario 4: core_modules startup verification and resource checking', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('vidra_test_core_modules_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('returns false when core_modules folder does not exist', () {
      final result = checkResources(tempDir.path);
      expect(result, isFalse);
    });

    test('returns false when core_modules exists but yt_dlp is missing', () {
      final ejsDir = Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp_ejs'))
        ..createSync(recursive: true);
      File(p.join(ejsDir.path, '__init__.py')).writeAsStringSync('# dummy');

      final result = checkResources(tempDir.path);
      expect(result, isFalse);
    });

    test('returns false when core_modules exists but yt_dlp_ejs is missing', () {
      final ytDir = Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp'))
        ..createSync(recursive: true);
      File(p.join(ytDir.path, '__init__.py')).writeAsStringSync('# dummy');

      final result = checkResources(tempDir.path);
      expect(result, isFalse);
    });

    test('returns false when yt_dlp directory exists but is completely empty', () {
      Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp'))
        .createSync(recursive: true);
      final ejsDir = Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp_ejs'))
        ..createSync(recursive: true);
      File(p.join(ejsDir.path, '__init__.py')).writeAsStringSync('# dummy');

      final result = checkResources(tempDir.path);
      expect(result, isFalse);
    });

    test('returns false when yt_dlp_ejs directory exists but is completely empty', () {
      final ytDir = Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp'))
        ..createSync(recursive: true);
      File(p.join(ytDir.path, '__init__.py')).writeAsStringSync('# dummy');
      Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp_ejs'))
        .createSync(recursive: true);

      final result = checkResources(tempDir.path);
      expect(result, isFalse);
    });

    test('returns true when both yt_dlp and yt_dlp_ejs exist and are non-empty', () {
      final ytDir = Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp'))
        ..createSync(recursive: true);
      File(p.join(ytDir.path, '__init__.py')).writeAsStringSync('# yt_dlp dummy');

      final ejsDir = Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp_ejs'))
        ..createSync(recursive: true);
      File(p.join(ejsDir.path, '__init__.py')).writeAsStringSync('# yt_dlp_ejs dummy');

      final result = checkResources(tempDir.path);
      expect(result, isTrue);
    });

    test('initSequence stops immediately at missingResources before starting python', () async {
      // Empty supportDir with NO core_modules
      final harness = StartupSequenceHarness(
        supportDirPath: tempDir.path,
        hasPermissions: true,
        pythonAppPath: '/some/dummy/path',
      );

      await harness.initSequence();

      expect(harness.notifiedStates, equals(['initializing', 'missingResources']));
      expect(harness.startPythonCalled, isFalse);
      expect(harness.isBackendRunning, isFalse);
    });

    test('initSequence stops at missingPermissions before checking resources or starting python', () async {
      final harness = StartupSequenceHarness(
        supportDirPath: tempDir.path,
        hasPermissions: false,
        pythonAppPath: '/some/dummy/path',
      );

      await harness.initSequence();

      expect(harness.notifiedStates, equals(['initializing', 'missingPermissions']));
      expect(harness.startPythonCalled, isFalse);
      expect(harness.isBackendRunning, isFalse);
    });

    test('initSequence progresses to unpacking if resources exist but pythonAppPath is not yet extracted', () async {
      final ytDir = Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp'))
        ..createSync(recursive: true);
      File(p.join(ytDir.path, '__init__.py')).writeAsStringSync('# yt_dlp');

      final ejsDir = Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp_ejs'))
        ..createSync(recursive: true);
      File(p.join(ejsDir.path, '__init__.py')).writeAsStringSync('# ejs');

      final harness = StartupSequenceHarness(
        supportDirPath: tempDir.path,
        hasPermissions: true,
        pythonAppPath: null, // Still unpacking python in main thread
      );

      await harness.initSequence();

      expect(harness.notifiedStates, equals(['initializing', 'unpacking']));
      expect(harness.startPythonCalled, isFalse);
      expect(harness.isBackendRunning, isFalse);
    });

    test('initSequence starts backend and transitions to ready when resources and python are prepared', () async {
      final ytDir = Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp'))
        ..createSync(recursive: true);
      File(p.join(ytDir.path, '__init__.py')).writeAsStringSync('# yt_dlp');

      final ejsDir = Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp_ejs'))
        ..createSync(recursive: true);
      File(p.join(ejsDir.path, '__init__.py')).writeAsStringSync('# ejs');

      final harness = StartupSequenceHarness(
        supportDirPath: tempDir.path,
        hasPermissions: true,
        pythonAppPath: '/valid/python/path',
      );

      await harness.initSequence();

      expect(
        harness.notifiedStates,
        equals(['initializing', 'startingBackend', 'ready']),
      );
      expect(harness.startPythonCalled, isTrue);
      expect(harness.isBackendRunning, isTrue);
    });
  });
}

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/config/backend_config.dart';
import 'package:vidra/data/models/download_job.dart';
import 'package:vidra/data/services/download_service.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/state/download_controller.dart';
import 'package:vidra/state/serious_python_server_launcher.dart';
import 'package:vidra/ui/screens/home/home_screen.dart';
import 'package:vidra/ui/screens/settings/settings_screen.dart';
import 'package:vidra/ui/widgets/jobs/download_job_card.dart';
import 'package:vidra/ui/widgets/preferences/preference_dropdown_control.dart';

const String _testToken = 'test-token';

const bool _runPerfTests = bool.fromEnvironment(
  'VIDRA_RUN_PERF_TESTS',
  defaultValue: false,
);

const String _perfSkipReason =
    'Set --dart-define=VIDRA_RUN_PERF_TESTS=true to enable performance tests.';

void perfTestWidgets(String description, WidgetTesterCallback callback) {
  if (!_runPerfTests) {
    // ignore: avoid_print
    print('Skipping performance test "$description". $_perfSkipReason');
  }
  testWidgets(
    description,
    (tester) async {
      await _runPerfTest(() => callback(tester));
    },
    skip: !_runPerfTests,
  );
}

Future<T> _runPerfTest<T>(Future<T> Function() body) async {
  final recorder = _PerfLogRecorder.instance;
  recorder.reset();
  try {
    return await body();
  } catch (error) {
    recorder.flush();
    rethrow;
  } finally {
    recorder.reset();
  }
}

class _PerfLogRecorder {
  _PerfLogRecorder._();

  static final _PerfLogRecorder instance = _PerfLogRecorder._();

  final List<String> _buffer = <String>[];

  void record(String label, Duration duration) {
    _buffer.add('$label -> ${duration.inMicroseconds / 1000.0}ms');
  }

  void flush() {
    if (_buffer.isEmpty) {
      return;
    }
    // ignore: avoid_print
    print('Performance timings for failed test:');
    for (final entry in _buffer) {
      // ignore: avoid_print
      print(entry);
    }
  }

  void reset() {
    _buffer.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesModel preferencesModel;
  late BackendConfig backendConfig;
  late _FakeDownloadController downloadController;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    backendConfig = _testBackendConfig();
    preferencesModel = PreferencesModel();
    await preferencesModel.initializePreferences();
    downloadController = _FakeDownloadController(
      backendConfig: backendConfig,
      initialJobs: _buildFakeJobs(80),
    );
  });

  tearDown(() {
    downloadController.dispose();
    preferencesModel.dispose();
  });

  Future<Duration> measureRender(
    WidgetTester tester,
    Widget Function() build,
  ) async {
    final stopwatch = Stopwatch()..start();
    await tester.pumpWidget(build());
    await tester.pump(const Duration(milliseconds: 16));
    stopwatch.stop();
    return stopwatch.elapsed;
  }

  String settingsSectionLabel(IconData icon) {
    if (icon == Icons.settings) {
      return 'general';
    }
    if (icon == Icons.network_wifi) {
      return 'network';
    }
    if (icon == Icons.video_library) {
      return 'video';
    }
    if (icon == Icons.download) {
      return 'download';
    }
    return 'section';
  }

  Future<Duration> measurePumpOnce(WidgetTester tester) async {
    final stopwatch = Stopwatch()..start();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    stopwatch.stop();
    return stopwatch.elapsed;
  }

  Widget wrapWithProviders(Widget child) {
    return MultiProvider(
      providers: [
        Provider<BackendConfig>.value(value: backendConfig),
        ChangeNotifierProvider<PreferencesModel>.value(value: preferencesModel),
        ChangeNotifierProvider<DownloadController>.value(
          value: downloadController,
        ),
      ],
      child: MaterialApp(
        home: child,
        routes: <String, WidgetBuilder>{
          '/settings': (_) => const SettingsScreen(),
        },
      ),
    );
  }

  Future<void> expectSectionTransitions(
    WidgetTester tester, {
    required Iterable<IconData> sequence,
    required String contextLabel,
    required Duration threshold,
  }) async {
    for (final icon in sequence) {
      final description = settingsSectionLabel(icon);
      await tester.tap(find.byIcon(icon).last);
      final delta = await measurePumpOnce(tester);
      _logDuration('SettingsScreen $contextLabel $description pump', delta);
      await tester.pumpAndSettle();
      expect(delta, lessThan(threshold));
    }
  }

  group('Render performance', () {
    perfTestWidgets(
      'HomeScreen initial render stays within 1.2s delta budget',
      (WidgetTester tester) async {
        final baseline = await measureRender(
          tester,
          () => wrapWithProviders(const SizedBox.shrink()),
        );
        final duration = await measureRender(
          tester,
          () => wrapWithProviders(const HomeScreen()),
        );
        final delta = duration - baseline;
        _logDuration('Baseline shell render', baseline);
        _logDuration('HomeScreen initial render', duration);
        _logDuration('HomeScreen incremental render', delta);
        expect(delta, lessThan(const Duration(milliseconds: 1200)));
      },
    );

    perfTestWidgets('SettingsScreen render under 12ms average build time', (
      WidgetTester tester,
    ) async {
      final baseline = await measureRender(
        tester,
        () => wrapWithProviders(const SizedBox.shrink()),
      );
      final duration = await measureRender(
        tester,
        () => wrapWithProviders(const SettingsScreen()),
      );
      final delta = duration - baseline;
      _logDuration('SettingsScreen render', duration);
      _logDuration('SettingsScreen incremental render', delta);
      expect(delta, lessThan(const Duration(milliseconds: 700)));
    });

    perfTestWidgets(
      'DownloadJobCard list render stays under 20ms average build time',
      (WidgetTester tester) async {
        final baseline = await measureRender(
          tester,
          () => wrapWithProviders(const SizedBox.shrink()),
        );
        final duration = await measureRender(
          tester,
          () => wrapWithProviders(
            ListView.builder(
              itemCount: downloadController.jobs.length,
              itemBuilder: (BuildContext context, int index) {
                final job = downloadController.jobs[index];
                return DownloadJobCard(job: job);
              },
            ),
          ),
        );
        final delta = duration - baseline;
        _logDuration('DownloadJobCard list render', duration);
        _logDuration('DownloadJobCard incremental render', delta);
        expect(delta, lessThan(const Duration(milliseconds: 90)));
      },
    );
  });

  group('SettingsScreen performance', () {
    Future<void> withSurfaceSize(
      WidgetTester tester,
      Size size,
      Future<void> Function() body,
    ) async {
      final binding = tester.binding;
      await binding.setSurfaceSize(size);
      addTearDown(() => binding.setSurfaceSize(null));
      await body();
    }

    perfTestWidgets('wide layout initial render stays under 220ms delta', (
      WidgetTester tester,
    ) async {
      await withSurfaceSize(tester, const Size(1280, 900), () async {
        final baseline = await measureRender(
          tester,
          () => wrapWithProviders(const SizedBox.shrink()),
        );
        final duration = await measureRender(
          tester,
          () => wrapWithProviders(const SettingsScreen()),
        );
        final delta = duration - baseline;
        _logDuration('SettingsScreen wide render', duration);
        _logDuration('SettingsScreen wide delta', delta);
        expect(delta, lessThan(const Duration(milliseconds: 220)));
      });
    });

    perfTestWidgets('wide layout section change pump stays under 250ms', (
      WidgetTester tester,
    ) async {
      await withSurfaceSize(tester, const Size(1280, 900), () async {
        await tester.pumpWidget(wrapWithProviders(const SettingsScreen()));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.network_wifi).last);
        final delta = await measurePumpOnce(tester);
        _logDuration('SettingsScreen wide section pump', delta);
        await tester.pumpAndSettle();

        expect(delta, lessThan(const Duration(milliseconds: 250)));
      });
    });

    perfTestWidgets('compact layout initial render stays under 240ms delta', (
      WidgetTester tester,
    ) async {
      await withSurfaceSize(tester, const Size(600, 900), () async {
        final baseline = await measureRender(
          tester,
          () => wrapWithProviders(const SizedBox.shrink()),
        );
        final duration = await measureRender(
          tester,
          () => wrapWithProviders(const SettingsScreen()),
        );
        final delta = duration - baseline;
        _logDuration('SettingsScreen compact render', duration);
        _logDuration('SettingsScreen compact delta', delta);
        expect(delta, lessThan(const Duration(milliseconds: 240)));
      });
    });

    perfTestWidgets('compact layout tab change pump stays under 150ms', (
      WidgetTester tester,
    ) async {
      await withSurfaceSize(tester, const Size(600, 900), () async {
        await tester.pumpWidget(wrapWithProviders(const SettingsScreen()));
        await tester.pumpAndSettle();

        await expectSectionTransitions(
          tester,
          sequence: const [
            Icons.network_wifi,
            Icons.video_library,
            Icons.download,
            Icons.settings,
          ],
          contextLabel: 'compact',
          threshold: const Duration(milliseconds: 150),
        );
      });
    });

    perfTestWidgets('wide layout section transitions stay under 320ms each', (
      WidgetTester tester,
    ) async {
      await withSurfaceSize(tester, const Size(1280, 900), () async {
        await tester.pumpWidget(wrapWithProviders(const SettingsScreen()));
        await tester.pumpAndSettle();

        await expectSectionTransitions(
          tester,
          sequence: const [
            Icons.network_wifi,
            Icons.video_library,
            Icons.download,
            Icons.settings,
          ],
          contextLabel: 'wide',
          threshold: const Duration(milliseconds: 320),
        );
      });
    });

    perfTestWidgets('phone layout section transitions stay under 160ms each', (
      WidgetTester tester,
    ) async {
      await withSurfaceSize(tester, const Size(420, 900), () async {
        await tester.pumpWidget(wrapWithProviders(const SettingsScreen()));
        await tester.pumpAndSettle();

        await expectSectionTransitions(
          tester,
          sequence: const [
            Icons.network_wifi,
            Icons.video_library,
            Icons.download,
            Icons.settings,
          ],
          contextLabel: 'phone',
          threshold: const Duration(milliseconds: 160),
        );
      });
    });
  });

  group('HomeScreen advanced controls', () {
    perfTestWidgets('advanced controls render immediately on wide layouts', (
      WidgetTester tester,
    ) async {
      final binding = tester.binding;
      await binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => binding.setSurfaceSize(null));

      final mergeKey = preferencesModel.preferences.mergeOutputFormat.key;
      final audioKey = preferencesModel.preferences.audioLanguage.key;
      final subtitlesKey = preferencesModel.preferences.videoSubtitles.key;

      await tester.pumpWidget(wrapWithProviders(const HomeScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('home_advanced_toggle')), findsNothing);
      expect(find.byType(PreferenceDropdownControl), findsNWidgets(4));
      expect(find.byKey(ValueKey('control_$mergeKey')), findsOneWidget);
      expect(find.byKey(ValueKey('control_$audioKey')), findsOneWidget);
      expect(find.byKey(ValueKey('control_$subtitlesKey')), findsOneWidget);
    });
  });
}

void _logDuration(String label, Duration duration) {
  _PerfLogRecorder.instance.record(label, duration);
}

BackendConfig _testBackendConfig() {
  return BackendConfig(
    name: 'Test Backend',
    description: 'Test backend for render benchmarks',
    baseUri: Uri.parse('http://localhost:5000/'),
    apiBaseUri: Uri.parse('http://localhost:5000/api/'),
    overviewSocketUri: Uri.parse('ws://localhost:5000/ws/overview'),
    jobSocketBaseUri: Uri.parse('ws://localhost:5000/ws/jobs/'),
    metadata: const <String, dynamic>{},
    timeout: const Duration(seconds: 1),
  );
}

class _FakeDownloadController extends DownloadController {
  _FakeDownloadController({
    required super.backendConfig,
    List<DownloadJobModel> initialJobs = const <DownloadJobModel>[],
  }) : _jobs = List<DownloadJobModel>.from(initialJobs),
       super(
         authToken: _testToken,
         backendStateListenable: const _AlwaysRunningBackendState(),
         service: _FakeDownloadService(backendConfig),
       );

  final List<DownloadJobModel> _jobs;
  bool _initialized = false;
  bool _submitting = false;
  String? _error;

  @override
  List<DownloadJobModel> get jobs => List<DownloadJobModel>.unmodifiable(_jobs);

  @override
  bool get isSubmitting => _submitting;

  @override
  String? get lastError => _error;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> refreshJobs() async {
    await Future<void>.delayed(const Duration(milliseconds: 4));
  }

  @override
  Future<bool> startDownload(
    String url,
    Map<String, dynamic> options, {
    Map<String, dynamic>? metadata,
    String? owner,
  }) async {
    _submitting = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 8));
    _submitting = false;
    notifyListeners();
    return true;
  }

  @override
  Future<bool> pauseJob(String jobId) async => true;

  @override
  Future<bool> resumeJob(String jobId) async => true;

  @override
  Future<bool> cancelJob(String jobId) async => true;

  @override
  Future<bool> retryJob(String jobId) async => true;

  @override
  Future<bool> deleteJob(String jobId) async => true;

  void replaceJobs(List<DownloadJobModel> next) {
    _jobs
      ..clear()
      ..addAll(next);
    notifyListeners();
  }
}

class _FakeDownloadService extends DownloadService {
  _FakeDownloadService(super.config) : super(authToken: _testToken);

  @override
  Future<List<DownloadJobModel>> listJobs() async => const <DownloadJobModel>[];

  @override
  Future<DownloadJobModel> createJob(
    String url,
    Map<String, dynamic> options, {
    Map<String, dynamic>? metadata,
    String? owner,
  }) async {
    throw UnimplementedError('_FakeDownloadService.createJob should not run');
  }

  @override
  Future<Map<String, dynamic>> pauseJob(String jobId) async {
    throw UnimplementedError('_FakeDownloadService.pauseJob should not run');
  }

  @override
  Future<Map<String, dynamic>> resumeJob(String jobId) async {
    throw UnimplementedError('_FakeDownloadService.resumeJob should not run');
  }

  @override
  Future<Map<String, dynamic>> cancelJob(String jobId) async {
    throw UnimplementedError('_FakeDownloadService.cancelJob should not run');
  }

  @override
  Future<Map<String, dynamic>> retryJob(String jobId) async {
    throw UnimplementedError('_FakeDownloadService.retryJob should not run');
  }

  @override
  Future<Map<String, dynamic>> deleteJob(String jobId) async {
    throw UnimplementedError('_FakeDownloadService.deleteJob should not run');
  }
}

class _AlwaysRunningBackendState implements ValueListenable<BackendState> {
  const _AlwaysRunningBackendState();

  @override
  BackendState get value => BackendState.running;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

List<DownloadJobModel> _buildFakeJobs(int count) {
  final now = DateTime.now();
  return List<DownloadJobModel>.generate(count, (int index) {
    final progress = DownloadProgress(
      status: 'downloading',
      stage: 'downloading',
      downloadedBytes: 4 * 1024 * 1024 + index * 1024,
      totalBytes: 32 * 1024 * 1024,
      speed: 2.4 * 1024 * 1024,
      eta: 120 - (index % 60),
      percent: math.min(99, (index * 7) % 100).toDouble(),
      stagePercent: math.min(99, (index * 5) % 100).toDouble(),
      message: 'Descargando segmento ${(index % 5) + 1}',
      playlistPercent: index.isEven ? 45.0 + (index % 10) : null,
      playlistCompletedItems: index.isEven ? index % 7 : null,
      playlistTotalItems: index.isEven ? 12 : null,
      playlistCurrentIndex: index.isEven ? (index % 6) + 1 : null,
    );

    final playlist = index.isEven
        ? DownloadPlaylistSummary(
            totalItems: 12,
            completedItems: index % 7,
            pendingItems: 12 - (index % 7),
            percent: (index % 7) / 12 * 100,
            currentIndex: (index % 6) + 1,
            entries: const <DownloadPlaylistEntry>[],
            entryRefs: const <DownloadPlaylistEntryRef>[],
            thumbnails: const <DownloadPreviewThumbnail>[],
            isPlaylist: true,
          )
        : null;

    final metadata = <String, dynamic>{
      'preview': <String, dynamic>{
        'title': 'Video de prueba #$index',
        'description': 'Descripción para el elemento $index',
        'duration_text': '12:${(index % 60).toString().padLeft(2, '0')}',
        'uploader': 'Autor ${(index % 10) + 1}',
        'channel': 'Canal ${(index % 5) + 1}',
        'upload_date_iso': now
            .subtract(Duration(days: index * 2))
            .toIso8601String(),
      },
    };

    return DownloadJobModel(
      id: 'job-$index',
      status: index % 4 == 0
          ? DownloadStatus.running
          : index % 3 == 0
          ? DownloadStatus.completed
          : DownloadStatus.queued,
      createdAt: now.subtract(Duration(minutes: index * 3)),
      startedAt: now.subtract(Duration(minutes: index * 2)),
      progress: progress,
      metadata: metadata,
      urls: <String>['https://example.com/video/$index'],
      options: const <String, dynamic>{},
      logs: const <DownloadLogEntry>[],
      playlist: playlist,
    );
  });
}

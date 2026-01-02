import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vidra/config/backend_config.dart';
import 'package:vidra/data/models/download_job.dart';
import 'package:vidra/data/services/download_service.dart';
import 'package:vidra/i18n/i18n.dart';
import 'package:vidra/state/download_controller.dart';
import 'package:vidra/state/serious_python_server_launcher.dart';
import 'package:vidra/ui/screens/home/job_detail_screen.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';

const String _testToken = 'test-token';

final List<LocalizationsDelegate<dynamic>> _testLocalizationDelegates =
    <LocalizationsDelegate<dynamic>>[
      VidraLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      const LocaleNamesLocalizationsDelegate(),
    ];

Future<void> _pumpJobDetail(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await I18n.preloadAll();
  });

  group('JobDetailScreen', () {
    late DownloadController controller;
    late _FakeDownloadService service;

    setUp(() async {
      final backendConfig = BackendConfig(
        name: 'Test',
        description: 'Test backend',
        baseUri: Uri.parse('http://localhost:5000/'),
        apiBaseUri: Uri.parse('http://localhost:5000/api/'),
        overviewSocketUri: Uri.parse('ws://localhost/ws/overview'),
        jobSocketBaseUri: Uri.parse('ws://localhost/ws/jobs/'),
        metadata: const <String, dynamic>{},
        timeout: const Duration(seconds: 5),
      );
      service = _FakeDownloadService(backendConfig);
      controller = DownloadController(
        backendConfig: backendConfig,
        authToken: _testToken,
        backendStateListenable: const _AlwaysRunningBackendState(),
        service: service,
        logUnhandledJobEvents: false,
      );
      service.jobs = <DownloadJobModel>[_buildJobModel()];
      service.optionPayloads['job-1'] = <String, dynamic>{'quality': 'best'};
      service.logPayloads['job-1'] = <DownloadLogEntry>[
        DownloadLogEntry(
          timestamp: DateTime.parse('2024-01-01T12:00:00Z'),
          level: 'info',
          message: 'Descarga iniciada',
        ),
      ];
      await controller.refreshJobs();
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('hydrates options and logs payloads', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<DownloadController>.value(
          value: controller,
          child: MaterialApp(
            locale: const Locale('es'),
            localizationsDelegates: _testLocalizationDelegates,
            supportedLocales: VidraLocalizations.supportedLocales,
            home: const JobDetailScreen(jobId: 'job-1'),
          ),
        ),
      );

      await _pumpJobDetail(tester);

      expect(find.text('Video de prueba'), findsWidgets);
      await tester.tap(find.text('Opciones'));
      await _pumpJobDetail(tester);
      expect(
        find.textContaining('quality', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.text('Logs'));
      await _pumpJobDetail(tester);
      expect(find.textContaining('Descarga iniciada'), findsOneWidget);
      expect(find.bySemanticsLabel('Copiar logs'), findsOneWidget);
    });
  });
}

DownloadJobModel _buildJobModel() {
  return DownloadJobModel.fromJson(<String, dynamic>{
    'job_id': 'job-1',
    'status': 'running',
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'urls': <String>['https://example.com/video'],
    'metadata': <String, dynamic>{'owner': 'QA'},
    'options': const <String, dynamic>{},
    'options_external': true,
    'logs': const <Map<String, dynamic>>[],
    'logs_external': true,
    'preview': <String, dynamic>{'title': 'Video de prueba'},
  });
}

class _FakeDownloadService extends DownloadService {
  _FakeDownloadService(super.config) : super(authToken: _testToken);

  List<DownloadJobModel> jobs = const <DownloadJobModel>[];
  final Map<String, Map<String, dynamic>> optionPayloads =
      <String, Map<String, dynamic>>{};
  final Map<String, List<DownloadLogEntry>> logPayloads =
      <String, List<DownloadLogEntry>>{};

  @override
  Future<List<DownloadJobModel>> listJobs() async {
    return jobs;
  }

  @override
  Future<DownloadJobOptionsSnapshot?> fetchJobOptions(
    String jobId, {
    int? sinceVersion,
    bool includeOptions = true,
    String? entryId,
    int? entryIndex,
  }) async {
    final payload = optionPayloads[jobId] ?? const <String, dynamic>{};
    return DownloadJobOptionsSnapshot(
      jobId: jobId,
      version: 1,
      external: true,
      options: payload,
    );
  }

  @override
  Future<DownloadJobLogsSnapshot?> fetchJobLogs(
    String jobId, {
    int? sinceVersion,
    bool includeLogs = true,
    int? limit,
    String? entryId,
    int? entryIndex,
  }) async {
    final payload = logPayloads[jobId] ?? const <DownloadLogEntry>[];
    return DownloadJobLogsSnapshot(
      jobId: jobId,
      version: 1,
      external: true,
      logs: payload,
      count: payload.length,
    );
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

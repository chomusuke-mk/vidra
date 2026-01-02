import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:vidra/config/backend_config.dart';
import 'package:vidra/data/models/download_job.dart';
import 'package:vidra/data/services/download_service.dart';
import 'package:vidra/i18n/i18n.dart';
import 'package:vidra/state/download_controller.dart';
import 'package:vidra/state/serious_python_server_launcher.dart';
import 'package:vidra/ui/theme/download_visuals.dart';
import 'package:vidra/ui/widgets/jobs/download_job_card.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';

const String _testToken = 'test-token';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final backendConfig = BackendConfig(
    name: 'Test Backend',
    description: 'Test Backend',
    baseUri: Uri.parse('http://127.0.0.1:5000/'),
    apiBaseUri: Uri.parse('http://127.0.0.1:5000/api/'),
    overviewSocketUri: Uri.parse('ws://127.0.0.1:5000/ws/overview'),
    jobSocketBaseUri: Uri.parse('ws://127.0.0.1:5000/ws/jobs/'),
    metadata: const <String, dynamic>{},
    timeout: const Duration(seconds: 30),
  );

  late DownloadController controller;

  setUpAll(() async {
    await I18n.preloadAll();
  });

  setUp(() {
    controller = DownloadController(
      backendConfig: backendConfig,
      authToken: _testToken,
      backendStateListenable: ValueNotifier<BackendState>(BackendState.running),
      service: DownloadService(
        backendConfig,
        authToken: _testToken,
        httpClient: _NoNetworkClient(),
      ),
      logUnhandledJobEvents: false,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  DownloadJobModel buildJob({
    required String status,
    required Map<String, dynamic> progress,
    String? error,
    Map<String, dynamic>? overrides,
  }) {
    final json = <String, dynamic>{
      'job_id': 'job-${status.toLowerCase()}',
      'status': status,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'progress': progress,
      if (error != null) 'error': error,
      'logs': const <Map<String, dynamic>>[],
    };
    if (overrides != null && overrides.isNotEmpty) {
      json.addAll(overrides);
    }
    return DownloadJobModel.fromJson(json);
  }

  Widget buildTestable(DownloadJobModel job) {
    return ChangeNotifierProvider<DownloadController>.value(
      value: controller,
      child: MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: [
          VidraLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          const LocaleNamesLocalizationsDelegate(),
        ],
        supportedLocales: VidraLocalizations.supportedLocales,
        home: Scaffold(body: DownloadJobCard(job: job, enableActions: false)),
      ),
    );
  }

  Future<void> pumpCard(WidgetTester tester, DownloadJobModel job) async {
    await tester.pumpWidget(buildTestable(job));
    await tester
        .pump(); // Allow a frame for animations without waiting forever.
  }

  testWidgets(
    'Running job keeps stage text color non-error and hides warnings',
    (tester) async {
      final job = buildJob(
        status: 'running',
        progress: {
          'status': 'downloading',
          'stage': 'downloading',
          'message': 'Descarga en progreso',
          'percent': 42.0,
        },
        error: 'Warning: signature extraction partial failure',
      );

      await pumpCard(tester, job);

      final expectedColor = DownloadVisualPalette.stageColor(
        job.progress?.stage,
        status: job.progress?.status,
        postprocessor: job.progress?.postprocessor,
        preprocessor: job.progress?.preprocessor,
        jobStatus: job.status,
      );

      final stageFinder = find.textContaining('Descargando');
      expect(stageFinder, findsOneWidget);
      final stageText = tester.widget<Text>(stageFinder);
      expect(stageText.style?.color, equals(expectedColor));

      expect(
        find.text('Warning: signature extraction partial failure'),
        findsNothing,
      );
    },
  );

  testWidgets('Failed job paints stage text in error color and shows message', (
    tester,
  ) async {
    final job = buildJob(
      status: 'failed',
      progress: {
        'status': 'downloading',
        'stage': 'downloading',
        'message': 'Descarga fallida',
        'percent': 58.0,
      },
      error: 'Signature extraction failed',
    );

    await pumpCard(tester, job);

    final stageFinder = find.textContaining('Descargando');
    expect(stageFinder, findsOneWidget);
    final stageText = tester.widget<Text>(stageFinder);
    expect(
      stageText.style?.color,
      equals(DownloadVisualPalette.stageErrorColor),
    );

    expect(find.text('Signature extraction failed'), findsOneWidget);
  });

  testWidgets('DownloadJobCard expone resumen accesible', (tester) async {
    final job = buildJob(
      status: 'running',
      progress: {
        'status': 'downloading',
        'stage': 'downloading',
        'percent': 42.0,
      },
      overrides: {
        'preview': {'title': 'Video accesible'},
        'playlist': {
          'is_playlist': true,
          'total_items': 10,
          'completed_items': 4,
        },
        'urls': const ['https://example.com/demo'],
        'metadata': const {'requires_playlist_selection': false},
      },
    );

    await pumpCard(tester, job);

    final semanticsWidget = tester.widget<Semantics>(
      find.byKey(const ValueKey('job-card-semantics-job-running')),
    );
    final label = semanticsWidget.properties.label ?? '';
    expect(
      label,
      allOf(
        contains('Video accesible'),
        contains('Descargando'),
        contains('42'),
        contains('Lista de reproducción'),
      ),
    );
  });
}

class _NoNetworkClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError('Network calls are not expected in widget tests.');
  }
}

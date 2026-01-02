import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/config/backend_config.dart';
import 'package:vidra/data/models/download_job.dart';
import 'package:vidra/data/models/playlist_preview.dart';
import 'package:vidra/i18n/i18n.dart';
import 'package:vidra/main.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/state/download_controller.dart';
import 'package:vidra/state/serious_python_server_launcher.dart';
import 'package:vidra/ui/screens/home/home_screen.dart';
import 'package:vidra/ui/screens/home/playlist_selection_dialog.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';

const String _testToken = 'test-token';

final List<LocalizationsDelegate<dynamic>> _homeTestLocalizationDelegates =
    <LocalizationsDelegate<dynamic>>[
      VidraLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      const LocaleNamesLocalizationsDelegate(),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await I18n.preloadAll();
  });

  Future<void> withSuppressedWidgetLogs(Future<void> Function() body) async {
    final DebugPrintCallback original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message == null) {
        return;
      }
      final normalized = message.trimLeft();
      const blockedPrefixes = [
        '_alignControl',
        'PreferenceTile',
        'controlsRow',
        'addField',
        'chip ',
      ];
      if (blockedPrefixes.any(normalized.startsWith)) {
        return;
      }
      const blockedFragments = [' width=', ' maxWidth=', ' constraints='];
      if (blockedFragments.any(normalized.contains)) {
        return;
      }
      original(message, wrapWidth: wrapWidth);
    };

    try {
      await body();
    } finally {
      debugPrint = original;
    }
  }

  void silentHomeTestWidgets(
    String description,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(description, (tester) async {
      await withSuppressedWidgetLogs(() => body(tester));
    });
  }

  group('HomeScreen', () {
    late PreferencesModel preferencesModel;
    late BackendConfig backendConfig;
    late DownloadController idleDownloadController;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferencesModel = PreferencesModel();
      await preferencesModel.initializePreferences();
      await preferencesModel.setPreferenceValue(
        preferencesModel.preferences.language,
        'es',
      );
      backendConfig = _buildTestBackendConfig();
      idleDownloadController = _HarnessDownloadController(
        backendConfig: backendConfig,
      );
    });

    tearDown(() {
      idleDownloadController.dispose();
      preferencesModel.dispose();
    });

    Widget createApp() {
      return MultiProvider(
        providers: [
          Provider<BackendConfig>.value(value: backendConfig),
          ChangeNotifierProvider<PreferencesModel>.value(
            value: preferencesModel,
          ),
          ChangeNotifierProvider<DownloadController>.value(
            value: idleDownloadController,
          ),
        ],
        child: const MyApp(),
      );
    }

    silentHomeTestWidgets('reflects preference changes triggered via model', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createApp());
      await tester.pumpAndSettle();

      await preferencesModel.setPreferenceValue(
        preferencesModel.preferences.isDarkTheme,
        true,
      );
      await tester.pumpAndSettle();

      final themeSwitch = tester.widget<Switch>(
        find.byKey(const ValueKey('home_theme_switch_tile')),
      );
      expect(themeSwitch.value, isTrue);
    });

    silentHomeTestWidgets('theme mode toggles on preference change', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createApp());
      await tester.pumpAndSettle();

      MaterialApp app = tester.widget(find.byType(MaterialApp));
      expect(app.themeMode, equals(ThemeMode.light));

      await preferencesModel.setPreferenceValue(
        preferencesModel.preferences.isDarkTheme,
        true,
      );
      await tester.pumpAndSettle();

      app = tester.widget(find.byType(MaterialApp));
      expect(app.themeMode, equals(ThemeMode.dark));
    });

    silentHomeTestWidgets(
      'updates preference when toggled from quick settings',
      (WidgetTester tester) async {
        await tester.pumpWidget(createApp());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('home_theme_switch_tile')));
        await tester.pumpAndSettle();

        expect(
          preferencesModel.preferences.isDarkTheme.getValue<bool>(),
          isTrue,
        );
      },
    );

    silentHomeTestWidgets('language change updates visible copy', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createApp());
      await tester.pumpAndSettle();

      expect(find.text('Inicio'), findsOneWidget);
      expect(find.text('Home'), findsNothing);

      await preferencesModel.setPreferenceValue(
        preferencesModel.preferences.language,
        'en',
      );
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Inicio'), findsNothing);

      final languageButton = find.byKey(const ValueKey('home_language_button'));
      expect(languageButton, findsOneWidget);
    });

    silentHomeTestWidgets('playlist toggle reflects preference changes', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createApp());
      await tester.pumpAndSettle();

      await preferencesModel.setPreferenceValue(
        preferencesModel.preferences.playlist,
        true,
      );
      await tester.pumpAndSettle();

      final playlistToggle = tester.widget<IconButton>(
        find.byKey(const ValueKey('home_playlist_mode_toggle')),
      );
      expect(playlistToggle.isSelected, isTrue);
    });

    silentHomeTestWidgets('playlist toggle updates preference when pressed', (
      WidgetTester tester,
    ) async {
      await preferencesModel.setPreferenceValue(
        preferencesModel.preferences.playlist,
        false,
      );
      await tester.pumpWidget(createApp());
      await tester.pumpAndSettle();

      expect(preferencesModel.preferences.playlist.getValue<bool>(), isFalse);

      await tester.tap(find.byKey(const ValueKey('home_playlist_mode_toggle')));
      await tester.pumpAndSettle();

      expect(preferencesModel.preferences.playlist.getValue<bool>(), isTrue);
    });

    silentHomeTestWidgets(
      'extract audio switch reflects preference changes triggered via model',
      (WidgetTester tester) async {
        await tester.pumpWidget(createApp());
        await tester.pumpAndSettle();

        await preferencesModel.setPreferenceValue(
          preferencesModel.preferences.extractAudio,
          true,
        );
        await tester.pumpAndSettle();

        final extractSwitch = tester.widget<Switch>(
          find.byKey(const ValueKey('home_extract_audio_switch')),
        );
        expect(extractSwitch.value, isTrue);
      },
    );

    silentHomeTestWidgets(
      'extract audio switch updates preference when toggled',
      (WidgetTester tester) async {
        await tester.pumpWidget(createApp());
        await tester.pumpAndSettle();

        expect(
          preferencesModel.preferences.extractAudio.getValue<bool>(),
          isFalse,
        );

        await tester.tap(
          find.byKey(const ValueKey('home_extract_audio_switch')),
        );
        await tester.pumpAndSettle();

        expect(
          preferencesModel.preferences.extractAudio.getValue<bool>(),
          isTrue,
        );
      },
    );

    silentHomeTestWidgets(
      'shows playlist modal while playlist entries continue streaming',
      (WidgetTester tester) async {
        final job = _buildCollectingPlaylistJob(id: 'job-modal');
        final controller = _HarnessDownloadController(
          backendConfig: backendConfig,
          jobs: [job],
          collectingJobIds: {job.id},
          pendingSelectionJobId: job.id,
        );
        addTearDown(controller.dispose);
        final invokedJobs = <String>[];
        final capturedPreviews = <PlaylistPreviewData>[];

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<BackendConfig>.value(value: backendConfig),
              ChangeNotifierProvider<PreferencesModel>.value(
                value: preferencesModel,
              ),
              ChangeNotifierProvider<DownloadController>.value(
                value: controller,
              ),
            ],
            child: MaterialApp(
              locale: const Locale('es'),
              localizationsDelegates: _homeTestLocalizationDelegates,
              supportedLocales: VidraLocalizations.supportedLocales,
              home: HomeScreen(
                playlistDialogLauncher:
                    (context, boundController, jobId, previewData) async {
                      expect(boundController, same(controller));
                      invokedJobs.add(jobId);
                      capturedPreviews.add(previewData);
                      return const PlaylistSelectionResult(
                        selectedIndices: null,
                      );
                    },
                autoInitializeController: false,
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(invokedJobs, equals([job.id]));
        expect(controller.jobIsCollectingCallCount, greaterThan(0));
        expect(controller.submitSelectionCallCount, equals(1));
        expect(capturedPreviews, isNotEmpty);
        final preview = capturedPreviews.single;
        expect(preview.playlist, isNotNull);
        expect(preview.playlist!.isCollectingEntries, isTrue);
        expect(
          preview.playlist!.receivedCount,
          equals(job.progress?.playlistCompletedItems),
        );
      },
    );
  });
}

BackendConfig _buildTestBackendConfig() {
  return BackendConfig(
    name: 'Test Backend',
    description: 'Test backend',
    baseUri: Uri.parse('http://localhost:8080/'),
    apiBaseUri: Uri.parse('http://localhost:8080/api/'),
    overviewSocketUri: Uri.parse('ws://localhost:8080/ws/overview'),
    jobSocketBaseUri: Uri.parse('ws://localhost:8080/ws/jobs/'),
    metadata: const <String, dynamic>{},
    timeout: const Duration(seconds: 5),
  );
}

DownloadJobModel _buildCollectingPlaylistJob({
  required String id,
  int totalCount = 5,
  int receivedCount = 2,
}) {
  final playlistMap = <String, dynamic>{
    'id': id,
    'title': 'Lista $id',
    'entry_count': totalCount,
    'entries': <Map<String, dynamic>>[],
    'received_count': receivedCount,
    'is_collecting_entries': true,
  };
  final pending = totalCount - receivedCount;
  return DownloadJobModel(
    id: id,
    status: DownloadStatus.running,
    kind: DownloadKind.playlist,
    createdAt: DateTime(2023, 1, 1),
    progress: DownloadProgress(
      playlistCompletedItems: receivedCount,
      playlistTotalItems: totalCount,
      playlistCurrentIndex: receivedCount,
    ),
    metadata: {
      'preview': {
        'title': 'Lista $id',
        'description': 'Recopilando elementos...',
        'playlist': Map<String, dynamic>.from(playlistMap),
      },
      'playlist': Map<String, dynamic>.from(playlistMap),
    },
    playlist: DownloadPlaylistSummary(
      id: id,
      title: 'Lista $id',
      entryCount: totalCount,
      completedItems: receivedCount,
      pendingItems: pending > 0 ? pending : 0,
      isPlaylist: true,
    ),
  );
}

class _HarnessDownloadController extends DownloadController {
  _HarnessDownloadController({
    required super.backendConfig,
    List<DownloadJobModel> jobs = const <DownloadJobModel>[],
    Set<String> collectingJobIds = const <String>{},
    String? pendingSelectionJobId,
  }) : _jobsById = {for (final job in jobs) job.id: job},
       _collectingJobIds = Set<String>.from(collectingJobIds),
       _pendingRequests = Queue<String>(),
       super(
         authToken: _testToken,
         backendStateListenable: const _AlwaysRunningBackendState(),
       ) {
    if (pendingSelectionJobId != null) {
      _pendingRequests.add(pendingSelectionJobId);
    }
  }

  final Map<String, DownloadJobModel> _jobsById;
  final Set<String> _collectingJobIds;
  final Queue<String> _pendingRequests;

  int jobIsCollectingCallCount = 0;
  int submitSelectionCallCount = 0;

  @override
  List<DownloadJobModel> get jobs => _jobsById.values.toList(growable: false);

  @override
  DownloadJobModel? jobById(String jobId) => _jobsById[jobId];

  @override
  bool jobIsCollectingPlaylistEntries(String jobId) {
    jobIsCollectingCallCount += 1;
    return _collectingJobIds.contains(jobId);
  }

  @override
  String? takeNextPlaylistSelectionRequest() {
    if (_pendingRequests.isEmpty) {
      return null;
    }
    return _pendingRequests.removeFirst();
  }

  @override
  void completePlaylistSelectionRequest(
    String jobId, {
    bool keepQueued = false,
  }) {
    if (keepQueued) {
      _pendingRequests
        ..removeWhere((id) => id == jobId)
        ..add(jobId);
    } else {
      _pendingRequests.removeWhere((id) => id == jobId);
    }
    notifyListeners();
  }

  @override
  void requeuePlaylistSelection(String jobId) {
    _pendingRequests.add(jobId);
    notifyListeners();
  }

  @override
  Future<bool> submitPlaylistSelection(
    String jobId, {
    Set<int>? indices,
  }) async {
    submitSelectionCallCount += 1;
    return true;
  }

  @override
  Future<DownloadPlaylistSummary?> loadPlaylist(
    String jobId, {
    bool includeEntries = false,
    int? offset,
    int? limit,
  }) async {
    return _jobsById[jobId]?.playlist;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refreshJobs() async {}

  @override
  Future<bool> startDownload(
    String url,
    Map<String, dynamic> options, {
    Map<String, dynamic>? metadata,
    String? owner,
  }) async {
    return true;
  }

  @override
  bool get isSubmitting => false;

  @override
  String? get lastError => null;
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

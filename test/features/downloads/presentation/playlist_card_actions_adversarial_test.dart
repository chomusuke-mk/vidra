import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart' as model;
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/shared/widgets/download_card.dart';

class FakeSystemController extends ChangeNotifier
    with WidgetsBindingObserver
    implements SystemController {
  @override
  SystemState get state => SystemState.ready;
  @override
  int? get backendPort => 5000;
  @override
  String? get backendToken => 'test_token';
  @override
  String? get serverLogsFilePath => '/path/to/logs';
  @override
  Future<void> get whenPortReady => Future.value();
  @override
  Future<void> stopBackendForUpdate() async {}
  @override
  Future<void> resumeInitialization() async {}
  @override
  void enqueueDownload(String url, Map<String, dynamic> options) {}
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}
}

class FakeDownloadRepository implements DownloadRepository {
  final List<String> actionsSent = [];

  @override
  Future<List<model.Download>> getAllDownloads() async => [];
  @override
  Future<model.Download?> getDownloadById(String id) async => null;
  @override
  Future<String> addDownload(String url, {Map<String, dynamic>? options}) async => 'mock_id';
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<List<model.SubDownload>> getEntries(String id) async => [];
  @override
  Future<void> submitSelectedEntries(String id, List<String> entries) async {}
  @override
  Future<void> pauseDownload(String id) async => actionsSent.add('pause:$id');
  @override
  Future<void> resumeDownload(String id) async => actionsSent.add('resume:$id');
  @override
  Future<void> cancelDownload(String id) async => actionsSent.add('cancel:$id');
  @override
  Future<void> retryDownload(String id) async => actionsSent.add('retry:$id');
  @override
  Future<void> deleteDownload(String id) async => actionsSent.add('delete:$id');
  @override
  Future<String> fetchLogs(String? id) async => '';
  @override
  Stream<List<model.Delta>> watchGlobalProgress() => const Stream.empty();
  @override
  Stream<List<model.Delta>> watchDetailedProgress(String id) => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDownloadRepository fakeRepo;
  late DownloadsController downloadsCtrl;
  late LocaleController localeCtrl;
  late FakeSystemController fakeSystemCtrl;

  setUp(() async {
    localeCtrl = LocaleController(LocaleRepository(), 'en');
    await localeCtrl.whenReady;
    fakeSystemCtrl = FakeSystemController();
    fakeRepo = FakeDownloadRepository();
    downloadsCtrl = DownloadsController(fakeRepo, fakeSystemCtrl);
  });

  Widget createTestWidget(Widget child) {
    return MultiProvider(
      providers: [
        Provider<DownloadRepository>.value(value: fakeRepo),
        ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
        ChangeNotifierProvider<DownloadsController>.value(value: downloadsCtrl),
        ChangeNotifierProvider<SystemController>.value(value: fakeSystemCtrl),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: child,
        ),
      ),
    );
  }

  group('Adversarial Stress Test: Playlist Card & Sub-Item Action Matrix (R6)', () {
    testWidgets('1. Playlist Master Card: completed with errors has Folder, Retry, Delete actions', (tester) async {
      final playlistInfo = model.Info(
        title: 'Mixed Album Playlist',
        type: model.DownloadType.list,
        url: 'https://youtube.com/playlist?list=mixed123',
        file: '/home/user/Music/MixedAlbum',
      );
      final completedWithErrorsState = model.DownloadState(
        value: model.DownloadStateEnum.completedWithErrors,
        errorMessage: '2 of 10 items failed',
      );

      await tester.pumpWidget(
        createTestWidget(
          DownloadCard(
            downloadId: 'playlist_with_errors_1',
            info: playlistInfo,
            state: completedWithErrorsState,
            isDetailScreen: false,
            isSubItem: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Slidable), findsOneWidget);
      await tester.drag(find.byType(Slidable), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.folder), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byIcon(Icons.delete), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
    });

    testWidgets('2. Sub-Item with no file path (hasFile=false): renders NO Slidable even if completed', (tester) async {
      final subInfo = model.Info(
        title: 'Track No File',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=nofile',
        file: null, // No file
      );
      final completedState = model.DownloadState(
        value: model.DownloadStateEnum.completed,
      );

      await tester.pumpWidget(
        createTestWidget(
          DownloadCard(
            downloadId: 'sub_nofile',
            info: subInfo,
            state: completedState,
            isDetailScreen: true,
            isSubItem: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Slidable), findsNothing);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
    });

    testWidgets('3. Sub-Items in all non-completed states: exhaustive check for zero action buttons', (tester) async {
      final statesToTest = [
        model.DownloadStateEnum.requested,
        model.DownloadStateEnum.pending,
        model.DownloadStateEnum.awaitingSelection,
        model.DownloadStateEnum.inProgress,
        model.DownloadStateEnum.cancelling,
        model.DownloadStateEnum.paused,
        model.DownloadStateEnum.pausing,
        model.DownloadStateEnum.failed,
        model.DownloadStateEnum.cancelled,
        model.DownloadStateEnum.deleted,
      ];

      for (final stateEnum in statesToTest) {
        final subInfo = model.Info(
          title: 'Track ${stateEnum.name}',
          type: model.DownloadType.video,
          url: 'https://youtube.com/watch?v=${stateEnum.name}',
          file: '/path/to/file.mp4',
        );
        final state = model.DownloadState(value: stateEnum);

        await tester.pumpWidget(
          createTestWidget(
            DownloadCard(
              downloadId: 'sub_${stateEnum.name}',
              info: subInfo,
              state: state,
              isDetailScreen: true,
              isSubItem: true,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.byType(Slidable),
          findsNothing,
          reason: 'Sub-item with state ${stateEnum.name} must not render Slidable actions',
        );
        expect(
          find.byIcon(Icons.chevron_left),
          findsNothing,
          reason: 'Sub-item with state ${stateEnum.name} must not render action chevron indicator',
        );
      }
    });

    testWidgets('4. Sub-Item dismissible swipe: cannot be dismissed or deleted via full drag', (tester) async {
      final subInfo = model.Info(
        title: 'Completed Sub Track',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=track_comp',
        file: '/home/user/Music/01.mp3',
      );
      final completedState = model.DownloadState(
        value: model.DownloadStateEnum.completed,
      );

      await tester.pumpWidget(
        createTestWidget(
          DownloadCard(
            downloadId: 'sub_track_dismiss_test',
            info: subInfo,
            state: completedState,
            isDetailScreen: true,
            isSubItem: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Slidable), findsOneWidget);

      // Perform a full across-screen drag (swipe to delete attempt)
      await tester.drag(find.byType(Slidable), const Offset(-800, 0));
      await tester.pumpAndSettle();

      // No delete action should have been recorded in repository
      expect(fakeRepo.actionsSent, isEmpty);
      // Card is still present and not dismissed
      expect(find.byType(DownloadCard), findsOneWidget);
    });

    testWidgets('5. Playlist Master Card in Detail Screen: Dismissible swipe is disabled', (tester) async {
      final masterInfo = model.Info(
        title: 'Master Album',
        type: model.DownloadType.list,
        url: 'https://youtube.com/playlist?list=master1',
        file: '/home/user/Music/Master',
      );
      final completedState = model.DownloadState(
        value: model.DownloadStateEnum.completed,
      );

      await tester.pumpWidget(
        createTestWidget(
          DownloadCard(
            downloadId: 'master_detail_test',
            info: masterInfo,
            state: completedState,
            isDetailScreen: true, // Master card rendered at top of DownloadDetailScreen
            isSubItem: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Slidable), findsOneWidget);

      // Full swipe attempt
      await tester.drag(find.byType(Slidable), const Offset(-800, 0));
      await tester.pumpAndSettle();

      // DismissiblePane is disabled in detail screen, so no automatic delete triggered on full swipe
      expect(fakeRepo.actionsSent, isEmpty);
    });
  });
}

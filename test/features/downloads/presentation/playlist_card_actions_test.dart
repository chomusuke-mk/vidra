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
  Future<String> addDownload(String url,
          {Map<String, dynamic>? options}) async =>
      'mock_id';

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<List<model.SubDownload>> getEntries(String id) async => [];

  @override
  Future<void> submitSelectedEntries(String id, List<String> entries) async {}

  @override
  Future<void> pauseDownload(String id) async {
    actionsSent.add('pause:$id');
  }

  @override
  Future<void> resumeDownload(String id) async {
    actionsSent.add('resume:$id');
  }

  @override
  Future<void> cancelDownload(String id) async {
    actionsSent.add('cancel:$id');
  }

  @override
  Future<void> retryDownload(String id) async {
    actionsSent.add('retry:$id');
  }

  @override
  Future<void> deleteDownload(String id) async {
    actionsSent.add('delete:$id');
  }

  @override
  Future<String> fetchLogs(String? id) async => '';

  @override
  Stream<List<model.Delta>> watchGlobalProgress() => const Stream.empty();

  @override
  Stream<List<model.Delta>> watchDetailedProgress(String id) =>
      const Stream.empty();
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

  group('Playlist Card and Sub-Item Actions (R6)', () {
    testWidgets(
        '1. Main screen playlist card completed: exposes Open Folder action on desktop',
        (tester) async {
      final playlistInfo = model.Info(
        title: 'Complete Album Playlist',
        type: model.DownloadType.list,
        url: 'https://youtube.com/playlist?list=album123',
        file: '/home/user/Music/Album',
      );
      final completedState = model.DownloadState(
        value: model.DownloadStateEnum.completed,
      );

      await tester.pumpWidget(
        createTestWidget(
          DownloadCard(
            downloadId: 'playlist_main_1',
            info: playlistInfo,
            state: completedState,
            isDetailScreen: false,
            isSubItem: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Slidable), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);

      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.folder), findsOneWidget);
      expect(find.byIcon(Icons.delete), findsOneWidget);
      // Play is not shown for playlist master card
      expect(find.byIcon(Icons.play_arrow), findsNothing);
    });

    testWidgets(
        '2. Playlist detail screen sub-item completed: exposes ONLY Play and Folder actions',
        (tester) async {
      final subInfo = model.Info(
        title: 'Track 01 - Intro',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=track1',
        file: '/home/user/Music/Album/01_intro.mp3',
      );
      final completedState = model.DownloadState(
        value: model.DownloadStateEnum.completed,
      );

      await tester.pumpWidget(
        createTestWidget(
          DownloadCard(
            downloadId: 'sub_track_1',
            info: subInfo,
            state: completedState,
            isDetailScreen: true,
            isSubItem: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Slidable), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);

      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();

      // STRICTLY Play and Folder
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.folder), findsOneWidget);

      // STRICTLY NO delete, pause, cancel, retry, info
      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.byIcon(Icons.pause), findsNothing);
      expect(find.byIcon(Icons.cancel), findsNothing);
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.byIcon(Icons.info), findsNothing);
    });

    testWidgets(
        '3. Playlist detail screen sub-item in progress / pending: NO Slidable rendered',
        (tester) async {
      final subInfo = model.Info(
        title: 'Track 02 - In Progress',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=track2',
      );
      final inProgressState = model.DownloadState(
        value: model.DownloadStateEnum.inProgress,
        progressValue: 0.45,
      );

      await tester.pumpWidget(
        createTestWidget(
          DownloadCard(
            downloadId: 'sub_track_2',
            info: subInfo,
            state: inProgressState,
            isDetailScreen: true,
            isSubItem: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Slidable), findsNothing);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.pause), findsNothing);
      expect(find.byIcon(Icons.cancel), findsNothing);
      expect(find.byIcon(Icons.delete), findsNothing);
    });

    testWidgets(
        '4. Playlist detail screen sub-item failed: NO Slidable rendered',
        (tester) async {
      final subInfo = model.Info(
        title: 'Track 03 - Failed Track',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=track3',
      );
      final errorState = model.DownloadState(
        value: model.DownloadStateEnum.failed,
        errorMessage: 'Network timeout',
      );

      await tester.pumpWidget(
        createTestWidget(
          DownloadCard(
            downloadId: 'sub_track_3',
            info: subInfo,
            state: errorState,
            isDetailScreen: true,
            isSubItem: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Slidable), findsNothing);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.byIcon(Icons.delete), findsNothing);
    });
  });
}

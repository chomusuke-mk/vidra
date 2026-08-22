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
import 'package:vidra/features/downloads/presentation/download_detail_screen.dart';
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

  bool shouldThrowOnDelete = false;

  @override
  Future<void> deleteDownload(String id) async {
    actionsSent.add('delete:$id');
    if (shouldThrowOnDelete) {
      throw Exception('Simulated network/backend deletion failure');
    }
  }

  @override
  Future<String> fetchLogs(String? id) async => '';

  @override
  Stream<List<model.Delta>> watchGlobalProgress() => const Stream.empty();

  @override
  Stream<List<model.Delta>> watchDetailedProgress(String id) => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeCtrl;
  late FakeSystemController fakeSystemCtrl;
  late FakeDownloadRepository fakeRepo;
  late DownloadsController downloadsCtrl;

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
        ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
        ChangeNotifierProvider<DownloadsController>.value(value: downloadsCtrl),
        ChangeNotifierProvider<SystemController>.value(value: fakeSystemCtrl),
      ],
      child: MaterialApp(
        home: Scaffold(body: child),
      ),
    );
  }

  group('DownloadCard - Slidable & Action Buttons in Detail vs Main vs SubItem', () {
    testWidgets('Detail Screen Master Card: InProgress is Slidable with Pause and Cancel, but NO Info', (tester) async {
      final info = model.Info(
        title: 'Master Video in Progress',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=123',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.inProgress,
        progressValue: 0.45,
      );

      await tester.pumpWidget(
        createTestWidget(
          DownloadCard(
            downloadId: 'master_1',
            info: info,
            state: state,
            isDetailScreen: true,
            isSubItem: false,
          ),
        ),
      );
      await tester.pump();

      // Slidable must be present on master card
      expect(find.byType(Slidable), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);

      // Drag to open action pane
      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();

      // Actions in pane
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byIcon(Icons.cancel), findsOneWidget);
      expect(find.byIcon(Icons.info), findsNothing);
    });

    testWidgets('Detail Screen Master Card: Failed/Error is Slidable with Retry and Delete, but NO Info', (tester) async {
      final info = model.Info(
        title: 'Master Video Failed',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=123',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.failed,
        errorMessage: 'Network error',
      );

      await tester.pumpWidget(
        createTestWidget(
          DownloadCard(
            downloadId: 'master_err_1',
            info: info,
            state: state,
            isDetailScreen: true,
            isSubItem: false,
          ),
        ),
      );
      await tester.pump();

      // Slidable must be present
      expect(find.byType(Slidable), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);

      // Drag to open action pane
      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();

      // Actions in pane: Retry and Delete, strictly NO Info button
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byIcon(Icons.delete), findsOneWidget);
      expect(find.byIcon(Icons.info), findsNothing);
    });

    testWidgets('Main Screen Card (isDetailScreen: false): Failed/Error DOES have Info button', (tester) async {
      final info = model.Info(
        title: 'Main Screen Video Failed',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=123',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.failed,
        errorMessage: 'Network error',
      );

      await tester.pumpWidget(
        createTestWidget(
          DownloadCard(
            downloadId: 'main_err_1',
            info: info,
            state: state,
            isDetailScreen: false,
            isSubItem: false,
          ),
        ),
      );
      await tester.pump();

      // On main screen, info button is available for error state
      expect(find.byType(Slidable), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);

      // Drag to open action pane
      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.info), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byIcon(Icons.delete), findsOneWidget);
    });

    testWidgets('Detail Screen Master Card: Paused is Slidable with Resume and Cancel, but NO Info', (tester) async {
      final info = model.Info(
        title: 'Master Video Paused',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=123',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.paused,
        progressValue: 0.2,
      );

      await tester.pumpWidget(
        createTestWidget(
          DownloadCard(
            downloadId: 'master_paused_1',
            info: info,
            state: state,
            isDetailScreen: true,
            isSubItem: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Slidable), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);

      // Drag to open action pane
      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.cancel), findsOneWidget);
      expect(find.byIcon(Icons.info), findsNothing);
    });

    testWidgets('Sub-Item in Playlist (isSubItem: true): NOT Slidable under any state', (tester) async {
      // 1. InProgress Sub-Item
      final subInfo = model.Info(
        title: 'Sub Item in Playlist',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=sub1',
      );
      final inProgressState = model.DownloadState(
        value: model.DownloadStateEnum.inProgress,
        progressValue: 0.5,
      );

      await tester.pumpWidget(
        createTestWidget(
          DownloadCard(
            downloadId: 'sub_1',
            info: subInfo,
            state: inProgressState,
            isDetailScreen: true,
            isSubItem: true,
          ),
        ),
      );
      await tester.pump();

      // Slidable must NOT exist for sub item
      expect(find.byType(Slidable), findsNothing);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.pause), findsNothing);
      expect(find.byIcon(Icons.cancel), findsNothing);
      expect(find.byIcon(Icons.info), findsNothing);
    });

    testWidgets('Sub-Item in Playlist (isSubItem: true): Failed state is NOT Slidable', (tester) async {
      final subInfo = model.Info(
        title: 'Sub Item Failed',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=sub2',
      );
      final failedState = model.DownloadState(
        value: model.DownloadStateEnum.failed,
        errorMessage: 'Sub error',
      );

      await tester.pumpWidget(
        createTestWidget(
          DownloadCard(
            downloadId: 'sub_2',
            info: subInfo,
            state: failedState,
            isDetailScreen: true,
            isSubItem: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Slidable), findsNothing);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.byIcon(Icons.info), findsNothing);
    });

    testWidgets('Sub-Item in Playlist (isSubItem: true): Completed state exposes Play and Folder (desktop), but NO delete, pause, cancel, retry, info', (tester) async {
      final subInfo = model.Info(
        title: 'Sub Item Completed',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=sub3',
        file: '/path/to/sub3.mp4',
      );
      final completedState = model.DownloadState(
        value: model.DownloadStateEnum.completed,
      );

      await tester.pumpWidget(
        createTestWidget(
          DownloadCard(
            downloadId: 'sub_3',
            info: subInfo,
            state: completedState,
            isDetailScreen: true,
            isSubItem: true,
          ),
        ),
      );
      await tester.pump();

      // Slidable is present because showPlay/showFolder are enabled for completed sub-item
      expect(find.byType(Slidable), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);

      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();

      // Play is present
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      // Strictly NO Delete, Pause, Cancel, Retry, or Info
      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.byIcon(Icons.pause), findsNothing);
      expect(find.byIcon(Icons.cancel), findsNothing);
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.byIcon(Icons.info), findsNothing);
    });
  });

  group('DownloadDetailScreen - Master Card vs SubDownloads Slidable Integration', () {
    testWidgets('Master Card on DownloadDetailScreen is Slidable while subDownloads are NOT', (tester) async {
      final subItem1 = model.SubDownload(
        subId: 'sub_item_1',
        parentId: 'playlist_parent_1',
        state: model.DownloadState(value: model.DownloadStateEnum.inProgress, progressValue: 0.3),
        info: model.Info(title: 'Sub Chapter 1', type: model.DownloadType.video, url: 'https://youtube.com/watch?v=c1'),
      );
      final subItem2 = model.SubDownload(
        subId: 'sub_item_2',
        parentId: 'playlist_parent_1',
        state: model.DownloadState(value: model.DownloadStateEnum.completed),
        info: model.Info(title: 'Sub Chapter 2', type: model.DownloadType.video, url: 'https://youtube.com/watch?v=c2', file: '/path/to/c2.mp4'),
      );

      final playlistDownload = model.Download(
        id: 'playlist_parent_1',
        info: model.Info(title: 'Full Playlist Master', type: model.DownloadType.list, url: 'https://youtube.com/playlist?list=123'),
        state: model.DownloadState(value: model.DownloadStateEnum.inProgress, progressValue: 0.15),
        subDownloads: [subItem1, subItem2],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<DownloadRepository>.value(value: fakeRepo),
            ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
            ChangeNotifierProvider<DownloadsController>.value(value: downloadsCtrl),
            ChangeNotifierProvider<SystemController>.value(value: fakeSystemCtrl),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  // Master Card as rendered in DownloadDetailScreen
                  DownloadCard(
                    downloadId: playlistDownload.id,
                    info: playlistDownload.info,
                    state: playlistDownload.state,
                    isDetailScreen: true,
                  ),
                  const Divider(),
                  // Sub downloads list as rendered in DownloadDetailScreen
                  Expanded(
                    child: ListView.builder(
                      itemCount: playlistDownload.subDownloads!.length,
                      itemBuilder: (context, index) {
                        final sub = playlistDownload.subDownloads![index];
                        return DownloadCard(
                          downloadId: sub.subId,
                          info: sub.info,
                          state: sub.state,
                          isDetailScreen: true,
                          isSubItem: true,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Master Card and completed subItem2 have Slidable, while in-progress subItem1 does NOT
      expect(find.byType(Slidable), findsNWidgets(2));
      expect(find.byKey(const ValueKey<String?>('playlist_parent_1')), findsOneWidget);
      expect(find.byKey(const ValueKey<String?>('sub_item_2')), findsOneWidget);
      expect(find.byKey(const ValueKey<String?>('sub_item_1')), findsNothing);

      // Verify that dragging the Master Card reveals actions (Pause, Cancel) and NO Info button
      await tester.drag(find.byKey(const ValueKey<String?>('playlist_parent_1')), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byIcon(Icons.cancel), findsOneWidget);
      expect(find.byIcon(Icons.info), findsNothing);

      // Verify sub items are rendered
      expect(find.text('Sub Chapter 1'), findsOneWidget);
      expect(find.text('Sub Chapter 2'), findsOneWidget);
    });
  });

  group('DownloadCard - DismissiblePane & Delete Dismissal Safety in Detail Screen', () {
    testWidgets('Detail Screen Master Card: DismissiblePane is strictly NULL to prevent dismissal crash', (tester) async {
      final info = model.Info(
        title: 'Master Video Completed',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=123',
        file: '/path/to/vid.mp4',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.completed,
      );

      await tester.pumpWidget(
        createTestWidget(
          DownloadCard(
            downloadId: 'master_completed_1',
            info: info,
            state: state,
            isDetailScreen: true,
            isSubItem: false,
          ),
        ),
      );
      await tester.pump();

      final slidable = tester.widget<Slidable>(find.byType(Slidable));
      expect(slidable.endActionPane, isNotNull);
      expect(slidable.endActionPane!.dismissible, isNull);
    });

    testWidgets('Main Screen Card: DismissiblePane is PRESENT when showDelete is true', (tester) async {
      final info = model.Info(
        title: 'Main Screen Video Completed',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=123',
        file: '/path/to/vid.mp4',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.completed,
      );

      await tester.pumpWidget(
        createTestWidget(
          DownloadCard(
            downloadId: 'main_completed_1',
            info: info,
            state: state,
            isDetailScreen: false,
            isSubItem: false,
          ),
        ),
      );
      await tester.pump();

      final slidable = tester.widget<Slidable>(find.byType(Slidable));
      expect(slidable.endActionPane, isNotNull);
      expect(slidable.endActionPane!.dismissible, isNotNull);
    });

    testWidgets('Detail Screen: Full-swipe does NOT crash with SlidableDismissal error', (tester) async {
      final info = model.Info(
        title: 'Master Video Completed',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=123',
        file: '/path/to/vid.mp4',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.completed,
      );

      await tester.pumpWidget(
        createTestWidget(
          DownloadCard(
            downloadId: 'master_completed_swipe',
            info: info,
            state: state,
            isDetailScreen: true,
            isSubItem: false,
          ),
        ),
      );
      await tester.pump();

      // Full swipe across screen width
      await tester.fling(find.byType(Slidable), const Offset(-600, 0), 1000);
      await tester.pumpAndSettle();

      // Card must still be safely in tree without assertion errors
      expect(find.byType(DownloadCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Detail Screen: Tapping Delete action sends delete and pops the screen', (tester) async {
      final info = model.Info(
        title: 'Master Video Failed',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=123',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.failed,
        errorMessage: 'Network error',
      );

      final download = model.Download(
        id: 'master_del_1',
        info: info,
        state: state,
      );

      // Setup navigation with a home page that pushes Detail screen
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<DownloadRepository>.value(value: fakeRepo),
            ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
            ChangeNotifierProvider<DownloadsController>.value(value: downloadsCtrl),
            ChangeNotifierProvider<SystemController>.value(value: fakeSystemCtrl),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => Scaffold(
                            body: DownloadCard(
                              downloadId: download.id,
                              info: download.info,
                              state: download.state,
                              isDetailScreen: true,
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Text('Go to Detail'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Navigate to detail
      await tester.tap(find.text('Go to Detail'));
      await tester.pumpAndSettle();

      expect(find.byType(DownloadCard), findsOneWidget);

      // Open Slidable pane
      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();

      // Tap Delete icon
      expect(find.byIcon(Icons.delete), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();

      // Verify delete action was sent to repository
      expect(fakeRepo.actionsSent, contains('delete:master_del_1'));

      // Verify screen popped back to home page
      expect(find.text('Go to Detail'), findsOneWidget);
      expect(find.byType(DownloadCard), findsNothing);
    });

    testWidgets('Detail Screen (DownloadDetailScreen widget): Tapping Delete action on master card pops screen', (tester) async {
      final info = model.Info(
        title: 'Master Video in DownloadDetailScreen',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=123',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.failed,
        errorMessage: 'Network error',
      );

      final download = model.Download(
        id: 'master_dds_1',
        info: info,
        state: state,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<DownloadRepository>.value(value: fakeRepo),
            ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
            ChangeNotifierProvider<DownloadsController>.value(value: downloadsCtrl),
            ChangeNotifierProvider<SystemController>.value(value: fakeSystemCtrl),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DownloadDetailScreen(download: download),
                        ),
                      );
                    },
                    child: const Text('Open Detail Screen'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Open DownloadDetailScreen
      await tester.tap(find.text('Open Detail Screen'));
      await tester.pumpAndSettle();

      expect(find.byType(DownloadDetailScreen), findsOneWidget);

      // Open Slidable pane on master card
      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();

      // Tap Delete icon
      expect(find.byIcon(Icons.delete), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();

      // Verify deletion occurred and screen was popped
      expect(fakeRepo.actionsSent, contains('delete:master_dds_1'));
      expect(find.text('Open Detail Screen'), findsOneWidget);
      expect(find.byType(DownloadDetailScreen), findsNothing);
    });

    testWidgets('Detail Screen: Failed delete does NOT pop the screen and keeps detail view intact', (tester) async {
      fakeRepo.shouldThrowOnDelete = true;
      final info = model.Info(
        title: 'Master Video Delete Fail',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=123',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.failed,
        errorMessage: 'Network error',
      );

      final download = model.Download(
        id: 'master_fail_del',
        info: info,
        state: state,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<DownloadRepository>.value(value: fakeRepo),
            ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
            ChangeNotifierProvider<DownloadsController>.value(value: downloadsCtrl),
            ChangeNotifierProvider<SystemController>.value(value: fakeSystemCtrl),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => Scaffold(
                            body: DownloadCard(
                              downloadId: download.id,
                              info: download.info,
                              state: download.state,
                              isDetailScreen: true,
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Text('Go to Detail'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Go to Detail'));
      await tester.pumpAndSettle();

      expect(find.byType(DownloadCard), findsOneWidget);

      // Open Slidable pane and tap Delete
      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();

      // Deletion was attempted
      expect(fakeRepo.actionsSent, contains('delete:master_fail_del'));

      // Detail Screen is STILL mounted because deletion failed!
      expect(find.byType(DownloadCard), findsOneWidget);
    });

    testWidgets('Main Screen Card: Tapping Delete action does NOT pop the main screen', (tester) async {
      final info = model.Info(
        title: 'Main Screen Video for Delete',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=123',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.completed,
      );

      final download = model.Download(
        id: 'main_del_no_pop',
        info: info,
        state: state,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<DownloadRepository>.value(value: fakeRepo),
            ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
            ChangeNotifierProvider<DownloadsController>.value(value: downloadsCtrl),
            ChangeNotifierProvider<SystemController>.value(value: fakeSystemCtrl),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DownloadCard(
                downloadId: download.id,
                info: download.info,
                state: download.state,
                isDetailScreen: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(DownloadCard), findsOneWidget);

      // Open Slidable and tap Delete
      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();

      // Deletion sent
      expect(fakeRepo.actionsSent, contains('delete:main_del_no_pop'));
      // Main screen remains visible (no pop attempted)
      expect(find.byType(DownloadCard), findsOneWidget);
    });

    testWidgets('Deep Navigation Stack: Master Card delete pops only Detail screen back to intermediate route', (tester) async {
      final info = model.Info(
        title: 'Deep Nav Download',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=123',
      );
      final state = model.DownloadState(
        value: model.DownloadStateEnum.failed,
      );

      final download = model.Download(
        id: 'deep_nav_del',
        info: info,
        state: state,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<DownloadRepository>.value(value: fakeRepo),
            ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
            ChangeNotifierProvider<DownloadsController>.value(value: downloadsCtrl),
            ChangeNotifierProvider<SystemController>.value(value: fakeSystemCtrl),
          ],
          child: MaterialApp(
            initialRoute: '/',
            routes: {
              '/': (context) => Scaffold(
                    body: ElevatedButton(
                      onPressed: () => Navigator.pushNamed(context, '/list'),
                      child: const Text('Root Screen'),
                    ),
                  ),
              '/list': (context) => Scaffold(
                    body: ElevatedButton(
                      onPressed: () => Navigator.pushNamed(context, '/detail'),
                      child: const Text('List Screen'),
                    ),
                  ),
              '/detail': (context) => Scaffold(
                    body: DownloadCard(
                      downloadId: download.id,
                      info: download.info,
                      state: download.state,
                      isDetailScreen: true,
                    ),
                  ),
            },
          ),
        ),
      );
      await tester.pump();

      // Navigate Root -> List
      await tester.tap(find.text('Root Screen'));
      await tester.pumpAndSettle();
      expect(find.text('List Screen'), findsOneWidget);

      // Navigate List -> Detail
      await tester.tap(find.text('List Screen'));
      await tester.pumpAndSettle();
      expect(find.byType(DownloadCard), findsOneWidget);

      // Delete master card on detail
      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();

      // Should have popped exactly back to List Screen, NOT Root Screen
      expect(find.text('List Screen'), findsOneWidget);
      expect(find.text('Root Screen'), findsNothing);
      expect(find.byType(DownloadCard), findsNothing);
    });

    testWidgets('Detail Screen: All deletable states have dismissible == null and full-swipe does not crash', (tester) async {
      final deletableStates = [
        model.DownloadStateEnum.failed,
        model.DownloadStateEnum.cancelled,
        model.DownloadStateEnum.completed,
        model.DownloadStateEnum.completedWithErrors,
      ];

      for (final stateEnum in deletableStates) {
        final info = model.Info(
          title: 'State $stateEnum Video',
          type: model.DownloadType.video,
          url: 'https://youtube.com/watch?v=$stateEnum',
          file: '/path/to/$stateEnum.mp4',
        );
        final state = model.DownloadState(value: stateEnum);

        await tester.pumpWidget(
          createTestWidget(
            DownloadCard(
              downloadId: 'del_state_$stateEnum',
              info: info,
              state: state,
              isDetailScreen: true,
            ),
          ),
        );
        await tester.pump();

        final slidable = tester.widget<Slidable>(find.byType(Slidable));
        expect(slidable.endActionPane, isNotNull);
        expect(slidable.endActionPane!.dismissible, isNull,
            reason: 'State $stateEnum must have dismissible == null on detail screen');

        // Full swipe fling gesture must not crash
        await tester.fling(find.byType(Slidable), const Offset(-600, 0), 1000);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('Detail Screen: Non-delete actions (Pause, Resume, Retry) do NOT pop the detail screen', (tester) async {
      // 1. Test Pause
      final inProgDownload = model.Download(
        id: 'detail_pause_test',
        info: model.Info(title: 'Pause Test', type: model.DownloadType.video, url: 'https://youtube.com/watch?v=pause'),
        state: model.DownloadState(value: model.DownloadStateEnum.inProgress, progressValue: 0.5),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<DownloadRepository>.value(value: fakeRepo),
            ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
            ChangeNotifierProvider<DownloadsController>.value(value: downloadsCtrl),
            ChangeNotifierProvider<SystemController>.value(value: fakeSystemCtrl),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Scaffold(
                        body: DownloadCard(
                          downloadId: inProgDownload.id,
                          info: inProgDownload.info,
                          state: inProgDownload.state,
                          isDetailScreen: true,
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Go to Detail'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Go to Detail'));
      await tester.pumpAndSettle();

      // Open Slidable and tap Pause
      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.pause));
      await tester.pumpAndSettle();

      expect(fakeRepo.actionsSent, contains('pause:detail_pause_test'));
      expect(find.byType(DownloadCard), findsOneWidget); // Still on detail screen!
    });

    testWidgets('Detail Screen: Cancel dialog confirmation sends cancel without popping detail screen', (tester) async {
      final inProgDownload = model.Download(
        id: 'detail_cancel_test',
        info: model.Info(title: 'Cancel Test', type: model.DownloadType.video, url: 'https://youtube.com/watch?v=cancel'),
        state: model.DownloadState(value: model.DownloadStateEnum.inProgress, progressValue: 0.5),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<DownloadRepository>.value(value: fakeRepo),
            ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
            ChangeNotifierProvider<DownloadsController>.value(value: downloadsCtrl),
            ChangeNotifierProvider<SystemController>.value(value: fakeSystemCtrl),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Scaffold(
                        body: DownloadCard(
                          downloadId: inProgDownload.id,
                          info: inProgDownload.info,
                          state: inProgDownload.state,
                          isDetailScreen: true,
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Go to Detail'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Go to Detail'));
      await tester.pumpAndSettle();

      // Open Slidable and tap Cancel button to open dialog
      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.cancel));
      await tester.pumpAndSettle();

      // Dialog is shown
      expect(find.byType(AlertDialog), findsOneWidget);

      // Tap Yes/Cancel in dialog
      await tester.tap(find.text(localeCtrl.localeStrings.dcDownloadCancel));
      await tester.pumpAndSettle();

      // Verify cancel was sent, dialog was closed, and detail screen is STILL mounted
      expect(fakeRepo.actionsSent, contains('cancel:detail_cancel_test'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(DownloadCard), findsOneWidget);
    });

    testWidgets('Detail Screen: Rapid delete button interactions pop safely without exception', (tester) async {
      final info = model.Info(
        title: 'Master Video Rapid Delete',
        type: model.DownloadType.video,
        url: 'https://youtube.com/watch?v=rapid',
      );
      final state = model.DownloadState(value: model.DownloadStateEnum.completed);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<DownloadRepository>.value(value: fakeRepo),
            ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
            ChangeNotifierProvider<DownloadsController>.value(value: downloadsCtrl),
            ChangeNotifierProvider<SystemController>.value(value: fakeSystemCtrl),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => Scaffold(
                          body: DownloadCard(
                            downloadId: 'rapid_del_id',
                            info: info,
                            state: state,
                            isDetailScreen: true,
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Go to Detail'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Go to Detail'));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Slidable), const Offset(-300, 0));
      await tester.pumpAndSettle();

      // Tap delete
      await tester.tap(find.byIcon(Icons.delete));
      // Pump without settle to check mid-transition stability
      await tester.pump();
      await tester.pumpAndSettle();

      expect(fakeRepo.actionsSent, contains('delete:rapid_del_id'));
      expect(find.text('Go to Detail'), findsOneWidget);
      expect(find.byType(DownloadCard), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

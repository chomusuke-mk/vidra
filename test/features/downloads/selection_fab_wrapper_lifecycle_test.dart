import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/downloads/presentation/selection_wrapper.dart';
import 'package:vidra/features/locales/domain/locale.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';

class MockLocaleController extends ChangeNotifier implements LocaleController {
  final AppStringKey _strings = AppStringKey();

  MockLocaleController() {
    _strings.updateFromJson({
      'sw_selection_enqueued': 'Selection enqueued',
      'sw_list_forwarded': 'List forwarded to queue',
      'sw_unknown_title': 'Unknown Title',
      'sw_search': 'Search',
      'sw_filter_selected': 'Selected only',
      'sw_button_select_all': 'Select all',
      'sw_button_deselect_all': 'Deselect all',
      'sw_button_invert_selection': 'Invert',
      'sw_no_elements_match': 'No elements match',
      'sw_sending_selection': 'Sending...',
      'sw_button_download_selected': 'Download selected',
      'sw_no_elements_selected': 'No elements selected',
      'sw_send_selection_success': 'Success',
      'sw_send_selection_error': 'Error',
    });
  }

  @override
  AppStringKey get localeStrings => _strings;

  @override
  String get currentLocaleCode => 'en';

  @override
  Future<void> get whenReady => Future.value();

  @override
  void setLocale(String localeCode) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDownloadRepository implements DownloadRepository {
  @override
  Stream<List<Delta>> watchGlobalProgress() => const Stream.empty();

  @override
  Future<List<Download>> getAllDownloads() async => [];

  @override
  Future<List<SubDownload>> getEntries(String id) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestableDownloadsController extends ChangeNotifier implements DownloadsController {
  List<Download> _downloads = [];
  String? _manualModalRequestId;
  int listenerCount = 0;

  @override
  List<Download> get downloads => _downloads;

  @override
  bool get isLoading => false;

  @override
  String? get manualModalRequestId => _manualModalRequestId;

  @override
  void requestSelectionModal(String id) {
    _manualModalRequestId = id;
    notifyListeners();
  }

  @override
  void consumeManualModalRequest() {
    _manualModalRequestId = null;
  }

  void setDownloads(List<Download> newDownloads) {
    _downloads = newDownloads;
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    listenerCount++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerCount--;
    super.removeListener(listener);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SelectionFabWrapper Lifecycle & Listener Leak Tests', () {
    late TestableDownloadsController downloadsController;
    late MockLocaleController localeController;
    late FakeDownloadRepository downloadRepo;

    setUp(() {
      downloadsController = TestableDownloadsController();
      localeController = MockLocaleController();
      downloadRepo = FakeDownloadRepository();
    });

    testWidgets('1. Proper unregistration of DownloadsController listener on dispose (No memory leaks)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DownloadsController>.value(value: downloadsController),
            ChangeNotifierProvider<LocaleController>.value(value: localeController),
            Provider<DownloadRepository>.value(value: downloadRepo),
          ],
          child: const MaterialApp(
            home: SelectionFabWrapper(
              child: Scaffold(body: Text('Main Content')),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Expect that listeners were registered (watch + addListener)
      expect(downloadsController.listenerCount, greaterThan(0));

      // Trigger state updates while mounted without modal
      downloadsController.setDownloads([
        Download(
          id: 'dl_1',
          state: DownloadState(value: DownloadStateEnum.completed),
          info: Info(title: 'Completed Video 1'),
        ),
      ]);
      await tester.pumpAndSettle();

      // Unmount / Dispose SelectionFabWrapper and providers
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // Assert listener count dropped to 0 (no lingering listeners or memory leaks)
      expect(downloadsController.listenerCount, equals(0));

      // Firing notifyListeners after dispose should NOT throw any exceptions
      expect(
        () => downloadsController.setDownloads([
          Download(
            id: 'dl_2',
            state: DownloadState(value: DownloadStateEnum.inProgress),
          ),
        ]),
        returnsNormally,
      );
    });

    testWidgets('2. FloatingActionButton renders with dynamic badge count based on pending selections', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DownloadsController>.value(value: downloadsController),
            ChangeNotifierProvider<LocaleController>.value(value: localeController),
            Provider<DownloadRepository>.value(value: downloadRepo),
          ],
          child: const MaterialApp(
            home: SelectionFabWrapper(
              child: Scaffold(body: Text('Main View')),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially no pending downloads -> no FAB
      expect(find.byType(FloatingActionButton), findsNothing);

      // Add 2 pending downloads
      downloadsController.setDownloads([
        Download(
          id: 'dl_1',
          state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          info: Info(title: 'Video 1'),
        ),
        Download(
          id: 'dl_2',
          state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          info: Info(title: 'Video 2'),
        ),
      ]);
      await tester.pumpAndSettle();

      // FAB is visible with badge '2'
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      // Add 1 more pending download
      downloadsController.setDownloads([
        Download(
          id: 'dl_1',
          state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          info: Info(title: 'Video 1'),
        ),
        Download(
          id: 'dl_2',
          state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          info: Info(title: 'Video 2'),
        ),
        Download(
          id: 'dl_3',
          state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          info: Info(title: 'Video 3'),
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget);

      // Transition all downloads to completed
      downloadsController.setDownloads([
        Download(
          id: 'dl_1',
          state: DownloadState(value: DownloadStateEnum.completed),
          info: Info(title: 'Video 1'),
        ),
      ]);
      await tester.pumpAndSettle();

      // FAB is removed
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('3. Modal auto-closes when active download leaves awaitingSelection state', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DownloadsController>.value(value: downloadsController),
            ChangeNotifierProvider<LocaleController>.value(value: localeController),
            Provider<DownloadRepository>.value(value: downloadRepo),
          ],
          child: const MaterialApp(
            home: SelectionFabWrapper(
              child: Scaffold(body: Text('Main View')),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Add pending download
      downloadsController.setDownloads([
        Download(
          id: 'dl_active',
          state: DownloadState(value: DownloadStateEnum.awaitingSelection),
          info: Info(title: 'Playlist Active'),
        ),
      ]);
      await tester.pumpAndSettle();

      // Modal dialog should be open
      expect(find.byType(Dialog), findsOneWidget);

      // Now external event (Delta) changes state to inProgress
      downloadsController.setDownloads([
        Download(
          id: 'dl_active',
          state: DownloadState(value: DownloadStateEnum.inProgress),
          info: Info(title: 'Playlist Active'),
        ),
      ]);
      await tester.pumpAndSettle();

      // Modal dialog should have auto-closed
      expect(find.byType(Dialog), findsNothing);
    });
  });
}

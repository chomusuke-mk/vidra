import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/core/network/vidra_http_client.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';

class FakeSystemController extends ChangeNotifier
    with WidgetsBindingObserver
    implements SystemController {
  SystemState _state = SystemState.ready;
  final List<Map<String, dynamic>> enqueuedCommands = [];

  @override
  SystemState get state => _state;

  void setState(SystemState newState) {
    _state = newState;
    notifyListeners();
  }

  @override
  int? get backendPort => 5000;

  @override
  String? get backendToken => 'mock_token';

  @override
  String? get serverLogsFilePath => '/tmp/mock.log';

  @override
  Future<void> get whenPortReady => Future.value();

  @override
  void enqueueDownload(String url, Map<String, dynamic> options) {
    enqueuedCommands.add({'url': url, 'options': options});
  }

  @override
  Future<void> resumeInitialization() async {}

  @override
  Future<void> stopBackendForUpdate() async {}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}
}

class FakeDownloadRepository extends DownloadRepository {
  List<Download> mockDownloads;
  int getAllDownloadsCallCount = 0;
  int currentActiveFetches = 0;
  int peakConcurrentFetches = 0;
  Duration fetchDelay = Duration.zero;
  bool shouldThrow = false;
  final List<String> deletedIds = [];
  final List<String> cancelledIds = [];
  final List<String> pausedIds = [];
  final List<String> resumedIds = [];
  final List<String> retriedIds = [];

  final StreamController<List<Delta>> deltaController =
      StreamController<List<Delta>>.broadcast();

  FakeDownloadRepository({this.mockDownloads = const []})
      : super(VidraHttpClient(baseUrl: 'http://127.0.0.1:5000', defaultHeaders: {}));

  @override
  Future<List<Download>> getAllDownloads() async {
    getAllDownloadsCallCount++;
    currentActiveFetches++;
    if (currentActiveFetches > peakConcurrentFetches) {
      peakConcurrentFetches = currentActiveFetches;
    }

    if (fetchDelay > Duration.zero) {
      await Future.delayed(fetchDelay);
    }

    currentActiveFetches--;

    if (shouldThrow) {
      throw Exception('Mock network failure');
    }

    return mockDownloads
        .map(
          (d) => Download(
            id: d.id,
            info: d.info != null
                ? Info(
                    url: d.info?.url,
                    title: d.info?.title,
                    image: d.info?.image,
                    type: d.info?.type,
                  )
                : null,
            state: d.state != null
                ? DownloadState(
                    value: d.state?.value,
                    progressValue: d.state?.progressValue,
                    speed: d.state?.speed,
                    timeLeft: d.state?.timeLeft,
                  )
                : null,
          ),
        )
        .toList();
  }

  @override
  Stream<List<Delta>> watchGlobalProgress() => deltaController.stream;

  @override
  Future<void> deleteDownload(String id) async {
    deletedIds.add(id);
  }

  @override
  Future<void> cancelDownload(String id) async {
    cancelledIds.add(id);
  }

  @override
  Future<void> pauseDownload(String id) async {
    pausedIds.add(id);
  }

  @override
  Future<void> resumeDownload(String id) async {
    resumedIds.add(id);
  }

  @override
  Future<void> retryDownload(String id) async {
    retriedIds.add(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSystemController fakeSystemCtrl;
  late FakeDownloadRepository fakeRepo;
  late List<Download> sampleDownloads;

  setUp(() {
    fakeSystemCtrl = FakeSystemController();
    sampleDownloads = [
      Download(
        id: 'dl_1',
        info: Info(title: 'Video 1', type: DownloadType.video),
        state: DownloadState(value: DownloadStateEnum.inProgress, progressValue: 10.0),
      ),
      Download(
        id: 'dl_2',
        info: Info(title: 'Video 2', type: DownloadType.video),
        state: DownloadState(value: DownloadStateEnum.completed, progressValue: 100.0),
      ),
    ];
    fakeRepo = FakeDownloadRepository(mockDownloads: sampleDownloads);
  });

  group('Group 1: Cold-Start Initial Loading & State Transitions', () {
    test('Initial sync on ready system transitions isLoading from true to false', () async {
      fakeRepo.fetchDelay = const Duration(milliseconds: 20);
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);

      expect(controller.isLoading, isTrue);
      expect(controller.downloads, isEmpty);

      await Future.delayed(const Duration(milliseconds: 60));

      expect(controller.isLoading, isFalse);
      expect(controller.downloads.length, equals(2));
      expect(fakeRepo.getAllDownloadsCallCount, equals(1));
      controller.dispose();
    });

    test('Initial sync preserves error resilience when repository throws', () async {
      fakeRepo.shouldThrow = true;
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);

      await Future.delayed(const Duration(milliseconds: 30));

      expect(controller.isLoading, isFalse);
      expect(controller.downloads, isEmpty);
      controller.dispose();
    });
  });

  group('Group 2: Silent Background Synchronization', () {
    test('Background sync (isInitialLoad: false) preserves isLoading == false throughout', () async {
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await pumpEventQueue();

      expect(controller.isLoading, isFalse);

      bool wasLoadingDuringSync = false;
      controller.addListener(() {
        if (controller.isLoading) wasLoadingDuringSync = true;
      });

      fakeRepo.fetchDelay = const Duration(milliseconds: 30);
      fakeRepo.mockDownloads = [
        ...sampleDownloads,
        Download(
          id: 'dl_3',
          info: Info(title: 'Video 3'),
          state: DownloadState(value: DownloadStateEnum.pending),
        ),
      ];

      final syncFuture = controller.syncDownloads(isInitialLoad: false);
      expect(controller.isLoading, isFalse);

      await syncFuture;

      expect(controller.isLoading, isFalse);
      expect(wasLoadingDuringSync, isFalse);
      expect(controller.downloads.length, equals(3));
      controller.dispose();
    });

    test('refreshDownloads() helper runs silently without setting isLoading true', () async {
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await pumpEventQueue();

      bool wasLoading = false;
      controller.addListener(() {
        if (controller.isLoading) wasLoading = true;
      });

      await controller.refreshDownloads();

      expect(wasLoading, isFalse);
      expect(controller.isLoading, isFalse);
      controller.dispose();
    });
  });

  group('Group 3: Single-Flight Deduplication & 50 Concurrent Calls', () {
    test('50 concurrent syncDownloads calls trigger at most 1 active + 1 queued fetch (peak concurrency <= 1)', () async {
      fakeRepo.fetchDelay = const Duration(milliseconds: 30);
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await Future.delayed(const Duration(milliseconds: 50));

      fakeRepo.getAllDownloadsCallCount = 0;
      fakeRepo.peakConcurrentFetches = 0;

      final futures = List.generate(50, (_) => controller.syncDownloads(isInitialLoad: false));
      await Future.wait(futures);

      expect(fakeRepo.peakConcurrentFetches, lessThanOrEqualTo(1));
      expect(fakeRepo.getAllDownloadsCallCount, lessThanOrEqualTo(2));
      controller.dispose();
    });
  });

  group('Group 4: Queued Follow-Up Coalescing', () {
    test('Sync requests during active fetch coalesce into exactly 1 follow-up', () async {
      fakeRepo.fetchDelay = const Duration(milliseconds: 40);
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await Future.delayed(const Duration(milliseconds: 60));

      fakeRepo.getAllDownloadsCallCount = 0;
      fakeRepo.peakConcurrentFetches = 0;

      // 1. First fetch starts
      final firstFetch = controller.syncDownloads(isInitialLoad: false);
      expect(fakeRepo.getAllDownloadsCallCount, equals(1));

      // 2. 10 callers invoke sync while first is in-flight
      await Future.delayed(const Duration(milliseconds: 10));
      for (int i = 0; i < 10; i++) {
        controller.syncDownloads(isInitialLoad: false);
      }

      await firstFetch;
      await Future.delayed(const Duration(milliseconds: 80));

      expect(fakeRepo.getAllDownloadsCallCount, equals(2));
      expect(fakeRepo.peakConcurrentFetches, lessThanOrEqualTo(1));
      controller.dispose();
    });
  });

  group('Group 5: Tombstoning & Deleted ID Filtering', () {
    test('tombstoneId removes item, adds to tombstonedIds, and ignores future deltas', () async {
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await pumpEventQueue();

      expect(controller.downloads.any((d) => d.id == 'dl_1'), isTrue);

      controller.tombstoneId('dl_1');

      expect(controller.downloads.any((d) => d.id == 'dl_1'), isFalse);
      expect(controller.isTombstoned('dl_1'), isTrue);
      expect(controller.tombstonedIds.contains('dl_1'), isTrue);

      fakeRepo.getAllDownloadsCallCount = 0;

      // 20 rapid deltas for tombstoned ID
      for (int i = 0; i < 20; i++) {
        fakeRepo.deltaController.add([
          Delta(id: 'dl_1', status: DownloadState(value: DownloadStateEnum.inProgress)),
        ]);
      }
      await pumpEventQueue();

      expect(fakeRepo.getAllDownloadsCallCount, equals(0));
      controller.dispose();
    });

    test('Deleted state delta automatically tombstones ID and purges item', () async {
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await pumpEventQueue();

      expect(controller.downloads.any((d) => d.id == 'dl_1'), isTrue);
      fakeRepo.getAllDownloadsCallCount = 0;

      // Emit deleted delta
      fakeRepo.deltaController.add([
        Delta(id: 'dl_1', status: DownloadState(value: DownloadStateEnum.deleted)),
      ]);
      await pumpEventQueue();

      expect(controller.downloads.any((d) => d.id == 'dl_1'), isFalse);
      expect(controller.isTombstoned('dl_1'), isTrue);

      // Trailing deltas for dl_1
      fakeRepo.deltaController.add([
        Delta(id: 'dl_1', status: DownloadState(value: DownloadStateEnum.inProgress)),
      ]);
      await pumpEventQueue();

      expect(fakeRepo.getAllDownloadsCallCount, equals(0));
      controller.dispose();
    });

    test('Tombstoned set enforces FIFO eviction at max 500 entries', () async {
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await pumpEventQueue();

      for (int i = 0; i < 600; i++) {
        controller.tombstoneId('tomb_$i');
      }

      expect(controller.tombstonedIds.length, equals(500));
      expect(controller.isTombstoned('tomb_0'), isFalse); // Evicted oldest
      expect(controller.isTombstoned('tomb_599'), isTrue); // Retained newest
      controller.dispose();
    });
  });

  group('Group 6: Ghost / Missing ID Handling & Delta Suppression', () {
    test('Unknown ID delta triggers sync; confirmed missing promotes to ignoredMissingIds', () async {
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await pumpEventQueue();

      fakeRepo.getAllDownloadsCallCount = 0;

      // Emit delta for ghost ID not present on backend
      fakeRepo.deltaController.add([
        Delta(id: 'ghost_404', status: DownloadState(value: DownloadStateEnum.inProgress)),
      ]);
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 30));

      expect(fakeRepo.getAllDownloadsCallCount, equals(1));
      expect(controller.isIgnoredMissing('ghost_404'), isTrue);

      // 10 subsequent deltas for ghost_404 trigger 0 network requests
      for (int i = 0; i < 10; i++) {
        fakeRepo.deltaController.add([
          Delta(id: 'ghost_404', status: DownloadState(value: DownloadStateEnum.inProgress)),
        ]);
      }
      await pumpEventQueue();

      expect(fakeRepo.getAllDownloadsCallCount, equals(1));
      controller.dispose();
    });

    test('Ignored missing set enforces FIFO eviction at max 500 entries', () async {
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await pumpEventQueue();

      fakeRepo.mockDownloads = []; // Empty DB

      // Ingest 550 unknown deltas
      for (int i = 0; i < 550; i++) {
        fakeRepo.deltaController.add([
          Delta(id: 'ghost_$i', status: DownloadState(value: DownloadStateEnum.inProgress)),
        ]);
      }
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(controller.ignoredMissingIds.length, lessThanOrEqualTo(500));
      controller.dispose();
    });
  });

  group('Group 7: Safe Batch Delta Loop & Non-Truncation', () {
    test('Batch with unknown ID at index 0 does not drop valid updates at indices 1..N', () async {
      fakeRepo.fetchDelay = const Duration(milliseconds: 50);
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await Future.delayed(const Duration(milliseconds: 60));

      expect(controller.downloads.firstWhere((d) => d.id == 'dl_1').state?.value, equals(DownloadStateEnum.inProgress));

      // Batch: Index 0 is unknown, Index 1 updates dl_1 to paused, Index 2 updates dl_2 to completed
      fakeRepo.deltaController.add([
        Delta(id: 'unknown_item', status: DownloadState(value: DownloadStateEnum.inProgress)),
        Delta(id: 'dl_1', status: DownloadState(value: DownloadStateEnum.paused)),
        Delta(
          id: 'dl_2',
          info: Info(title: 'Updated Title 2'),
          status: DownloadState(value: DownloadStateEnum.completed, progressValue: 100.0),
        ),
      ]);
      await pumpEventQueue();

      expect(controller.downloads.firstWhere((d) => d.id == 'dl_1').state?.value, equals(DownloadStateEnum.paused));
      expect(controller.downloads.firstWhere((d) => d.id == 'dl_2').info?.title, equals('Updated Title 2'));
      controller.dispose();
    });

    test('Batch with subId deltas skips sub-deltas and processes root deltas', () async {
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await pumpEventQueue();

      fakeRepo.deltaController.add([
        Delta(id: 'dl_1', subId: 'sub_1', status: DownloadState(value: DownloadStateEnum.failed)),
        Delta(id: 'dl_1', status: DownloadState(value: DownloadStateEnum.inProgress, progressValue: 45.0)),
      ]);
      await pumpEventQueue();

      final dl1 = controller.downloads.firstWhere((d) => d.id == 'dl_1');
      expect(dl1.state?.value, equals(DownloadStateEnum.inProgress));
      expect(dl1.state?.progressValue, equals(45.0));
      controller.dispose();
    });
  });

  group('Group 8: Disposal Safety & Action Motor', () {
    test('In-flight sync finishing after controller disposal does not throw', () async {
      fakeRepo.fetchDelay = const Duration(milliseconds: 50);
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);

      final syncFuture = controller.syncDownloads(isInitialLoad: false);
      controller.dispose();

      expect(() async => await syncFuture, returnsNormally);
    });

    test('deleteDownload optimistically tombstones and invokes repository', () async {
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await pumpEventQueue();

      final success = await controller.deleteDownload('dl_1');

      expect(success, isTrue);
      expect(controller.isTombstoned('dl_1'), isTrue);
      expect(controller.downloads.any((d) => d.id == 'dl_1'), isFalse);
      expect(fakeRepo.deletedIds, contains('dl_1'));
      controller.dispose();
    });

    test('cancelDownload invokes repository without tombstoning', () async {
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await pumpEventQueue();

      final success = await controller.cancelDownload('dl_1');

      expect(success, isTrue);
      expect(controller.isTombstoned('dl_1'), isFalse);
      expect(fakeRepo.cancelledIds, contains('dl_1'));
      controller.dispose();
    });

    test('sendAction correctly dispatches all gesture actions', () async {
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await pumpEventQueue();

      expect(await controller.sendAction('dl_1', 'pause'), isTrue);
      expect(fakeRepo.pausedIds, contains('dl_1'));

      expect(await controller.sendAction('dl_1', 'resume'), isTrue);
      expect(fakeRepo.resumedIds, contains('dl_1'));

      expect(await controller.sendAction('dl_1', 'retry'), isTrue);
      expect(fakeRepo.retriedIds, contains('dl_1'));

      expect(await controller.sendAction('dl_1', 'cancel'), isTrue);
      expect(fakeRepo.cancelledIds, contains('dl_1'));

      expect(await controller.sendAction('dl_1', 'delete'), isTrue);
      expect(fakeRepo.deletedIds, contains('dl_1'));

      expect(await controller.sendAction('dl_1', 'unknown_action'), isFalse);
      controller.dispose();
    });
  });
}

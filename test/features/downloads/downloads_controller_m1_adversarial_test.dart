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
        info: Info(title: 'Active Video 1', type: DownloadType.video),
        state: DownloadState(value: DownloadStateEnum.inProgress, progressValue: 25.0),
      ),
      Download(
        id: 'dl_2',
        info: Info(title: 'Active Video 2', type: DownloadType.video),
        state: DownloadState(value: DownloadStateEnum.awaitingSelection, progressValue: 0.0),
      ),
    ];
    fakeRepo = FakeDownloadRepository(mockDownloads: sampleDownloads);
  });

  group('Adversarial Challenge 1: Memory Bounding & FIFO Eviction (2,000+ entries)', () {
    test('Sequential insertion of 2,500 tombstones strictly limits size to 500 and evicts in exact FIFO order', () async {
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await pumpEventQueue();

      const totalEntries = 2500;
      for (int i = 0; i < totalEntries; i++) {
        controller.tombstoneId('tomb_$i');
      }

      // Exact bound verification
      expect(controller.tombstonedIds.length, equals(500));

      // Oldest 2000 entries MUST be evicted
      for (int i = 0; i < 2000; i++) {
        expect(controller.isTombstoned('tomb_$i'), isFalse,
            reason: 'tomb_$i should have been evicted by FIFO queue');
      }

      // Newest 500 entries MUST be retained
      for (int i = 2000; i < 2500; i++) {
        expect(controller.isTombstoned('tomb_$i'), isTrue,
            reason: 'tomb_$i should be present in the active 500 tombstone set');
      }

      controller.dispose();
    });

    test('Re-tombstoning an existing ID updates FIFO position and protects it from immediate eviction', () async {
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await pumpEventQueue();

      // Insert 500 items: tomb_0 .. tomb_499
      for (int i = 0; i < 500; i++) {
        controller.tombstoneId('tomb_$i');
      }
      expect(controller.tombstonedIds.length, equals(500));
      expect(controller.isTombstoned('tomb_0'), isTrue);

      // Re-touch / re-tombstone tomb_0 (moves it to newest)
      controller.tombstoneId('tomb_0');
      expect(controller.tombstonedIds.length, equals(500));

      // Add one more item tomb_500. This should evict tomb_1 (not tomb_0!)
      controller.tombstoneId('tomb_500');

      expect(controller.tombstonedIds.length, equals(500));
      expect(controller.isTombstoned('tomb_1'), isFalse, reason: 'tomb_1 was oldest and should be evicted');
      expect(controller.isTombstoned('tomb_0'), isTrue, reason: 'tomb_0 was re-touched and should be retained');
      expect(controller.isTombstoned('tomb_500'), isTrue);

      controller.dispose();
    });

    test('Processing 2,500 ghost IDs via SSE deltas caps ignoredMissingIds to exactly 500 with FIFO eviction', () async {
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await pumpEventQueue();

      fakeRepo.mockDownloads = []; // Empty DB so all unknowns become confirmed missing ghosts
      fakeRepo.fetchDelay = const Duration(milliseconds: 1);

      // Feed 2,500 unknown IDs in batches of 50
      const totalGhosts = 2500;
      for (int i = 0; i < totalGhosts; i += 50) {
        final batch = List.generate(
          50,
          (j) => Delta(id: 'ghost_${i + j}', status: DownloadState(value: DownloadStateEnum.inProgress)),
        );
        fakeRepo.deltaController.add(batch);
        await Future.delayed(const Duration(milliseconds: 5));
      }

      await Future.delayed(const Duration(milliseconds: 50));
      await controller.syncDownloads(isInitialLoad: false);

      // Set must be bounded to <= 500
      expect(controller.ignoredMissingIds.length, lessThanOrEqualTo(500));
      expect(controller.ignoredMissingIds.length, equals(500));

      // Oldest ghosts (e.g. ghost_0 .. ghost_1999) must be evicted
      for (int i = 0; i < 2000; i += 50) {
        expect(controller.isIgnoredMissing('ghost_$i'), isFalse,
            reason: 'ghost_$i should have been evicted from ignoredMissingIds');
      }

      // Newest ghosts (e.g. ghost_2000 .. ghost_2499) must be retained
      for (int i = 2000; i < 2500; i += 50) {
        expect(controller.isIgnoredMissing('ghost_$i'), isTrue,
            reason: 'ghost_$i should be retained in ignoredMissingIds');
      }

      controller.dispose();
    });

    test('Cross-set consistency: tombstoning an ignored missing ID purges it from ignoredMissing and adds to tombstoned', () async {
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await pumpEventQueue();

      fakeRepo.mockDownloads = [];
      fakeRepo.deltaController.add([
        Delta(id: 'ghost_x', status: DownloadState(value: DownloadStateEnum.inProgress)),
      ]);
      await Future.delayed(const Duration(milliseconds: 30));

      expect(controller.isIgnoredMissing('ghost_x'), isTrue);
      expect(controller.isTombstoned('ghost_x'), isFalse);

      // Now tombstone ghost_x
      controller.tombstoneId('ghost_x');

      expect(controller.isTombstoned('ghost_x'), isTrue);
      expect(controller.isIgnoredMissing('ghost_x'), isFalse);

      controller.dispose();
    });
  });

  group('Adversarial Challenge 2: Cancellation Lifecycle & Memory Retention', () {
    test('cancelDownload dispatches to repository, retains item in _downloads, and never tombstones it', () async {
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await pumpEventQueue();

      expect(controller.downloads.any((d) => d.id == 'dl_1'), isTrue);

      final success = await controller.cancelDownload('dl_1');

      expect(success, isTrue);
      expect(fakeRepo.cancelledIds, contains('dl_1'));
      // Must NOT be tombstoned
      expect(controller.isTombstoned('dl_1'), isFalse);
      expect(controller.isIgnoredMissing('dl_1'), isFalse);
      // Item MUST still exist in _downloads
      expect(controller.downloads.any((d) => d.id == 'dl_1'), isTrue);

      controller.dispose();
    });

    test('Delta with DownloadStateEnum.cancelled updates state in-place without removing or tombstoning', () async {
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await pumpEventQueue();

      final dl1Before = controller.downloads.firstWhere((d) => d.id == 'dl_1');
      expect(dl1Before.state?.value, equals(DownloadStateEnum.inProgress));

      // Emit cancelled delta
      fakeRepo.deltaController.add([
        Delta(
          id: 'dl_1',
          status: DownloadState(value: DownloadStateEnum.cancelled, progressValue: 35.0),
        ),
      ]);
      await pumpEventQueue();

      // Must remain in downloads list
      expect(controller.downloads.any((d) => d.id == 'dl_1'), isTrue);
      final dl1After = controller.downloads.firstWhere((d) => d.id == 'dl_1');
      expect(dl1After.state?.value, equals(DownloadStateEnum.cancelled));
      expect(dl1After.state?.progressValue, equals(35.0));

      // Must NOT be tombstoned
      expect(controller.isTombstoned('dl_1'), isFalse);
      expect(controller.isIgnoredMissing('dl_1'), isFalse);

      controller.dispose();
    });

    test('syncDownloads preserves cancelled downloads returned from server (never filters them)', () async {
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await pumpEventQueue();

      // Backend returns dl_1 with cancelled state
      fakeRepo.mockDownloads = [
        Download(
          id: 'dl_1',
          info: Info(title: 'Cancelled Video'),
          state: DownloadState(value: DownloadStateEnum.cancelled, progressValue: 40.0),
        ),
      ];

      await controller.syncDownloads(isInitialLoad: false);

      expect(controller.downloads.length, equals(1));
      expect(controller.downloads.first.id, equals('dl_1'));
      expect(controller.downloads.first.state?.value, equals(DownloadStateEnum.cancelled));
      expect(controller.isTombstoned('dl_1'), isFalse);

      controller.dispose();
    });

    test('Subsequent deltas for cancelled items continue to update properties and are not blocked', () async {
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await pumpEventQueue();

      // Set dl_1 to cancelled
      fakeRepo.deltaController.add([
        Delta(id: 'dl_1', status: DownloadState(value: DownloadStateEnum.cancelled)),
      ]);
      await pumpEventQueue();

      // Send info update delta for dl_1
      fakeRepo.deltaController.add([
        Delta(id: 'dl_1', info: Info(title: 'Cancelled Video - New Title')),
      ]);
      await pumpEventQueue();

      final dl1 = controller.downloads.firstWhere((d) => d.id == 'dl_1');
      expect(dl1.info?.title, equals('Cancelled Video - New Title'));

      // Send retry gesture action
      await controller.sendAction('dl_1', 'retry');
      expect(fakeRepo.retriedIds, contains('dl_1'));

      controller.dispose();
    });
  });

  group('Adversarial Challenge 3: Background Delta Sync UI Stability & Loading Guard', () {
    test('100 concurrent background delta syncs under latency never set isLoading to true', () async {
      fakeRepo.fetchDelay = const Duration(milliseconds: 20);
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);

      // Wait for initial cold load to finish
      await Future.delayed(const Duration(milliseconds: 50));
      expect(controller.isLoading, isFalse);
      expect(controller.downloads.isNotEmpty, isTrue);

      final List<bool> observedLoadingStates = [];
      controller.addListener(() {
        observedLoadingStates.add(controller.isLoading);
      });

      // Fire 100 rapid concurrent background syncs and refreshes
      final futures = <Future<void>>[];
      for (int i = 0; i < 50; i++) {
        futures.add(controller.syncDownloads(isInitialLoad: false));
        futures.add(controller.refreshDownloads());
      }

      await Future.wait(futures);
      await Future.delayed(const Duration(milliseconds: 60));

      expect(controller.isLoading, isFalse);
      expect(observedLoadingStates.any((state) => state == true), isFalse,
          reason: 'Background sync must NEVER set isLoading = true when downloads are present');

      controller.dispose();
    });

    test('syncDownloads(isInitialLoad: true) when _downloads is already populated does NOT set isLoading = true', () async {
      fakeRepo.fetchDelay = const Duration(milliseconds: 30);
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await Future.delayed(const Duration(milliseconds: 60));

      expect(controller.isLoading, isFalse);
      expect(controller.downloads.isNotEmpty, isTrue);

      bool wasLoading = false;
      controller.addListener(() {
        if (controller.isLoading) wasLoading = true;
      });

      // Call with isInitialLoad: true while downloads are present
      final future = controller.syncDownloads(isInitialLoad: true);
      expect(controller.isLoading, isFalse);

      await future;
      expect(controller.isLoading, isFalse);
      expect(wasLoading, isFalse,
          reason: 'isInitialLoad: true must only show spinner when _downloads is empty');

      controller.dispose();
    });

    test('Network error during background delta sync does not set isLoading = true and preserves existing items', () async {
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await pumpEventQueue();

      expect(controller.downloads.length, equals(2));
      expect(controller.isLoading, isFalse);

      fakeRepo.shouldThrow = true;
      fakeRepo.fetchDelay = const Duration(milliseconds: 10);

      bool wasLoading = false;
      controller.addListener(() {
        if (controller.isLoading) wasLoading = true;
      });

      await controller.syncDownloads(isInitialLoad: false);

      expect(controller.isLoading, isFalse);
      expect(wasLoading, isFalse);
      // Existing items must be retained on error
      expect(controller.downloads.length, equals(2));

      controller.dispose();
    });
  });

  group('Adversarial Challenge 4: High-Throughput Delta Ingestion & Storm Resilience', () {
    test('Stream burst of 2,000 mixed deltas processes completely without truncation or unhandled exceptions', () async {
      fakeRepo.fetchDelay = const Duration(milliseconds: 5);
      final controller = DownloadsController(fakeRepo, fakeSystemCtrl);
      await Future.delayed(const Duration(milliseconds: 20));

      fakeRepo.getAllDownloadsCallCount = 0;

      // Generate 2,000 deltas: 500 progress on dl_1, 500 progress on dl_2, 500 sub-deltas, 500 ghosts
      final List<Delta> burstDeltas = [];
      for (int i = 0; i < 500; i++) {
        burstDeltas.add(Delta(id: 'dl_1', status: DownloadState(value: DownloadStateEnum.inProgress, progressValue: (i % 100).toDouble())));
        burstDeltas.add(Delta(id: 'dl_2', status: DownloadState(value: DownloadStateEnum.inProgress, progressValue: ((i * 2) % 100).toDouble())));
        burstDeltas.add(Delta(id: 'dl_1', subId: 'sub_$i', status: DownloadState(value: DownloadStateEnum.inProgress)));
        burstDeltas.add(Delta(id: 'storm_ghost_$i', status: DownloadState(value: DownloadStateEnum.inProgress)));
      }

      // Update mockDownloads in repo to inProgress so sync reconciliation matches latest state
      fakeRepo.mockDownloads = [
        Download(
          id: 'dl_1',
          info: Info(title: 'Active Video 1', type: DownloadType.video),
          state: DownloadState(value: DownloadStateEnum.inProgress, progressValue: 99.0),
        ),
        Download(
          id: 'dl_2',
          info: Info(title: 'Active Video 2', type: DownloadType.video),
          state: DownloadState(value: DownloadStateEnum.inProgress, progressValue: 99.0),
        ),
      ];

      // Feed in 10 bursts of 200 deltas
      for (int b = 0; b < burstDeltas.length; b += 200) {
        final chunk = burstDeltas.sublist(b, b + 200);
        fakeRepo.deltaController.add(chunk);
      }

      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 50));

      // Both downloads must reflect updates
      final dl1 = controller.downloads.firstWhere((d) => d.id == 'dl_1');
      final dl2 = controller.downloads.firstWhere((d) => d.id == 'dl_2');
      expect(dl1.state?.value, equals(DownloadStateEnum.inProgress));
      expect(dl2.state?.value, equals(DownloadStateEnum.inProgress));

      // Peak concurrency during storm must remain <= 1
      expect(fakeRepo.peakConcurrentFetches, lessThanOrEqualTo(1));

      controller.dispose();
    });
  });
}

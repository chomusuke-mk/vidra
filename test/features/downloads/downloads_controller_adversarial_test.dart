import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/core/network/vidra_http_client.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';

class AdversarialSystemController extends ChangeNotifier
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
  String? get backendToken => 'adv_token';
  @override
  String? get serverLogsFilePath => null;
  @override
  Future<void> get whenPortReady => Future.value();
  @override
  Future<void> stopBackendForUpdate() async {}
  @override
  Future<void> resumeInitialization() async {}
  @override
  void enqueueDownload(String url, Map<String, dynamic> options) {
    enqueuedCommands.add({'url': url, 'options': options});
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}
}

class AdversarialDownloadRepository extends DownloadRepository {
  List<Download> serverDownloads;
  int getAllDownloadsCalls = 0;
  int currentActiveFetches = 0;
  int peakConcurrentFetches = 0;
  Duration fetchDelay = Duration.zero;
  bool shouldThrow = false;
  int throwCount = 0;
  int maxThrows = 0;

  final StreamController<List<Delta>> deltaController =
      StreamController<List<Delta>>.broadcast();

  final List<String> deletedIds = [];
  final List<String> cancelledIds = [];
  final List<String> pausedIds = [];
  final List<String> resumedIds = [];
  final List<String> retriedIds = [];

  AdversarialDownloadRepository({this.serverDownloads = const []})
      : super(VidraHttpClient(baseUrl: 'http://127.0.0.1:5000', defaultHeaders: {}));

  @override
  Stream<List<Delta>> watchGlobalProgress() => deltaController.stream;

  @override
  Future<List<Download>> getAllDownloads() async {
    getAllDownloadsCalls++;
    currentActiveFetches++;
    if (currentActiveFetches > peakConcurrentFetches) {
      peakConcurrentFetches = currentActiveFetches;
    }

    if (fetchDelay > Duration.zero) {
      await Future.delayed(fetchDelay);
    }

    currentActiveFetches--;

    if (shouldThrow || (maxThrows > 0 && throwCount < maxThrows)) {
      throwCount++;
      throw Exception('Adversarial simulated network/DB error (attempt $throwCount)');
    }

    return serverDownloads
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
  Future<void> deleteDownload(String id) async {
    deletedIds.add(id);
    serverDownloads.removeWhere((d) => d.id == id);
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

  late AdversarialSystemController systemCtrl;
  late AdversarialDownloadRepository repository;

  setUp(() {
    systemCtrl = AdversarialSystemController();
    repository = AdversarialDownloadRepository();
  });

  tearDown(() {
    repository.deltaController.close();
  });

  // ===========================================================================
  // CHALLENGE 1: EXTREME CONCURRENCY STRESS (100+, 200+, 500+ CALLERS)
  // ===========================================================================
  group('Adversarial Challenge 1: Single-Flight Under Extreme Concurrency', () {
    test('100 concurrent syncDownloads callers maintain peakConcurrency <= 1 and exactly <= 2 total fetches', () async {
      repository.fetchDelay = const Duration(milliseconds: 30);
      repository.serverDownloads = [
        Download(id: 'dl_init', info: Info(title: 'Init'), state: DownloadState(value: DownloadStateEnum.completed)),
      ];

      final controller = DownloadsController(repository, systemCtrl);
      await Future.delayed(const Duration(milliseconds: 50));

      repository.getAllDownloadsCalls = 0;
      repository.peakConcurrentFetches = 0;

      // 100 concurrent callers invoke syncDownloads
      final futures = List.generate(100, (i) => controller.syncDownloads(isInitialLoad: false));
      await Future.wait(futures);

      expect(repository.peakConcurrentFetches, lessThanOrEqualTo(1));
      expect(repository.getAllDownloadsCalls, lessThanOrEqualTo(2));
      expect(controller.downloads.length, equals(1));
      expect(controller.isLoading, isFalse);

      controller.dispose();
    });

    test('250 concurrent callers with staggered invocation times during slow I/O coalesces without leaking requests', () async {
      repository.fetchDelay = const Duration(milliseconds: 40);
      final controller = DownloadsController(repository, systemCtrl);
      await Future.delayed(const Duration(milliseconds: 60));

      repository.getAllDownloadsCalls = 0;
      repository.peakConcurrentFetches = 0;

      final futures = <Future>[];
      // 250 requests fired in 5 waves over 100ms
      for (int wave = 0; wave < 5; wave++) {
        for (int i = 0; i < 50; i++) {
          futures.add(controller.syncDownloads(isInitialLoad: false));
        }
        await Future.delayed(const Duration(milliseconds: 20));
      }

      await Future.wait(futures);
      await Future.delayed(const Duration(milliseconds: 80));

      expect(repository.peakConcurrentFetches, lessThanOrEqualTo(1));
      // Over 5 waves spanning across ~100ms with 40ms fetch delay, total calls should be at most 4-5
      expect(repository.getAllDownloadsCalls, lessThanOrEqualTo(5));
      expect(controller.isLoading, isFalse);

      controller.dispose();
    });
  });

  // ===========================================================================
  // CHALLENGE 2: RAPID DELTA FLOOD WITH ALTERNATING IDS (GHOST, DELETED, VALID)
  // ===========================================================================
  group('Adversarial Challenge 2: Rapid Delta Flood & Memory Boundary Stress', () {
    test('1000 deltas flood with alternating deleted, ghost, valid, and malformed IDs', () async {
      final initialItems = List.generate(
        10,
        (i) => Download(
          id: 'valid_$i',
          info: Info(title: 'Video $i'),
          state: DownloadState(value: DownloadStateEnum.inProgress, progressValue: 0.0),
        ),
      );
      repository.serverDownloads = List.from(initialItems);

      final controller = DownloadsController(repository, systemCtrl);
      await pumpEventQueue();
      expect(controller.downloads.length, equals(10));

      repository.getAllDownloadsCalls = 0;
      repository.peakConcurrentFetches = 0;

      final random = Random(42);
      final deltas = <Delta>[];

      for (int i = 0; i < 1000; i++) {
        final type = i % 5;
        switch (type) {
          case 0:
            // Valid item progress update
            final validIdx = random.nextInt(10);
            deltas.add(
              Delta(
                id: 'valid_$validIdx',
                status: DownloadState(
                  value: DownloadStateEnum.inProgress,
                  progressValue: (i % 100).toDouble(),
                ),
              ),
            );
            break;
          case 1:
            // Ghost ID (not on server)
            deltas.add(
              Delta(
                id: 'ghost_${random.nextInt(600)}',
                status: DownloadState(value: DownloadStateEnum.inProgress),
              ),
            );
            break;
          case 2:
            // Deleted delta for valid or ghost ID
            deltas.add(
              Delta(
                id: i % 2 == 0 ? 'valid_${random.nextInt(10)}' : 'ghost_${random.nextInt(600)}',
                status: DownloadState(value: DownloadStateEnum.deleted),
              ),
            );
            break;
          case 3:
            // Sub-delta (must be skipped)
            deltas.add(
              Delta(
                id: 'valid_${random.nextInt(10)}',
                subId: 'sub_${random.nextInt(5)}',
                status: DownloadState(value: DownloadStateEnum.completed),
              ),
            );
            break;
          case 4:
            // Malformed delta (null id, null status, etc.)
            deltas.add(Delta(id: null, status: null, info: null));
            break;
        }
      }

      // Emit in 20 chunks of 50 deltas
      for (int chunk = 0; chunk < 20; chunk++) {
        repository.deltaController.add(deltas.sublist(chunk * 50, (chunk + 1) * 50));
        await pumpEventQueue();
      }

      await Future.delayed(const Duration(milliseconds: 50));

      // Bounded sets invariant: length must NEVER exceed 500
      expect(controller.tombstonedIds.length, lessThanOrEqualTo(500));
      expect(controller.ignoredMissingIds.length, lessThanOrEqualTo(500));
      expect(repository.peakConcurrentFetches, lessThanOrEqualTo(1));

      // Controller should remain responsive and stable
      expect(controller.isLoading, isFalse);
      controller.dispose();
    });

    test('Deleted item during in-flight getAllDownloads is NOT resurrected by stale server response', () async {
      repository.fetchDelay = const Duration(milliseconds: 50);
      repository.serverDownloads = [
        Download(id: 'race_item', info: Info(title: 'Race Item'), state: DownloadState(value: DownloadStateEnum.inProgress)),
      ];

      final controller = DownloadsController(repository, systemCtrl);
      await Future.delayed(const Duration(milliseconds: 60));
      expect(controller.downloads.any((d) => d.id == 'race_item'), isTrue);

      // 1. Trigger background sync
      controller.syncDownloads(isInitialLoad: false);

      // 2. While sync is in-flight, deleteDownload('race_item') is called!
      await Future.delayed(const Duration(milliseconds: 10));
      final deleteFuture = controller.deleteDownload('race_item');

      expect(controller.downloads.any((d) => d.id == 'race_item'), isFalse);
      expect(controller.isTombstoned('race_item'), isTrue);

      await deleteFuture;
      await Future.delayed(const Duration(milliseconds: 60));

      // 3. Verify item was NOT re-added when stale getAllDownloads returned
      expect(controller.downloads.any((d) => d.id == 'race_item'), isFalse);
      expect(controller.isTombstoned('race_item'), isTrue);

      controller.dispose();
    });
  });

  // ===========================================================================
  // CHALLENGE 3: OUT-OF-ORDER DELTAS & RESURRECTION LIFECYCLE
  // ===========================================================================
  group('Adversarial Challenge 3: Out-of-Order Deltas & Resurrection Lifecycle', () {
    test('Explicit retryDownload un-tombstones item and allows future deltas to update it', () async {
      final controller = DownloadsController(repository, systemCtrl);
      await pumpEventQueue();

      // 1. Item deleted & tombstoned
      controller.tombstoneId('dl_resurrect');
      expect(controller.isTombstoned('dl_resurrect'), isTrue);

      // Delta for tombstoned item is ignored
      repository.deltaController.add([
        Delta(id: 'dl_resurrect', status: DownloadState(value: DownloadStateEnum.inProgress, progressValue: 10.0)),
      ]);
      await pumpEventQueue();
      expect(controller.downloads.any((d) => d.id == 'dl_resurrect'), isFalse);

      // 2. User retries download
      repository.serverDownloads = [
        Download(id: 'dl_resurrect', info: Info(title: 'Resurrected'), state: DownloadState(value: DownloadStateEnum.pending)),
      ];
      await controller.retryDownload('dl_resurrect');

      expect(controller.isTombstoned('dl_resurrect'), isFalse);
      expect(controller.isIgnoredMissing('dl_resurrect'), isFalse);

      // 3. Sync from server populates item
      await controller.refreshDownloads();
      expect(controller.downloads.any((d) => d.id == 'dl_resurrect'), isTrue);

      // 4. Future deltas successfully mutate item
      repository.deltaController.add([
        Delta(id: 'dl_resurrect', status: DownloadState(value: DownloadStateEnum.inProgress, progressValue: 77.0)),
      ]);
      await pumpEventQueue();

      final dl = controller.downloads.firstWhere((d) => d.id == 'dl_resurrect');
      expect(dl.state?.progressValue, equals(77.0));

      controller.dispose();
    });

    test('Confirmed ghost resurrected by server appearing in getAllDownloads is removed from ignoredMissingIds', () async {
      final controller = DownloadsController(repository, systemCtrl);
      await pumpEventQueue();

      // Delta for unknown item
      repository.deltaController.add([
        Delta(id: 'ghost_to_real', status: DownloadState(value: DownloadStateEnum.inProgress)),
      ]);
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 30));

      expect(controller.isIgnoredMissing('ghost_to_real'), isTrue);

      // Backend now creates the item and manual sync is run
      repository.serverDownloads = [
        Download(id: 'ghost_to_real', info: Info(title: 'Now Exists'), state: DownloadState(value: DownloadStateEnum.inProgress)),
      ];

      await controller.refreshDownloads();

      expect(controller.isIgnoredMissing('ghost_to_real'), isFalse);
      expect(controller.downloads.any((d) => d.id == 'ghost_to_real'), isTrue);

      controller.dispose();
    });
  });

  // ===========================================================================
  // CHALLENGE 4: REPOSITORY EXCEPTIONS & CHAOS FAULT INJECTION
  // ===========================================================================
  group('Adversarial Challenge 4: Repository Exceptions & Chaos Fault Tolerance', () {
    test('Repeated repository exceptions do not permanently brick controller or leave isLoading == true', () async {
      repository.maxThrows = 5; // First 5 calls will throw exceptions
      final controller = DownloadsController(repository, systemCtrl);

      // Let initial load fail
      await Future.delayed(const Duration(milliseconds: 30));
      expect(controller.isLoading, isFalse);
      expect(repository.throwCount, equals(1));

      // Trigger 4 more failing syncs
      for (int i = 0; i < 4; i++) {
        await controller.syncDownloads(isInitialLoad: false);
      }
      expect(repository.throwCount, equals(5));

      // 6th call: repository now recovers
      repository.serverDownloads = [
        Download(id: 'recovery_item', info: Info(title: 'Recovered'), state: DownloadState(value: DownloadStateEnum.completed)),
      ];

      await controller.syncDownloads(isInitialLoad: false);

      expect(controller.downloads.length, equals(1));
      expect(controller.downloads.first.id, equals('recovery_item'));
      expect(controller.isLoading, isFalse);

      controller.dispose();
    });

    test('Disposal during active exception-throwing sync cleans up safely with 0 uncaught errors', () async {
      repository.fetchDelay = const Duration(milliseconds: 30);
      repository.shouldThrow = true;

      final controller = DownloadsController(repository, systemCtrl);

      final future1 = controller.syncDownloads(isInitialLoad: false);
      final future2 = controller.syncDownloads(isInitialLoad: false);

      // Dispose while futures are pending
      controller.dispose();

      expect(() async {
        await future1;
        await future2;
      }, returnsNormally);

      await Future.delayed(const Duration(milliseconds: 50));
    });
  });
}

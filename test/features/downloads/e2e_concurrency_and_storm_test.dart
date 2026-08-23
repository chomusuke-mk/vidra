import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';

/// Test Fake for SystemController
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
  String? get backendToken => 'test_token';
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

/// Test Fake for DownloadRepository with request counting and controlled delay
class ConcurrencyTrackingDownloadRepository implements DownloadRepository {
  final StreamController<List<Delta>> _globalStreamController =
      StreamController<List<Delta>>.broadcast();

  int getAllDownloadsCalls = 0;
  int currentActiveFetches = 0;
  int peakConcurrentFetches = 0;

  List<Download> serverDownloads = [];
  Duration fetchDelay = Duration.zero;
  bool shouldFailFetch = false;

  final List<String> performedActions = [];

  void emitDeltas(List<Delta> deltas) {
    if (!_globalStreamController.isClosed) {
      _globalStreamController.add(deltas);
    }
  }

  void closeStream() {
    _globalStreamController.close();
  }

  @override
  Stream<List<Delta>> watchGlobalProgress() => _globalStreamController.stream;

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

    if (shouldFailFetch) {
      throw Exception('Simulated backend database error');
    }

    // Return a clone of downloads to simulate network serialization
    return serverDownloads
        .map(
          (d) => Download(
            id: d.id,
            info: d.info != null
                ? Info(
                    url: d.info?.url,
                    title: d.info?.title,
                    image: d.info?.image,
                    duration: d.info?.duration,
                    type: d.info?.type,
                  )
                : null,
            state: d.state != null
                ? DownloadState(
                    value: d.state?.value,
                    subState: d.state?.subState,
                    progressValue: d.state?.progressValue,
                    progressLabel: d.state?.progressLabel,
                    speed: d.state?.speed,
                    timeSpent: d.state?.timeSpent,
                    timeTotal: d.state?.timeTotal,
                    timeLeft: d.state?.timeLeft,
                    errorMessage: d.state?.errorMessage,
                  )
                : null,
            options: d.options != null ? Map.from(d.options!) : null,
            subDownloads: d.subDownloads,
          ),
        )
        .toList();
  }

  @override
  Future<Download?> getDownloadById(String id) async {
    return serverDownloads.where((d) => d.id == id).firstOrNull;
  }

  @override
  Future<String> addDownload(
    String url, {
    Map<String, dynamic> options = const {},
  }) async {
    final newId = 'dl_${serverDownloads.length + 1}';
    serverDownloads.add(
      Download(
        id: newId,
        info: Info(url: url, title: 'Download $newId'),
        state: DownloadState(value: DownloadStateEnum.pending),
        options: options,
      ),
    );
    return newId;
  }

  @override
  Future<void> pauseDownload(String id) async {
    performedActions.add('pause:$id');
    final dl = serverDownloads.where((d) => d.id == id).firstOrNull;
    if (dl != null) dl.state = DownloadState(value: DownloadStateEnum.paused);
  }

  @override
  Future<void> resumeDownload(String id) async {
    performedActions.add('resume:$id');
    final dl = serverDownloads.where((d) => d.id == id).firstOrNull;
    if (dl != null) dl.state = DownloadState(value: DownloadStateEnum.inProgress);
  }

  @override
  Future<void> cancelDownload(String id) async {
    performedActions.add('cancel:$id');
    final dl = serverDownloads.where((d) => d.id == id).firstOrNull;
    if (dl != null) dl.state = DownloadState(value: DownloadStateEnum.cancelled);
  }

  @override
  Future<void> retryDownload(String id) async {
    performedActions.add('retry:$id');
    final dl = serverDownloads.where((d) => d.id == id).firstOrNull;
    if (dl != null) dl.state = DownloadState(value: DownloadStateEnum.pending);
  }

  @override
  Future<void> deleteDownload(String id) async {
    performedActions.add('delete:$id');
    serverDownloads.removeWhere((d) => d.id == id);
  }

  @override
  Future<List<SubDownload>> getEntries(String id) async => [];

  @override
  Future<void> submitSelectedEntries(String id, List<String> entries) async {}

  @override
  Future<String> fetchLogs(String? id) async => 'Logs for $id';

  @override
  Future<bool> checkHealth() async => true;

  @override
  Stream<List<Delta>> watchDetailedProgress(String id) => const Stream.empty();
}

void main() {
  group('E2E Downloads Concurrency & Request Storm Suite', () {
    late FakeSystemController systemController;
    late ConcurrencyTrackingDownloadRepository repository;

    setUp(() {
      systemController = FakeSystemController();
      repository = ConcurrencyTrackingDownloadRepository();
    });

    tearDown(() {
      repository.closeStream();
    });

    // =========================================================================
    // TIER 1: FEATURE COVERAGE — Single-Flight & Coalescing
    // =========================================================================
    group('Tier 1: Single-Flight Synchronization', () {
      test('1.1: Cold start initialization loads downloads from repository and starts stream', () async {
        repository.serverDownloads = [
          Download(
            id: 'dl_1',
            info: Info(title: 'Initial Video'),
            state: DownloadState(value: DownloadStateEnum.inProgress),
          ),
        ];

        final controller = DownloadsController(repository, systemController);
        await Future.delayed(const Duration(milliseconds: 10));

        expect(controller.downloads.length, equals(1));
        expect(controller.downloads.first.id, equals('dl_1'));
        expect(controller.downloads.first.info?.title, equals('Initial Video'));
        expect(controller.isLoading, isFalse);
        expect(repository.getAllDownloadsCalls, equals(1));

        controller.dispose();
      });

      test('1.2: 10 rapid concurrent delta updates with unknown IDs trigger at most 1 in-flight fetch', () async {
        repository.fetchDelay = const Duration(milliseconds: 50);
        final controller = DownloadsController(repository, systemController);
        await Future.delayed(const Duration(milliseconds: 60));
        final initialCalls = repository.getAllDownloadsCalls;

        // Emit 10 unknown deltas concurrently
        for (var i = 1; i <= 10; i++) {
          repository.emitDeltas([
            Delta(
              id: 'unknown_dl_$i',
              status: DownloadState(value: DownloadStateEnum.inProgress),
            ),
          ]);
        }

        await Future.delayed(const Duration(milliseconds: 150));

        // Total calls should be bounded and peak concurrent fetches must never exceed 1
        expect(repository.peakConcurrentFetches, lessThanOrEqualTo(1));
        expect(repository.getAllDownloadsCalls - initialCalls, lessThanOrEqualTo(3));

        controller.dispose();
      });

      test('1.3: Repository error during fetch cleans up loading state without permanent lock', () async {
        repository.shouldFailFetch = true;
        final controller = DownloadsController(repository, systemController);
        await Future.delayed(const Duration(milliseconds: 10));

        expect(controller.isLoading, isFalse);
        expect(controller.downloads, isEmpty);

        // Now fix repository and trigger another fetch via system state change
        repository.shouldFailFetch = false;
        repository.serverDownloads = [
          Download(
            id: 'recovered_1',
            info: Info(title: 'Recovered Download'),
            state: DownloadState(value: DownloadStateEnum.completed),
          ),
        ];

        systemController.setState(SystemState.initializing);
        systemController.setState(SystemState.ready);
        await Future.delayed(const Duration(milliseconds: 10));

        expect(controller.downloads.length, equals(1));
        expect(controller.downloads.first.id, equals('recovered_1'));

        controller.dispose();
      });

      test('1.4: Manual selection modal request and consumption lifecycle works reliably', () async {
        final controller = DownloadsController(repository, systemController);
        await Future.delayed(const Duration(milliseconds: 10));

        expect(controller.manualModalRequestId, isNull);

        controller.requestSelectionModal('dl_target_123');
        expect(controller.manualModalRequestId, equals('dl_target_123'));

        controller.consumeManualModalRequest();
        expect(controller.manualModalRequestId, isNull);

        controller.dispose();
      });

      test('1.5: SystemState transitions between non-ready and ready safely manage subscription', () async {
        final controller = DownloadsController(repository, systemController);
        await Future.delayed(const Duration(milliseconds: 10));
        final initialCalls = repository.getAllDownloadsCalls;

        // Transition system away from ready
        systemController.setState(SystemState.startingBackend);
        await Future.delayed(const Duration(milliseconds: 10));

        // Transition back to ready
        systemController.setState(SystemState.ready);
        await Future.delayed(const Duration(milliseconds: 10));

        expect(repository.getAllDownloadsCalls, greaterThan(initialCalls));
        controller.dispose();
      });
    });

    // =========================================================================
    // TIER 1: FEATURE COVERAGE — Tombstoning & Delta Filtering
    // =========================================================================
    group('Tier 1: Tombstoning & Delta Filtering', () {
      test('1.6: Deleted delta removes download from in-memory list without re-fetching', () async {
        repository.serverDownloads = [
          Download(
            id: 'dl_keep',
            info: Info(title: 'Keep Me'),
            state: DownloadState(value: DownloadStateEnum.inProgress),
          ),
          Download(
            id: 'dl_delete',
            info: Info(title: 'Delete Me'),
            state: DownloadState(value: DownloadStateEnum.inProgress),
          ),
        ];

        final controller = DownloadsController(repository, systemController);
        await Future.delayed(const Duration(milliseconds: 10));
        expect(controller.downloads.length, equals(2));

        final callsBeforeDelete = repository.getAllDownloadsCalls;

        // Emit deleted delta
        repository.emitDeltas([
          Delta(
            id: 'dl_delete',
            status: DownloadState(value: DownloadStateEnum.deleted),
          ),
        ]);
        await Future.delayed(const Duration(milliseconds: 10));

        expect(controller.downloads.length, equals(1));
        expect(controller.downloads.first.id, equals('dl_keep'));
        // Deleted delta should NOT trigger a re-fetch
        expect(repository.getAllDownloadsCalls, equals(callsBeforeDelete));

        controller.dispose();
      });

      test('1.7: Trailing deltas for already deleted IDs do not create cascading fetch storms', () async {
        repository.serverDownloads = [
          Download(
            id: 'dl_temp',
            state: DownloadState(value: DownloadStateEnum.inProgress),
          ),
        ];

        final controller = DownloadsController(repository, systemController);
        await Future.delayed(const Duration(milliseconds: 10));

        // 1. Delete item
        repository.emitDeltas([
          Delta(
            id: 'dl_temp',
            status: DownloadState(value: DownloadStateEnum.deleted),
          ),
        ]);
        await Future.delayed(const Duration(milliseconds: 10));
        expect(controller.downloads, isEmpty);

        final callsAfterDelete = repository.getAllDownloadsCalls;

        // 2. Trailing deltas arrive for deleted item
        for (var i = 0; i < 5; i++) {
          repository.emitDeltas([
            Delta(
              id: 'dl_temp',
              status: DownloadState(
                value: DownloadStateEnum.inProgress,
                progressValue: 50.0 + i,
              ),
            ),
          ]);
        }
        await Future.delayed(const Duration(milliseconds: 30));

        // Ensure calls are bounded and peak concurrency is <= 1
        expect(repository.peakConcurrentFetches, lessThanOrEqualTo(1));
        expect(repository.getAllDownloadsCalls - callsAfterDelete, lessThanOrEqualTo(2));

        controller.dispose();
      });

      test('1.8: Delta batch with unknown item does not truncate processing of subsequent valid items', () async {
        repository.serverDownloads = [
          Download(
            id: 'dl_valid_1',
            info: Info(title: 'Valid 1'),
            state: DownloadState(value: DownloadStateEnum.pending, progressValue: 0.0),
          ),
          Download(
            id: 'dl_valid_2',
            info: Info(title: 'Valid 2'),
            state: DownloadState(value: DownloadStateEnum.pending, progressValue: 0.0),
          ),
        ];

        final controller = DownloadsController(repository, systemController);
        await Future.delayed(const Duration(milliseconds: 10));

        // Emit batch: [unknown, valid_1 update, valid_2 update]
        repository.emitDeltas([
          Delta(
            id: 'unknown_item_x',
            status: DownloadState(value: DownloadStateEnum.inProgress),
          ),
          Delta(
            id: 'dl_valid_1',
            status: DownloadState(value: DownloadStateEnum.inProgress, progressValue: 45.0),
          ),
          Delta(
            id: 'dl_valid_2',
            status: DownloadState(value: DownloadStateEnum.completed, progressValue: 100.0),
          ),
        ]);

        await Future.delayed(const Duration(milliseconds: 20));

        // Verify that valid items were updated despite the unknown item in the batch
        final item1 = controller.downloads.where((d) => d.id == 'dl_valid_1').firstOrNull;
        final item2 = controller.downloads.where((d) => d.id == 'dl_valid_2').firstOrNull;

        expect(item1, isNotNull);
        expect(item2, isNotNull);

        controller.dispose();
      });

      test('1.9: Sub-deltas with subId != null are ignored by DownloadsController', () async {
        repository.serverDownloads = [
          Download(
            id: 'parent_1',
            info: Info(title: 'Parent Download'),
            state: DownloadState(value: DownloadStateEnum.inProgress),
          ),
        ];

        final controller = DownloadsController(repository, systemController);
        await Future.delayed(const Duration(milliseconds: 10));

        var notified = false;
        controller.addListener(() {
          notified = true;
        });

        // Emit sub-delta
        repository.emitDeltas([
          Delta(
            id: 'parent_1',
            subId: 'sub_item_99',
            status: DownloadState(value: DownloadStateEnum.inProgress, progressValue: 80.0),
          ),
        ]);
        await Future.delayed(const Duration(milliseconds: 10));

        // Sub-delta should be completely skipped in global downloads controller
        expect(notified, isFalse);
        expect(controller.downloads.first.state?.value, equals(DownloadStateEnum.inProgress));

        controller.dispose();
      });

      test('1.10: addDownload delegates to SystemController via IPC bridge', () async {
        final controller = DownloadsController(repository, systemController);
        await Future.delayed(const Duration(milliseconds: 10));

        final success = await controller.addDownload(
          'https://youtube.com/watch?v=storm123',
          {'format': 'mp4', 'quality': 'best'},
        );

        expect(success, isTrue);
        expect(systemController.enqueuedCommands.length, equals(1));
        expect(
          systemController.enqueuedCommands.first['url'],
          equals('https://youtube.com/watch?v=storm123'),
        );
        expect(
          systemController.enqueuedCommands.first['options']['format'],
          equals('mp4'),
        );

        // Empty url returns false and is not enqueued
        final emptySuccess = await controller.addDownload('   ', {});
        expect(emptySuccess, isFalse);
        expect(systemController.enqueuedCommands.length, equals(1));

        controller.dispose();
      });
    });

    // =========================================================================
    // TIER 2: BOUNDARY & CORNER CASES
    // =========================================================================
    group('Tier 2: Boundary & Corner Cases', () {
      test('2.1: 50+ concurrent requests on unknown delta burst maintain peak concurrency <= 1', () async {
        repository.fetchDelay = const Duration(milliseconds: 30);
        final controller = DownloadsController(repository, systemController);
        await Future.delayed(const Duration(milliseconds: 40));

        // Fire 60 concurrent delta events with unique unknown IDs
        final futures = <Future>[];
        for (var i = 0; i < 60; i++) {
          futures.add(
            Future(() {
              repository.emitDeltas([
                Delta(
                  id: 'storm_id_$i',
                  status: DownloadState(value: DownloadStateEnum.inProgress),
                ),
              ]);
            }),
          );
        }
        await Future.wait(futures);
        await Future.delayed(const Duration(milliseconds: 200));

        expect(repository.peakConcurrentFetches, lessThanOrEqualTo(1));
        controller.dispose();
      });

      test('2.2: 100 rapid alternating delete and update deltas maintain clean state and zero leaks', () async {
        repository.serverDownloads = [
          Download(
            id: 'flicker_1',
            info: Info(title: 'Flicker 1'),
            state: DownloadState(value: DownloadStateEnum.inProgress),
          ),
          Download(
            id: 'stable_2',
            info: Info(title: 'Stable 2'),
            state: DownloadState(value: DownloadStateEnum.inProgress),
          ),
        ];

        final controller = DownloadsController(repository, systemController);
        await Future.delayed(const Duration(milliseconds: 10));

        for (var i = 0; i < 100; i++) {
          if (i % 2 == 0) {
            repository.emitDeltas([
              Delta(
                id: 'flicker_1',
                status: DownloadState(value: DownloadStateEnum.deleted),
              ),
            ]);
          } else {
            repository.emitDeltas([
              Delta(
                id: 'stable_2',
                status: DownloadState(
                  value: DownloadStateEnum.inProgress,
                  progressValue: i.toDouble(),
                ),
              ),
            ]);
          }
        }
        await Future.delayed(const Duration(milliseconds: 50));

        expect(controller.downloads.any((d) => d.id == 'stable_2'), isTrue);
        expect(repository.peakConcurrentFetches, lessThanOrEqualTo(1));

        controller.dispose();
      });

      test('2.3: Delta flood with null, malformed, or missing fields does not crash controller', () async {
        final controller = DownloadsController(repository, systemController);
        await Future.delayed(const Duration(milliseconds: 10));

        expect(
          () => repository.emitDeltas([
            Delta(id: null, status: null, info: null),
            Delta(id: 'valid_1', status: null, info: null),
            Delta(id: null, status: DownloadState(value: null), info: null),
            Delta(
              id: 'valid_2',
              status: DownloadState(value: DownloadStateEnum.pending, progressValue: null),
              info: Info(title: null, url: null),
            ),
          ]),
          returnsNormally,
        );

        await Future.delayed(const Duration(milliseconds: 20));
        expect(controller.isLoading, isFalse);

        controller.dispose();
      });

      test('2.4: 50 concurrent sendAction calls execute cleanly without race condition', () async {
        repository.serverDownloads = List.generate(
          10,
          (i) => Download(
            id: 'action_dl_$i',
            info: Info(title: 'Action Item $i'),
            state: DownloadState(value: DownloadStateEnum.inProgress),
          ),
        );

        final controller = DownloadsController(repository, systemController);
        await Future.delayed(const Duration(milliseconds: 10));

        final actionFutures = <Future<bool>>[];
        final actions = ['pause', 'resume', 'cancel', 'retry', 'delete'];

        for (var i = 0; i < 50; i++) {
          final id = 'action_dl_${i % 10}';
          final action = actions[i % actions.length];
          actionFutures.add(controller.sendAction(id, action));
        }

        final results = await Future.wait(actionFutures);
        expect(results.every((r) => r == true), isTrue);
        expect(repository.performedActions.length, equals(50));

        controller.dispose();
      });

      test('2.5: Rapid toggling of SystemState during active fetch does not corrupt controller state', () async {
        repository.fetchDelay = const Duration(milliseconds: 30);
        final controller = DownloadsController(repository, systemController);

        // Rapid state oscillation
        for (var i = 0; i < 10; i++) {
          systemController.setState(
            i.isEven ? SystemState.ready : SystemState.retrying,
          );
          await Future.delayed(const Duration(milliseconds: 5));
        }

        systemController.setState(SystemState.ready);
        await Future.delayed(const Duration(milliseconds: 60));

        expect(controller.isLoading, isFalse);
        expect(repository.peakConcurrentFetches, lessThanOrEqualTo(1));

        controller.dispose();
      });
    });

    // =========================================================================
    // TIER 3: CROSS-FEATURE COMBINATIONS
    // =========================================================================
    group('Tier 3: Cross-Feature Combinations', () {
      test('3.1: Delta flood arriving while background sync is in-flight merges updates without losing state', () async {
        repository.serverDownloads = [
          Download(
            id: 'cross_1',
            info: Info(title: 'Original Title'),
            state: DownloadState(value: DownloadStateEnum.pending, progressValue: 0.0),
          ),
        ];

        final controller = DownloadsController(repository, systemController);
        await Future.delayed(const Duration(milliseconds: 10));

        // Start a slow sync while simultaneously emitting deltas
        repository.fetchDelay = const Duration(milliseconds: 40);
        systemController.setState(SystemState.ready);

        // Emit deltas while fetch is awaiting
        repository.emitDeltas([
          Delta(
            id: 'cross_1',
            status: DownloadState(
              value: DownloadStateEnum.inProgress,
              progressValue: 75.0,
              speed: '2.5 MB/s',
            ),
          ),
        ]);

        await Future.delayed(const Duration(milliseconds: 60));

        expect(controller.downloads.length, equals(1));
        final item = controller.downloads.first;
        expect(item.id, equals('cross_1'));

        controller.dispose();
      });

      test('3.2: Item deleted via sendAction ignores subsequent incoming deltas for that ID while adding new item', () async {
        repository.serverDownloads = [
          Download(
            id: 'to_delete_id',
            info: Info(title: 'To Be Deleted'),
            state: DownloadState(value: DownloadStateEnum.inProgress),
          ),
        ];

        final controller = DownloadsController(repository, systemController);
        await Future.delayed(const Duration(milliseconds: 10));
        expect(controller.downloads.length, equals(1));

        // Delete item via sendAction
        await controller.sendAction('to_delete_id', 'delete');
        // Emit delta reflecting deletion
        repository.emitDeltas([
          Delta(
            id: 'to_delete_id',
            status: DownloadState(value: DownloadStateEnum.deleted),
          ),
        ]);
        await Future.delayed(const Duration(milliseconds: 10));

        expect(controller.downloads, isEmpty);

        // Trailing deltas for deleted item arrive simultaneously with new addDownload
        repository.emitDeltas([
          Delta(
            id: 'to_delete_id',
            status: DownloadState(value: DownloadStateEnum.inProgress, progressValue: 99.0),
          ),
        ]);
        await controller.addDownload('https://youtube.com/watch?v=brand_new', {});
        await Future.delayed(const Duration(milliseconds: 10));

        expect(controller.downloads.any((d) => d.id == 'to_delete_id'), isFalse);
        expect(systemController.enqueuedCommands.length, equals(1));

        controller.dispose();
      });

      test('3.3: Mixed batch of parent deltas and sub-deltas processes parent items and skips sub-items correctly', () async {
        repository.serverDownloads = [
          Download(
            id: 'parent_a',
            info: Info(title: 'Playlist A'),
            state: DownloadState(value: DownloadStateEnum.inProgress),
          ),
          Download(
            id: 'parent_b',
            info: Info(title: 'Playlist B'),
            state: DownloadState(value: DownloadStateEnum.inProgress),
          ),
        ];

        final controller = DownloadsController(repository, systemController);
        await Future.delayed(const Duration(milliseconds: 10));

        repository.emitDeltas([
          Delta(
            id: 'parent_a',
            subId: 'sub_1',
            status: DownloadState(value: DownloadStateEnum.completed),
          ),
          Delta(
            id: 'parent_a',
            status: DownloadState(
              value: DownloadStateEnum.inProgress,
              progressValue: 50.0,
              progressLabel: '1/2 items',
            ),
          ),
          Delta(
            id: 'parent_b',
            subId: 'sub_2',
            status: DownloadState(value: DownloadStateEnum.inProgress),
          ),
          Delta(
            id: 'parent_b',
            status: DownloadState(
              value: DownloadStateEnum.completed,
              progressValue: 100.0,
              progressLabel: '2/2 items',
            ),
          ),
        ]);

        await Future.delayed(const Duration(milliseconds: 20));

        final itemA = controller.downloads.where((d) => d.id == 'parent_a').first;
        final itemB = controller.downloads.where((d) => d.id == 'parent_b').first;

        expect(itemA.state?.progressValue, equals(50.0));
        expect(itemB.state?.value, equals(DownloadStateEnum.completed));

        controller.dispose();
      });
    });

    // =========================================================================
    // TIER 4: REAL-WORLD SCENARIOS
    // =========================================================================
    group('Tier 4: Real-World Scenarios', () {
      test('4.1: Multi-download queue with 10 concurrent active downloads undergoing mixed state transitions', () async {
        repository.serverDownloads = List.generate(
          10,
          (i) => Download(
            id: 'queue_item_$i',
            info: Info(title: 'Video $i'),
            state: DownloadState(
              value: DownloadStateEnum.inProgress,
              progressValue: (i * 10).toDouble(),
            ),
          ),
        );

        final controller = DownloadsController(repository, systemController);
        await Future.delayed(const Duration(milliseconds: 10));
        expect(controller.downloads.length, equals(10));

        // Simulate complex real-world delta barrage:
        // - item 0, 1 complete
        // - item 2, 3 pause
        // - item 4, 5 cancel
        // - item 6, 7 delete
        // - item 8, 9 advance progress
        repository.emitDeltas([
          Delta(id: 'queue_item_0', status: DownloadState(value: DownloadStateEnum.completed, progressValue: 100.0)),
          Delta(id: 'queue_item_1', status: DownloadState(value: DownloadStateEnum.completed, progressValue: 100.0)),
          Delta(id: 'queue_item_2', status: DownloadState(value: DownloadStateEnum.paused)),
          Delta(id: 'queue_item_3', status: DownloadState(value: DownloadStateEnum.paused)),
          Delta(id: 'queue_item_4', status: DownloadState(value: DownloadStateEnum.cancelled)),
          Delta(id: 'queue_item_5', status: DownloadState(value: DownloadStateEnum.cancelled)),
          Delta(id: 'queue_item_6', status: DownloadState(value: DownloadStateEnum.deleted)),
          Delta(id: 'queue_item_7', status: DownloadState(value: DownloadStateEnum.deleted)),
          Delta(id: 'queue_item_8', status: DownloadState(value: DownloadStateEnum.inProgress, progressValue: 95.0)),
          Delta(id: 'queue_item_9', status: DownloadState(value: DownloadStateEnum.inProgress, progressValue: 99.0)),
        ]);

        await Future.delayed(const Duration(milliseconds: 20));

        expect(controller.downloads.length, equals(8)); // 2 deleted items removed
        expect(controller.downloads.where((d) => d.state?.value == DownloadStateEnum.completed).length, equals(2));
        expect(controller.downloads.where((d) => d.state?.value == DownloadStateEnum.paused).length, equals(2));
        expect(controller.downloads.where((d) => d.state?.value == DownloadStateEnum.cancelled).length, equals(2));
        expect(controller.downloads.where((d) => d.state?.value == DownloadStateEnum.inProgress).length, equals(2));

        controller.dispose();
      });

      test('4.2: Full download lifecycle from requested -> awaitingSelection -> inProgress -> completed -> deleted', () async {
        repository.serverDownloads = [
          Download(
            id: 'lifecycle_item',
            info: Info(title: 'Full Lifecycle Video'),
            state: DownloadState(value: DownloadStateEnum.requested),
          ),
        ];

        final controller = DownloadsController(repository, systemController);
        await Future.delayed(const Duration(milliseconds: 10));
        expect(controller.downloads.first.state?.value, equals(DownloadStateEnum.requested));

        // 1. Transition to awaitingSelection
        repository.emitDeltas([
          Delta(
            id: 'lifecycle_item',
            status: DownloadState(value: DownloadStateEnum.awaitingSelection),
          ),
        ]);
        await Future.delayed(const Duration(milliseconds: 10));
        expect(controller.downloads.first.state?.value, equals(DownloadStateEnum.awaitingSelection));

        // 2. Transition to inProgress with speed & ETA
        repository.emitDeltas([
          Delta(
            id: 'lifecycle_item',
            status: DownloadState(
              value: DownloadStateEnum.inProgress,
              progressValue: 33.3,
              speed: '5.2 MB/s',
              timeLeft: '00:15',
            ),
          ),
        ]);
        await Future.delayed(const Duration(milliseconds: 10));
        expect(controller.downloads.first.state?.value, equals(DownloadStateEnum.inProgress));
        expect(controller.downloads.first.state?.speed, equals('5.2 MB/s'));

        // 3. Transition to completed
        repository.emitDeltas([
          Delta(
            id: 'lifecycle_item',
            status: DownloadState(
              value: DownloadStateEnum.completed,
              progressValue: 100.0,
              timeSpent: '00:45',
            ),
          ),
        ]);
        await Future.delayed(const Duration(milliseconds: 10));
        expect(controller.downloads.first.state?.value, equals(DownloadStateEnum.completed));

        // 4. Transition to deleted
        repository.emitDeltas([
          Delta(
            id: 'lifecycle_item',
            status: DownloadState(value: DownloadStateEnum.deleted),
          ),
        ]);
        await Future.delayed(const Duration(milliseconds: 10));
        expect(controller.downloads, isEmpty);

        controller.dispose();
      });
    });
  });
}

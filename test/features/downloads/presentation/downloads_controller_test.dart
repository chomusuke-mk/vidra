import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/core/network/vidra_http_client.dart';
import 'package:vidra/features/downloads/data/download_repository.dart';
import 'package:vidra/features/downloads/domain/download.dart';
import 'package:vidra/features/downloads/presentation/downloads_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';

class MockSystemController extends ChangeNotifier
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
  String? get backendToken => 'token_xyz';

  @override
  String? get serverLogsFilePath => null;

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

class MockDownloadRepository extends DownloadRepository {
  List<Download> serverDownloads;
  int getAllDownloadsCalls = 0;
  int currentActiveFetches = 0;
  int peakConcurrentFetches = 0;
  Duration fetchDelay = Duration.zero;
  bool shouldThrow = false;
  final StreamController<List<Delta>> deltaController =
      StreamController<List<Delta>>.broadcast();

  MockDownloadRepository({this.serverDownloads = const []})
      : super(VidraHttpClient(baseUrl: 'http://127.0.0.1:5000', defaultHeaders: {}));

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

    if (shouldThrow) {
      throw Exception('Repository simulated error');
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
  Stream<List<Delta>> watchGlobalProgress() => deltaController.stream;

  @override
  Future<void> deleteDownload(String id) async {}
  @override
  Future<void> cancelDownload(String id) async {}
  @override
  Future<void> pauseDownload(String id) async {}
  @override
  Future<void> resumeDownload(String id) async {}
  @override
  Future<void> retryDownload(String id) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSystemController systemController;
  late MockDownloadRepository repository;

  setUp(() {
    systemController = MockSystemController();
    repository = MockDownloadRepository(
      serverDownloads: [
        Download(
          id: 'test_1',
          info: Info(title: 'Download 1', type: DownloadType.video),
          state: DownloadState(value: DownloadStateEnum.inProgress, progressValue: 50.0),
        ),
      ],
    );
  });

  group('DownloadsController Presentation Unit Tests', () {
    test('Initial cold start sets isLoading false after data is loaded', () async {
      final controller = DownloadsController(repository, systemController);
      await pumpEventQueue();

      expect(controller.isLoading, isFalse);
      expect(controller.downloads.length, equals(1));
      expect(controller.downloads.first.id, equals('test_1'));
      controller.dispose();
    });

    test('Single-flight deduplication coalesces concurrent syncDownloads calls', () async {
      repository.fetchDelay = const Duration(milliseconds: 30);
      final controller = DownloadsController(repository, systemController);
      await pumpEventQueue();

      repository.getAllDownloadsCalls = 0;
      repository.peakConcurrentFetches = 0;

      final futures = List.generate(20, (_) => controller.syncDownloads(isInitialLoad: false));
      await Future.wait(futures);

      expect(repository.peakConcurrentFetches, lessThanOrEqualTo(1));
      expect(repository.getAllDownloadsCalls, lessThanOrEqualTo(2));
      controller.dispose();
    });

    test('Tombstoned IDs are filtered out from delta processing', () async {
      final controller = DownloadsController(repository, systemController);
      await pumpEventQueue();

      controller.tombstoneId('test_1');
      expect(controller.downloads, isEmpty);
      expect(controller.isTombstoned('test_1'), isTrue);

      repository.getAllDownloadsCalls = 0;

      repository.deltaController.add([
        Delta(id: 'test_1', status: DownloadState(value: DownloadStateEnum.completed)),
      ]);
      await pumpEventQueue();

      expect(repository.getAllDownloadsCalls, equals(0));
      controller.dispose();
    });

    test('Delta with unknown ID triggers background sync without truncating batch', () async {
      repository.fetchDelay = const Duration(milliseconds: 50);
      final controller = DownloadsController(repository, systemController);
      await Future.delayed(const Duration(milliseconds: 60));

      repository.deltaController.add([
        Delta(id: 'unknown_x', status: DownloadState(value: DownloadStateEnum.inProgress)),
        Delta(id: 'test_1', status: DownloadState(value: DownloadStateEnum.completed)),
      ]);
      await pumpEventQueue();

      final item = controller.downloads.firstWhere((d) => d.id == 'test_1');
      expect(item.state?.value, equals(DownloadStateEnum.completed));
      controller.dispose();
    });

    test('Ghost ID is promoted to ignored missing set and suppresses further fetches', () async {
      final controller = DownloadsController(repository, systemController);
      await pumpEventQueue();

      repository.getAllDownloadsCalls = 0;

      repository.deltaController.add([
        Delta(id: 'ghost_z', status: DownloadState(value: DownloadStateEnum.inProgress)),
      ]);
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 30));

      expect(repository.getAllDownloadsCalls, equals(1));
      expect(controller.isIgnoredMissing('ghost_z'), isTrue);

      // Trailing deltas do not re-fetch
      repository.deltaController.add([
        Delta(id: 'ghost_z', status: DownloadState(value: DownloadStateEnum.inProgress)),
      ]);
      await pumpEventQueue();

      expect(repository.getAllDownloadsCalls, equals(1));
      controller.dispose();
    });

    test('Manual selection modal request and consumption', () {
      final controller = DownloadsController(repository, systemController);

      expect(controller.manualModalRequestId, isNull);

      controller.requestSelectionModal('req_123');
      expect(controller.manualModalRequestId, equals('req_123'));

      controller.consumeManualModalRequest();
      expect(controller.manualModalRequestId, isNull);

      controller.dispose();
    });

    test('Disposal safety guards listeners and subscriptions', () async {
      repository.fetchDelay = const Duration(milliseconds: 40);
      final controller = DownloadsController(repository, systemController);

      final future = controller.syncDownloads(isInitialLoad: false);
      controller.dispose();

      expect(() async => await future, returnsNormally);
    });
  });
}

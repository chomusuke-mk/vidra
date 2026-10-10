import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/core/utils/platform_utils.dart';
import 'package:vidra/features/downloads/domain/download.dart';

void main() {
  group('PlatformUtils.scanFiles MediaStore indexing tests', () {
    test('does nothing if platform is not Android', () async {
      bool scannerCalled = false;
      bool fetchCalled = false;

      final download = Download(
        id: 'dl_video_1',
        info: Info(
          file: '/storage/emulated/0/Download/video.mp4',
          type: DownloadType.video,
        ),
        state: DownloadState(value: DownloadStateEnum.completed),
      );

      await PlatformUtils.scanFiles(
        download,
        isAndroid: false,
        scanMediaFileFn: (path) async {
          scannerCalled = true;
          return 'uri';
        },
        fetchDownloadDetails: (id) async {
          fetchCalled = true;
          return {};
        },
      );

      expect(scannerCalled, isFalse);
      expect(fetchCalled, isFalse);
    });

    test('scans individual video file when type is video and file exists', () async {
      final scannedPaths = <String>[];
      bool fetchCalled = false;

      final download = Download(
        id: 'dl_video_1',
        info: Info(
          file: '/storage/emulated/0/Download/my_video.mp4',
          type: DownloadType.video,
        ),
        state: DownloadState(value: DownloadStateEnum.completed),
      );

      await PlatformUtils.scanFiles(
        download,
        isAndroid: true,
        scanMediaFileFn: (path) async {
          scannedPaths.add(path);
          return 'content://media/external/video/media/1';
        },
        fetchDownloadDetails: (id) async {
          fetchCalled = true;
          return {};
        },
      );

      expect(fetchCalled, isFalse);
      expect(scannedPaths, equals(['/storage/emulated/0/Download/my_video.mp4']));
    });

    test('fetches full details from backend if video file is empty', () async {
      final scannedPaths = <String>[];
      bool fetchCalled = false;

      final download = Download(
        id: 'dl_video_empty',
        info: Info(
          file: '',
          type: DownloadType.video,
        ),
        state: DownloadState(value: DownloadStateEnum.completed),
      );

      await PlatformUtils.scanFiles(
        download,
        isAndroid: true,
        scanMediaFileFn: (path) async {
          scannedPaths.add(path);
          return 'content://media/external/video/media/2';
        },
        fetchDownloadDetails: (id) async {
          fetchCalled = true;
          return {
            'id': id,
            'info': {
              'file': '/storage/emulated/0/Download/resolved_video.mp4',
              'type': 'video',
            },
          };
        },
      );

      expect(fetchCalled, isTrue);
      expect(
        scannedPaths,
        equals(['/storage/emulated/0/Download/resolved_video.mp4']),
      );
    });

    test('when type is list, fetches full details and scans only completed sub-downloads with files', () async {
      final scannedPaths = <String>[];
      final requestedIds = <String>[];

      final download = Download(
        id: 'dl_playlist_100',
        info: Info(
          type: DownloadType.list,
          file: '/storage/emulated/0/Download',
        ),
        state: DownloadState(value: DownloadStateEnum.completed),
      );

      await PlatformUtils.scanFiles(
        download,
        isAndroid: true,
        scanMediaFileFn: (path) async {
          scannedPaths.add(path);
          return 'content://media/external/video/media/$path';
        },
        fetchDownloadDetails: (id) async {
          requestedIds.add(id);
          return {
            'id': id,
            'info': {'type': 'list'},
            'sub_descargas': [
              {
                'sub_id': 'sub_1',
                'state': {'value': 'completed'},
                'info': {'file': '/storage/emulated/0/Download/track_1.mp3'},
              },
              {
                'sub_id': 'sub_2',
                'state': {'value': 'failed'},
                'info': {'file': '/storage/emulated/0/Download/track_2.mp3'},
              },
              {
                'sub_id': 'sub_3',
                'state': {'value': 'completed'},
                'info': {'file': ''}, // file is empty
              },
              {
                'sub_id': 'sub_4',
                'state': {'value': 'completed'},
                'info': {'file': '/storage/emulated/0/Download/track_4.mp3'},
              },
              {
                'sub_id': 'sub_5',
                'state': {'value': 'in_progress'},
                'info': {'file': '/storage/emulated/0/Download/track_5.mp3'},
              },
            ],
          };
        },
      );

      expect(requestedIds, equals(['dl_playlist_100']));
      // Only track_1 and track_4 should be scanned
      expect(
        scannedPaths,
        equals([
          '/storage/emulated/0/Download/track_1.mp3',
          '/storage/emulated/0/Download/track_4.mp3',
        ]),
      );
    });

    test('handles backend errors gracefully when fetching playlist details', () async {
      final scannedPaths = <String>[];

      final download = Download(
        id: 'dl_playlist_error',
        info: Info(type: DownloadType.list),
        state: DownloadState(value: DownloadStateEnum.completedWithErrors),
      );

      await PlatformUtils.scanFiles(
        download,
        isAndroid: true,
        scanMediaFileFn: (path) async {
          scannedPaths.add(path);
          return 'uri';
        },
        fetchDownloadDetails: (id) async {
          throw Exception('Backend connection timeout');
        },
      );

      expect(scannedPaths, isEmpty);
    });
  });

  group('Backend Isolate MediaStore scan trigger conditions', () {
    bool shouldTriggerScan(DownloadStateEnum newState, DownloadType? type) {
      return newState == DownloadStateEnum.completed ||
          newState == DownloadStateEnum.completedWithErrors ||
          (newState == DownloadStateEnum.paused && type == DownloadType.list);
    }

    test('triggers for completed video and list', () {
      expect(shouldTriggerScan(DownloadStateEnum.completed, DownloadType.video), isTrue);
      expect(shouldTriggerScan(DownloadStateEnum.completed, DownloadType.list), isTrue);
    });

    test('triggers for completedWithErrors video and list', () {
      expect(shouldTriggerScan(DownloadStateEnum.completedWithErrors, DownloadType.video), isTrue);
      expect(shouldTriggerScan(DownloadStateEnum.completedWithErrors, DownloadType.list), isTrue);
    });

    test('triggers for paused ONLY when type is list', () {
      expect(shouldTriggerScan(DownloadStateEnum.paused, DownloadType.list), isTrue);
      expect(shouldTriggerScan(DownloadStateEnum.paused, DownloadType.video), isFalse);
      expect(shouldTriggerScan(DownloadStateEnum.paused, null), isFalse);
    });

    test('does not trigger for other states', () {
      expect(shouldTriggerScan(DownloadStateEnum.inProgress, DownloadType.video), isFalse);
      expect(shouldTriggerScan(DownloadStateEnum.pending, DownloadType.video), isFalse);
      expect(shouldTriggerScan(DownloadStateEnum.failed, DownloadType.video), isFalse);
      expect(shouldTriggerScan(DownloadStateEnum.cancelled, DownloadType.video), isFalse);
      expect(shouldTriggerScan(DownloadStateEnum.deleted, DownloadType.video), isFalse);
    });
  });
}

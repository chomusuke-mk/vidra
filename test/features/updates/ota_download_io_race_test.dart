import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Mock download service simulating both defective (unflushed/premature return/ignored error)
/// and robust (flushed, closed, verified) file download operations.
class MockOtaDownloadService {
  /// Unfixed implementation simulating delayed file creation / unawaited background write
  /// and premature return before file exists or is flushed on disk.
  static Future<bool> downloadUnfixed({
    required File targetFile,
    required List<int> payload,
    bool simulateFailedDownload = false,
    Duration chunkDelay = const Duration(milliseconds: 30),
  }) async {
    if (simulateFailedDownload) {
      // Simulates Dio deleteOnError: file is deleted or never written, returns false
      if (targetFile.existsSync()) targetFile.deleteSync();
      return false;
    }

    // Simulates delayed async write where file creation and sink flush happen in background
    Future(() async {
      await Future.delayed(chunkDelay);
      if (!targetFile.parent.existsSync()) {
        targetFile.parent.createSync(recursive: true);
      }
      final sink = targetFile.openWrite();
      sink.add(payload);
      await sink.flush();
      await sink.close();
    });

    // Premature resolution defect: returns true before file is created/flushed on disk
    return true;
  }

  /// Fixed implementation with guaranteed parent directory creation, flush, close, and disk verification
  static Future<bool> downloadFixed({
    required File targetFile,
    required Stream<List<int>> payloadStream,
  }) async {
    if (!targetFile.parent.existsSync()) {
      targetFile.parent.createSync(recursive: true);
    }

    final sink = targetFile.openWrite();
    try {
      await for (final chunk in payloadStream) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();

      if (!targetFile.existsSync() || targetFile.lengthSync() == 0) {
        return false;
      }
      return true;
    } catch (e) {
      await sink.close();
      return false;
    }
  }
}

void main() {
  group('OTA Update I/O Latency & PathNotFoundException Reproduction', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('vidra_ota_repro_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    group('Scenario 1: Reproduction of PathNotFoundException on Unfixed Code', () {
      test('immediate read on unfixed download triggers PathNotFoundException', () async {
        final sumsFile = File(p.join(tempDir.path, 'sums'));
        final sumsPayload = utf8.encode('abcdef1234567890 *yt-dlp\n');

        final downloadResult = await MockOtaDownloadService.downloadUnfixed(
          targetFile: sumsFile,
          payload: sumsPayload,
          chunkDelay: const Duration(milliseconds: 50),
        );

        expect(downloadResult, isTrue);

        // Immediate synchronous and asynchronous reads MUST throw PathNotFoundException
        // because the file has not yet been written or committed to disk
        expect(
          () => sumsFile.readAsStringSync(),
          throwsA(isA<PathNotFoundException>()),
        );

        await expectLater(
          sumsFile.readAsString(),
          throwsA(isA<PathNotFoundException>()),
        );
      });

      test('PgpVerifier binary openRead stream throws PathNotFoundException when binary download is not flushed', () async {
        final binaryFile = File(p.join(tempDir.path, 'yt-dlp'));
        final binaryPayload = utf8.encode('simulated binary executable bytes');

        final downloadResult = await MockOtaDownloadService.downloadUnfixed(
          targetFile: binaryFile,
          payload: binaryPayload,
          chunkDelay: const Duration(milliseconds: 50),
        );

        expect(downloadResult, isTrue);

        // Attempting to calculate SHA-512 over unflushed binary file stream fails with PathNotFoundException
        await expectLater(
          () async {
            final stream = binaryFile.openRead();
            await sha512.bind(stream).first;
          }(),
          throwsA(isA<PathNotFoundException>()),
        );
      });

      test('ignoring failed auxiliary download return value causes PathNotFoundException in verifier', () async {
        final sigFile = File(p.join(tempDir.path, 'sig'));
        // Download failed (e.g. 404 or network drop), returning false and deleting file
        final downloadOk = await MockOtaDownloadService.downloadUnfixed(
          targetFile: sigFile,
          payload: [],
          simulateFailedDownload: true,
        );

        // In unfixed UpdateController, downloadOk was ignored and sigFile.readAsBytes() was called directly
        expect(downloadOk, isFalse);
        expect(sigFile.existsSync(), isFalse);

        await expectLater(
          sigFile.readAsBytes(),
          throwsA(isA<PathNotFoundException>()),
        );
      });
    });

    group('Scenario 2: Verification of Fixed Code with Guaranteed Flush & Disk Sync', () {
      test('fixed download completes flush and allows immediate synchronous and asynchronous reads', () async {
        final sumsFile = File(p.join(tempDir.path, 'sums'));
        const rawSums = 'abcdef1234567890 *yt-dlp\n';
        final payload = utf8.encode(rawSums);

        Stream<List<int>> createChunkedStream(List<int> bytes) async* {
          for (int i = 0; i < bytes.length; i += 4) {
            await Future.delayed(const Duration(milliseconds: 5));
            yield bytes.sublist(i, (i + 4 < bytes.length) ? i + 4 : bytes.length);
          }
        }

        final downloadResult = await MockOtaDownloadService.downloadFixed(
          targetFile: sumsFile,
          payloadStream: createChunkedStream(payload),
        );

        expect(downloadResult, isTrue);
        expect(sumsFile.existsSync(), isTrue);
        expect(sumsFile.readAsStringSync(), equals(rawSums));

        final content = await sumsFile.readAsString();
        expect(content, equals(rawSums));
      });

      test('fixed binary download completes and allows sha512 streaming calculation', () async {
        final binaryFile = File(p.join(tempDir.path, 'yt-dlp'));
        final binaryPayload = utf8.encode('simulated binary executable payload content');

        Stream<List<int>> createChunkedStream(List<int> bytes) async* {
          for (int i = 0; i < bytes.length; i += 8) {
            await Future.delayed(const Duration(milliseconds: 5));
            yield bytes.sublist(i, (i + 8 < bytes.length) ? i + 8 : bytes.length);
          }
        }

        final downloadResult = await MockOtaDownloadService.downloadFixed(
          targetFile: binaryFile,
          payloadStream: createChunkedStream(binaryPayload),
        );

        expect(downloadResult, isTrue);
        expect(binaryFile.existsSync(), isTrue);

        final stream = binaryFile.openRead();
        final digest = await sha512.bind(stream).first;
        final expectedDigest = sha512.convert(binaryPayload);

        expect(digest.toString(), equals(expectedDigest.toString()));
      });
    });

    group('Scenario 3: Multi-File Download Sequence (Binary, Sums, Sig) Under High Latency', () {
      test('sequential download of binary, sums, and sig files all flush and synchronize cleanly', () async {
        final binaryFile = File(p.join(tempDir.path, 'yt-dlp.tar.gz'));
        final sumsFile = File(p.join(tempDir.path, 'sums'));
        final sigFile = File(p.join(tempDir.path, 'sig'));

        final binaryBytes = utf8.encode('sample-tarball-bytes');
        final expectedHash = sha512.convert(binaryBytes).toString();
        final sumsBytes = utf8.encode('$expectedHash  yt-dlp.tar.gz\n');
        final sigBytes = utf8.encode('-----BEGIN PGP SIGNATURE-----\nfake_sig\n-----END PGP SIGNATURE-----');

        Stream<List<int>> delayedStream(List<int> bytes) async* {
          yield bytes;
          await Future.delayed(const Duration(milliseconds: 10));
        }

        final okBinary = await MockOtaDownloadService.downloadFixed(
          targetFile: binaryFile,
          payloadStream: delayedStream(binaryBytes),
        );
        final okSums = await MockOtaDownloadService.downloadFixed(
          targetFile: sumsFile,
          payloadStream: delayedStream(sumsBytes),
        );
        final okSig = await MockOtaDownloadService.downloadFixed(
          targetFile: sigFile,
          payloadStream: delayedStream(sigBytes),
        );

        expect(okBinary && okSums && okSig, isTrue);

        // Verify all 3 files exist and can be read concurrently
        expect(binaryFile.existsSync(), isTrue);
        expect(sumsFile.existsSync(), isTrue);
        expect(sigFile.existsSync(), isTrue);

        final sumsContent = await sumsFile.readAsString();
        final sigReadBytes = await sigFile.readAsBytes();
        final binaryHash = (await sha512.bind(binaryFile.openRead()).first).toString();

        expect(sumsContent.contains(expectedHash), isTrue);
        expect(sigReadBytes, equals(sigBytes));
        expect(binaryHash, equals(expectedHash));
      });
    });
  });
}

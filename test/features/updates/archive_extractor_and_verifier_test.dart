import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidra/core/security/pgp_verifier.dart';
import 'package:vidra/core/utils/archive_extractor.dart';

void main() {
  group('ArchiveExtractor Staging & Safety Tests', () {
    late Directory tempDir;
    late Directory destDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('archive_extractor_test_');
      destDir = Directory(p.join(tempDir.path, 'core_modules', 'yt_dlp'));
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('extractPythonModule returns false when archive file does not exist', () async {
      final nonExistentFile = File(p.join(tempDir.path, 'does_not_exist.tar.gz'));

      final result = await ArchiveExtractor.extractPythonModule(
        archiveFile: nonExistentFile,
        destinationDir: destDir,
        targetSubfolderName: 'yt_dlp',
      );

      expect(result, isFalse);
      expect(destDir.existsSync(), isFalse);
    });

    test('extractPythonModule returns false and preserves existing destination when archive is empty', () async {
      // Pre-populate destination directory
      destDir.createSync(recursive: true);
      final existingFile = File(p.join(destDir.path, '__init__.py'));
      existingFile.writeAsStringSync('# existing valid module');

      final emptyArchive = File(p.join(tempDir.path, 'empty.tar.gz'));
      emptyArchive.writeAsBytesSync([]);

      final result = await ArchiveExtractor.extractPythonModule(
        archiveFile: emptyArchive,
        destinationDir: destDir,
        targetSubfolderName: 'yt_dlp',
      );

      expect(result, isFalse);
      // Ensure existing module was NOT deleted
      expect(destDir.existsSync(), isTrue);
      expect(existingFile.existsSync(), isTrue);
      expect(existingFile.readAsStringSync(), equals('# existing valid module'));
    });

    test('extractPythonModule correctly extracts target subfolder via staging without leaving staging artifacts', () async {
      // Create a dummy zip archive with files in yt_dlp/
      final archive = Archive();
      archive.addFile(
        ArchiveFile('yt_dlp/__init__.py', 14, utf8.encode('__version__=1')),
      );
      archive.addFile(
        ArchiveFile('yt_dlp/main.py', 18, utf8.encode('def run(): pass\n')),
      );
      archive.addFile(
        ArchiveFile('other_folder/dummy.txt', 5, utf8.encode('dummy')),
      );

      final zipData = ZipEncoder().encode(archive);
      final zipFile = File(p.join(tempDir.path, 'yt_dlp.zip'));
      zipFile.writeAsBytesSync(zipData);

      final result = await ArchiveExtractor.extractPythonModule(
        archiveFile: zipFile,
        destinationDir: destDir,
        targetSubfolderName: 'yt_dlp',
      );

      expect(result, isTrue);
      expect(destDir.existsSync(), isTrue);

      final initFile = File(p.join(destDir.path, '__init__.py'));
      final mainFile = File(p.join(destDir.path, 'main.py'));
      final unwantedFile = File(p.join(destDir.path, 'other_folder', 'dummy.txt'));

      expect(initFile.existsSync(), isTrue);
      expect(initFile.readAsStringSync(), equals('__version__=1'));
      expect(mainFile.existsSync(), isTrue);
      expect(unwantedFile.existsSync(), isFalse);

      // Verify no leftover staging directories in parent
      final parentDir = destDir.parent;
      final stagingDirs = parentDir
          .listSync()
          .where((e) => e.path.contains('_staging_'))
          .toList();
      expect(stagingDirs, isEmpty);
    });
  });

  group('PgpVerifier Defensive Checks & Token Matching Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pgp_verifier_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('verifyBinary returns false gracefully if any required file is missing or 0 bytes', () async {
      final binaryFile = File(p.join(tempDir.path, 'yt-dlp'));
      final sumsFile = File(p.join(tempDir.path, 'sums'));
      final sigFile = File(p.join(tempDir.path, 'sig'));

      // 1. Files do not exist
      final resultMissing = await PgpVerifier.verifyBinary(
        binaryFile: binaryFile,
        sumsFile: sumsFile,
        sigFile: sigFile,
        publicKey: 'dummy_key',
        expectedBinaryName: 'yt-dlp',
      );
      expect(resultMissing, isFalse);

      // 2. Binary file is 0 bytes
      binaryFile.writeAsBytesSync([]);
      sumsFile.writeAsStringSync('dummy sums');
      sigFile.writeAsStringSync('dummy sig');

      final resultEmptyBinary = await PgpVerifier.verifyBinary(
        binaryFile: binaryFile,
        sumsFile: sumsFile,
        sigFile: sigFile,
        publicKey: 'dummy_key',
        expectedBinaryName: 'yt-dlp',
      );
      expect(resultEmptyBinary, isFalse);
    });
  });
}

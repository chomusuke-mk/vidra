import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/features/settings/data/settings_repository.dart';
import 'package:vidra/features/settings/domain/download_options.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late SettingsRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repository = SettingsRepository(prefs);
  });

  group('SettingsController Platform Fallbacks Verification', () {
    test('SettingsController initializes cleanly without throwing when path_provider is unmocked', () async {
      final controller = SettingsController(repository);

      // Verify sync defaults on construction
      expect(controller.isInitialized, isFalse);
      expect(controller.appLanguage, equals('defaultOption'));
      expect(controller.downloadOptions, isNotNull);

      // Await async _loadSettings to complete
      await controller.initialized;

      expect(controller.isInitialized, isTrue);

      final opts = controller.downloadOptions;
      // REGLA 1: PathsKey.home should have resolved to Downloads directory (via getDownloadsDirectory or fallback)
      if (Platform.environment['HOME'] != null || Platform.environment['USERPROFILE'] != null) {
        expect(opts.paths[PathsKey.home], isNotNull);
        expect(opts.paths[PathsKey.home], contains('Downloads'));
      }

      // REGLA 3: cookiesFromWebview should resolve to vidra_cookies
      expect(opts.cookiesFromWebview, isNotNull);
      expect(opts.cookiesFromWebview, contains('vidra_cookies'));
      expect(Directory(opts.cookiesFromWebview!).existsSync(), isTrue);
    });

    test('SettingsController preserves custom user-configured home path without overriding', () async {
      await repository.saveDownloadOptions(
        DownloadOptions(
          paths: {PathsKey.home: '/custom/user/downloads'},
        ),
      );

      final controller = SettingsController(repository);
      expect(controller.isInitialized, isFalse);

      await controller.initialized;
      expect(controller.isInitialized, isTrue);
      expect(controller.downloadOptions.paths[PathsKey.home], equals('/custom/user/downloads'));
    });
  });
}

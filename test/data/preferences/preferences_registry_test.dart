import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/data/preferences/preferences_registry.dart';

void main() {
  late Preferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    preferences = Preferences();
    final storage = await SharedPreferences.getInstance();
    await preferences.initializeAll(storage);
  });

  test('toBackendOptions excludes UI-only preference keys', () {
    final result = preferences.toBackendOptions(
      excludeKeys: const {'theme_dark', 'language', 'font_size'},
    );

    expect(result.containsKey('theme_dark'), isFalse);
    expect(result.containsKey('language'), isFalse);
    expect(result.containsKey('font_size'), isFalse);

    expect(result.containsKey('extract_audio'), isTrue);
    expect(result.containsKey('audio_format'), isTrue);
    expect(result['extract_audio'], isFalse);
  });

  test('format lists serialize into slash-separated strings', () async {
    await preferences.format.setValue(<String>['bestvideo+bestaudio', 'best']);

    final result = preferences.toBackendOptions();

    expect(result['format'], equals('bestvideo+bestaudio/best'));
  });

  test('output template lists expand to yt-dlp placeholders', () async {
    await preferences.output.setValue(<String>[
      'title',
      ' - ',
      'artist',
      '[',
      'id',
      ']',
      '.',
      'ext',
    ]);

    final result = preferences.toBackendOptions();

    expect(result['output'], equals('%(title)s - %(artist)s[%(id)s].%(ext)s'));
  });

  test('download_archive false or empty values are stripped', () async {
    final result = preferences.toBackendOptions();
    expect(result.containsKey('download_archive'), isFalse);

    await preferences.downloadArchive.setValue('  archive.txt  ');
    final updated = preferences.toBackendOptions();
    expect(updated['download_archive'], equals('archive.txt'));

    await preferences.downloadArchive.setValue('   ');
    final reset = preferences.toBackendOptions();
    expect(reset.containsKey('download_archive'), isFalse);
  });
}

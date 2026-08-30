import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/features/settings/domain/download_options.dart';

void main() {
  group('Adversarial Stress Tests: DownloadOptions Serialization & Edge Cases', () {
    test('1. Infinite vs finite integers union fields serialization and deserialization', () {
      // Test matrix for all infinite/integer union fields:
      // socketTimeout, skipPlaylistAfterErrors, retries, fileAccessRetries, fragmentRetries, extractorRetries

      // Case A: All infinite
      final allInfinite = DownloadOptions(
        infiniteSocketTimeout: true,
        infiniteSkipPlaylistAfterErrors: true,
        infiniteRetries: true,
        infiniteFileAccessRetries: true,
        infiniteFragmentRetries: true,
        infiniteExtractorRetries: true,
      );

      final jsonInfinite = allInfinite.toJson();
      expect(jsonInfinite['socket_timeout'], equals('infinite'));
      expect(jsonInfinite['skip_playlist_after_errors'], equals('infinite'));
      expect(jsonInfinite['retries'], equals('infinite'));
      expect(jsonInfinite['file_access_retries'], equals('infinite'));
      expect(jsonInfinite['fragment_retries'], equals('infinite'));
      expect(jsonInfinite['extractor_retries'], equals('infinite'));

      final restoredInfinite = DownloadOptions.fromJson(jsonInfinite);
      expect(restoredInfinite.infiniteSocketTimeout, isTrue);
      expect(restoredInfinite.infiniteSkipPlaylistAfterErrors, isTrue);
      expect(restoredInfinite.infiniteRetries, isTrue);
      expect(restoredInfinite.infiniteFileAccessRetries, isTrue);
      expect(restoredInfinite.infiniteFragmentRetries, isTrue);
      expect(restoredInfinite.infiniteExtractorRetries, isTrue);

      // Case B: All finite numbers
      final allFinite = DownloadOptions(
        socketTimeout: 30,
        infiniteSocketTimeout: false,
        skipPlaylistAfterErrors: 5,
        infiniteSkipPlaylistAfterErrors: false,
        retries: 25,
        infiniteRetries: false,
        fileAccessRetries: 7,
        infiniteFileAccessRetries: false,
        fragmentRetries: 50,
        infiniteFragmentRetries: false,
        extractorRetries: 12,
        infiniteExtractorRetries: false,
      );

      final jsonFinite = allFinite.toJson();
      expect(jsonFinite['socket_timeout'], equals(30));
      expect(jsonFinite['skip_playlist_after_errors'], equals(5));
      expect(jsonFinite['retries'], equals(25));
      expect(jsonFinite['file_access_retries'], equals(7));
      expect(jsonFinite['fragment_retries'], equals(50));
      expect(jsonFinite['extractor_retries'], equals(12));

      final restoredFinite = DownloadOptions.fromJson(jsonFinite);
      expect(restoredFinite.socketTimeout, equals(30));
      expect(restoredFinite.infiniteSocketTimeout, isFalse);
      expect(restoredFinite.skipPlaylistAfterErrors, equals(5));
      expect(restoredFinite.infiniteSkipPlaylistAfterErrors, isFalse);
      expect(restoredFinite.retries, equals(25));
      expect(restoredFinite.infiniteRetries, isFalse);
      expect(restoredFinite.fileAccessRetries, equals(7));
      expect(restoredFinite.infiniteFileAccessRetries, isFalse);
      expect(restoredFinite.fragmentRetries, equals(50));
      expect(restoredFinite.infiniteFragmentRetries, isFalse);
      expect(restoredFinite.extractorRetries, equals(12));
      expect(restoredFinite.infiniteExtractorRetries, isFalse);

      // Case C: Extreme and boundary integers (0, negative, large values)
      final extreme = DownloadOptions(
        socketTimeout: 0,
        infiniteSocketTimeout: false,
        skipPlaylistAfterErrors: 0,
        infiniteSkipPlaylistAfterErrors: false,
        retries: 999999,
        infiniteRetries: false,
        fileAccessRetries: 0,
        infiniteFileAccessRetries: false,
        fragmentRetries: 1000000,
        infiniteFragmentRetries: false,
        extractorRetries: 0,
        infiniteExtractorRetries: false,
      );

      final jsonExtreme = extreme.toJson();
      expect(jsonExtreme['socket_timeout'], equals(0));
      expect(jsonExtreme['skip_playlist_after_errors'], equals(0));
      expect(jsonExtreme['retries'], equals(999999));
      expect(jsonExtreme['file_access_retries'], equals(0));
      expect(jsonExtreme['fragment_retries'], equals(1000000));
      expect(jsonExtreme['extractor_retries'], equals(0));

      final restoredExtreme = DownloadOptions.fromJson(jsonExtreme);
      expect(restoredExtreme.socketTimeout, equals(0));
      expect(restoredExtreme.infiniteSocketTimeout, isFalse);
      expect(restoredExtreme.retries, equals(999999));
      expect(restoredExtreme.infiniteRetries, isFalse);
    });

    test('2. Disabled booleans vs custom values / string paths (cookies, browser, webview, remux, archive, wait, limitRate)', () {
      // Case A: All disabled
      final allDisabled = DownloadOptions(
        disableCookies: true,
        cookies: '/some/path/cookies.txt', // Even if string exists, disableCookies should take precedence in toJson
        disableCookiesFromBrowser: true,
        cookiesFromBrowser: Browser.chrome,
        disableCookiesFromWebview: true,
        cookiesFromWebview: '/some/path/webview_cookies.txt',
        disableRemuxVideo: true,
        remuxVideo: RemuxVideoFormat.mp4,
        disableDownloadArchive: true,
        downloadArchive: '/some/archive.txt',
        disableWaitForVideo: true,
        waitForVideo: 60,
        disableLimitRate: true,
        limitRate: '5M',
      );

      final jsonDisabled = allDisabled.toJson();
      expect(jsonDisabled['cookies'], isFalse);
      expect(jsonDisabled['cookies_from_browser'], isFalse);
      expect(jsonDisabled['cookies_from_webview'], isFalse);
      expect(jsonDisabled['remux_video'], isFalse);
      expect(jsonDisabled['download_archive'], isFalse);
      expect(jsonDisabled['wait_for_video'], isFalse);
      expect(jsonDisabled['limit_rate'], isFalse);

      final restoredDisabled = DownloadOptions.fromJson(jsonDisabled);
      expect(restoredDisabled.disableCookies, isTrue);
      expect(restoredDisabled.cookies, isNull);
      expect(restoredDisabled.disableCookiesFromBrowser, isTrue);
      expect(restoredDisabled.cookiesFromBrowser, isNull);
      expect(restoredDisabled.disableCookiesFromWebview, isTrue);
      expect(restoredDisabled.cookiesFromWebview, isNull);
      expect(restoredDisabled.disableRemuxVideo, isTrue);
      expect(restoredDisabled.remuxVideo, isNull);
      expect(restoredDisabled.disableDownloadArchive, isTrue);
      expect(restoredDisabled.downloadArchive, isNull);
      expect(restoredDisabled.disableWaitForVideo, isTrue);
      expect(restoredDisabled.waitForVideo, isNull);
      expect(restoredDisabled.disableLimitRate, isTrue);
      expect(restoredDisabled.limitRate, isNull);

      // Case B: Custom enabled values
      final allCustom = DownloadOptions(
        disableCookies: false,
        cookies: '/custom/cookies.txt',
        disableCookiesFromBrowser: false,
        cookiesFromBrowser: Browser.brave,
        disableCookiesFromWebview: false,
        cookiesFromWebview: '/custom/webview_cookies.txt',
        disableRemuxVideo: false,
        remuxVideo: RemuxVideoFormat.mkv,
        disableDownloadArchive: false,
        downloadArchive: '/custom/archive.txt',
        disableWaitForVideo: false,
        waitForVideo: 120,
        disableLimitRate: false,
        limitRate: '2.5M',
      );

      final jsonCustom = allCustom.toJson();
      expect(jsonCustom['cookies'], equals('/custom/cookies.txt'));
      expect(jsonCustom['cookies_from_browser'], equals('brave'));
      expect(jsonCustom['cookies_from_webview'], equals('/custom/webview_cookies.txt'));
      expect(jsonCustom['remux_video'], equals('mkv'));
      expect(jsonCustom['download_archive'], equals('/custom/archive.txt'));
      expect(jsonCustom['wait_for_video'], equals(120));
      expect(jsonCustom['limit_rate'], equals('2.5M'));

      final restoredCustom = DownloadOptions.fromJson(jsonCustom);
      expect(restoredCustom.disableCookies, isFalse);
      expect(restoredCustom.cookies, equals('/custom/cookies.txt'));
      expect(restoredCustom.disableCookiesFromBrowser, isFalse);
      expect(restoredCustom.cookiesFromBrowser, equals(Browser.brave));
      expect(restoredCustom.disableCookiesFromWebview, isFalse);
      expect(restoredCustom.cookiesFromWebview, equals('/custom/webview_cookies.txt'));
      expect(restoredCustom.disableRemuxVideo, isFalse);
      expect(restoredCustom.remuxVideo, equals(RemuxVideoFormat.mkv));
      expect(restoredCustom.disableDownloadArchive, isFalse);
      expect(restoredCustom.downloadArchive, equals('/custom/archive.txt'));
      expect(restoredCustom.disableWaitForVideo, isFalse);
      expect(restoredCustom.waitForVideo, equals(120));
      expect(restoredCustom.disableLimitRate, isFalse);
      expect(restoredCustom.limitRate, equals('2.5M'));
    });

    test('3. Video & Audio Option Unions (default, best, custom resolution/language code)', () {
      // Resolution: defaultOption
      final resDefault = DownloadOptions(videoResolution: VideoOption.defaultOption);
      expect(resDefault.toJson()['video_resolution'], equals('default'));
      final resDefaultRestored = DownloadOptions.fromJson({'video_resolution': 'default'});
      expect(resDefaultRestored.videoResolution, equals(VideoOption.defaultOption));
      expect(resDefaultRestored.videoResolutionValue, isNull);

      // Resolution: bestvideo
      final resBest = DownloadOptions(videoResolution: VideoOption.bestvideo);
      expect(resBest.toJson()['video_resolution'], equals('bestvideo'));
      final resBestRestored = DownloadOptions.fromJson({'video_resolution': 'bestvideo'});
      expect(resBestRestored.videoResolution, equals(VideoOption.bestvideo));
      expect(resBestRestored.videoResolutionValue, isNull);

      // Resolution: custom value (e.g. 4320, 2160, 1440, 1080)
      final resCustom = DownloadOptions(
        videoResolution: VideoOption.resolution,
        videoResolutionValue: '2160',
      );
      expect(resCustom.toJson()['video_resolution'], equals('2160'));
      final resCustomRestored = DownloadOptions.fromJson({'video_resolution': '2160'});
      expect(resCustomRestored.videoResolution, equals(VideoOption.resolution));
      expect(resCustomRestored.videoResolutionValue, equals('2160'));

      // Audio: defaultOption
      final audioDefault = DownloadOptions(audioLanguage: AudioOption.defaultOption);
      expect(audioDefault.toJson()['audio_language'], equals('default'));
      final audioDefaultRestored = DownloadOptions.fromJson({'audio_language': 'default'});
      expect(audioDefaultRestored.audioLanguage, equals(AudioOption.defaultOption));
      expect(audioDefaultRestored.audioLanguageCode, isNull);

      // Audio: bestaudio
      final audioBest = DownloadOptions(audioLanguage: AudioOption.bestaudio);
      expect(audioBest.toJson()['audio_language'], equals('bestaudio'));
      final audioBestRestored = DownloadOptions.fromJson({'audio_language': 'bestaudio'});
      expect(audioBestRestored.audioLanguage, equals(AudioOption.bestaudio));
      expect(audioBestRestored.audioLanguageCode, isNull);

      // Audio: language code (e.g. 'ja', 'es', 'en')
      final audioCustom = DownloadOptions(
        audioLanguage: AudioOption.language,
        audioLanguageCode: 'ja',
      );
      expect(audioCustom.toJson()['audio_language'], equals('ja'));
      final audioCustomRestored = DownloadOptions.fromJson({'audio_language': 'ja'});
      expect(audioCustomRestored.audioLanguage, equals(AudioOption.language));
      expect(audioCustomRestored.audioLanguageCode, equals('ja'));
    });

    test('4. Complex collections, enums, and case-insensitive/sanitized enum parsing', () {
      final opts = DownloadOptions(
        sponsorblockMark: SponsorblockCategory.values,
        sponsorblockRemove: [
          SponsorblockCategory.music_offtopic,
          SponsorblockCategory.poi_highlight,
        ],
        paths: {
          PathsKey.home: '/home',
          PathsKey.video: '/videos',
          PathsKey.audio: '/audios',
          PathsKey.subtitle: '/subs',
          PathsKey.thumbnail: '/thumbs',
          PathsKey.infojson: '/info',
          PathsKey.pl_thumbnail: '/pl_thumbs',
          PathsKey.description: '/desc',
          PathsKey.annotation: '/ann',
          PathsKey.chapter: '/chap',
          PathsKey.sponsor: '/spon',
        },
        jsRuntimes: {
          JsRuntime.deno: '/usr/bin/deno',
          JsRuntime.node: '/usr/bin/node',
          JsRuntime.quickjs: '/usr/bin/qjs',
          JsRuntime.bun: '/usr/bin/bun',
        },
        mergeOutputFormat: MergeOutputFormat.webm,
        audioFormat: AudioFormat.opus,
        subFormat: SubtitleFormat.ass,
        fixup: FixupOption.detect_or_warn,
        convertThumbnails: ThumbnailFormat.png,
        addHeaders: {'X-Custom-1': 'V1', 'X-Custom-2': 'V2'},
        output: ['%(title)s', '.', '%(ext)s'],
        subLangs: ['en', 'es', 'de', 'fr'],
      );

      final json = opts.toJson();
      expect(json['sponsorblock_mark'].length, equals(11));
      expect(json['sponsorblock_remove'], equals(['music_offtopic', 'poi_highlight']));
      expect(json['paths'].length, equals(11));
      expect(json['js_runtimes'].length, equals(4));
      expect(json['merge_output_format'], equals('webm'));
      expect(json['audio_format'], equals('opus'));
      expect(json['sub_format'], equals('ass'));
      expect(json['fixup'], equals('detect_or_warn'));
      expect(json['convert_thumbnails'], equals('png'));

      // Test parsing with underscores, uppercase, and malformed casing
      final rawCorruptedJson = {
        'sponsorblock_mark': ['MUSIC_OFFTOPIC', 'POI_HIGHLIGHT', 'chapter', 'NON_EXISTENT_CAT'],
        'paths': {'HOME': '/custom_home', 'PL_THUMBNAIL': '/custom_pl', 'INVALID_KEY': '/ignored'},
        'js_runtimes': {'QUICKJS': '/custom_qjs', 'INVALID_RUNTIME': '/ignored'},
        'fixup': 'DETECT_OR_WARN',
        'merge_output_format': 'WEBM',
        'audio_format': 'OPUS',
        'sub_format': 'ASS',
        'convert_thumbnails': 'PNG',
        'cookies_from_browser': 'FIREFOX',
      };

      final restored = DownloadOptions.fromJson(rawCorruptedJson);
      expect(restored.sponsorblockMark, contains(SponsorblockCategory.music_offtopic));
      expect(restored.sponsorblockMark, contains(SponsorblockCategory.poi_highlight));
      expect(restored.sponsorblockMark, contains(SponsorblockCategory.chapter));
      expect(restored.sponsorblockMark.length, equals(3)); // Non-existent category filtered out safely

      expect(restored.paths[PathsKey.home], equals('/custom_home'));
      expect(restored.paths[PathsKey.pl_thumbnail], equals('/custom_pl'));
      expect(restored.paths.length, equals(2));

      expect(restored.jsRuntimes[JsRuntime.quickjs], equals('/custom_qjs'));
      expect(restored.jsRuntimes.length, equals(1));

      expect(restored.fixup, equals(FixupOption.detect_or_warn));
      expect(restored.mergeOutputFormat, equals(MergeOutputFormat.webm));
      expect(restored.audioFormat, equals(AudioFormat.opus));
      expect(restored.subFormat, equals(SubtitleFormat.ass));
      expect(restored.convertThumbnails, equals(ThumbnailFormat.png));
      expect(restored.cookiesFromBrowser, equals(Browser.firefox));
    });

    test('5. Robustness against empty/null JSON inputs without throwing', () {
      final emptyJson = <String, dynamic>{};
      final opts = DownloadOptions.fromJson(emptyJson);

      // Verify safe defaults
      expect(opts.videoResolution, equals(VideoOption.resolution));
      expect(opts.audioLanguage, equals(AudioOption.bestaudio));
      expect(opts.subLangs, isEmpty);
      expect(opts.sponsorblockMark, isEmpty);
      expect(opts.sponsorblockRemove, isEmpty);
      expect(opts.paths, isEmpty);
      expect(opts.jsRuntimes, isEmpty);
      expect(opts.addHeaders, isEmpty);
      expect(opts.output, equals(["title", ".", "ext"]));
      expect(opts.mergeOutputFormat, equals(MergeOutputFormat.mkv));
      expect(opts.audioFormat, equals(AudioFormat.best));
      expect(opts.subFormat, equals(SubtitleFormat.srt));
      expect(opts.concurrentFragments, equals(1));
      expect(opts.cookiesFromWebview, isNull);
      expect(opts.disableCookiesFromWebview, isFalse);
    });

    test('6. Exhaustive copyWith preserves unmentioned fields and correctly overrides specified fields', () {
      final base = DownloadOptions(
        proxy: 'http://old-proxy.com',
        audioQuality: 9,
        concurrentFragments: 2,
        windowsFilenames: true,
        forceOverwrites: false,
      );

      final updated = base.copyWith(
        proxy: 'http://new-proxy.com',
        audioQuality: 0,
        windowsFilenames: false,
        forceOverwrites: true,
      );

      expect(updated.proxy, equals('http://new-proxy.com'));
      expect(updated.audioQuality, equals(0));
      expect(updated.concurrentFragments, equals(2)); // Preserved
      expect(updated.windowsFilenames, isFalse);
      expect(updated.forceOverwrites, isTrue);
    });

    test('7. Adversarial Fuzzing: cookies_from_webview malformed & edge-case payloads', () {
      final adversarialPayloads = <dynamic>[
        null,
        false,
        true, // Boolean true should not crash fromJson and should not be treated as a string path
        0,
        1,
        -100,
        999999,
        3.14159,
        double.nan,
        double.infinity,
        '',
        '   ',
        '\t\n\r',
        '/valid/unix/path/cookies.txt',
        'C:\\Program Files\\Vidra\\cookies.txt',
        'file:///storage/emulated/0/cookies.txt',
        'https://example.com/cookies',
        '🍪 special_unicode_emoji_path.txt',
        'path_with_\x00_null_byte.txt',
        'a' * 4096, // Long path payload
        [],
        ['/path/in/list.txt'],
        [false],
        [true],
        [null],
        {},
        {'path': '/path/in/map.txt'},
        {'cookies_from_webview': false},
      ];

      for (final payload in adversarialPayloads) {
        final rawJson = {'cookies_from_webview': payload};

        DownloadOptions? restored;
        expect(() {
          restored = DownloadOptions.fromJson(rawJson);
        }, returnsNormally, reason: 'Failed to deserialize payload: $payload');

        expect(restored, isNotNull);
        expect(restored!.disableCookiesFromWebview, isA<bool>());
        if (payload is String) {
          expect(restored!.cookiesFromWebview, equals(payload));
          expect(restored!.disableCookiesFromWebview, isFalse);
        } else if (payload == false) {
          expect(restored!.cookiesFromWebview, isNull);
          expect(restored!.disableCookiesFromWebview, isTrue);
        } else {
          expect(restored!.cookiesFromWebview, isNull);
          expect(restored!.disableCookiesFromWebview, isFalse);
        }

        // Invariant: toJson must serialize without exception
        Map<String, dynamic>? serialized;
        expect(() {
          serialized = restored!.toJson();
        }, returnsNormally);

        expect(serialized, isNotNull);
        if (restored!.disableCookiesFromWebview) {
          expect(serialized!['cookies_from_webview'], isFalse);
        } else if (restored!.cookiesFromWebview != null && restored!.cookiesFromWebview!.isNotEmpty) {
          expect(serialized!['cookies_from_webview'], equals(restored!.cookiesFromWebview));
        }
      }
    });

    test('8. High-volume randomized fuzz matrix for cookies_from_webview', () {
      final rand = Random(1337);
      final pathGenerators = [
        () => null,
        () => false,
        () => true,
        () => rand.nextInt(10000) - 5000,
        () => rand.nextDouble() * 1000.0,
        () => '',
        () => '   ',
        () => '/app/storage/${rand.nextInt(1000)}/cookies.txt',
        () => 'C:\\Data\\Vidra\\${rand.nextInt(1000)}\\cookies.txt',
        () => 'path_${rand.nextInt(500)}_\u1F36A.txt',
        () => <dynamic>[rand.nextBool()],
        () => <String, dynamic>{'nested_${rand.nextInt(100)}': 'val'},
      ];

      for (int i = 0; i < 500; i++) {
        final payload = pathGenerators[rand.nextInt(pathGenerators.length)]();
        final json = <String, dynamic>{'cookies_from_webview': payload};

        DownloadOptions? options;
        expect(() {
          options = DownloadOptions.fromJson(json);
        }, returnsNormally);

        expect(options, isNotNull);
        expect(options!.disableCookiesFromWebview, isA<bool>());

        final serialized = options!.toJson();
        final reRestored = DownloadOptions.fromJson(serialized);
        expect(reRestored.disableCookiesFromWebview, equals(options!.disableCookiesFromWebview));
        if (options!.cookiesFromWebview != null &&
            options!.cookiesFromWebview!.isNotEmpty &&
            !options!.disableCookiesFromWebview) {
          expect(reRestored.cookiesFromWebview, equals(options!.cookiesFromWebview));
        } else {
          expect(reRestored.cookiesFromWebview, isNull);
        }
      }
    });

    test('9. HashCode and Equality collision resistance with cookies_from_webview combinations', () {
      final base = DownloadOptions(
        disableCookiesFromWebview: false,
        cookiesFromWebview: '/data/path/a.txt',
      );

      final identicalInstance = DownloadOptions(
        disableCookiesFromWebview: false,
        cookiesFromWebview: '/data/path/a.txt',
      );

      final diffDisabled = base.copyWith(disableCookiesFromWebview: true);
      final diffPath = base.copyWith(cookiesFromWebview: '/data/path/b.txt');
      final diffNullPath = DownloadOptions(
        disableCookiesFromWebview: false,
        cookiesFromWebview: null,
      );

      expect(base, equals(identicalInstance));
      expect(base.hashCode, equals(identicalInstance.hashCode));

      expect(base, isNot(equals(diffDisabled)));
      expect(base, isNot(equals(diffPath)));
      expect(base, isNot(equals(diffNullPath)));

      final set = <DownloadOptions>{
        base,
        identicalInstance,
        diffDisabled,
        diffPath,
        diffNullPath,
      };
      expect(set.length, equals(4)); // Base & identical collapse into 1, leaving 4 unique items
    });
  });
}

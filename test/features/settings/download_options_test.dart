import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/features/settings/domain/download_options.dart';

void main() {
  group('DownloadOptions Domain Model Tests', () {
    test('Default DownloadOptions initializes with expected default values', () {
      final options = DownloadOptions();

      expect(options.videoResolution, equals(VideoOption.resolution));
      expect(options.videoResolutionValue, equals('1080'));
      expect(options.audioLanguage, equals(AudioOption.bestaudio));
      expect(options.audioLanguageCode, isNull);
      expect(options.extractAudio, isFalse);
      expect(options.playlist, isFalse);
      expect(options.mergeOutputFormat, equals(MergeOutputFormat.mkv));
      expect(options.audioFormat, equals(AudioFormat.best));
      expect(options.subFormat, equals(SubtitleFormat.srt));
      expect(options.concurrentFragments, equals(1));
      expect(options.retries, equals(10));
      expect(options.infiniteRetries, isFalse);
    });

    test('toJson and fromJson preserve default DownloadOptions', () {
      final options = DownloadOptions();
      final json = options.toJson();

      expect(json['video_resolution'], equals('1080'));
      expect(json['audio_language'], equals('bestaudio'));
      expect(json['merge_output_format'], equals('mkv'));

      final restored = DownloadOptions.fromJson(json);
      expect(restored.videoResolution, equals(options.videoResolution));
      expect(restored.videoResolutionValue, equals(options.videoResolutionValue));
      expect(restored.audioLanguage, equals(options.audioLanguage));
      expect(restored.mergeOutputFormat, equals(options.mergeOutputFormat));
    });

    test('toJson and fromJson correctly serialize and deserialize customized fields', () {
      final custom = DownloadOptions(
        videoResolution: VideoOption.bestvideo,
        audioLanguage: AudioOption.language,
        audioLanguageCode: 'es',
        subLangs: ['es', 'en'],
        extractAudio: true,
        playlist: true,
        sponsorblockMark: [SponsorblockCategory.sponsor, SponsorblockCategory.intro],
        sponsorblockRemove: [SponsorblockCategory.selfpromo],
        proxy: 'http://127.0.0.1:8080',
        infiniteSocketTimeout: true,
        forceIpv4: true,
        addHeaders: {'User-Agent': 'CustomAgent/1.0', 'Referer': 'https://example.com'},
        disableCookies: true,
        cookiesFromBrowser: Browser.firefox,
        disableCookiesFromBrowser: false,
        mergeOutputFormat: MergeOutputFormat.mp4,
        audioFormat: AudioFormat.mp3,
        subFormat: SubtitleFormat.vtt,
        audioQuality: 5,
        remuxVideo: RemuxVideoFormat.mp4,
        disableRemuxVideo: false,
        embedSubs: true,
        embedThumbnail: true,
        paths: {PathsKey.home: '/downloads', PathsKey.video: '/downloads/videos'},
        jsRuntimes: {JsRuntime.quickjs: '/usr/bin/quickjs'},
        concurrentFragments: 4,
        infiniteRetries: true,
        infiniteSkipPlaylistAfterErrors: true,
      );

      final json = custom.toJson();

      expect(json['video_resolution'], equals('bestvideo'));
      expect(json['audio_language'], equals('es'));
      expect(json['sub_langs'], equals(['es', 'en']));
      expect(json['extract_audio'], isTrue);
      expect(json['playlist'], isTrue);
      expect(json['sponsorblock_mark'], equals(['sponsor', 'intro']));
      expect(json['sponsorblock_remove'], equals(['selfpromo']));
      expect(json['proxy'], equals('http://127.0.0.1:8080'));
      expect(json['socket_timeout'], equals('infinite'));
      expect(json['force_ipv4'], isTrue);
      expect(json['add_headers'], equals({'User-Agent': 'CustomAgent/1.0', 'Referer': 'https://example.com'}));
      expect(json['cookies'], isFalse);
      expect(json['cookies_from_browser'], equals('firefox'));
      expect(json['merge_output_format'], equals('mp4'));
      expect(json['audio_format'], equals('mp3'));
      expect(json['sub_format'], equals('vtt'));
      expect(json['audio_quality'], equals(5));
      expect(json['remux_video'], equals('mp4'));
      expect(json['paths'], equals({'home': '/downloads', 'video': '/downloads/videos'}));
      expect(json['js_runtimes'], equals({'quickjs': '/usr/bin/quickjs'}));
      expect(json['concurrent_fragments'], equals(4));
      expect(json['retries'], equals('infinite'));
      expect(json['skip_playlist_after_errors'], equals('infinite'));

      final restored = DownloadOptions.fromJson(json);

      expect(restored.videoResolution, equals(VideoOption.bestvideo));
      expect(restored.audioLanguage, equals(AudioOption.language));
      expect(restored.audioLanguageCode, equals('es'));
      expect(restored.subLangs, equals(['es', 'en']));
      expect(restored.extractAudio, isTrue);
      expect(restored.playlist, isTrue);
      expect(restored.sponsorblockMark, equals([SponsorblockCategory.sponsor, SponsorblockCategory.intro]));
      expect(restored.sponsorblockRemove, equals([SponsorblockCategory.selfpromo]));
      expect(restored.proxy, equals('http://127.0.0.1:8080'));
      expect(restored.infiniteSocketTimeout, isTrue);
      expect(restored.forceIpv4, isTrue);
      expect(restored.addHeaders, equals({'User-Agent': 'CustomAgent/1.0', 'Referer': 'https://example.com'}));
      expect(restored.disableCookies, isTrue);
      expect(restored.cookiesFromBrowser, equals(Browser.firefox));
      expect(restored.mergeOutputFormat, equals(MergeOutputFormat.mp4));
      expect(restored.audioFormat, equals(AudioFormat.mp3));
      expect(restored.subFormat, equals(SubtitleFormat.vtt));
      expect(restored.audioQuality, equals(5));
      expect(restored.remuxVideo, equals(RemuxVideoFormat.mp4));
      expect(restored.paths[PathsKey.home], equals('/downloads'));
      expect(restored.paths[PathsKey.video], equals('/downloads/videos'));
      expect(restored.jsRuntimes[JsRuntime.quickjs], equals('/usr/bin/quickjs'));
      expect(restored.concurrentFragments, equals(4));
      expect(restored.infiniteRetries, isTrue);
      expect(restored.infiniteSkipPlaylistAfterErrors, isTrue);
    });

    test('toJson and fromJson correctly round-trip underscored enum values', () {
      final options = DownloadOptions(
        sponsorblockMark: [
          SponsorblockCategory.music_offtopic,
          SponsorblockCategory.poi_highlight,
        ],
        sponsorblockRemove: [
          SponsorblockCategory.music_offtopic,
        ],
        fixup: FixupOption.detect_or_warn,
        paths: {
          PathsKey.pl_thumbnail: '/downloads/thumbnails',
        },
      );

      final json = options.toJson();
      expect(
        json['sponsorblock_mark'],
        equals(['music_offtopic', 'poi_highlight']),
      );
      expect(
        json['sponsorblock_remove'],
        equals(['music_offtopic']),
      );
      expect(json['fixup'], equals('detect_or_warn'));
      expect(
        json['paths'],
        equals({'pl_thumbnail': '/downloads/thumbnails'}),
      );

      final restored = DownloadOptions.fromJson(json);
      expect(
        restored.sponsorblockMark,
        equals([
          SponsorblockCategory.music_offtopic,
          SponsorblockCategory.poi_highlight,
        ]),
      );
      expect(
        restored.sponsorblockRemove,
        equals([SponsorblockCategory.music_offtopic]),
      );
      expect(restored.fixup, equals(FixupOption.detect_or_warn));
      expect(
        restored.paths[PathsKey.pl_thumbnail],
        equals('/downloads/thumbnails'),
      );
    });

    test('fromJson correctly parses underscored enums with case-insensitive and snake_case variations', () {
      final rawJson = {
        'sponsorblock_mark': [
          'MUSIC_OFFTOPIC',
          'poi_highlight',
          'musicofftopic',
          'POI_HIGHLIGHT',
        ],
        'fixup': 'DETECT_OR_WARN',
        'paths': {
          'PL_THUMBNAIL': '/custom/thumbnails',
          'plthumbnail': '/custom/pl',
        },
      };

      final restored = DownloadOptions.fromJson(rawJson);
      expect(
        restored.sponsorblockMark,
        contains(SponsorblockCategory.music_offtopic),
      );
      expect(
        restored.sponsorblockMark,
        contains(SponsorblockCategory.poi_highlight),
      );
      expect(restored.fixup, equals(FixupOption.detect_or_warn));
      expect(
        restored.paths[PathsKey.pl_thumbnail],
        isNotNull,
      );
    });

    test('copyWith properly produces a new updated instance preserving other fields', () {
      final original = DownloadOptions(
        proxy: 'http://proxy.com',
        concurrentFragments: 2,
      );

      final modified = original.copyWith(
        concurrentFragments: 8,
        extractAudio: true,
      );

      expect(modified.proxy, equals('http://proxy.com'));
      expect(modified.concurrentFragments, equals(8));
      expect(modified.extractAudio, isTrue);
      expect(original.concurrentFragments, equals(2));
      expect(original.extractAudio, isFalse);
    });
  });
}

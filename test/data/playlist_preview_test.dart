import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/data/models/download_job.dart';
import 'package:vidra/data/models/playlist_preview.dart';

void main() {
  Map<String, dynamic> loadFixture() {
    const path = 'app/json/playlist_incomplete_info.jsonc';
    final file = File(path);
    if (!file.existsSync()) {
      fail('Missing fixture at $path');
    }
    final dynamic decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      fail('Fixture must decode to a Map<String, dynamic>');
    }
    return Map<String, dynamic>.from(decoded);
  }

  test('PlaylistPreviewData tolerates incomplete mix playlist metadata', () {
    final fixture = loadFixture();
    final payload = <String, dynamic>{
      'title': fixture['title'] ?? 'Mix playlist',
      if (fixture['webpage_url'] != null) 'webpage_url': fixture['webpage_url'],
      'playlist': fixture,
    };

    final previewData = PlaylistPreviewData.fromJson(payload);

    expect(previewData.playlist, isNotNull);
    expect(previewData.playlist!.entries, isEmpty);
    expect(previewData.playlist!.entryCount, 0);
  });

  test(
    'DownloadPlaylistSummary ignores non-list playlist entries payloads',
    () {
      final fixture = loadFixture();

      final summary = DownloadPlaylistSummary.fromJson(fixture);

      expect(summary.title, fixture['title']);
      expect(summary.entries, isEmpty);
      expect(summary.entryCount, 0);
    },
  );
}

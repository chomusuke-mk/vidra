import 'package:vidra/data/models/download_job.dart';

class PlaylistPreviewData {
  const PlaylistPreviewData({
    required this.preview,
    required this.playlist,
    required this.raw,
  });

  factory PlaylistPreviewData.fromJson(Map<String, dynamic> json) {
    final preview = DownloadPreview.fromJson(json);
    final playlistJson = json['playlist'];
    final playlist = playlistJson is Map<String, dynamic>
        ? PlaylistPreview.fromJson(playlistJson)
        : null;
    return PlaylistPreviewData(
      preview: preview,
      playlist: playlist,
      raw: Map<String, dynamic>.from(json),
    );
  }

  final DownloadPreview preview;
  final PlaylistPreview? playlist;
  final Map<String, dynamic> raw;

  bool get isPlaylist => playlist != null;

  Map<String, dynamic> toMetadata({Iterable<int>? selectedIndices}) {
    final previewCopy = Map<String, dynamic>.from(raw);
    final metadata = <String, dynamic>{'preview': previewCopy};
    final playlistMap = previewCopy.remove('playlist');
    if (playlistMap is Map<String, dynamic>) {
      final copy = Map<String, dynamic>.from(playlistMap);
      if (selectedIndices != null) {
        final indices = selectedIndices.map((index) => index).toList()..sort();
        copy['selected_indices'] = indices;
      }
      metadata['playlist'] = copy;
    }
    return metadata;
  }
}

class PlaylistPreview {
  const PlaylistPreview({
    this.id,
    this.title,
    this.uploader,
    this.channel,
    this.thumbnailUrl,
    this.description,
    this.descriptionShort,
    this.webpageUrl,
    this.viewCount,
    this.likeCount,
    this.entryCount,
    this.entries = const <PlaylistPreviewEntry>[],
    this.receivedCount,
    this.isCollectingEntries = false,
    this.collectionComplete = false,
    this.hasIndefiniteLength = false,
  });

  factory PlaylistPreview.fromJson(Map<String, dynamic> json) {
    String? resolveString(String key) {
      final value = json[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    final rawEntries = json['entries'];
    List<PlaylistPreviewEntry> entries;
    if (rawEntries is Iterable) {
      entries = rawEntries
          .whereType<Map>()
          .map(
            (entry) =>
                PlaylistPreviewEntry.fromJson(entry.cast<String, dynamic>()),
          )
          .where((entry) => entry.index != null)
          .toList(growable: false);
    } else if (rawEntries is Map) {
      entries = rawEntries.values
          .whereType<Map>()
          .map(
            (entry) =>
                PlaylistPreviewEntry.fromJson(entry.cast<String, dynamic>()),
          )
          .where((entry) => entry.index != null)
          .toList(growable: false);
    } else {
      entries = const <PlaylistPreviewEntry>[];
    }

    return PlaylistPreview(
      id: resolveString('id'),
      title: resolveString('title'),
      uploader: resolveString('uploader'),
      channel: resolveString('channel'),
      thumbnailUrl: resolveString('thumbnail_url'),
      description: resolveString('description'),
      descriptionShort: resolveString('description_short'),
      webpageUrl: resolveString('webpage_url'),
      viewCount: _toInt(json['view_count']),
      likeCount: _toInt(json['like_count']),
      entryCount: _toInt(json['entry_count']) ?? entries.length,
      entries: entries,
      receivedCount: _toInt(json['received_count']),
      isCollectingEntries: _toBool(json['is_collecting_entries']),
      collectionComplete: _toBool(json['collection_complete']),
      hasIndefiniteLength: _toBool(json['has_indefinite_length']),
    );
  }

  final String? id;
  final String? title;
  final String? uploader;
  final String? channel;
  final String? thumbnailUrl;
  final String? description;
  final String? descriptionShort;
  final String? webpageUrl;
  final int? viewCount;
  final int? likeCount;
  final int? entryCount;
  final List<PlaylistPreviewEntry> entries;
  final int? receivedCount;
  final bool isCollectingEntries;
  final bool collectionComplete;
  final bool hasIndefiniteLength;
}

class PlaylistPreviewEntry {
  const PlaylistPreviewEntry({
    this.index,
    this.id,
    this.title,
    this.uploader,
    this.channel,
    this.webpageUrl,
    this.durationSeconds,
    this.durationText,
    this.thumbnailUrl,
    this.isLive = false,
  });

  factory PlaylistPreviewEntry.fromJson(Map<String, dynamic> json) {
    String? resolveString(String key) {
      final value = json[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    return PlaylistPreviewEntry(
      index: _toInt(json['index']),
      id: resolveString('id'),
      title: resolveString('title'),
      uploader: resolveString('uploader'),
      channel: resolveString('channel'),
      webpageUrl: resolveString('webpage_url'),
      durationSeconds: _toInt(json['duration_seconds']),
      durationText: resolveString('duration_text'),
      thumbnailUrl: resolveString('thumbnail_url'),
      isLive: json['is_live'] == true,
    );
  }

  final int? index;
  final String? id;
  final String? title;
  final String? uploader;
  final String? channel;
  final String? webpageUrl;
  final int? durationSeconds;
  final String? durationText;
  final String? thumbnailUrl;
  final bool isLive;

  Duration? get duration => durationSeconds != null && durationSeconds! > 0
      ? Duration(seconds: durationSeconds!)
      : null;
}

int? _toInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

bool _toBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    if (value == 0) {
      return false;
    }
    if (value == 1) {
      return true;
    }
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
  }
  return false;
}

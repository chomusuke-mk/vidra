import 'package:vidra/share/share_intent_payload.dart';

class ManualDownloadOptionsModel {
  ManualDownloadOptionsModel({
    required this.onlyAudio,
    this.resolution,
    this.videoFormat,
    this.audioFormat,
    this.audioLanguage,
    this.subtitles,
  });

  final bool onlyAudio;
  final String? resolution;
  final String? videoFormat;
  final String? audioFormat;
  final String? audioLanguage;
  final String? subtitles;

  static ManualDownloadOptionsModel? maybeFrom(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final map = Map<dynamic, dynamic>.from(raw);
    return ManualDownloadOptionsModel(
      onlyAudio: map['onlyAudio'] == true,
      resolution: _readString(map['resolution']),
      videoFormat: _readString(map['videoFormat']),
      audioFormat: _readString(map['audioFormat']),
      audioLanguage: _readString(map['audioLanguage']),
      subtitles: _readString(map['subtitles']),
    );
  }

  static String? _readString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

class PendingDownloadEntryModel {
  PendingDownloadEntryModel({
    required this.id,
    required this.presetId,
    required this.payload,
    required this.addedAt,
    this.options,
    this.preferenceOverrides,
  });

  final String id;
  final String presetId;
  final ShareIntentPayload payload;
  final DateTime addedAt;
  final ManualDownloadOptionsModel? options;
  final Map<String, dynamic>? preferenceOverrides;

  factory PendingDownloadEntryModel.fromMap(Map<dynamic, dynamic> raw) {
    final payloadMap = raw['payload'];
    final payload = payloadMap is Map
        ? ShareIntentPayload.fromMap(payloadMap)
        : ShareIntentPayload.fromMap(<String, dynamic>{});
    final timestampValue = raw['addedAt'];
    final addedAt = timestampValue is num
        ? DateTime.fromMillisecondsSinceEpoch(timestampValue.toInt())
        : DateTime.now();
    final presetId = raw['presetId']?.toString() ?? '';
    final id = raw['id']?.toString() ?? '';
    return PendingDownloadEntryModel(
      id: id.isEmpty ? payload.timestamp.millisecondsSinceEpoch.toString() : id,
      presetId: presetId.isEmpty ? (payload.presetId ?? '') : presetId,
      payload: payload,
      addedAt: addedAt,
      options: ManualDownloadOptionsModel.maybeFrom(raw['options']),
      preferenceOverrides: _readOverrides(raw['preferenceOverrides']),
    );
  }
}

Map<String, dynamic>? _readOverrides(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  return Map<String, dynamic>.from(raw);
}

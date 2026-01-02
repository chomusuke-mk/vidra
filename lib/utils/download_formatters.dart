import 'package:vidra/constants/app_strings.dart';

typedef AppStringLookup = String Function(String key);

/// Reusable helpers to format download-related text fragments.
String formatBytesCompact(num value) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var bytes = value.abs().toDouble();
  if (bytes <= 0) {
    return '0B';
  }
  var unitIndex = 0;
  while (bytes >= 1024 && unitIndex < units.length - 1) {
    bytes /= 1024;
    unitIndex++;
  }
  final useDecimals = bytes < 10 && bytes != bytes.roundToDouble();
  final formatted = useDecimals
      ? bytes.toStringAsFixed(1)
      : bytes.toStringAsFixed(0);
  return '$formatted${units[unitIndex]}';
}

String formatEntriesRate(double value) {
  final rate = value < 10 ? value.toStringAsFixed(1) : value.toStringAsFixed(0);
  return rate;
}

String formatEta(int seconds) {
  final clamped = seconds.clamp(0, 24 * 60 * 60 * 7);
  final duration = Duration(seconds: clamped);
  if (duration.inHours >= 1) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);
    final hoursText = hours.toString().padLeft(2, '0');
    final minutesText = minutes.toString().padLeft(2, '0');
    final secondsText = secs.toString().padLeft(2, '0');
    return '$hoursText:$minutesText:$secondsText';
  }
  final minutesText = duration.inMinutes.toString().padLeft(2, '0');
  final secondsText = duration.inSeconds
      .remainder(60)
      .toString()
      .padLeft(2, '0');
  return '$minutesText:$secondsText';
}

String? describeStatus(String? status, AppStringLookup localize) {
  if (status == null || status.isEmpty) {
    return null;
  }
  switch (status) {
    case 'downloading':
      return _localized(localize, AppStringKey.jobStatusDownloading);
    case 'finished':
      return _localized(localize, AppStringKey.jobStatusFinished);
    case 'error':
      return _localized(localize, AppStringKey.jobStatusError);
    case 'processing':
      return _localized(localize, AppStringKey.jobStatusProcessing);
    case 'paused':
      return _localized(localize, AppStringKey.jobStatusPaused);
    case 'pausing':
      return _localized(localize, AppStringKey.jobStatusPausing);
    case 'cancelling':
      return _localized(localize, AppStringKey.jobStatusCancelling);
    default:
      return status[0].toUpperCase() + status.substring(1);
  }
}

String? describeStage(
  String? stage,
  String? postprocessor,
  String? preprocessor, {
  required AppStringLookup lookup,
}) {
  if (stage == null || stage.isEmpty) {
    return null;
  }
  final normalized = stage.toLowerCase();
  if (normalized.startsWith('postprocessing:')) {
    final name = postprocessor?.isNotEmpty == true
        ? postprocessor!
        : stage.substring('postprocessing:'.length);
    final label = _postprocessorDescription(name, lookup);
    if (label != null) {
      return label;
    }
    if (name.isEmpty) {
      return _localized(lookup, AppStringKey.jobStatusProcessing);
    }
    return _localized(lookup, AppStringKey.jobStageProcessingNamed, {
      'name': name,
    });
  }
  if (normalized.startsWith('preprocessing:')) {
    final name = preprocessor?.isNotEmpty == true
        ? preprocessor!
        : stage.substring('preprocessing:'.length);
    final label = _preprocessorDescription(name, lookup);
    if (label != null) {
      return label;
    }
    if (name.isEmpty) {
      return _localized(lookup, AppStringKey.jobStagePreparing);
    }
    return _localized(lookup, AppStringKey.jobStagePreparingNamed, {
      'name': name,
    });
  }
  switch (normalized) {
    case 'downloading':
      return _localized(lookup, AppStringKey.jobStatusDownloading);
    case 'downloading_fragments':
      return _localized(lookup, AppStringKey.jobStageDownloadingFragments);
    case 'merging':
      return _localized(lookup, AppStringKey.jobStageMerging);
    case 'extracting_info':
    case 'identificando':
      return _localized(lookup, AppStringKey.jobStageExtractingInfo);
    case 'getting_items':
    case 'wait_for_elements':
      return _localized(lookup, AppStringKey.jobStageWaitingForItems);
    case 'wait_for_selection':
      return _localized(lookup, AppStringKey.jobStageWaitingForSelection);
    case 'processing_thumbnails':
      return _localized(lookup, AppStringKey.jobStageProcessingThumbnails);
    case 'embedding_subtitles':
      return _localized(lookup, AppStringKey.jobStageEmbeddingSubtitles);
    case 'embedding_metadata':
      return _localized(lookup, AppStringKey.jobStageEmbeddingMetadata);
    case 'embedding_thumbnail':
      return _localized(lookup, AppStringKey.jobStageEmbeddingThumbnail);
    case 'writing_metadata':
      return _localized(lookup, AppStringKey.jobStageWritingMetadata);
    case 'download_finished':
      return _localized(lookup, AppStringKey.jobStageDownloadFinished);
    case 'postprocessing':
      return _localized(lookup, AppStringKey.jobStatusProcessing);
    case 'preprocessing':
      return _localized(lookup, AppStringKey.jobStagePreparing);
    case 'queued':
      return _localized(lookup, AppStringKey.jobStageQueued);
    case 'preparing':
      return _localized(lookup, AppStringKey.jobStagePreparing);
    default:
      if (normalized == 'completed') {
        return _localized(lookup, AppStringKey.jobStatusFinished);
      }
      final sanitized = normalized.replaceAll('_', ' ');
      return sanitized[0].toUpperCase() + sanitized.substring(1);
  }
}

String? formatStageName(String? raw) {
  final sanitized = sanitizeText(raw);
  if (sanitized == null) {
    return null;
  }
  final spaced = sanitized
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .replaceAllMapped(
        RegExp(r'(?<=[a-z0-9])([A-Z])'),
        (match) => ' ${match.group(1)}',
      )
      .trim();
  if (spaced.isEmpty) {
    return null;
  }
  final words = spaced.split(RegExp(r'\s+')).map((word) {
    final lower = word.toLowerCase();
    if (lower == 'ffmpeg') {
      return 'FFmpeg';
    }
    if (lower == 'mp3') {
      return 'MP3';
    }
    if (word.isEmpty) {
      return word;
    }
    return '${word[0].toUpperCase()}${lower.substring(1)}';
  }).toList();
  return words.join(' ');
}

String? sanitizeMessage(String? value) {
  if (value == null) {
    return null;
  }
  var text = value.trim();
  if (text.isEmpty) {
    return null;
  }
  final tagMatch = RegExp(r'^\[[^\]]+\]\s*(.+)$').firstMatch(text);
  if (tagMatch != null) {
    final candidate = tagMatch.group(1)?.trim();
    if (candidate != null && candidate.isNotEmpty) {
      text = candidate;
    }
  }
  final colonIndex = text.indexOf(':');
  if (colonIndex > -1) {
    final left = text.substring(0, colonIndex).trim().toLowerCase();
    final right = text.substring(colonIndex + 1).trim();
    if (_messagePrefixes.contains(left) && right.isNotEmpty) {
      text = right;
    }
  }
  text = text.replaceAll(RegExp(r'\s+'), ' ');
  return text.isEmpty ? null : text;
}

String? sanitizeText(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? composeStageLine(String? stage, String? message) {
  final stageText = sanitizeText(stage);
  final messageText = sanitizeMessage(message);
  if (stageText == null && messageText == null) {
    return null;
  }
  if (stageText == null) {
    return messageText;
  }
  if (messageText == null) {
    return stageText;
  }
  return '$stageText: $messageText';
}

String? _postprocessorDescription(String? name, AppStringLookup lookup) {
  if (name == null || name.isEmpty) {
    return null;
  }
  switch (name.toLowerCase()) {
    case 'embedsubtitle':
      return _localized(lookup, AppStringKey.jobStageEmbeddingSubtitles);
    case 'metadata':
      return _localized(lookup, AppStringKey.jobStageEmbeddingMetadata);
    case 'embedthumbnail':
      return _localized(lookup, AppStringKey.jobStageEmbeddingThumbnail);
    case 'thumbnailsconvertor':
      return _localized(lookup, AppStringKey.jobStageProcessingThumbnails);
    case 'xattrmetadata':
      return _localized(lookup, AppStringKey.jobStageWritingMetadata);
    case 'finalizer':
      return _localized(lookup, AppStringKey.jobStagePostprocessingComplete);
    case 'extractaudio':
      return _localized(lookup, AppStringKey.jobStageExtractingAudio);
    case 'ffmpeg':
      return _localized(lookup, AppStringKey.jobStageProcessingWithFfmpeg);
    case 'ffmpegmerger':
      return _localized(lookup, AppStringKey.jobStageMerging);
    case 'ffmpegmetadata':
      return _localized(lookup, AppStringKey.jobStageEmbeddingMetadata);
    case 'ffmpegvideoconvertor':
      return _localized(lookup, AppStringKey.jobStageProcessingVideo);
    default:
      return null;
  }
}

String? _preprocessorDescription(String? name, AppStringLookup lookup) {
  if (name == null || name.isEmpty) {
    return null;
  }
  switch (name.toLowerCase()) {
    case 'thumbnailsconvertor':
    case 'thumbnailconvertor':
      return _localized(lookup, AppStringKey.jobStagePreparingThumbnails);
    case 'ffmpeg':
    case 'ffmpegvideoconvertor':
      return _localized(lookup, AppStringKey.jobStagePreparingVideoResources);
    case 'ffmpegmetadata':
    case 'metadata':
      return _localized(lookup, AppStringKey.jobStagePreparingMetadata);
    default:
      return null;
  }
}

String _localized(
  AppStringLookup lookup,
  String key, [
  Map<String, String>? values,
]) {
  final template = lookup(key);
  if (values == null || values.isEmpty) {
    return template;
  }
  return values.entries.fold<String>(
    template,
    (result, entry) => result.replaceAll('{${entry.key}}', entry.value),
  );
}

const Set<String> _messagePrefixes = <String>{
  'info',
  'warning',
  'warn',
  'error',
};

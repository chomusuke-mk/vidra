import 'package:flutter/material.dart';
import 'package:vidra/constants/app_strings.dart';
import 'package:vidra/data/models/download_job.dart' show DownloadStatus;

class DownloadMetricColors {
  const DownloadMetricColors({
    required this.portion,
    required this.speed,
    required this.eta,
  });

  final Color portion;
  final Color speed;
  final Color eta;
}

class DownloadStateColors {
  const DownloadStateColors({
    required this.labelKey,
    required this.icon,
    required this.progressColor,
    required this.cardColor,
    required this.iconColor,
    required this.iconBackgroundColor,
  });

  final String labelKey;
  final IconData icon;
  final Color progressColor;
  final Color cardColor;
  final Color iconColor;
  final Color iconBackgroundColor;
}

class DownloadVisualPalette {
  static const DownloadMetricColors metricColors = DownloadMetricColors(
    portion: Color.fromARGB(255, 22, 93, 175),
    speed: Color.fromARGB(255, 108, 26, 143),
    eta: Color.fromARGB(255, 21, 136, 124),
  );

  static DownloadStateColors resolveState(
    DownloadStatus status,
    ThemeData theme,
  ) {
    final _StateDefinition definition =
        _stateDefinitions[status] ?? _stateDefinitions[DownloadStatus.unknown]!;
    Color background = theme.cardColor;
    final bool isDark = theme.brightness == Brightness.dark;
    Color baseColor = definition.baseColor;
    background = isDark
        ? Color.alphaBlend(
            background.withAlpha(210),
            const Color.fromARGB(80, 255, 255, 255),
          )
        : background;
    final Color cardColor = Color.alphaBlend(
      baseColor.withAlpha(30),
      background.withAlpha(250),
    );
    final Color iconBackground = Color.alphaBlend(
      baseColor.withAlpha(50),
      background.withAlpha(250),
    );
    baseColor = isDark
        ? Color.alphaBlend(definition.baseColor.withAlpha(150), Colors.white)
        : definition.baseColor;
    return DownloadStateColors(
      labelKey: definition.labelKey,
      icon: definition.icon,
      progressColor: baseColor,
      cardColor: cardColor,
      iconColor: baseColor,
      iconBackgroundColor: iconBackground,
    );
  }

  static Color? stageColor(
    String? rawStage, {
    String? status,
    String? postprocessor,
    String? preprocessor,
    DownloadStatus? jobStatus,
  }) {
    final String stage = rawStage?.toLowerCase().trim() ?? '';
    final String normalizedStatus = status?.toLowerCase().trim() ?? '';
    final String post = postprocessor?.toLowerCase().trim() ?? '';
    final String pre = preprocessor?.toLowerCase().trim() ?? '';

    bool containsAny(String target, List<String> needles) {
      if (target.isEmpty) {
        return false;
      }
      for (final String needle in needles) {
        if (target.contains(needle)) {
          return true;
        }
      }
      return false;
    }

    final bool jobFailed =
        jobStatus == DownloadStatus.failed ||
        jobStatus == DownloadStatus.completedWithErrors;
    final bool jobCancelled = jobStatus == DownloadStatus.cancelled;
    final bool shouldTrustStatusFlag =
        jobStatus == null ||
        jobFailed ||
        jobCancelled ||
        jobStatus == DownloadStatus.unknown;
    final bool statusSignalsError =
        normalizedStatus == 'error' || normalizedStatus == 'failed';
    final bool statusMarksError = shouldTrustStatusFlag && statusSignalsError;
    final bool stageMarksError =
        containsAny(stage, ['error', 'fail', 'panic']) ||
        containsAny(post, ['error', 'fail', 'panic']) ||
        containsAny(pre, ['error', 'fail', 'panic']);

    _StageCategory? resolvedCategory;
    if (containsAny(stage, ['thumbnail', 'miniatur', 'poster']) ||
        containsAny(post, ['thumbnail', 'miniatur']) ||
        containsAny(pre, ['thumbnail', 'miniatur'])) {
      resolvedCategory = _StageCategory.thumbnail;
    } else if (containsAny(stage, ['preprocess', 'pre-proc']) ||
        containsAny(pre, ['preprocess', 'pre-proc'])) {
      resolvedCategory = _StageCategory.prepare;
    } else if (containsAny(stage, [
          'embed',
          'incrust',
          'merge',
          'mezcl',
          'ffmpeg',
          'process',
          'proces',
          'metadat',
        ]) ||
        containsAny(post, ['ffmpeg', 'embed', 'incrust', 'metadat']) ||
        containsAny(pre, ['ffmpeg', 'embed', 'incrust', 'metadat']) ||
        normalizedStatus == 'postprocessing' ||
        normalizedStatus == 'processing') {
      resolvedCategory = _StageCategory.postprocess;
    } else if (containsAny(stage, ['download', 'fragment', 'descarg']) ||
        normalizedStatus == 'downloading' ||
        normalizedStatus == 'running') {
      resolvedCategory = _StageCategory.download;
    } else if (containsAny(stage, [
          'extract',
          'extra',
          'prepare',
          'prepar',
          'getting',
          'obten',
          'queue',
          'cola',
          'initializ',
          'inicializ',
          'gather',
        ]) ||
        normalizedStatus == 'waiting' ||
        normalizedStatus == 'queued' ||
        normalizedStatus == 'preparing') {
      resolvedCategory = _StageCategory.prepare;
    } else if (containsAny(stage, ['final', 'complet', 'cleanup', 'limpi']) ||
        normalizedStatus == 'finished' ||
        normalizedStatus == 'completed') {
      resolvedCategory = _StageCategory.finalize;
    }

    if (resolvedCategory != null) {
      if (jobFailed || jobCancelled) {
        return _stageColors[_StageCategory.error];
      }
      if (statusMarksError && jobStatus == DownloadStatus.unknown) {
        return _stageColors[_StageCategory.error];
      }
      return _stageColors[resolvedCategory];
    }

    if (statusMarksError || stageMarksError || jobFailed || jobCancelled) {
      return _stageColors[_StageCategory.error];
    }

    return _stageColors[_StageCategory.defaultColor];
  }

  static Color get stageErrorColor => _stageColors[_StageCategory.error]!;

  static const Map<DownloadStatus, _StateDefinition> _stateDefinitions = {
    DownloadStatus.completed: _StateDefinition(
      labelKey: AppStringKey.jobStatusFinished,
      icon: Icons.check_circle_rounded,
      baseColor: Color.fromARGB(255, 5, 92, 5),
    ),
    DownloadStatus.completedWithErrors: _StateDefinition(
      labelKey: AppStringKey.jobStatusFinishedWithErrors,
      icon: Icons.error_outline,
      baseColor: Color.fromARGB(255, 196, 125, 5),
    ),
    DownloadStatus.running: _StateDefinition(
      labelKey: AppStringKey.jobStatusDownloading,
      icon: Icons.downloading_rounded,
      baseColor: Color.fromARGB(255, 7, 7, 224),
    ),
    DownloadStatus.pausing: _StateDefinition(
      labelKey: AppStringKey.jobStatusPausing,
      icon: Icons.pause_circle_outline,
      baseColor: Color.fromARGB(255, 175, 175, 17),
    ),
    DownloadStatus.paused: _StateDefinition(
      labelKey: AppStringKey.jobStatusPaused,
      icon: Icons.pause_circle_filled,
      baseColor: Color.fromARGB(255, 204, 204, 15),
    ),
    DownloadStatus.failed: _StateDefinition(
      labelKey: AppStringKey.jobStatusError,
      icon: Icons.error_outline,
      baseColor: Color.fromARGB(255, 206, 10, 10),
    ),
    DownloadStatus.queued: _StateDefinition(
      labelKey: AppStringKey.jobStatusQueued,
      icon: Icons.schedule_outlined,
      baseColor: Color.fromARGB(255, 36, 47, 201),
    ),
    DownloadStatus.cancelling: _StateDefinition(
      labelKey: AppStringKey.jobStatusCancelling,
      icon: Icons.stop_circle_outlined,
      baseColor: Color.fromARGB(255, 92, 90, 90),
    ),
    DownloadStatus.cancelled: _StateDefinition(
      labelKey: AppStringKey.jobStatusCancelled,
      icon: Icons.cancel_outlined,
      baseColor: Color.fromARGB(255, 92, 90, 90),
    ),
    DownloadStatus.unknown: _StateDefinition(
      labelKey: AppStringKey.jobStatusUnknown,
      icon: Icons.help_outline,
      baseColor: Color.fromARGB(255, 92, 90, 90),
    ),
  };

  static const Map<_StageCategory, Color> _stageColors = {
    _StageCategory.prepare: Color(0xFF00897B),
    _StageCategory.download: Color(0xFF1E88E5),
    _StageCategory.postprocess: Color(0xFF8E24AA),
    _StageCategory.thumbnail: Color(0xFFFF7043),
    _StageCategory.finalize: Color(0xFF6D4C41),
    _StageCategory.error: Color(0xFFE53935),
    _StageCategory.defaultColor: Color(0xFF546E7A),
  };
}

class _StateDefinition {
  const _StateDefinition({
    required this.labelKey,
    required this.icon,
    required this.baseColor,
  });

  final String labelKey;
  final IconData icon;
  final Color baseColor;
}

enum _StageCategory {
  prepare,
  download,
  postprocess,
  thumbnail,
  finalize,
  error,
  defaultColor,
}

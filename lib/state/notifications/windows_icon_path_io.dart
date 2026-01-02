import 'dart:io';

String? resolveWindowsToastIconPath() {
  if (!Platform.isWindows) {
    return null;
  }
  final exeDir = File(Platform.resolvedExecutable).parent;
  final candidates = <String>[
    _joinSegments(exeDir.path, const [
      'data',
      'flutter_assets',
      'assets',
      'icon',
      'icon.ico',
    ]),
    _joinSegments(Directory.current.path, const [
      'data',
      'flutter_assets',
      'assets',
      'icon',
      'icon.ico',
    ]),
    _joinSegments(Directory.current.path, const ['assets', 'icon', 'icon.ico']),
  ];
  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) {
      return file.path;
    }
  }
  return candidates.first;
}

String _joinSegments(String base, List<String> segments) {
  var path = base;
  for (final segment in segments) {
    if (segment.isEmpty) {
      continue;
    }
    if (!path.endsWith(Platform.pathSeparator)) {
      path += Platform.pathSeparator;
    }
    path += segment;
  }
  return path;
}

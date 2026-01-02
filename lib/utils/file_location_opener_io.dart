import 'dart:io';

Future<bool> revealInFileManager(String targetPath) async {
  final rawPath = targetPath.trim();
  if (rawPath.isEmpty) {
    return false;
  }
  if (Platform.isAndroid || Platform.isIOS || Platform.isFuchsia) {
    return false;
  }
  final absolutePath = _resolveAbsolutePath(rawPath);
  if (absolutePath == null) {
    return false;
  }

  if (Platform.isWindows) {
    if (await _runProcess('explorer.exe', ['/select,$absolutePath'])) {
      return true;
    }
    final fallback = _resolveRevealDirectory(absolutePath);
    return _runProcess('explorer.exe', [fallback]);
  }

  if (Platform.isMacOS) {
    if (await _runProcess('open', ['-R', absolutePath])) {
      return true;
    }
    final directory = _resolveRevealDirectory(absolutePath);
    return _runProcess('open', [directory]);
  }

  if (Platform.isLinux) {
    final directory = _resolveRevealDirectory(absolutePath);
    return _runProcess('xdg-open', [directory]);
  }

  return false;
}

String? _resolveAbsolutePath(String rawPath) {
  try {
    return File(rawPath).absolute.path;
  } catch (_) {
    try {
      return Directory(rawPath).absolute.path;
    } catch (_) {
      return null;
    }
  }
}

String _resolveRevealDirectory(String absolutePath) {
  try {
    final entityType = FileSystemEntity.typeSync(
      absolutePath,
      followLinks: true,
    );
    if (entityType == FileSystemEntityType.directory) {
      return Directory(absolutePath).absolute.path;
    }
  } catch (_) {
    // ignore resolution errors and fallback to parent inference
  }
  return File(absolutePath).parent.absolute.path;
}

Future<bool> _runProcess(String executable, List<String> arguments) async {
  try {
    final result = await Process.run(executable, arguments);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

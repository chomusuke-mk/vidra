import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class PlatformUtils {
  static const _platform = MethodChannel('vidra_channel');

  static Future<String> resolveExecutable(String baseName) async {
    if (Platform.isAndroid) {
      try {
        final nativeLibDir = await _platform.invokeMethod<String>(
          'getNativeLibDir',
        );
        return p.join(nativeLibDir ?? '', 'lib$baseName.so');
      } catch (e) {
        debugPrint('Fallo al obtener NativeLibDir para $baseName: $e');
        return 'lib$baseName.so';
      }
    } else {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final ext = Platform.isWindows ? '.exe' : '';
      return p.join(exeDir, '$baseName$ext');
    }
  }
}

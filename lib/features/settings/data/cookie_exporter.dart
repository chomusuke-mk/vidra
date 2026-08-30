import 'dart:io';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/netscape_cookie_formatter.dart';

/// Exporter responsible for converting [Cookie] lists into Netscape format
/// and saving them to persistent storage on disk.
class CookieExporter {
  static const String defaultCookieFileName = 'webview_cookies.txt';

  /// Saves the given [cookies] formatted in standard Netscape format to disk.
  ///
  /// If [targetPath] is omitted, saves to `webview_cookies.txt` inside the directory
  /// specified by [baseDirectory] or [getApplicationSupportDirectory].
  ///
  /// Returns the absolute path to the generated cookie file.
  static Future<String> saveCookiesToFile(
    List<Cookie> cookies, {
    required String defaultDomain,
    String? targetPath,
    Directory? baseDirectory,
  }) async {
    final String filePath;
    if (targetPath != null && targetPath.trim().isNotEmpty) {
      filePath = targetPath.trim();
    } else {
      final Directory dir =
          baseDirectory ?? await getApplicationSupportDirectory();
      filePath = p.join(dir.path, defaultCookieFileName);
    }

    final File file = File(filePath);
    final Directory parentDir = file.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    final String netscapeContent = NetscapeCookieFormatter.format(
      cookies,
      defaultDomain: defaultDomain,
    );

    await file.writeAsString(netscapeContent, flush: true);
    return file.absolute.path;
  }
}

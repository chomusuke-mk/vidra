import 'dart:io';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

import '../domain/netscape_cookie_formatter.dart';

/// Exporter responsible for converting [Cookie] lists into Netscape format
/// and saving them to persistent storage on disk.
class CookieExporter {

  /// Sanitizes a domain name to produce a safe filename `<domain>_cookies.txt`.
  static String sanitizeDomainFileName(String domain) {
    var sanitized = domain.trim();
    if (sanitized.startsWith('http://') || sanitized.startsWith('https://')) {
      final uri = Uri.tryParse(sanitized);
      if (uri != null && uri.host.isNotEmpty) {
        sanitized = uri.host;
      }
    } else if (!sanitized.startsWith('/') &&
        !sanitized.startsWith('.') &&
        sanitized.contains('/')) {
      final uri = Uri.tryParse('https://$sanitized');
      if (uri != null && uri.host.isNotEmpty) {
        sanitized = uri.host;
      }
    }
    // Remove port if present
    if (sanitized.contains(':')) {
      sanitized = sanitized.split(':').first;
    }
    // Remove leading dots and underscores
    while (sanitized.startsWith('.') || sanitized.startsWith('_')) {
      sanitized = sanitized.substring(1);
    }
    // Lowercase and sanitize filesystem characters
    sanitized = sanitized.toLowerCase().replaceAll(RegExp(r'[^\w\.-]'), '_');
    // Remove leading dots and underscores again after replacement
    while (sanitized.startsWith('.') || sanitized.startsWith('_')) {
      sanitized = sanitized.substring(1);
    }
    // Remove trailing dots which are illegal in Windows filenames
    sanitized = sanitized.replaceAll(RegExp(r'\.+$'), '');

    if (sanitized.isEmpty) {
      sanitized = 'default';
    }
    return '${sanitized}_cookies.txt';
  }

  /// Saves the given [cookies] formatted in standard Netscape format to disk.
  ///
  /// Returns the absolute path to the generated cookie file.
  static Future<String> saveCookiesToFile(
    List<Cookie> cookies, {
    required String savePath,
  }) async {
    final String filePath;
    if (savePath.trim().isNotEmpty) {
      filePath = savePath.trim();
    } else {
      throw ArgumentError('targetPath must be a non-empty string.');
    }

    final File file = File(filePath);
    final Directory parentDir = file.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    final String netscapeContent = NetscapeCookieFormatter.format(cookies);

    await file.writeAsString(netscapeContent, flush: true);
    return file.absolute.path;
  }

  /// Saves cookies for a specific domain as `<domain>_cookies.txt` inside the directory.
  ///
  /// Returns the absolute path to the generated cookie file.
  static Future<String> saveDomainCookies(
    List<Cookie> cookies, {
    required String domain,
    required Directory directory,
  }) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final fileName = sanitizeDomainFileName(domain);
    final File file = File(p.join(directory.path, fileName));

    final String netscapeContent = NetscapeCookieFormatter.format(cookies);

    await file.writeAsString(netscapeContent, flush: true);
    return file.absolute.path;
  }

  /// Synchronously returns all `.txt` cookie files present in the target or base directory.
  static List<File> getSavedCookieFiles({required Directory directory}) {
    try {
      if (!directory.existsSync()) {
        return [];
      }

      final entities = directory.listSync();
      final files = entities
          .whereType<File>()
          .where((f) => f.path.endsWith('.txt'))
          .toList();

      files.sort((a, b) {
        try {
          return b.lastModifiedSync().compareTo(a.lastModifiedSync());
        } catch (_) {
          return a.path.compareTo(b.path);
        }
      });
      return files;
    } catch (_) {
      return [];
    }
  }
}

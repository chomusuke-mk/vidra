import 'dart:collection';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vidra/share/pending_download_entry.dart';

class PendingDownloadInbox extends ChangeNotifier {
  PendingDownloadInbox({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev.chomusuke.vidra/native');

  final MethodChannel _channel;
  final List<PendingDownloadEntryModel> _entries =
      <PendingDownloadEntryModel>[];
  bool get _supportsNativePull => !kIsWeb && Platform.isAndroid;

  UnmodifiableListView<PendingDownloadEntryModel> get entries =>
      UnmodifiableListView<PendingDownloadEntryModel>(_entries);

  List<PendingDownloadEntryModel> takeEntries() {
    if (_entries.isEmpty) {
      return const <PendingDownloadEntryModel>[];
    }
    final taken = List<PendingDownloadEntryModel>.from(_entries);
    _entries.clear();
    return taken;
  }

  Future<void> pullFromNative() async {
    if (!_supportsNativePull) {
      return;
    }
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'drainPendingDownloads',
      );
      debugPrint(
        '[PendingDownloadInbox] drainPendingDownloads rawCount=${raw?.length ?? 0}',
      );
      if (raw == null || raw.isEmpty) {
        return;
      }
      var updated = false;
      for (final item in raw) {
        if (item is Map) {
          debugPrint('[PendingDownloadInbox] raw item map=$item');
          final entry = PendingDownloadEntryModel.fromMap(
            Map<dynamic, dynamic>.from(item),
          );
          debugPrint(
            '[PendingDownloadInbox] parsed entry id=${entry.id} '
            'preset=${entry.presetId} urls=${entry.payload.urls.length} '
            'addedAt=${entry.addedAt.toIso8601String()}',
          );
          _entries.add(entry);
          updated = true;
        }
      }
      if (updated) {
        debugPrint(
          '[PendingDownloadInbox] total entries after pull=${_entries.length}',
        );
        notifyListeners();
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to pull pending downloads: $error');
      debugPrint(stackTrace.toString());
    }
  }

  void clear() {
    if (_entries.isEmpty) {
      return;
    }
    _entries.clear();
    notifyListeners();
  }
}

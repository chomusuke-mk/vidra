/// Shared constants that mirror the Python backend identifiers.
///
/// Keeping these values in sync with the backend avoids hard coded strings
/// spread across the Flutter codebase and makes it easier to reason about
/// socket events, job statuses and server responses.
class BackendSocketEvent {
  BackendSocketEvent._();

  static const String overview = 'overview';
  static const String update = 'update';
  static const String log = 'log';
  static const String progress = 'progress';
  static const String playlistPreviewEntry = 'playlist_preview_entry';
  static const String playlistSnapshot = 'playlist_snapshot';
  static const String playlistProgress = 'playlist_progress';
  static const String playlistEntryProgress = 'playlist_entry_progress';
  static const String globalInfo = 'global_info';
  static const String entryInfo = 'entry_info';
  static const String listInfoEnds = 'list_info_ends';
  static const String error = 'error';

  static const Set<String> knownEvents = <String>{
    overview,
    update,
    log,
    progress,
    playlistPreviewEntry,
    playlistSnapshot,
    playlistProgress,
    playlistEntryProgress,
    globalInfo,
    entryInfo,
    listInfoEnds,
    error,
  };
}

class BackendJobStatus {
  BackendJobStatus._();

  static const String queued = 'queued';
  static const String running = 'running';
  static const String starting = 'starting';
  static const String retrying = 'retrying';
  static const String pausing = 'pausing';
  static const String paused = 'paused';
  static const String cancelling = 'cancelling';
  static const String cancelled = 'cancelled';
  static const String completed = 'completed';
  static const String completedWithErrors = 'completed_with_errors';
  static const String failed = 'failed';
  static const String deleted = 'deleted';
  static const String notFound = 'not_found';

  static const Set<String> active = <String>{
    running,
    starting,
    retrying,
    pausing,
    cancelling,
  };

  static const Set<String> resumable = <String>{paused, failed};

  static const Set<String> terminal = <String>{
    completed,
    completedWithErrors,
    failed,
    cancelled,
  };
}

class BackendJobCommandStatus {
  BackendJobCommandStatus._();

  static const String notFound = 'not_found';
  static const String jobActive = 'job_active';
  static const String deleted = 'deleted';
  static const String notPlaylist = 'not_playlist';
  static const String noEntries = 'no_entries';
  static const String entriesNotFailed = 'entries_not_failed';
  static const String entriesAlreadyRemoved = 'entries_already_removed';
  static const String entriesRemoved = 'entries_removed';

  static const Set<String> knownStatuses = <String>{
    notFound,
    jobActive,
    deleted,
    notPlaylist,
    noEntries,
    entriesNotFailed,
    entriesAlreadyRemoved,
    entriesRemoved,
  };
}

class BackendJobCommandReason {
  BackendJobCommandReason._();

  static const String jobIsNotPlaylist = 'job_is_not_playlist';
  static const String playlistEntriesRequired = 'playlist_entries_required';
  static const String entriesNotFailed = 'entries_not_failed';
  static const String deleted = 'deleted';
  static const String jobTerminated = 'job_terminated';
  static const String playlistSelectionLocked = 'playlist_selection_locked';

  static const Set<String> knownReasons = <String>{
    jobIsNotPlaylist,
    playlistEntriesRequired,
    entriesNotFailed,
    deleted,
    jobTerminated,
    playlistSelectionLocked,
  };
}

class BackendJobUpdateReason {
  BackendJobUpdateReason._();

  static const String created = 'created';
  static const String started = 'started';
  static const String updated = 'updated';
  static const String resumed = 'resumed';
  static const String retry = 'retry';
  static const String completed = 'completed';
  static const String completedWithErrors = 'completed_with_errors';
  static const String failed = 'failed';
  static const String cancelled = 'cancelled';
  static const String pausing = 'pausing';
  static const String cancelling = 'cancelling';
  static const String paused = 'paused';
  static const String restored = 'restored';
  static const String initialSync = 'initial_sync';
  static const String deleted = 'deleted';
}

class BackendJobKind {
  BackendJobKind._();

  static const String unknown = 'unknown';
  static const String video = 'video';
  static const String playlist = 'playlist';

  static const Set<String> knownKinds = <String>{unknown, video, playlist};
}

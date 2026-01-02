import 'dart:convert';
import 'dart:io';

import 'package:external_path/external_path.dart';
import 'package:file_picker/file_picker.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:vidra/constants/app_strings.dart';
import 'package:vidra/data/preferences/preference_options.dart';
import 'package:vidra/i18n/delegates/vidra_localizations.dart';
import 'package:vidra/models/preference.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/ui/widgets/preferences/preference_control_shared.dart';
import 'package:device_info_plus/device_info_plus.dart';

class PreferenceTextFieldControl extends StatefulWidget {
  const PreferenceTextFieldControl({
    super.key,
    required this.preference,
    this.language,
    this.suggestions,
    this.keyboardType,
    this.allowNull = false,
    this.allowFolder = false,
    this.focusNode,
    this.onSubmit,
    this.minLines = 1,
    this.maxLines = 1,
    this.controllerOverride,
    this.fieldKey,
    this.manualEntryOverride,
    this.useDirectoryPicker = false,
    this.maxWidth,
    this.submitOnEditingComplete = true,
    this.submitOnTapOutside = true,
    this.onFolderPicked,
  });

  final Preference preference;
  final String? language;
  final List<String>? suggestions;
  final TextInputType? keyboardType;
  final bool allowNull;
  final bool allowFolder;
  final FocusNode? focusNode;
  final Future<bool> Function(String trimmedValue)? onSubmit;
  final int minLines;
  final int maxLines;
  final TextEditingController? controllerOverride;
  final String? fieldKey;
  final bool? manualEntryOverride;
  final bool useDirectoryPicker;
  final double? maxWidth;
  final bool submitOnEditingComplete;
  final bool submitOnTapOutside;
  final Future<void> Function(String path)? onFolderPicked;

  @override
  State<PreferenceTextFieldControl> createState() =>
      _PreferenceTextFieldControlState();
}

class _PreferenceTextFieldControlState
    extends State<PreferenceTextFieldControl> {
  late final TextEditingController _controller;
  late final bool _ownsController;
  FocusNode? _focusNode;
  bool _ownsFocusNode = false;
  String _lastSyncedValue = '';
  SpinnerState? _spinnerState;
  String? _spinnerLastValidText;
  bool _spinnerListenerAttached = false;
  bool _spinnerListenerLocked = false;

  Preference get preference => widget.preference;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controllerOverride == null;
    _controller = widget.controllerOverride ?? TextEditingController();
    if (_ownsController) {
      _controller.text = _resolveTextValue();
      _lastSyncedValue = _controller.text;
      _controller.addListener(_handleTextChanged);
    }
    if (widget.focusNode == null) {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncControllerWithPreference();
  }

  @override
  void didUpdateWidget(covariant PreferenceTextFieldControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_ownsController &&
        oldWidget.controllerOverride != widget.controllerOverride) {
      oldWidget.controllerOverride?.removeListener(_handleTextChanged);
      widget.controllerOverride?.addListener(_handleTextChanged);
    }
    _syncControllerWithPreference(force: true);
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    } else {
      widget.controllerOverride?.removeListener(_handleTextChanged);
    }
    if (_ownsFocusNode) {
      _focusNode?.dispose();
    }
    super.dispose();
  }

  FocusNode? get _effectiveFocusNode => widget.focusNode ?? _focusNode;

  void _handleTextChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _resolveTextValue() {
    final value = preference.get('value');
    if (value == null) {
      return '';
    }
    if (preference.key == 'cookies_from_browser' && value is bool) {
      return '';
    }
    if (preference.key == 'cookies' && value is bool) {
      return '';
    }
    if (value is String) {
      return value;
    }
    if (value is Map) {
      final mapped = value.map(
        (key, dynamic val) => MapEntry(key.toString(), val?.toString() ?? ''),
      );
      if (kMapTextKeys.contains(preference.key)) {
        const encoder = JsonEncoder.withIndent('  ');
        return encoder.convert(mapped);
      }
      return jsonEncode(mapped);
    }
    if (value is List) {
      return value.map((item) => item.toString()).join(',');
    }
    return value.toString();
  }

  void _syncControllerWithPreference({bool force = false}) {
    if (!_ownsController) {
      return;
    }
    final latest = _resolveTextValue();
    if (!force && _lastSyncedValue == latest) {
      return;
    }
    if (_controller.text != latest) {
      _controller
        ..text = latest
        ..selection = TextSelection.fromPosition(
          TextPosition(offset: latest.length),
        );
    }
    _lastSyncedValue = latest;
  }

  SpinnerState? _resolveSpinnerState() {
    final config = integerSpinnerConfigs[preference.key];
    if (config == null) {
      return null;
    }
    return SpinnerState(config);
  }

  Future<void> _updatePreference(Object value) async {
    final model = context.read<PreferencesModel>();
    await model.setPreferenceValue(preference, value);
  }

  Future<Directory> _getUserDirectory() async {
    if (Platform.isAndroid) {
      final Directory? internalRoot = await _androidInternalStorageDirectory();
      if (internalRoot != null) {
        return internalRoot;
      }
      return Directory('/storage/emulated/0');
    } else if (Platform.isIOS) {
      return await getApplicationDocumentsDirectory();
    } else {
      String? home = Platform.environment['HOME'];
      String? userProfile = Platform.environment['USERPROFILE'];

      return Directory(home ?? userProfile ?? '/');
    }
  }

  Future<String?> _pickDirectoryPath({String? initialPath}) {
    final localizations = VidraLocalizations.of(context);
    return _pickPath(
      wantsDirectory: true,
      title: localizations.ui(AppStringKey.preferencePickerSelectFolderTitle),
      pickText: localizations.ui(AppStringKey.preferencePickerUseFolderAction),
      initialPath: initialPath,
    );
  }

  Future<String?> _pickFilePath({String? initialPath}) {
    final localizations = VidraLocalizations.of(context);
    return _pickPath(
      wantsDirectory: false,
      title: localizations.ui(AppStringKey.preferencePickerSelectFileTitle),
      pickText: localizations.ui(AppStringKey.preferencePickerUseFileAction),
      initialPath: initialPath,
    );
  }

  Future<String?> _pickPath({
    required bool wantsDirectory,
    required String title,
    required String pickText,
    String? initialPath,
  }) async {
    final backend = _preferredPickerBackend(wantsDirectory: wantsDirectory);
    if (backend == _PickerBackend.filePicker) {
      return _openFilePicker(
        wantsDirectory: wantsDirectory,
        title: title,
        initialPath: initialPath,
      );
    }

    return _openFilesystemPicker(
      type: wantsDirectory ? FilesystemType.folder : FilesystemType.file,
      title: title,
      pickText: pickText,
      initialPath: initialPath,
    );
  }

  Future<String?> _openFilesystemPicker({
    required FilesystemType type,
    required String title,
    required String pickText,
    String? initialPath,
  }) async {
    final localizations = VidraLocalizations.of(context);
    if (!await _ensureStoragePermission()) {
      if (!mounted) {
        return null;
      }
      _showPickerMessage(
        localizations.ui(AppStringKey.preferencePickerGrantStoragePermission),
      );
      return null;
    }

    final Directory? userDirectory = await _existingDirectory(
      await _getUserDirectory(),
    );
    final Directory? preferredDirectory = await _resolveStartDirectory(
      type: type,
      userDirectory: userDirectory,
      initialPath: initialPath,
    );
    final shortcuts = await _buildShortcuts(userDirectory, localizations);
    final Directory? startDirectory =
        preferredDirectory ??
        (shortcuts.isNotEmpty ? shortcuts.first.path : null);

    if (startDirectory == null) {
      if (!mounted) {
        return null;
      }
      _showPickerMessage(
        localizations.ui(AppStringKey.preferencePickerNoStorageLocations),
      );
      return null;
    }

    if (!mounted) {
      return null;
    }
    final pickerTheme = _buildPickerTheme(context);

    try {
      if (!mounted) {
        return null;
      }
      return await FilesystemPicker.open(
        context: context,
        directory: startDirectory,
        fsType: type,
        title: title,
        pickText: pickText,
        permissionText: localizations.ui(
          AppStringKey.preferencePickerPermissionDenied,
        ),
        folderIconColor: Theme.of(context).colorScheme.primary,
        showGoUp: true,
        requestPermission: _ensureStoragePermission,
        shortcuts: shortcuts,
        theme: pickerTheme,
        fileTileSelectMode: type == FilesystemType.file
            ? FileTileSelectMode.wholeTile
            : FileTileSelectMode.checkButton,
        contextActions: [FilesystemPickerNewFolderContextAction()],
      );
    } catch (error) {
      debugPrint('Filesystem picker error: $error');
      if (!mounted) {
        return null;
      }
      _showPickerMessage(
        localizations.ui(AppStringKey.preferencePickerFilesystemUnavailable),
      );
      return null;
    }
  }

  Future<String?> _openFilePicker({
    required bool wantsDirectory,
    required String title,
    String? initialPath,
  }) async {
    final localizations = VidraLocalizations.of(context);
    try {
      if (wantsDirectory) {
        return await FilePicker.platform.getDirectoryPath(
          dialogTitle: title,
          initialDirectory: _initialDirectoryForPicker(initialPath),
        );
      }
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: title,
        initialDirectory: _initialDirectoryForPicker(initialPath),
        allowMultiple: false,
      );
      final files = result?.files;
      if (files == null || files.isEmpty) {
        return null;
      }
      return files.first.path;
    } on PlatformException catch (error) {
      debugPrint('File picker platform exception: $error');
      _showPickerMessage(
        localizations.ui(AppStringKey.preferencePickerSystemPickerUnavailable),
      );
      return null;
    } catch (error) {
      debugPrint('File picker error: $error');
      _showPickerMessage(
        localizations.ui(AppStringKey.preferencePickerFilePickerUnavailable),
      );
      return null;
    }
  }
  String? _initialDirectoryForPicker(String? desired) {
    if (desired == null) {
      return null;
    }
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      return desired;
    }
    return null;
  }

  _PickerBackend _preferredPickerBackend({required bool wantsDirectory}) {
    if (!wantsDirectory) {
      return _PickerBackend.filePicker;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      return _PickerBackend.filesystem;
    }
    return _PickerBackend.filePicker;
  }

  FilesystemPickerTheme _buildPickerTheme(BuildContext context) {
    final localizations = VidraLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return FilesystemPickerTheme(
      topBar: FilesystemPickerTopBarThemeData(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 1,
        titleTextStyle: textTheme.titleMedium,

      ),
      fileList: FilesystemPickerFileListThemeData(
        folderIcon: Icons.folder_outlined,
        folderIconColor: colors.primary,
        folderTextStyle: textTheme.bodyLarge,
        fileIcon: Icons.description_outlined,
        fileIconColor: colors.primary,
        shortcutIconColor: colors.secondary,
        iconSize: 32,
        upIcon: Icons.drive_folder_upload,
        upIconSize: 32,
        upIconColor: colors.secondary,
        upText: localizations.ui(AppStringKey.preferencePickerGoUp),
        upTextStyle: textTheme.bodyLarge?.copyWith(color: colors.secondary),
        checkIcon: Icons.check_circle_rounded,
        checkIconColor: colors.primary,
      ),
      pickerAction: FilesystemPickerActionThemeData(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: textTheme.labelLarge?.copyWith(
          color: colors.onPrimary,
          fontWeight: FontWeight.w600,
        ),
        checkIcon: Icons.check_circle_rounded,
      ),
    );
  }

  Future<List<FilesystemPickerShortcut>> _buildShortcuts(
    Directory? userDirectory,
    VidraLocalizations localizations,
  ) async {
    final shortcuts = <FilesystemPickerShortcut>[];
    final seen = <String>{};

    Future<void> addShortcut(
      Directory? directory,
      String name,
      IconData icon,
    ) async {
      if (directory == null) {
        return;
      }
      final existing = await _existingDirectory(directory);
      if (existing == null) {
        return;
      }
      final key = await _directoryIdentityKey(existing);
      if (!seen.add(key)) {
        return;
      }
      shortcuts.add(
        FilesystemPickerShortcut(name: name, icon: icon, path: existing),
      );
    }

    if (!Platform.isAndroid) {
      await addShortcut(
        userDirectory,
        localizations.ui(AppStringKey.preferencePickerUserFolder),
        Icons.home_rounded,
      );
    }

    final roots = await _platformRootDirectories();
    for (final dir in roots) {
      await addShortcut(
        dir,
        _friendlyRootName(dir, localizations),
        _iconForDirectory(dir),
      );
    }

    if (shortcuts.isEmpty) {
      await addShortcut(
        Directory('/'),
        localizations.ui(AppStringKey.preferencePickerSystemLabel),
        Icons.storage_rounded,
      );
    }

    return shortcuts;
  }

  Future<Directory?> _existingDirectory(Directory directory) async {
    try {
      if (await directory.exists()) {
        return directory;
      }
    } catch (_) {
      // ignored on purpose to maintain robustness
    }
    return null;
  }

  Future<String> _directoryIdentityKey(Directory directory) async {
    try {
      final resolved = await directory.resolveSymbolicLinks();
      if (resolved.isNotEmpty) {
        return _normalizePathKey(resolved);
      }
    } catch (_) {
      // ignored: best-effort canonical path resolution only
    }
    return _normalizePathKey(directory.path);
  }

  String _normalizePathKey(String path) {
    var normalized = path.replaceAll('\\', '/');
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.isEmpty) {
      normalized = '/';
    }
    return normalized.toLowerCase();
  }

  Future<List<Directory>> _platformRootDirectories() async {
    if (Platform.isAndroid) {
      return _androidStorageDirectories();
    }
    if (Platform.isWindows) {
      return _windowsDriveDirectories();
    }
    if (Platform.isIOS) {
      return [await getApplicationDocumentsDirectory()];
    }
    return _unixRootDirectories();
  }

  Future<List<Directory>> _androidStorageDirectories() async {
    final directories = <Directory>[];
    final seen = <String>{};

    Future<void> tryAdd(String? path) async {
      if (path == null || path.isEmpty) {
        return;
      }
      final dir = await _existingDirectory(Directory(path));
      if (dir == null) {
        return;
      }
      final key = await _directoryIdentityKey(dir);
      if (seen.add(key)) {
        directories.add(dir);
      }
    }

    final externalPaths = await _androidExternalStoragePaths();
    for (final path in externalPaths) {
      await tryAdd(path);
    }

    if (directories.isEmpty) {
      for (final path in const [
        '/storage/emulated/0',
        '/storage/self/primary',
        '/sdcard',
      ]) {
        await tryAdd(path);
      }
    }

    final storageRoot = await _existingDirectory(Directory('/storage'));
    if (storageRoot != null) {
      try {
        await for (final entity in storageRoot.list(followLinks: false)) {
          if (entity is! Directory) {
            continue;
          }
          final name = entity.path.split('/').last;
          if (name == 'self') {
            await tryAdd('${entity.path}/primary');
            continue;
          }
          if (name == 'emulated') {
            await tryAdd('${entity.path}/0');
            continue;
          }
          await tryAdd(entity.path);
        }
      } catch (_) {
        // ignored: partial access is acceptable
      }
    }

    return directories;
  }

  Future<List<Directory>> _windowsDriveDirectories() async {
    final drives = <Directory>[];
    for (var code = 65; code <= 90; code++) {
      final letter = String.fromCharCode(code);
      final dir = await _existingDirectory(Directory('$letter:\\'));
      if (dir != null) {
        drives.add(dir);
      }
    }
    return drives;
  }

  Future<List<Directory>> _unixRootDirectories() async {
    final directories = <Directory>[];
    final root = await _existingDirectory(Directory('/'));
    if (root != null) {
      directories.add(root);
    }
    directories.addAll(await _collectChildDirectories('/mnt'));
    directories.addAll(await _collectChildDirectories('/media'));
    if (Platform.isMacOS) {
      directories.addAll(await _collectChildDirectories('/Volumes'));
    }
    return directories;
  }

  Future<List<Directory>> _collectChildDirectories(String parentPath) async {
    final results = <Directory>[];
    final parent = await _existingDirectory(Directory(parentPath));
    if (parent == null) {
      return results;
    }
    try {
      await for (final entity in parent.list(followLinks: false)) {
        if (entity is Directory) {
          final dir = await _existingDirectory(Directory(entity.path));
          if (dir != null) {
            results.add(dir);
          }
        }
      }
    } catch (_) {
      // ignored to keep traversal resilient
    }
    return results;
  }

  Future<List<String>> _androidExternalStoragePaths() async {
    if (!Platform.isAndroid) {
      return const [];
    }
    try {
      final List<String>? paths =
          await ExternalPath.getExternalStorageDirectories();
      if (paths == null || paths.isEmpty) {
        return const [];
      }
      return List<String>.from(paths);
    } catch (error) {
      debugPrint('ExternalPath directories error: $error');
      return const [];
    }
  }

  Future<Directory?> _androidInternalStorageDirectory() async {
    if (!Platform.isAndroid) {
      return null;
    }
    final paths = await _androidExternalStoragePaths();
    for (final path in paths) {
      final existing = await _existingDirectory(Directory(path));
      if (existing != null) {
        return existing;
      }
    }
    return await _existingDirectory(Directory('/storage/emulated/0'));
  }

  Future<Directory?> _resolveStartDirectory({
    required FilesystemType type,
    required Directory? userDirectory,
    String? initialPath,
  }) async {
    final trimmed = initialPath?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      final directMatch = await _existingDirectory(Directory(trimmed));
      if (directMatch != null) {
        return directMatch;
      }
      if (type == FilesystemType.file) {
        try {
          final parent = File(trimmed).parent;
          final parentDir = await _existingDirectory(parent);
          if (parentDir != null) {
            return parentDir;
          }
        } catch (_) {
          // ignored: invalid file path
        }
      }
    }
    return userDirectory;
  }

  String _friendlyRootName(Directory dir, VidraLocalizations localizations) {
    final path = dir.path;
    if (Platform.isWindows) {
      final drive = path.length >= 2
          ? path.substring(0, 2).toUpperCase()
          : path;
      return _formatTemplate(
        localizations.ui(AppStringKey.preferencePickerDriveLabel),
        {'drive': drive},
      );
    }
    if (Platform.isAndroid) {
      if (path.contains('emulated/0')) {
        return localizations.ui(AppStringKey.preferencePickerInternalStorage);
      }
      final segments = path.split('/');
      final last = segments.isNotEmpty ? segments.last : path;
      final isSd = RegExp(r'^[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}$').hasMatch(last);
      if (isSd) {
        return _formatTemplate(
          localizations.ui(AppStringKey.preferencePickerSdCardLabel),
          {'id': last},
        );
      }
      return last.isEmpty ? path : last;
    }
    if (Platform.isMacOS) {
      final segments = path.split('/');
      final last = segments.isNotEmpty ? segments.last : '';
      if (last.isEmpty) {
        return localizations.ui(AppStringKey.preferencePickerMainDisk);
      }
      return last;
    }
    if (Platform.isLinux) {
      final segments = path.split('/');
      final last = segments.isNotEmpty ? segments.last : '';
      return last.isEmpty
          ? localizations.ui(AppStringKey.preferencePickerSystemLabel)
          : last;
    }
    return path;
  }

  IconData _iconForDirectory(Directory dir) {
    if (Platform.isAndroid) {
      if (RegExp(r'[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}').hasMatch(dir.path)) {
        return Icons.sd_card_rounded;
      }
      return Icons.phone_android_rounded;
    }
    if (Platform.isWindows) {
      return Icons.storage_rounded;
    }
    return Icons.folder_outlined;
  }

  Future<bool> _ensureStoragePermission() async {
    if (!Platform.isAndroid) {
      return true;
    }

    Future<PermissionStatus> requestPermission(Permission permission) async {
      try {
        final currentStatus = await permission.status;
        if (currentStatus.isGranted || currentStatus.isLimited) {
          return currentStatus;
        }
        return await permission.request();
      } catch (e) {
        return PermissionStatus.denied;
      }
    }

    final legacyStatus = await requestPermission(Permission.storage);
    if (legacyStatus.isGranted) {
      return true;
    } else if (legacyStatus.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }
    final manageStatus = await requestPermission(
      Permission.manageExternalStorage,
    );
    if (manageStatus.isGranted) {
      return true;
    } else if (manageStatus.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }
    //para sdk >=33 se dará true
    final sdkInt = await DeviceInfoPlugin().androidInfo.then(
      (info) => info.version.sdkInt,
    );
    if (sdkInt >= 33) {
      return true;
    }
    return false;
  }

  void _showPickerMessage(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          elevation: 10,
        ),
      );
  }

  String _formatTemplate(String template, Map<String, String> values) {
    return values.entries.fold<String>(
      template,
      (result, entry) => result.replaceAll('{${entry.key}}', entry.value),
    );
  }

  String _folderTooltip() {
    final localizations = VidraLocalizations.of(context);
    return localizations.ui(AppStringKey.preferencePickerTooltipFolder);
  }

  IconButton _compactIconButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      key: key,
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
    );
  }

  bool get _allowsString => preference.isTypeAllowed(String);
  bool get _allowsInt => preference.isTypeAllowed(int);
  bool get _allowsNull => preference.isTypeAllowed(Null) || widget.allowNull;

  Future<void> _commitEmpty() async {
    _controller.clear();
    if (_allowsNull || _allowsString) {
      await _updatePreference('');
    }
  }

  Future<void> _commitIntValue(int? value) async {
    if (value == null) {
      await _commitEmpty();
      return;
    }
    final text = value.toString();
    if (_controller.text != text) {
      _controller
        ..text = text
        ..selection = TextSelection.fromPosition(
          TextPosition(offset: text.length),
        );
    }
    await _updatePreference(value);
  }

  Future<void> _commitSpinnerValue(
    Object value,
    SpinnerState spinnerState,
  ) async {
    final normalized = spinnerState.normalizeValue(value);
    if (normalized == null) {
      return;
    }
    final text = spinnerState.format(normalized).toString();
    _spinnerLastValidText = text;
    _setSpinnerText(text);
    await _updatePreference(normalized);
  }

  void _setSpinnerText(String text) {
    if (_spinnerListenerLocked) {
      return;
    }
    _spinnerListenerLocked = true;
    try {
      if (_controller.text != text) {
        _controller.text = text;
      }
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: text.length),
      );
    } finally {
      _spinnerListenerLocked = false;
    }
  }

  Object _spinnerFallbackValue(SpinnerState spinnerState) {
    if (_spinnerLastValidText != null) {
      final parsed = spinnerState.parse(_spinnerLastValidText);
      if (parsed != null) {
        return parsed;
      }
    }
    final normalized = spinnerState.normalizeValue(preference.get('value'));
    if (normalized != null) {
      return normalized;
    }
    return spinnerState.defaultMinInt;
  }

  Future<void> _handleTextCommit(String rawValue) async {
    final trimmed = rawValue.trim();
    if (widget.onSubmit != null) {
      final handled = await widget.onSubmit!(trimmed);
      if (handled) {
        return;
      }
    }
    if (trimmed.isEmpty) {
      await _commitEmpty();
    } else {
      await _updatePreference(trimmed);
    }
  }

  Future<void> _handleFlexibleSubmit(String value) async {
    final trimmed = value.trim();
    if (_allowsInt && trimmed.isNotEmpty) {
      final parsed = int.tryParse(trimmed);
      if (parsed != null) {
        await _updatePreference(parsed);
        return;
      }
    }
    await _handleTextCommit(value);
  }

  Future<void> _handleIntegerSubmit(
    String value,
    SpinnerState? spinnerState,
  ) async {
    final trimmed = value.trim();
    if (spinnerState != null) {
      if (trimmed.isEmpty) {
        final fallback = _spinnerFallbackValue(spinnerState);
        await _commitSpinnerValue(fallback, spinnerState);
        return;
      }
      final parsed = spinnerState.parse(trimmed);
      if (parsed == null) {
        final fallback = _spinnerFallbackValue(spinnerState);
        await _commitSpinnerValue(fallback, spinnerState);
        return;
      }
      await _commitSpinnerValue(parsed, spinnerState);
      return;
    }

    if (trimmed.isEmpty) {
      if (_allowsNull || _allowsString) {
        await _commitEmpty();
      }
      return;
    }
    final parsed = int.tryParse(trimmed);
    if (parsed != null) {
      await _updatePreference(parsed);
    }
  }

  Future<void> _adjustValue(int delta, SpinnerState? spinnerState) async {
    if (spinnerState != null) {
      final current =
          spinnerState.parse(_controller.text) ??
          spinnerState.normalizeValue(preference.get('value')) ??
          spinnerState.defaultMinInt;
      final next = spinnerState.stepValue(current, delta);
      if (next != current) {
        await _commitSpinnerValue(next, spinnerState);
      }
      _effectiveFocusNode?.requestFocus();
      return;
    }

    final trimmed = _controller.text.trim();
    final current = int.tryParse(trimmed);
    final base = current ?? 0;
    final candidate = base + delta;
    if (candidate < 0) {
      if (_allowsNull || _allowsString) {
        await _commitEmpty();
      } else if (base != 0) {
        await _commitIntValue(0);
      }
    } else if (candidate != current) {
      await _commitIntValue(candidate);
    }
    _effectiveFocusNode?.requestFocus();
  }

  Widget _buildSpinnerButtons(SpinnerState? spinnerState) {
    return SizedBox(
      width: 36,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            height: 22,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 18,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              constraints: const BoxConstraints.tightFor(width: 32, height: 22),
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: () => _adjustValue(1, spinnerState),
            ),
          ),
          SizedBox(
            width: 32,
            height: 22,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 18,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              constraints: const BoxConstraints.tightFor(width: 32, height: 22),
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: () => _adjustValue(-1, spinnerState),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<PreferencesModel>();

    _spinnerState ??= _resolveSpinnerState();

    final spinnerState = _spinnerState;
    final bool isPureInteger =
        _allowsInt && !_allowsString && spinnerState == null;
    final bool useIntegerSpinner = spinnerState != null || isPureInteger;
    final bool restrictToDigits = isPureInteger && spinnerState == null;
    final bool manualAllowed =
        widget.manualEntryOverride ??
        (!widget.allowFolder || allowCustomValues.contains(preference.key));

    final resolvedKeyboardType = useIntegerSpinner
        ? (spinnerState != null ? TextInputType.text : TextInputType.number)
        : (kNumericTextKeys.contains(preference.key)
              ? TextInputType.number
              : (widget.keyboardType ?? TextInputType.text));

    if (spinnerState != null && !_spinnerListenerAttached) {
      _spinnerListenerAttached = true;
      _controller.addListener(() {
        if (_spinnerListenerLocked) {
          return;
        }
        final raw = _controller.text;
        final trimmed = raw.trim();
        if (trimmed.isEmpty) {
          return;
        }
        final parsed = spinnerState.parse(trimmed);
        if (parsed != null) {
          _spinnerLastValidText = spinnerState.format(parsed).toString();
          return;
        }
        if (isPotentialSpinnerInput(spinnerState, trimmed)) {
          return;
        }
        final fallbackText =
            _spinnerLastValidText ??
            spinnerState.format(spinnerState.defaultMinInt).toString();
        if (fallbackText != raw) {
          _setSpinnerText(fallbackText);
        }
      });
    }

    if (spinnerState != null) {
      final currentNormalized =
          spinnerState.normalizeValue(preference.get('value')) ??
          spinnerState.defaultMinInt;
      final canonicalText = spinnerState.format(currentNormalized).toString();
      _spinnerLastValidText = canonicalText;
      if (_controller.text != canonicalText) {
        _setSpinnerText(canonicalText);
      }
    }

    final hintText =
        (widget.suggestions ?? textPlaceholder[preference.key] ?? []).join(
          ', ',
        );

    InputDecoration decoration() {
      if (!useIntegerSpinner) {
        return InputDecoration(hintText: hintText.isEmpty ? null : hintText);
      }
      return InputDecoration(
        hintText: hintText.isEmpty ? null : hintText,
        suffixIcon: useIntegerSpinner
            ? _buildSpinnerButtons(spinnerState)
            : null,
      );
    }

    Future<void> handleSubmitted(String value) async {
      if (useIntegerSpinner) {
        await _handleIntegerSubmit(value, spinnerState);
      } else {
        await _handleFlexibleSubmit(value);
      }
    }

    Future<void> handleEditingComplete() async {
      if (!widget.submitOnEditingComplete) {
        return;
      }
      await handleSubmitted(_controller.text);
    }

    Future<void> handleTapOutside() async {
      if (!widget.submitOnTapOutside) {
        return;
      }
      await handleSubmitted(_controller.text);
    }

    Widget field = TextField(
      key: ValueKey(widget.fieldKey ?? 'control_${preference.key}'),
      controller: _controller,
      keyboardType: resolvedKeyboardType,
      focusNode: _effectiveFocusNode,
      minLines: useIntegerSpinner ? 1 : widget.minLines,
      maxLines: useIntegerSpinner ? 1 : widget.maxLines,
      inputFormatters: restrictToDigits
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      decoration: decoration(),
      readOnly: widget.allowFolder && !manualAllowed,
      enableInteractiveSelection: manualAllowed,
      onSubmitted: manualAllowed ? handleSubmitted : null,
      onEditingComplete: manualAllowed ? handleEditingComplete : null,
      onTapOutside: manualAllowed
          ? (_) {
              handleTapOutside();
            }
          : null,
    );

    if (!useIntegerSpinner) {
      if (widget.allowFolder) {
        Future<void> pickPath() async {
          final currentValue = _controller.text.trim();
          final initialPath = currentValue.isEmpty ? null : currentValue;
          final path = widget.useDirectoryPicker
              ? await _pickDirectoryPath(initialPath: initialPath)
              : await _pickFilePath(initialPath: initialPath);
          if (path == null) return;
          _controller
            ..text = path
            ..selection = TextSelection.fromPosition(
              TextPosition(offset: path.length),
            );
          if (widget.onFolderPicked != null) {
            await widget.onFolderPicked!(path);
          } else {
            await _updatePreference(path);
          }
        }

        final button = _compactIconButton(
          key: ValueKey('text_${preference.key}_pick_folder'),
          icon: Icons.folder_open,
          tooltip: _folderTooltip(),
          onPressed: pickPath,
        );

        field = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(child: field),
            const SizedBox(width: 8),
            button,
          ],
        );
      }

      field = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth ?? 320),
        child: field,
      );
    } else {
      field = SizedBox(width: 160, child: field);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [field],
    );
  }
}

enum _PickerBackend { filePicker, filesystem }

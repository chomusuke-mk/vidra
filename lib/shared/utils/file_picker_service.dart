import 'dart:io';
import 'package:external_path/external_path.dart';
import 'package:flutter/material.dart';
import 'package:filesystem_picker/filesystem_picker.dart';

class FilePickerService {
  static Future<String?> pickWithFlutter({
    required FilesystemType fsType,
    required BuildContext context,
    Directory? rootDirectory,
  }) async {
    final colorTheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final shortcuts = <FilesystemPickerShortcut>[];
    if (Platform.isAndroid || Platform.isIOS) {
      (await ExternalPath.getExternalStorageDirectories())?.forEach((path) {
        shortcuts.add(
          FilesystemPickerShortcut(
            path: Directory(path),
            name: path,
            icon: Icons.sd_storage_outlined,
          ),
        );
      });
    } else if (Platform.isWindows) {
      for (var code = 65; code <= 90; code++) {
        final letter = String.fromCharCode(code);
        final dir = Directory('$letter:\\');
        if (dir.existsSync()) {
          shortcuts.add(
            FilesystemPickerShortcut(
              path: dir,
              name: dir.path,
              icon: Icons.dns,
            ),
          );
        }
      }
    } else if (Platform.isLinux || Platform.isMacOS) {
      final directories = <Directory>[Directory("/")];
      for (var path in ["/home", "/mnt", "/media"]) {
        final dir = Directory(path);
        if (dir.existsSync()) {
          directories.addAll(
            dir.listSync(followLinks: false).whereType<Directory>(),
          );
        }
      }
      for (var dir in directories) {
        shortcuts.add(
          FilesystemPickerShortcut(
            path: dir,
            name: dir.path,
            icon: Icons.folder_outlined,
          ),
        );
      }
    }

    if (rootDirectory != null) {
      shortcuts.add(
        FilesystemPickerShortcut(
          path: rootDirectory,
          name: rootDirectory.path,
          icon: Icons.folder_special_rounded,
        ),
      );
    }

    if (!context.mounted) return null;

    return await FilesystemPicker.open(
          context: context,
          title:
              'Select ${fsType == FilesystemType.folder ? 'Folder' : 'File'}',
          pickText:
              'Select ${fsType == FilesystemType.folder ? 'Folder' : 'File'}',
          permissionText: 'Permission required to access the file system',
          folderIconColor: Theme.of(context).secondaryHeaderColor,
          showGoUp: true,
          shortcuts: shortcuts,
          fileTileSelectMode: fsType == FilesystemType.file
              ? FileTileSelectMode.wholeTile
              : FileTileSelectMode.checkButton,
          contextActions: [FilesystemPickerNewFolderContextAction()],
          fsType: fsType,
          requestPermission: () => Future.value(true),
          directory: rootDirectory,
          theme: FilesystemPickerTheme(
            topBar: FilesystemPickerTopBarThemeData(
              backgroundColor: colorTheme.primary,
              foregroundColor: colorTheme.onPrimary,
              elevation: 1,
              titleTextStyle: textTheme.titleMedium,
            ),
            fileList: FilesystemPickerFileListThemeData(
              folderIcon: Icons.folder_outlined,
              folderIconColor: colorTheme.primary,
              folderTextStyle: textTheme.bodyLarge,
              fileIcon: Icons.description_outlined,
              fileIconColor: colorTheme.primary,
              shortcutIconColor: colorTheme.secondary,
              iconSize: 32,
              upIcon: Icons.drive_folder_upload,
              upIconSize: 32,
              upIconColor: colorTheme.secondary,
              upText: 'Up',
              upTextStyle: textTheme.bodyLarge,
              checkIcon: Icons.check_circle_rounded,
              checkIconColor: colorTheme.primary,
            ),
            pickerAction: FilesystemPickerActionThemeData(
              backgroundColor: colorTheme.primary,
              foregroundColor: colorTheme.onPrimary,
              elevation: 2,
              textStyle: textTheme.labelLarge,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              checkIcon: Icons.check_circle_rounded,
            ),
          ),
        );
  }
}

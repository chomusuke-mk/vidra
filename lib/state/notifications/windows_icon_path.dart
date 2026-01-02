import 'windows_icon_path_stub.dart'
    if (dart.library.io) 'windows_icon_path_io.dart'
    as impl;

String? resolveWindowsToastIconPath() => impl.resolveWindowsToastIconPath();

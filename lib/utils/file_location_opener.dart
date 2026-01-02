import 'file_location_opener_stub.dart'
    if (dart.library.io) 'file_location_opener_io.dart'
    as opener;

Future<bool> revealInFileManager(String targetPath) {
  return opener.revealInFileManager(targetPath);
}

# Progreso de licencias

## Estado final

- Se creó el mapa de dependencias de Flutter/Dart y Python.
- Se descargaron y reemplazaron las licencias originales de los paquetes que siguen aplicando.
- Se reincorporaron `yt-dlp` y `yt-dlp-ejs` porque se descargan dinámicamente cuando el usuario solicita archivos necesarios.
- Se eliminaron del directorio de licencias los paquetes heredados que ya no pertenecen al inventario actual.
- Se actualizaron `THIRD_PARTY_LICENSES.md` y `third_party_licenses/THIRD_PARTY_LICENSES.txt` para reflejar el estado final.

## Inventario actual

### Python runtime (`app/requirements/*.txt`)

- `certifi`
- `brotli`
- `websockets`
- `requests`
- `mutagen`
- `yt-dlp`
- `yt-dlp-ejs`
- `phantomjs`
- `secretstorage`
- `flask`
- `waitress`
- `tldextract`
- `pycryptodomex`
- `xattr`
- `curl-cffi`

### Flutter / Dart runtime (`pubspec.yaml`)

- `cupertino_icons`
- `path_provider`
- `package_info_plus`
- `shared_preferences`
- `provider`
- `http`
- `cached_network_image`
- `flutter_cache_manager`
- `serious_python`
- `permission_handler`
- `filesystem_picker`
- `external_path`
- `flutter_local_notifications`
- `jsonc`
- `device_info_plus`
- `path`
- `crypto`
- `convert`
- `mime`
- `receive_sharing_intent`
- `openpgp`
- `dio`
- `archive`
- `url_launcher`
- `open_filex`
- `flutter_slidable`
- `file_picker`
- `flutter_screen_overlay`

### Native binaries

- `vidra-ffmpeg`

# Third-party notices and attributions

Vidra bundles a Python backend together with a Flutter desktop client, so the application ships code from both PyPI and pub.dev. The tables below list every direct runtime dependency declared in `app/requirements.txt` and `pubspec.yaml`, the license attached to each component, and where its full text lives inside the repository.

## Python backend runtime (app/requirements.txt)

| Dependency | Declared version | License | Obligations & notes | License text |
| --- | --- | --- | --- | --- |
| certifi | latest (unpinned) | MPL-2.0 | Keep the MPL notice with redistributed binaries; publish modifications that touch MPL-covered files. | `third_party_licenses/certifi` |
| fastapi | latest (unpinned) | MIT | Retain copyright and license text in source and binary form. | `third_party_licenses/fastapi` |
| httpx | latest (unpinned) | BSD-3-Clause | Keep copyright + disclaimer; no endorsement using maintainer names. | `third_party_licenses/httpx` |
| mutagen | latest (unpinned) | GPL-2.0-or-later | Copyleft: distributing Vidra with Mutagen requires providing the corresponding source for the backend bundle. | `third_party_licenses/mutagen` |
| pydantic (< 2) | `<2` | MIT | Preserve copyright and license text. | `third_party_licenses/pydantic` |
| requests | latest (unpinned) | Apache-2.0 | Keep LICENSE + NOTICE; document any local changes. | `third_party_licenses/requests` |
| secretstorage | latest (unpinned) | BSD-3-Clause | Retain copyright/permission statement and liability disclaimer. | `third_party_licenses/secretstorage` |
| uvicorn | latest (unpinned) | BSD-3-Clause | Same preservation requirements as other BSD components. | `third_party_licenses/uvicorn` |
| websockets | latest (unpinned) | BSD-3-Clause | Same preservation requirements as other BSD components. | `third_party_licenses/websockets` |
| yt-dlp | latest (unpinned) | Unlicense | Public-domain dedication; still respect YouTube/DRM laws when redistributing. | `third_party_licenses/yt-dlp` |
| yt-dlp-ejs | latest (unpinned) | Unlicense | Same as above. | `third_party_licenses/yt-dlp-ejs` |
| pycryptodomex | latest (unpinned) | BSD-2-Clause | Retain copyright/permission statement; no endorsement. | `third_party_licenses/pycryptodomex` |
| brotli | latest (unpinned) | MIT | Preserve license text in redistributions. | `third_party_licenses/brotli` |
| cffi | latest (unpinned) | MIT | Preserve license text in redistributions. | `third_party_licenses/cffi` |

## Flutter application runtime (pubspec.yaml)

| Dependency | Declared version | License | Obligations & notes | License text |
| --- | --- | --- | --- | --- |
| Flutter SDK / flutter_localizations | sdk `^3.9.2` | BSD-3-Clause | Flutter bundles its own `LICENSE`; include it when shipping binaries. | [Flutter LICENSE](https://raw.githubusercontent.com/flutter/flutter/master/LICENSE) |
| cupertino_icons | `^1.0.8` | MIT | Keep the MIT notice. | `third_party_licenses/cupertino_icons` |
| path_provider | `^2.1.5` | BSD-3-Clause | Keep copyright + disclaimer. | `third_party_licenses/path_provider` |
| package_info_plus | `^9.0.0` | BSD-3-Clause | Same BSD obligations. | `third_party_licenses/package_info_plus` |
| shared_preferences | `^2.5.3` | BSD-3-Clause | Same BSD obligations. | `third_party_licenses/shared_preferences` |
| provider | `^6.1.5+1` | MIT | Retain MIT notice. | `third_party_licenses/provider` |
| flutter_dotenv | `^6.0.0` | MIT | Retain MIT notice. | `third_party_licenses/flutter_dotenv` |
| http | `^1.1.0` | BSD-3-Clause | Same BSD obligations. | `third_party_licenses/http` |
| web_socket_channel | `^3.0.3` | BSD-3-Clause | Same BSD obligations. | `third_party_licenses/web_socket_channel` |
| intl | `^0.20.2` | BSD-3-Clause | Same BSD obligations. | `third_party_licenses/intl` |
| url_launcher | `^6.3.0` | BSD-3-Clause | Same BSD obligations. | `third_party_licenses/url_launcher` |
| cached_network_image | `^3.4.1` | MIT | Retain MIT notice. | `third_party_licenses/cached_network_image` |
| flutter_cache_manager | `^3.4.1` | MIT | Retain MIT notice. | `third_party_licenses/flutter_cache_manager` |
| data_table_2 | `^2.6.0` | MIT | Retain MIT notice. | `third_party_licenses/data_table_2` |
| serious_python | `^0.9.4` | Apache-2.0 | Keep LICENSE + NOTICE for appliance bundles. | `third_party_licenses/serious_python` |
| open_file | `^3.3.2` | BSD-3-Clause | Same BSD obligations. | `third_party_licenses/open_file` |
| permission_handler | `^12.0.1` | MIT | Retain MIT notice. | `third_party_licenses/permission_handler` |
| filesystem_picker | `^4.1.0` | BSD-3-Clause | Same BSD obligations. | `third_party_licenses/filesystem_picker` |
| file_picker | `^10.3.7` | MIT | Retain MIT notice. | `third_party_licenses/file_picker` |
| external_path | `^2.2.0` | MIT | Retain MIT notice. | `third_party_licenses/external_path` |
| flutter_local_notifications | `^19.5.0` | BSD-3-Clause | Same BSD obligations. | `third_party_licenses/flutter_local_notifications` |
| flutter_localized_locales | `^2.0.4` | MIT | Retain MIT notice. | `third_party_licenses/flutter_localized_locales` |
| jsonc | `^0.0.3` | BSD-3-Clause | Same BSD obligations. | `third_party_licenses/jsonc` |
| device_info_plus | `^11.5.0` | BSD-3-Clause | Same BSD obligations. | `third_party_licenses/device_info_plus` |
| path | `^1.9.1` | BSD-3-Clause | Same BSD obligations. | `third_party_licenses/path` |
| super_drag_and_drop | `^0.9.1` | MIT | Retain MIT notice; includes native binaries. | `third_party_licenses/super_drag_and_drop` |
| super_clipboard | `^0.9.1` | MIT | Retain MIT notice; used for DataReader APIs. | `third_party_licenses/super_clipboard` |

> _Transitive dependencies inherit the licensing of their upstream packages. Keep the Flutter `LICENSE` file emitted by `flutter build` inside your installers to cover those components._

## Native binaries (FFmpeg)

| Dependency | Declared version | License | Obligations & notes | License text |
| --- | --- | --- | --- | --- |
| FFmpeg binaries (vidra-ffmpeg build) | Prebuilt bundle | GPL-3.0-or-later | Built with `--enable-gpl` and `--enable-version3`; provide the corresponding source from [vidra-ffmpeg](https://github.com/chomusuke-mk/vidra-ffmpeg) and ship GPLv3 notices with redistributed binaries. | `third_party_licenses/vidra-ffmpeg` |

## Compliance approach

- **License texts** – Every entry listed above has its upstream license stored verbatim under `third_party_licenses/` (or linked when upstream distribution already includes it). Include that directory or a generated `THIRD_PARTY_LICENSES.txt` in every installer/distribution.
- **Notices in binaries** – When packaging with `serious_python` or creating Flutter release builds, copy `THIRD_PARTY_LICENSES.md` (or an equivalent auto-generated notice file) so end users can review third-party terms.
- **Copyleft dependencies** – `mutagen` is GPL-2.0-or-later. If you distribute Vidra externally, you must provide the corresponding source code for the backend bundle to satisfy GPL obligations.
- **Changes & contributions** – Document any local modifications to Apache-2.0/MPL-2.0 components directly inside this file and regenerate the affected license text if needed.


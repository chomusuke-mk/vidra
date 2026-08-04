# Avisos y atribuciones de terceros

Vidra distribuye un cliente Flutter desde este repositorio y un paquete de ejecución en Python descrito por `app/requirements/*.txt`. La aplicación backend en sí reside en `vidra-backend`; solo las dependencias de tiempo de ejecución empaquetadas desde este repositorio se enumeran aquí, incluyendo los binarios dinámicos que se descargan cuando la aplicación lo requiere.

## Paquete de ejecución de Python (`app/requirements/*.txt`)

| Dependencia   | Versión declarada | Licencia         | Obligaciones y notas                                                                                      | Texto de la licencia               |
| ------------- | ----------------- | ---------------- | --------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| certifi       | latest (unpinned) | MPL-2.0          | Mantener el aviso MPL con los binarios redistribuidos; publicar modificaciones que toquen archivos MPL.   | third_party_licenses/certifi       |
| brotli        | latest (unpinned) | MIT              | Conservar el texto de la licencia MIT en las redistribuciones.                                            | third_party_licenses/brotli        |
| websockets    | latest (unpinned) | BSD-3-Clause     | Conservar el copyright y el descargo de responsabilidad en redistribuciones.                              | third_party_licenses/websockets    |
| requests      | latest (unpinned) | Apache-2.0       | Mantener LICENSE y NOTICE; documentar los cambios locales si los hay.                                     | third_party_licenses/requests      |
| mutagen       | latest (unpinned) | GPL-2.0-or-later | Copyleft: distribuir Vidra con Mutagen requiere proveer el código fuente correspondiente para el backend. | third_party_licenses/mutagen       |
| phantomjs     | latest (unpinned) | BSD-3-Clause     | Conservar el aviso BSD y el descargo de responsabilidad.                                                  | third_party_licenses/phantomjs     |
| secretstorage | latest (unpinned) | BSD-3-Clause     | Conservar el aviso de copyright/permiso y el descargo de responsabilidad.                                 | third_party_licenses/secretstorage |
| flask         | latest (unpinned) | BSD-3-Clause     | Conservar el aviso BSD y el descargo de responsabilidad.                                                  | third_party_licenses/flask         |
| waitress      | latest (unpinned) | ZPL-2.1          | Mantener el texto de la licencia Zope Public License con las redistribuciones.                            | third_party_licenses/waitress      |
| tldextract    | latest (unpinned) | BSD-3-Clause     | Conservar el aviso BSD y el descargo de responsabilidad.                                                  | third_party_licenses/tldextract    |
| pycryptodomex | latest (unpinned) | BSD-2-Clause     | Conservar el aviso de copyright/permiso; sin aval comercial explícito.                                    | third_party_licenses/pycryptodomex |
| xattr         | latest (unpinned) | BSD-3-Clause     | Conservar el aviso BSD y el descargo de responsabilidad.                                                  | third_party_licenses/xattr         |
| curl-cffi     | latest (unpinned) | MIT              | Conservar el aviso de la licencia MIT.                                                                    | third_party_licenses/curl-cffi     |
| yt-dlp        | latest (unpinned) | Unlicense        | Dominio público; aún así, respetar leyes de DRM aplicables al redistribuir.                               | third_party_licenses/yt-dlp        |
| yt-dlp-ejs    | latest (unpinned) | Unlicense        | Ídem al caso de yt-dlp.                                                                                   | third_party_licenses/yt-dlp-ejs    |

## Tiempo de ejecución de la aplicación Flutter (`pubspec.yaml`)

| Dependencia                         | Versión declarada | Licencia     | Obligaciones y notas                                                   | Texto de la licencia                                               |
| ----------------------------------- | ----------------- | ------------ | ---------------------------------------------------------------------- | ------------------------------------------------------------------ |
| Flutter SDK / flutter_localizations | sdk               | BSD-3-Clause | Flutter incluye su propio archivo LICENSE; incluir al enviar binarios. | <https://raw.githubusercontent.com/flutter/flutter/master/LICENSE> |
| cupertino_icons                     | ^1.0.9            | MIT          | Conservar el aviso de la licencia MIT.                                 | third_party_licenses/cupertino_icons                               |
| path_provider                       | ^2.1.6            | BSD-3-Clause | Conservar el copyright y el descargo de responsabilidad.               | third_party_licenses/path_provider                                 |
| package_info_plus                   | ^10.2.1           | BSD-3-Clause | Conservar el aviso BSD y el descargo de responsabilidad.               | third_party_licenses/package_info_plus                             |
| shared_preferences                  | ^2.5.5            | BSD-3-Clause | Conservar el aviso BSD y el descargo de responsabilidad.               | third_party_licenses/shared_preferences                            |
| provider                            | ^6.1.5+1          | MIT          | Conservar el aviso de la licencia MIT.                                 | third_party_licenses/provider                                      |
| http                                | ^1.6.0            | BSD-3-Clause | Conservar el aviso BSD y el descargo de responsabilidad.               | third_party_licenses/http                                          |
| cached_network_image                | ^3.4.1            | MIT          | Conservar el aviso de la licencia MIT.                                 | third_party_licenses/cached_network_image                          |
| flutter_cache_manager               | ^3.4.2            | MIT          | Conservar el aviso de la licencia MIT.                                 | third_party_licenses/flutter_cache_manager                         |
| serious_python                      | ^4.5.1            | Apache-2.0   | Mantener LICENSE y NOTICE para distribuciones del appliance.           | third_party_licenses/serious_python                                |
| permission_handler                  | ^13.0.0           | MIT          | Conservar el aviso de la licencia MIT.                                 | third_party_licenses/permission_handler                            |
| filesystem_picker                   | ^4.1.0            | BSD-3-Clause | Conservar el aviso BSD y el descargo de responsabilidad.               | third_party_licenses/filesystem_picker                             |
| external_path                       | ^2.2.0            | MIT          | Conservar el aviso de la licencia MIT.                                 | third_party_licenses/external_path                                 |
| flutter_local_notifications         | ^22.2.0           | BSD-3-Clause | Conservar el aviso BSD y el descargo de responsabilidad.               | third_party_licenses/flutter_local_notifications                   |
| jsonc                               | ^0.0.3            | BSD-3-Clause | Conservar el aviso BSD y el descargo de responsabilidad.               | third_party_licenses/jsonc                                         |
| device_info_plus                    | ^13.2.0           | BSD-3-Clause | Conservar el aviso BSD y el descargo de responsabilidad.               | third_party_licenses/device_info_plus                              |
| path                                | ^1.9.1            | BSD-3-Clause | Conservar el aviso BSD y el descargo de responsabilidad.               | third_party_licenses/path                                          |
| crypto                              | ^3.0.7            | BSD-3-Clause | Conservar el aviso BSD y el descargo de responsabilidad.               | third_party_licenses/crypto                                        |
| convert                             | ^3.1.2            | BSD-3-Clause | Conservar el aviso BSD y el descargo de responsabilidad.               | third_party_licenses/convert                                       |
| mime                                | ^2.0.0            | BSD-3-Clause | Conservar el aviso BSD y el descargo de responsabilidad.               | third_party_licenses/mime                                          |
| receive_sharing_intent              | ^1.9.0            | Apache-2.0   | Conservar el texto de la licencia Apache en distribuciones.            | third_party_licenses/receive_sharing_intent                        |
| openpgp                             | ^3.10.7           | MIT          | Conservar el aviso de la licencia MIT.                                 | third_party_licenses/openpgp                                       |
| dio                                 | ^5.11.0           | MIT          | Conservar el aviso de la licencia MIT.                                 | third_party_licenses/dio                                           |
| archive                             | ^4.0.9            | MIT          | Conservar el aviso de la licencia MIT.                                 | third_party_licenses/archive                                       |
| url_launcher                        | ^6.3.2            | BSD-3-Clause | Conservar el aviso BSD y el descargo de responsabilidad.               | third_party_licenses/url_launcher                                  |
| open_filex                          | ^4.7.0            | BSD-3-Clause | Conservar el aviso BSD y el descargo de responsabilidad.               | third_party_licenses/open_filex                                    |
| flutter_slidable                    | ^4.0.3            | MIT          | Conservar el aviso de la licencia MIT.                                 | third_party_licenses/flutter_slidable                              |
| file_picker                         | ^12.0.0-beta.7    | MIT          | Conservar el aviso de la licencia MIT.                                 | third_party_licenses/file_picker                                   |
| flutter_screen_overlay              | ^1.0.7            | MIT          | Conservar el aviso de la licencia MIT.                                 | third_party_licenses/flutter_screen_overlay                        |
| flutter_markdown_plus               | ^1.0.12           | BSD-3-Clause | Conservar el aviso BSD y el descargo de responsabilidad.               | third_party_licenses/flutter_markdown_plus                         |
| tutorial_coach_mark                 | ^1.3.3            | MIT          | Conservar el aviso de la licencia MIT.                                 | third_party_licenses/tutorial_coach_mark                           |

> _Las dependencias transitivas heredan la licencia de sus paquetes upstream. Mantén el archivo `LICENSE` de Flutter emitido por `flutter build` dentro de tus instaladores para cubrir estos componentes._

## Binarios Nativos (FFmpeg, QuickJS)

| Dependencia                    | Versión declarada | Licencia         | Obligaciones y notas                                                                                                                                                                                                             | Texto de la licencia               |
| ------------------------------ | ----------------- | ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| vidra-ffmpeg (Binarios FFmpeg) | prebuilt bundle   | GPL-3.0-or-later | Compilado con --enable-gpl y --enable-version3; proporcionar el código fuente correspondiente desde <https://github.com/chomusuke-mk/vidra-ffmpeg> y entregar los avisos GPLv3 correspondientes con los binarios redistribuidos. | third_party_licenses/vidra-ffmpeg  |
| vidra-quickjs (QuickJS)        | prebuilt bundle   | MIT              | Conservar el aviso de la licencia MIT.                                                                                                                                                                                           | third_party_licenses/vidra-quickjs |

## Estrategia de Cumplimiento (Compliance)

- **Textos de licencia**: Cada entrada mencionada anteriormente tiene su licencia original guardada literalmente bajo el directorio `third_party_licenses/` (o vinculada en caso de que la distribución la incluya). Incluye ese directorio o un archivo generado `THIRD_PARTY_LICENSES.txt` en cada instalador.
- **Avisos en binarios**: Al empaquetar con `serious_python` o al compilar releases de Flutter, copia `THIRD_PARTY_LICENSES.md` para que los usuarios finales puedan revisar los términos de terceros.
- **Dependencias Copyleft**: `mutagen` tiene licencia GPL-2.0-or-later. Si distribuyes Vidra externamente, debes proporcionar el código fuente del paquete backend correspondiente para satisfacer las obligaciones de la GPL.
- **Cambios y contribuciones**: Documenta directamente cualquier modificación local en componentes Apache-2.0 o MPL-2.0 dentro de este archivo y regenera el texto de la licencia afectada de ser necesario.

<p align="center">
 <img src="assets/icon/icon.png" alt="Vidra" width="256" />
</p>
<h1 align="center">Vidra</h1>

<p align="center">
  Gestor de vídeo/tareas de nivel de escritorio (interfaz de usuario Flutter + backend Python en repositorio separado)
</p>

<p align="center">
 <a href="https://github.com/chomusuke-mk/vidra/releases"><img alt="Releases" src="https://img.shields.io/badge/Releases-Download-success?logo=github&logoColor=white" /></a>
 <a href="docs/system-architecture.md"><img alt="Docs" src="https://img.shields.io/badge/Docs-System%20architecture-informational?logo=readthedocs&logoColor=white" /></a>
 <a href="https://github.com/chomusuke-mk/vidra/issues"><img alt="Issues" src="https://img.shields.io/badge/Issues-Report%20a%20bug-important?logo=github&logoColor=white" /></a>
</p>

<p align="center">
 <a href="https://flutter.dev"><img alt="Flutter 3.9+" src="https://img.shields.io/badge/Flutter-3.9%2B-blue?logo=flutter&logoColor=white" /></a>
 <a href="https://www.python.org/"><img alt="Python 3.12" src="https://img.shields.io/badge/Python-3.12-blueviolet?logo=python&logoColor=white" /></a>
 <a href="THIRD_PARTY_LICENSES.md"><img alt="Licensing" src="https://img.shields.io/badge/Licensing-THIRD__PARTY__LICENSES-informational?logo=github&logoColor=white" /></a>
 <a href="https://www.buymeacoffee.com/chomusuke"><img alt="Donate (Buy me a coffee)" src="https://img.shields.io/badge/Donate-Buy%20me%20a%20coffee-orange?logo=buymeacoffee&logoColor=white" /></a>
 <a href="https://www.patreon.com/chomusuke_dev"><img alt="Donate (Patreon)" src="https://img.shields.io/badge/Donate-Patreon-critical?logo=patreon&logoColor=white" /></a>
</p>

> Vidra es un gestor de vídeo y tareas para escritorio que combina una interfaz de usuario Flutter con un backend Python mantenido en un repositorio separado.

## Aspectos destacados

- **Cliente moderno** – Una aplicación de escritorio Flutter con temas y localización para más de 150 idiomas.
- **Backend robusto y ligero** – Backend Python separado, con dependencias dinámicas para descargas y manejo de cambios mediante deltas.

## Instalación

Vidra se distribuye a través de **GitHub Releases**. Cada versión incluye instaladores para diferentes plataformas.

| Plataforma | Instalador                                                                                                              |
| ---------- | ----------------------------------------------------------------------------------------------------------------------- |
| `Windows`  | `vidra-windows.exe`                                                                                                     |
| `Linux`    | `vidra-x86_64.AppImage` <br>`vidra-linux.deb`                                                                           |
| `Android`  | `vidra-android.apk`<br> `vidra-android-arm64-v8a.apk`<br>`vidra-android-x86_64.apk` <br>`vidra-android-armeabi-v7a.apk` |
| `macOS`    | Próximamente                                                                                                            |

### Validar Firmas y Checksums

Cada release incluye los siguientes archivos para verificar la integridad y autenticidad de los instaladores:

- `SHA2-256SUMS`, `SHA2-512SUMS`: checksums.
- `SHA2-256SUMS.sig`, `SHA2-512SUMS.sig`: GPG signatures for the checksums.

Estos recursos se distribuyen bajo la licencia [LICENSE](LICENSE) y pueden incluir componentes bajo otras licencias enumeradas en [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

## Arquitectura

```mermaid
graph TD
  A[Cliente Flutter] <-->|Peticiones HTTP| B[Backend Python]
  subgraph serious_python
    B <--> C[yt-dlp]
    C <--> D[FFmpeg/ffprobe]
    C --> E[quickjs]
    C --> F[yt-dlp-ejs]
  end
```

### FFmpeg / ffprobe ejecutables

Para ejecutar Vidra, debe proporcionar `ffmpeg` y `ffprobe` por su cuenta.

Fuente recomendada: <https://github.com/chomusuke-mk/vidra-ffmpeg>

Coloca los archivos con los nombres **exactos** en las siguientes ubicaciones:

| Plataforma  | Ubicación esperada dentro del proyecto                                                                    |
| ----------- | --------------------------------------------------------------------------------------------------------- |
| **Windows** | `windows/ffmpeg.exe` <br> `windows/ffprobe.exe`                                                           |
| **Linux**   | `linux/ffmpeg` <br> `linux/ffprobe`                                                                       |
| **Android** | `android/app/src/main/jniLibs/<abi>/libffmpeg.so` <br> `android/app/src/main/jniLibs/<abi>/libffprobe.so` |

> - `<abi>` debe ser uno de `arm64-v8a`, `x86_64`, o `armeabi-v7a`.

### Quickjs ejecutables

Para ejecutar Vidra, debe proporcionar `quickjs` por su cuenta.

Fuente recomendada: <https://github.com/chomusuke-mk/vidra-quickjs>

Coloca los archivos con los nombres **exactos** en las siguientes ubicaciones:

| Plataforma  | Ubicación esperada dentro del proyecto                                                                     |
| ----------- | ---------------------------------------------------------------------------------------------------------- |
| **Windows** | `windows/quickjs.exe` <br> `windows/quickjs.exe`                                                           |
| **Linux**   | `linux/quickjs` <br> `linux/quickjs`                                                                       |
| **Android** | `android/app/src/main/jniLibs/<abi>/libquickjs.so` <br> `android/app/src/main/jniLibs/<abi>/libquickjs.so` |

> - `<abi>` debe ser uno de `arm64-v8a`, `x86_64`, o `armeabi-v7a`.

## Inicio rápido

### 1. Inicializar el espacio de trabajo de Flutter

```bash
flutter pub get
dart run flutter_launcher_icons # opcional, regenera los iconos
```

### 2. Configurar entorno y dependencias del backend

Vidra requiere un entorno preparado para el backend usando `serious_python`.
Se recomienda usar los perfiles de lanzamiento de VS Code (`.vscode/launch.json`) que configuran las variables de entorno automáticamente.
Para ejecución manual, debes configurar estas variables apuntando a los directorios generados:

- `SERIOUS_PYTHON_SITE_PACKAGES` apuntando a `.serious_python/site-packages`
- `SERIOUS_PYTHON_APP` apuntando a `.serious_python/app`

### Cliente de escritorio Flutter

```bash
# Configura las variables de entorno primero o ejecuta desde VS Code:
flutter run -d windows
flutter run -d linux
flutter run -d android
```

## Empaquetado y distribución

1. Asegúrate de que el paquete backend se prepare correctamente. En versiones actuales, ya **no** se requiere un archivo `app/app.zip` en los recursos (assets) de Flutter; en su lugar, `serious_python` prepara un entorno en el directorio temporal `.serious_python/`.

   ```bash
    dart run serious_python:main package app/src \
    -r -r -r app/requirements/base.txt \
    -r -r -r app/requirements/Windows.txt \
    -p Windows --verbose
   ```

   > El backend se distribuye en <https://github.com/chomusuke-mk/vidra-backend>. Este comando empaqueta la lógica e instala las dependencias (por plataforma) preparándolas para que el compilador de Flutter las integre mediante las variables de entorno declaradas.

2. Compila el artefacto de destino (`flutter build windows`, `flutter build linux`, etc.).

   > El repositorio incluye tareas de VS Code (`Serious Python: Package App`, `Build Android APK (Flutter)`) y un flujo automatizado en `.github/workflows/vidra-release.yml` que encapsulan los comandos correctos, la inyección de variables de entorno (`SERIOUS_PYTHON_SITE_PACKAGES` y `SERIOUS_PYTHON_APP`) y el despliegue dinámico de binarios complementarios (FFmpeg y QuickJS).

## Localización y recursos

- Las traducciones se encuentran en `i18n/locales/<código ISO>/`. Utilice los scripts auxiliares en `tool/` (por ejemplo, `auto_translate_locales.py`, `generate_translation_progress.py`) para mantener los idiomas sincronizados.
- El directorio `assets/` contiene iconos, animaciones y plantillas `.env`. Todos los recursos referenciados se declaran en `pubspec.yaml`.

## Testing & QA

| Scope                     | Command                                                                     |
| ------------------------- | --------------------------------------------------------------------------- |
| Flutter widget/unit tests | `flutter test`                                                              |
| Integration smoke test    | `flutter test --tags integration` (tests under `test/` and `test/backend/`) |

Use `VIDRA_SERVER_DATA` to point tests at a temporary directory so logs are isolated per run.

## Documentation & troubleshooting

- `docs/system-architecture.md` – end-to-end overview of the Flutter client, backend, sockets, and packaging flow.
- `docs/client-flows.md` – English descriptions of UI flows mapped to REST/WebSocket contracts.
- `docs/typed-architecture.md` – explains the typed model refactor and state layers inside the backend.
- `docs/backend-job-lifecycle.md` – canonical reference for job states, transitions, and related endpoints.
- `docs/configuration-and-ops.md` – environment variables, logging targets, and ops runbooks.
- `docs/troubleshooting.md` – symptom → cause → fix catalog for packaging, sockets, and localization failures.
- `temp/native-crash.txt` – crash dump location; include it with bug reports.
- Structured logs are written to `<VIDRA_SERVER_DATA>/release_logs.txt` automatically at runtime.

## Contributing & security

- Read `CONTRIBUTING.md` for coding standards, branching strategy, and review expectations.
- Vulnerability disclosures go through `SECURITY.md`.
- Please keep `git` history clean and avoid force-pushing to `main`.

## Licensing & attribution

- Project licensing follows the root `LICENSE` file.
- Every third-party dependency (Python + Flutter), incluyendo las descargas dinámicas `yt-dlp` y `yt-dlp-ejs`, is documented in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md), with verbatim license texts stored under `third_party_licenses/` for inclusion in installers.
- Remember that `mutagen` is GPL-2.0-or-later; distributing Vidra to end users requires shipping the corresponding backend sources to satisfy GPL obligations.

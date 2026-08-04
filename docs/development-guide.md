# Guía de Desarrollo, Empaquetado y Solución de Problemas

Este documento centraliza las directrices para el desarrollo diario, las pruebas de calidad, el flujo de empaquetado para lanzamientos y las soluciones a los problemas más comunes en el entorno de desarrollo de Vidra.

## 1. Configuración del Entorno de Desarrollo (Ops)

Para desarrollar en Vidra necesitas coordinar el cliente Flutter con el backend de Python inyectado por `serious_python`.

### Variables de Entorno

El backend empaquetado requiere ciertas variables para ubicarse correctamente cuando ejecutas el proyecto de forma local. En Visual Studio Code (a través de `launch.json`), estas variables generalmente se configuran solas si ejecutas las tareas de compilación, pero para ejecución manual en consola necesitas definirlas:

- `SERIOUS_PYTHON_SITE_PACKAGES`: Debe apuntar al directorio `.serious_python/site-packages` dentro de tu repositorio local.
- `SERIOUS_PYTHON_APP`: Debe apuntar a `.serious_python/app`.

### Empaquetado de la Lógica (serious_python)

Si realizas cambios en el código Python dentro de `app/src`, necesitas re-empaquetar el motor antes de compilar Flutter:

```bash
dart run serious_python:main package app/src -r -r -r app/requirements/base.txt -r -r -r app/requirements/Windows.txt -p Windows --verbose
```

_(Reemplaza Windows y Windows.txt por Linux o Android según corresponda)_.

## 2. Estrategia de Pruebas (Testing)

Mantenemos la calidad del código separando las pruebas en distintos niveles.

| Alcance                      | Comando de Ejecución                     | Propósito                                                      |
| ---------------------------- | ---------------------------------------- | -------------------------------------------------------------- |
| **Pruebas Unitarias**        | `flutter test`                           | Validar lógica aislada de Flutter, modelos y utilidades.       |
| **Pruebas de Integración**   | `flutter test --tags integration`        | End-to-End: Asegurar que el UI interactúa bien con el Backend. |
| **Pruebas del Backend (Py)** | `pytest` (dentro de `app/src` si aplica) | Asegurar el correcto parseo de la API, yt-dlp y ffmpeg.        |

**Aislamiento de Logs:**
Durante las pruebas automatizadas, se recomienda exportar la variable `VIDRA_SERVER_DATA` apuntando a un directorio temporal (ej. `/tmp/vidra_tests`). Esto garantiza que los logs del backend de las pruebas no colisionen con los logs de tu uso diario de la aplicación.

## 3. Empaquetado y Lanzamientos (Release)

El proceso oficial de despliegue está automatizado vía **GitHub Actions** (`.github/workflows/vidra-release.yml`).

### Flujo CI/CD a grandes rasgos

1. **Descarga del código fuente del backend:** Recupera `app.zip` desde el repositorio principal de backend.
2. **Obtención de precompilados:** Descarga los binarios de FFmpeg y QuickJS para cada arquitectura (ej. `x86_64`, `arm64-v8a`).
3. **Generación del motor:** Corre `serious_python:main package` para inyectar todo en los binarios.
4. **Compilación Flutter:** Llama a `flutter build apk`, `flutter build windows`, `flutter build linux`, etc.
5. **Firmado y Creación de instaladores:** Genera `.deb`, `.AppImage`, `.exe` (vía Inno Setup) y empaqueta las APKs junto con las firmas `SHA2-256SUMS.sig`.

**Nota:** Si vas a publicar localmente, puedes replicar los comandos de la Action leyendo el archivo YAML paso a paso.

## 4. Solución de Problemas (Troubleshooting)

### El servidor Backend no levanta (SystemState se queda en `startingBackend` o `fatalError`)

- **Posible Causa:** Falta empaquetar la aplicación de Python o dependencias nativas (FFmpeg/QuickJS) no están en la ruta correcta.
- **Solución:** Vuelve a ejecutar el comando `dart run serious_python:main package...` y asegúrate de haber copiado `ffmpeg.exe` o `libffmpeg.so` a las rutas especificadas en el `README.md`. Revisa el log local en `~/.cache/vidra/logs/server.log` (o su equivalente en AppData/Temp según la plataforma).

### Problemas de versiones con paquetes (`pub get` falla)

- **Posible Causa:** Conflictos de dependencias estrictas, especialmente si `serious_python` se actualizó.
- **Solución:** Ejecuta `flutter pub outdated` y evalúa. Borra `pubspec.lock` e intenta un `flutter pub get` limpio.

### Las descargas de video fallan inexplicablemente

- **Posible Causa:** YouTube u otros portales cambian frecuentemente la estructura de sus webs.
- **Solución:** `yt-dlp` debe estar en la última versión. Actualiza el backend descargando las dependencias Python más recientes e inyectando un nuevo `app.zip`. Si usas una instalación generada por CI, espera al próximo parche OTA.

### La interfaz gráfica no responde

- **Posible Causa:** Código costoso bloqueando el hilo de Dart en la UI.
- **Solución:** La comunicación de red HTTP con localhost no bloquea el hilo, pero asegúrate de no estar leyendo archivos masivos de log de forma sincrónica (`readFileSync`). Todo I/O pesado debe delegarse asincrónicamente o gestionarse directamente por el Isolate del backend.

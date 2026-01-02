# Backend: lanzamiento, token y sincronización de estado

Este documento describe (con base en el código actual del repositorio) cómo Vidra lanza el backend embebido (Python vía `serious_python`), cómo se maneja el token de acceso y qué archivos usa el backend para persistir/sincronizar estado entre sesiones.

## 1) Lanzamiento del backend (Flutter → Serious Python)

### 1.1 Flujo de arranque desde Flutter

El arranque ocurre en `lib/main.dart`:

- Se carga `.env` con `flutter_dotenv`.
- Se resuelve la configuración del backend (`BackendConfig.fromEnv()`) y el token (`BackendAuthToken.resolve(dotenv)`).
- Se calculan rutas en disco (por plataforma) usando:
  - `getApplicationSupportDirectory()` → carpeta de soporte persistente.
  - `getApplicationCacheDirectory()` → carpeta de caché.
- Se arma un `backendDataDir` bajo soporte: `<support>/backend`.
- Se definen rutas de archivos del launcher/backend en ese directorio:
  - `startup_status.json`
  - `vidra.start.lock`
  - `release_logs.txt`
- Se invoca el launcher:

```dart
SeriousPythonServerLauncher.instance.ensureStarted(
  extraEnvironment: {
    'VIDRA_SERVER_DATA': backendDataDir,
    'VIDRA_SERVER_CACHE': '<cache>/backend',
    'VIDRA_SERVER_LOG_LEVEL': 'info',
    'VIDRA_SERVER_STATUS_FILE': backendStatusFile,
    'VIDRA_SERVER_LOCK_FILE': backendLockFile,
    'VIDRA_SERVER_LOG_FILE': backendLogFile,
    ...
  },
)
```

### 1.2 Qué hace `SeriousPythonServerLauncher`

La lógica principal está en `lib/state/serious_python_server_launcher.dart`.

A alto nivel:

1. Combina variables de entorno:
   - `dotenv.env` (lo que viene de `.env`).
   - `extraEnvironment` (lo que pasa `main.dart`).
2. Prepara rutas en el directorio de soporte y setea (si no existían) variables:
   - `VIDRA_SERVER_STATUS_FILE`
   - `VIDRA_SERVER_LOCK_FILE`
   - `VIDRA_SERVER_LOG_FILE`
3. Intenta **reusar** un backend ya corriendo:
   - Verifica si el puerto está abierto.
   - Llama al health check y valida que el campo `service` coincida con `VIDRA_SERVER_NAME`.
   - Si coincide, marca el backend como `running` y no relanza.
4. Evita arranques simultáneos usando un lock de archivo (`vidra.start.lock`).
5. Determina si debe “desempaquetar” el backend embebido comparando un hash del asset (`app/app.zip.hash`) con un hash persistido en disco.
6. Lanza el backend con `SeriousPython.run(...)`:

```dart
SeriousPython.run(
  'app/app.zip',
  appFileName: 'main.py',
  environmentVariables: env,
  sync: false,
)
```

7. Espera a que el backend esté listo **observando el puerto TCP** (no sólo el proceso).
8. Escribe `startup_status.json` con fases como `starting`, `success`, `error`, `reused`.

## 2) Tratamiento del token (frontend y backend)

### 2.1 Cómo se obtiene el token en Flutter

En `lib/config/backend_auth_token.dart`:

- En **debug/profile**: requiere `VIDRA_SERVER_TOKEN` en `.env` (si falta, lanza error).
- En **release**: genera un token aleatorio (base64url) en memoria.

Importante: ese valor (`BackendAuthToken.value`) se inyecta al `DownloadController` y se usa para autenticar contra el backend.

### 2.2 Cómo se envía el token al backend

En el frontend:

- HTTP: `lib/data/services/download_service.dart` agrega headers cuando hay token:
  - `Authorization: Bearer <token>`
  - `X-API-Token: <token>`

- WebSocket: `lib/state/download_controller.dart` agrega `?token=<token>` a las URLs de socket (por ejemplo, overview/job socket).

### 2.3 Cómo valida el backend el token

En el backend Python:

- `app/src/security/tokens.py`:
  - Lee el token esperado desde `VIDRA_SERVER_TOKEN` (variable de entorno) **en import-time**.
  - Soporta token desde:
    - `Authorization: Bearer ...`
    - `X-API-Token: ...`
    - Query param `?token=...` (para websockets)
  - La validación es igualdad exacta: `candidate == EXPECTED_SERVER_TOKEN`.

- HTTP: `app/src/api/http.py` instala un middleware `enforce_token`:
  - Permite sin token el endpoint de health check y requests `OPTIONS`.
  - Para el resto: si el token falta o no coincide → responde `401` con código `token_missing_or_invalid`.

- WebSockets: `app/src/api/websockets.py` valida token antes de aceptar:
  - Lee `?token=` o headers.
  - Si falla: cierra el socket con código `1008`.

### 2.4 Nota sobre consistencia del token (punto crítico)

El backend **siempre** espera `VIDRA_SERVER_TOKEN` en su entorno (Python lanza error si falta).

A la vez, el frontend usa `BackendAuthToken.value` para firmar las requests.

Por lo tanto, para que el sistema funcione, el token que:

- el backend espera (`VIDRA_SERVER_TOKEN` en el entorno con el que se ejecuta `main.py`),

DEBE ser el mismo que:

- el frontend envía (headers/query).

Actualmente, el launcher arma el entorno del backend usando `dotenv.env` + `extraEnvironment`. Si el token cambia entre ambos lados, el backend va a responder 401 / cerrar websockets.

## 3) Archivos de sincronización/persistencia entre sesiones

Aquí “sincronización entre sesiones” significa: **persistir estado en disco para restaurarlo en el próximo arranque**.

### 3.1 Directorios base

El backend toma dos rutas desde variables de entorno (ver `app/src/config/environment.py`):

- `VIDRA_SERVER_DATA` → carpeta persistente de datos.
- `VIDRA_SERVER_CACHE` → carpeta de caché.

En Flutter (ver `lib/main.dart`) estas variables se setean típicamente como:

- `VIDRA_SERVER_DATA = <ApplicationSupport>/backend`
- `VIDRA_SERVER_CACHE = <ApplicationCache>/backend`

### 3.2 Archivos de estado que se restauran

En `app/src/download/manager.py` el `DownloadManager` inicializa stores bajo `DATA_FOLDER`:

- `download_state.json`
  - Guardado por `DownloadStateStore` (`app/src/download/state_store.py`).
  - Contiene un snapshot de trabajos: `{ "jobs": [ ... ] }`.
  - Escribe de forma atómica con `*.tmp` y `replace()`.

- `playlist_entries/<job_id>.json`
  - Guardado por `PlaylistEntryStore`.
  - Contiene `{ "version": <ms>, "entries": [...] }`.

- `job_options/<job_id>.json`
  - Guardado por `JobOptionsStore`.
  - Contiene `{ "version": <ms>, "options": {...} }`.

- `job_logs/<job_id>.json`
  - Guardado por `JobLogStore`.
  - Contiene `{ "version": <ms>, "logs": [...] }`.

En el arranque, `_restore_persisted_jobs()`:

- Carga `download_state.json`.
- Rehidrata jobs.
- Emite eventos websocket con razón `RESTORED`.
- Vuelve a persistir para normalizar el snapshot.

### 3.3 Archivos de arranque / diagnóstico

Además del estado de trabajos, se generan archivos para diagnóstico del ciclo de vida:

- `startup_status.json`
  - Escrito tanto por Flutter (`SeriousPythonServerLauncher`) como por el backend (`app/src/main.py`).
  - Incluye fase (`starting`, `success`, `error`, `reused`), timestamps y (en el caso del launcher) puede incluir `token`.

- `release_logs.txt`
  - En `app/src/main.py` se redirige `stdout`/`stderr` a este archivo (o el que indique `VIDRA_SERVER_LOG_FILE`).

### 3.4 ¿Cómo entra el token en la “sincronización”?

El token **no** se usa para construir rutas de los archivos (no hay carpetas “por token” en el código que persiste el estado).

El rol del token es:

- Proteger el acceso al backend (HTTP/WS).
- Evitar que un cliente sin token correcto lea/modifique el estado persistido.

Consecuencia práctica:

- Si el backend conserva `VIDRA_SERVER_DATA` entre sesiones, el estado se restaura.
- Si el token esperado cambia entre sesiones, el estado sigue existiendo en disco, pero el cliente no podrá acceder hasta que vuelva a usar el token correcto.

## 4) Pistas rápidas para depuración

- Si el backend no arranca:
  - Revisar `startup_status.json` y `release_logs.txt` en `VIDRA_SERVER_DATA`.
  - Verificar que `VIDRA_SERVER_TOKEN` esté presente en el entorno del backend.

- Si ves 401 o websockets que se cierran:
  - Revisar que el token que envía el frontend coincida con el token esperado por el backend.

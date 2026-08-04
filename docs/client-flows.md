# Flujos del Cliente (Client Flows)

Este documento detalla los principales flujos de interacción y ciclo de vida de la interfaz de usuario en la aplicación cliente (Flutter).

## 1. Secuencia de Arranque y Configuración

El punto de entrada principal (`main.dart`) inicializa los servicios asíncronos antes de levantar la interfaz de usuario.

1. **Inicialización Base:** Se asegura la vinculación de los widgets de Flutter (`WidgetsFlutterBinding.ensureInitialized()`), se inicia `SharedPreferences` y el servicio de notificaciones locales (`NotificationService.init()`).
2. **Inyección de Dependencias:** Se crea la jerarquía del árbol de `Provider`. El `SystemController` es instanciado de inmediato.
3. **Lanzamiento del Motor (Backend):**
   - El `SystemController` asigna el puerto y el token dinámico.
   - Crea el _Isolate_ del backend (`backendIsolateMain`).
   - Comienza a extraer los binarios de Python (esto ocurre de forma paralela en el hilo principal con un `await SeriousPython.prepareApp()`).
4. **Validación de la UI:** El componente `App` observa el estado. Si falta completar el inicio, muestra un indicador de carga circular. Una vez listo, se carga el tema, el idioma y se lanza el `MainRouter`.

## 2. Enrutador Principal (`MainRouter`)

El `MainRouter` decide la vista principal evaluando el estado dictado por `SystemController`:

- **Faltan Permisos (`missingPermissions`):** Muestra la pantalla `PermissionsScreen` solicitando al usuario el acceso al almacenamiento (y notificaciones si corresponde) necesarios para descargar archivos.
- **Preparado (`ready` o en progreso regular):** Envuelve la vista principal (`DownloadsScreen`) dentro del widget `ShareIntentWrapper`.

## 3. Recepción de Enlaces (Share Intent)

Vidra es capaz de recibir enlaces desde otras aplicaciones (por ejemplo, "Compartir desde YouTube" en dispositivos móviles). Esto se gestiona en `ShareIntentWrapper`.

1. **Intercepción del Enlace:** Mediante el paquete `receive_sharing_intent`, la aplicación detecta cuando es lanzada con una URL entrante o cuando recibe una URL en segundo plano.
2. **Transferencia al Controlador:** Si el texto entrante es una URL válida, se envía a `SystemController.enqueueDownload(url, options)`.
3. **Comunicación al Isolate:** El `SystemController` empaqueta la solicitud y la transmite al Isolate del backend a través del `SendPort`.
4. **Reflejo en la UI:** El backend acusa recibo del comando y comienza la tarea de descarga. El estado es consultado o notificado (según el patrón REST/WebSocket que se implemente), y el `DownloadsController` actualiza la vista.

## 4. El Sistema de Overlay (Isolate Independiente)

Para interactuar con la aplicación sin salir completamente del contexto de otras aplicaciones (muy útil en Android), Vidra incorpora un "Quick Share Overlay".

1. **Punto de Entrada Secundario:** En `main.dart` existe la función `@pragma("vm:entry-point") void overlayMain()`.
2. **Aislamiento:** Este es un árbol de Flutter completamente independiente que corre en su propio Isolate, mostrando la pantalla `QuickShareOverlay`.
3. **Restricciones:** Al ser un Isolate distinto, no comparte memoria ni la jerarquía de `Provider` principal; se comunica con el sistema central mediante canales o puertos (SendPort/ReceivePort) para inyectar descargas rápidamente sin abrir la interfaz completa de la aplicación principal.

## 5. Actualizaciones OTA (Over-The-Air)

Vidra incluye un gestor de actualizaciones integrado (`UpdateController`).

1. **Comprobación:** Consulta la API de GitHub Releases verificando la versión actual en contraposición a las versiones remotas.
2. **Pausa del Motor:** Si el usuario decide actualizar, la aplicación envía un comando `pause_for_update` al backend.
3. **Espera de Ack:** La UI espera confirmación (`paused_ack`) desde el Isolate para garantizar que no hay descriptores de archivos bloqueados ni descargas activas a medias.
4. **Instalación:** Procede con la descarga e instalación del nuevo paquete o ejecutable de Vidra.

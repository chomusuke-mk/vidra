# 🤖 Guía para Agentes de IA en Vidra

¡Bienvenido! Eres un agente de inteligencia artificial (IA) o asistente de código encargado de colaborar en el proyecto **Vidra**. Esta guía contiene las instrucciones, estándares y arquitectura del proyecto para que puedas empezar a trabajar de manera rápida y eficiente.

## 🎯 Objetivo General del Proyecto

**Vidra** es un gestor de descargas de video avanzado, multiplataforma (Android, Windows, Linux, macOS), construido con:

- **Frontend (Cliente):** Flutter (Dart) con enfoque en un diseño moderno, responsivo y usando principios de _Clean Architecture_.
- **Backend (Motor de descarga):** Python empaquetado como un proceso aislado (Isolate) usando `serious_python`. Utiliza internamente `yt-dlp` y `FFmpeg`/`QuickJS`.
- **Comunicación:** A través de una API REST HTTP local en un puerto dinámico y seguro.

---

## 📂 Estructura del Proyecto

El código está fuertemente separado entre el frontend (UI) y el backend (lógica de descarga). A continuación, se detallan los directorios clave:

- `/lib`: Contiene el código fuente en Dart/Flutter. Mantiene la separación de preocupaciones (UI, lógica de negocio/estado con `Provider`, servicios HTTP, manejo de archivos y modelos).
- `/app`: Contiene el código fuente del backend en Python y sus dependencias (`requirements/`).
- `/docs`: Documentación técnica detallada. **DEBES** consultar estos archivos cuando trabajes en características complejas.
  - `docs/system-architecture.md`: Detalles de cómo se comunica Flutter con el backend de Python.
  - `docs/client-flows.md`: Flujos principales de la UI y ciclo de vida de la app.
  - `docs/development-guide.md`: Guía de desarrollo, testing y _troubleshooting_.
- `/android`, `/windows`, `/linux`, `/macos`: Configuraciones nativas de las plataformas soportadas.
- `/.github/workflows`: Definición de los pipelines de CI/CD (GitHub Actions) para el empaquetado de dependencias nativas (como FFmpeg/QuickJS) y la automatización de _releases_.
- `/test` e `/integration_test`: Pruebas unitarias, de widgets y de integración en Dart.

---

## 📖 Orden de Lectura Sugerido

Antes de implementar modificaciones significativas, asegúrate de comprender la base de conocimiento del proyecto. Como agente, **debes priorizar leer estos archivos** utilizando tus herramientas de lectura:

1. **`README.md`**: Para entender cómo funciona el proyecto a alto nivel, cómo se compila y el rol de dependencias críticas como `serious_python`.
2. **`pubspec.yaml`**: Para conocer las dependencias de Dart disponibles en el proyecto (ej. `provider`, `dio`/`http`, `flutter_localizations`). ¡Usa lo que ya está instalado!
3. **`docs/system-architecture.md`** (Si vas a tocar la interacción entre Dart y Python): Para entender los puertos de la API local, encriptado de datos y cómo se sincroniza el progreso.
4. **`docs/development-guide.md`** (Si necesitas probar o compilar algo complejo): Para entender cómo manejar binarios nativos (FFmpeg, QuickJS) durante el entorno de desarrollo.

---

## 🛠️ Estándares y Convenciones de Código

### Frontend: Flutter / Dart (`/lib`)

- **Gestión de Estado:** Se usa el paquete `provider`. Respeta el flujo unidireccional. La UI consume _Providers_ y no almacena estado complejo de negocio internamente.
- **Internacionalización (i18n):** Cualquier texto visible en la interfaz debe estar localizado (archivos en el directorio `/i18n` y usando `flutter_localizations`). **Cero _strings hardcodeados_** en las vistas.
- **Diseño Adaptativo:** Vidra se ejecuta en móviles y escritorio. La UI debe adaptarse a múltiples resoluciones usando `LayoutBuilder`, `MediaQuery` o dependencias relacionadas. Sigue los lineamientos de diseño premium (esquemas oscuros, animaciones sutiles, fuentes modernas).
- **Manejo de Errores Asíncronos:** El backend es un ente separado; asume que las peticiones HTTP pueden fallar. Usa bloques `try/catch` de forma defensiva y maneja los estados visuales (carga, éxito, error).

### Backend: Python (`/app`)

- **Independencia Total:** El backend de Python ignora por completo la existencia de la UI. Su única interfaz es exponer un servicio API REST que la app consume localmente.
- **Respuestas Estandarizadas:** Retorna códigos de estado HTTP correctos (200, 400, 404, 500) y payloads JSON estructurados.
- **Rendimiento:** Evita bloquear el hilo principal. El proceso de descargas o conversión (`ffmpeg`) es intensivo, por lo que todo progreso debe reportarse asíncronamente o en intervalos para no colapsar la comunicación.

### Infraestructura y CI / CD

- **Sin Binarios Nativos Extra:** No subas binarios nativos precompilados de FFmpeg o QuickJS al repositorio. Estos son gestionados y descargados por GitHub Actions.
- **Modificación del Backend:** Si cambias la lógica en `/app`, asegúrate de que el empaquetado mediante el comando de `serious_python` no se rompa (se empaquetan en un archivo comprimido especial consumible por Flutter).

---

## 🚀 Flujo y Comandos Clave (CLI)

Como agente, puedes ejecutar scripts en bash si es necesario validar código (una vez el usuario haya aprobado tus cambios o si estás debugueando de forma segura).

- **Obtener dependencias (Dart):**
  `flutter pub get`
- **Empaquetar el Backend en Python (Ejemplo Windows):**
  `dart run serious_python:main package app/src -r -r -r app/requirements/base.txt -r -r -r app/requirements/Windows.txt -p Windows --verbose`
  _(Nota: Ajusta el archivo `.txt` y el target `-p` según el OS)_
- **Lanzar la app:**
  `flutter run -d <windows|linux|android>`
- **Ejecutar Pruebas Estáticas y Tests:**
  `dart analyze`
  `flutter test`

---

## 🤖 Reglas Generales de Comportamiento (Agente)

1. **Reutilización:** Antes de crear un nuevo componente, servicio o clase utilitaria, revisa `/lib` para ver si ya existe algo que resuelva la misma necesidad.
2. **Consistencia de APIs:** Si un usuario solicita un cambio en los parámetros que envía Python (API JSON), obligatoriamente debes ajustar el modelo y el servicio consumido en el lado de Dart (y viceversa).
3. **Planes de Ejecución (Planning Mode):** Si el cambio solicitado es muy grande (ej. un nuevo flujo completo, refactorización masiva o nueva página), debes **SIEMPRE** crear un plan de implementación detallado en un artefacto y esperar aprobación del usuario antes de empezar a programar.
4. **Dudas y Ambigüedades:** No adivines ni asumas. Si algo no queda claro, detente y pide aclaraciones al usuario mediante las herramientas correspondientes.

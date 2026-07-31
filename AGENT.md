# Entorno del Proyecto: Vidra

## Descripción General
**Vidra** es un gestor de vídeos y tareas diseñado para entornos de escritorio y dispositivos móviles. La aplicación se compone de una interfaz de usuario cliente desarrollada en **Flutter** y un servidor backend robusto y ligero desarrollado en **Python** (mantenido en un repositorio separado, pero integrado aquí para distribución). 

La comunicación principal entre el cliente y el backend en ejecución se realiza localmente mediante peticiones HTTP.

## Infraestructura y Arquitectura
La arquitectura sigue un patrón cliente-servidor, empaquetado conjuntamente para su distribución final:

1. **Cliente Flutter:** Interfaz gráfica moderna, con temas y soporte de localización para más de 150 idiomas.
2. **Backend Python:** Se encarga de la lógica pesada, la gestión de descargas y las actualizaciones. Utiliza herramientas externas críticas como `yt-dlp`, `FFmpeg`/`ffprobe`, y `quickjs`.
3. **Integración `serious_python`:** El código Python se empaqueta (dentro del archivo `app.zip`) y se lanza desde la aplicación Flutter utilizando el paquete `serious_python`.

```mermaid
graph TD
  A[Cliente Flutter (Dart)] <-->|Peticiones HTTP| B[Backend Python]
  subgraph Ecosistema Backend
    B <--> C[yt-dlp]
    C <--> D[FFmpeg/ffprobe]
    C --> E[quickjs]
    C --> F[yt-dlp-ejs]
  end
```

## Estructura de Directorios

A continuación se detalla el objetivo de las principales carpetas y archivos del proyecto:

### Frontend (Flutter / Dart)
- **`lib/`**: Código fuente principal de la aplicación cliente en Flutter. Sigue una arquitectura modular o limpia:
  - **`lib/core/`**: Lógica principal, servicios y configuraciones transversales.
  - **`lib/features/`**: Módulos y pantallas de la aplicación, agrupados por funcionalidad.
  - **`lib/shared/`**: Componentes visuales y utilidades reutilizables.
- **`test/`**: Pruebas unitarias, de widgets y pruebas de integración (smoke test) de Flutter.
- **`assets/`**: Archivos estáticos como iconos de la aplicación, plantillas `.env` y otros recursos declarados en `pubspec.yaml`.
- **`i18n/`**: Archivos de localización (traducciones) organizados por código ISO de idioma.
- **`android/`, `windows/`, `linux/`, `macos/`, `ios/`**: Directorios específicos de plataforma generados por Flutter. Aquí es también donde se deben colocar los ejecutables pre-compilados dependientes de la arquitectura (`ffmpeg`, `ffprobe`, `quickjs`) antes de empaquetar la app.

### Backend Integrado (Python)
- **`app/`**: Contiene la estructura base del backend de Python y sus dependencias (`requirements.txt`).
  - **`app/src/`**: Carpeta fuente del script/proyecto de Python.
  - *Nota: Durante la etapa de empaquetado, este contenido se comprime en `app.zip` usando el CLI de `serious_python`, para luego ser inyectado como un activo binario en el cliente Flutter.*

### Herramientas y Metadatos
- **`tools/`** (o `tool/`): Scripts de automatización interna (por ejemplo, scripts para sincronización o traducción de idiomas).
- **`third_party_licenses/`**: Documentación de licencias de dependencias y binarios de terceros (requerido por GPL y otros términos de distribución).
- **`pubspec.yaml`**: Archivo fundamental de Flutter y Dart. Define dependencias de paquetes (como `serious_python`, `provider`, `dio`, etc.), versión de la app, y registro de activos.

## Flujo de Trabajo de Empaquetado
Para construir y distribuir este entorno, el flujo normal es:
1. **Instalación de dependencias del UI:** `flutter pub get`
2. **Empaquetado del Backend:** Ejecución del comando de `serious_python` en `app/` para crear `app/app.zip` junto con su hash.
3. **Colocación de Binarios:** Asegurar de que `ffmpeg`, `ffprobe`, y `quickjs` (y sus librerías correspondientes compartidas para Android/Linux) estén insertados en sus respectivas rutas de plataforma.
4. **Construcción del Artefacto Final:** `flutter build windows` (o linux, apk, etc.).

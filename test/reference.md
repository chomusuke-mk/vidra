lib/
├── core/                   # Todo lo que es transversal y compartido en la app
│   ├── constants/          # Constantes globales, URLs, claves
│   ├── errors/             # Clases de excepciones y fallos personalizados
│   ├── native/             # Bindings FFI o Platform Channels (ej. para integrar binarios como FFmpeg)
│   ├── network/            # Clientes HTTP, interceptores
│   ├── theme/              # Paletas de colores, tipografías, ThemeData
│   └── utils/              # Funciones de ayuda generales
│
├── features/               # El corazón de la app, dividido por dominios independientes
│   ├── video_processing/   # Ejemplo de una funcionalidad principal
│   │   ├── data/           # Modelos de datos, repositorios y fuentes (API, DB local)
│   │   ├── domain/         # Lógica de negocio pura (Entidades, Casos de uso)
│   │   └── presentation/   # UI: Pantallas, Widgets específicos y State Management
│   │
│   ├── authentication/     # Otra funcionalidad aislada
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   └── settings/           # Configuraciones del usuario
│
├── shared/                 # Componentes visuales genéricos (botones, modales) que se usan en múltiples features
│   └── widgets/
│
├── app.dart                # Configuración de MaterialApp/CupertinoApp, rutas, temas
└── main.dart               # Punto de entrada, inicialización de dependencias
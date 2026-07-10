import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

class AppTutorialKeys {
  // Llaves de la pantalla de Sistema (Ya existían)
  static final systemBackend = GlobalKey();
  static final systemUpdates = GlobalKey();

  // Llaves de la pantalla Principal
  static final mainSystemStatus = GlobalKey();
  static final mainUrlBar = GlobalKey();
  static final mainFilter = GlobalKey();
  static final mainSettings = GlobalKey();

  // Llaves de la pantalla de Configuración
  static final settingsTabs = GlobalKey();
  static final settingsSearch = GlobalKey();
}

class TutorialUtils {
  // =========================================================================
  // TUTORIAL: PANTALLA PRINCIPAL
  // =========================================================================
  static Future<void> showMainAppTutorial(
    BuildContext context, {
    bool force = false,
  }) async {
    final prefs = context.read<SharedPreferences>();
    final hasSeen = prefs.getBool('has_seen_main_tutorial') ?? false;
    if (hasSeen && !force) return;

    if (!context.mounted) return;

    final targets = [
      TargetFocus(
        identify: "main_system",
        keyTarget: AppTutorialKeys.mainSystemStatus,
        alignSkip: Alignment.bottomRight,
        shape: ShapeLightFocus.Circle,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => _TutorialText(
              title: "Estado del Motor",
              description:
                  "Este icono te indica si el servidor interno está listo. Si tienes problemas, toca aquí para ver los errores o revisar los módulos.",
              controller: controller,
              nextKey: AppTutorialKeys.mainUrlBar,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "main_url",
        keyTarget: AppTutorialKeys.mainUrlBar,
        alignSkip: Alignment.bottomRight,
        shape: ShapeLightFocus.RRect,
        radius: 8,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => _TutorialText(
              title: "Descargar Contenido",
              description:
                  "Pega el enlace del video o playlist aquí. Al presionar el botón de descarga, se usará la calidad y formato que hayas elegido en tu configuración.",
              controller: controller,
              nextKey: AppTutorialKeys.mainFilter,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "main_filter",
        keyTarget: AppTutorialKeys.mainFilter,
        alignSkip: Alignment.bottomLeft,
        shape: ShapeLightFocus.Circle,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => _TutorialText(
              title: "Filtros y Búsqueda",
              description:
                  "Despliega este menú para buscar descargas por nombre o filtrar entre videos individuales y listas de reproducción.",
              controller: controller,
              nextKey: AppTutorialKeys.mainSettings,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "main_settings",
        keyTarget: AppTutorialKeys.mainSettings,
        alignSkip: Alignment.bottomLeft,
        shape: ShapeLightFocus.Circle,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => _TutorialText(
              title: "Ajustes Avanzados",
              description:
                  "Entra aquí para configurar resoluciones por defecto, inyectar metadatos, usar proxies o añadir subtítulos automáticos.",
              controller: controller,
              isLast: true,
            ),
          ),
        ],
      ),
    ];

    _showTutorial(context, targets, 'has_seen_main_tutorial');
  }

  // =========================================================================
  // TUTORIAL: PANTALLA DE CONFIGURACIÓN
  // =========================================================================
  static Future<void> showSettingsTutorial(
    BuildContext context, {
    bool force = false,
  }) async {
    final prefs = context.read<SharedPreferences>();
    final hasSeen = prefs.getBool('has_seen_settings_tutorial') ?? false;
    if (hasSeen && !force) return;

    if (!context.mounted) return;

    final isWideScreen = MediaQuery.of(context).size.width >= 600;

    final targets = [
      TargetFocus(
        identify: "settings_tabs",
        keyTarget: AppTutorialKeys.settingsTabs,
        alignSkip: Alignment.topRight,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        contents: [
          TargetContent(
            align: isWideScreen ? ContentAlign.right : ContentAlign.bottom,
            builder: (context, controller) => _TutorialText(
              title: "Categorías",
              description:
                  "La configuración está dividida en General, Red (Proxies, Cookies), Video (Formatos, Subtítulos) y Descarga (Rutas, Nombres).",
              controller: controller,
              nextKey: AppTutorialKeys.settingsSearch,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "settings_search",
        keyTarget: AppTutorialKeys.settingsSearch,
        alignSkip: Alignment.bottomLeft,
        shape: ShapeLightFocus.Circle,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => _TutorialText(
              title: "Búsqueda Rápida",
              description:
                  "Hay decenas de opciones. Si no encuentras algo específico (ej. 'Proxy' o 'Subtítulos'), usa el buscador para filtrar la lista al instante.",
              controller: controller,
              isLast: true,
            ),
          ),
        ],
      ),
    ];

    _showTutorial(context, targets, 'has_seen_settings_tutorial');
  }

  // =========================================================================
  // TUTORIAL: PANTALLA DE SISTEMA (El que ya teníamos)
  // =========================================================================
  static Future<void> showSystemTutorial(
    BuildContext context, {
    bool force = false,
  }) async {
    final prefs = context.read<SharedPreferences>();
    final hasSeen = prefs.getBool('has_seen_system_tutorial') ?? false;

    if (hasSeen && !force) return;

    if (AppTutorialKeys.systemBackend.currentContext != null) {
      await Scrollable.ensureVisible(
        AppTutorialKeys.systemBackend.currentContext!,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
      await Future.delayed(const Duration(milliseconds: 150));
    }

    if (!context.mounted) return;

    final targets = [
      TargetFocus(
        identify: "backend_status",
        keyTarget: AppTutorialKeys.systemBackend,
        alignSkip: Alignment.topLeft,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => _TutorialText(
              title: "Servidor Python",
              description:
                  "Vidra utiliza un servidor local para procesar las descargas. Aquí puedes verificar que esté corriendo y revisar sus logs en caso de error.",
              controller: controller,
              nextKey: AppTutorialKeys.systemUpdates,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "system_updates",
        keyTarget: AppTutorialKeys.systemUpdates,
        alignSkip: Alignment.topLeft,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) => _TutorialText(
              title: "Módulos y Motores",
              description:
                  "Mantén yt-dlp y los parches actualizados para asegurar la compatibilidad con las páginas soportadas. Puedes cambiar de canal si buscas versiones experimentales.",
              controller: controller,
              isLast: true,
            ),
          ),
        ],
      ),
    ];

    _showTutorial(context, targets, 'has_seen_system_tutorial');
  }

  // --- Método privado para no repetir la lógica de inicialización del paquete ---
  static void _showTutorial(
    BuildContext context,
    List<TargetFocus> targets,
    String prefsKey,
  ) {
    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      opacityShadow: 0.85,
      hideSkip: true,
      paddingFocus: 10,
      onClickOverlay: (target) {},
      onFinish: () async {
        final prefs = context.read<SharedPreferences>();
        await prefs.setBool(prefsKey, true);
      },
      onSkip: () {
        final prefs = context.read<SharedPreferences>();
        prefs.setBool(prefsKey, true);
        return true;
      },
    ).show(context: context);
  }
}

class _TutorialText extends StatelessWidget {
  final String title;
  final String description;
  final TutorialCoachMarkController controller;
  final bool isLast;
  final GlobalKey? nextKey;

  const _TutorialText({
    required this.title,
    required this.description,
    required this.controller,
    this.isLast = false,
    this.nextKey,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          description,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            shadows: [
              Shadow(
                blurRadius: 2.0,
                color: Colors.black54,
                offset: Offset(1.0, 1.0),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (!isLast)
              TextButton(
                onPressed: () => controller.skip(),
                child: const Text(
                  'Saltar',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            const SizedBox(width: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              onPressed: () async {
                if (isLast) {
                  controller.skip();
                } else {
                  if (nextKey != null && nextKey!.currentContext != null) {
                    await Scrollable.ensureVisible(
                      nextKey!.currentContext!,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                      alignment: 0.5,
                    );
                    await Future.delayed(const Duration(milliseconds: 150));
                  }
                  controller.next();
                }
              },
              child: Text(isLast ? 'Entendido' : 'Siguiente'),
            ),
          ],
        ),
      ],
    );
  }
}

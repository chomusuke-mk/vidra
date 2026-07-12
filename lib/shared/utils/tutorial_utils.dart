import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';

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
    final locale = context.read<LocaleController>().localeStrings;
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
              title: locale.tuPPEngineState,
              description: locale.tuPPEngineStateDesc,
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
              title: locale.tuPPDownload,
              description: locale.tuPPDownloadDesc,
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
              title: locale.tuPPFilters,
              description: locale.tuPPFiltersDesc,
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
              title: locale.tuPPSettings,
              description: locale.tuPPSettingsDesc,
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
    final locale = context.read<LocaleController>().localeStrings;
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
              title: locale.tuPSCategories,
              description: locale.tuPSCategoriesDesc,
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
              title: locale.tuPSSearch,
              description: locale.tuPSSearchDesc,
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
    final locale = context.read<LocaleController>().localeStrings;
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
              title: locale.tuPSDPythonServer,
              description: locale.tuPSDPythonServerDesc,
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
              title: locale.tuPSDModulesUpdates,
              description: locale.tuPSDModulesUpdatesDesc,
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
    final locale = context.read<LocaleController>().localeStrings;
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
                child: Text(
                  locale.tuSkip,
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
              child: Text(isLast ? locale.tuUnderstood : locale.tuNext),
            ),
          ],
        ),
      ],
    );
  }
}

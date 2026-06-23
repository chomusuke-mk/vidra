import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:vidra/app.dart';
import 'package:vidra/core/network/github_client.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';
import 'core/network/vidra_http_client.dart';
import 'features/downloads/data/download_repository.dart';
import 'features/downloads/presentation/downloads_controller.dart';
import 'features/settings/data/settings_repository.dart';
import 'features/settings/presentation/settings_controller.dart';
import 'package:vidra/shared/utils/notification_service.dart';
import 'package:vidra/features/downloads/presentation/overlay_main.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sharedPreferences = await SharedPreferences.getInstance();
  await NotificationService.init();
  runApp(
    MultiProvider(
      providers: [
        // =====================================================================
        // CAPA 1: INFRAESTRUCTURA BASE
        // =====================================================================
        ChangeNotifierProvider<SystemController>(
          create: (_) => SystemController(),
        ),
        // =====================================================================
        // CAPA 2: INFRAESTRUCTURA BASE (Red y Almacenamiento local)
        // =====================================================================
        Provider<GithubClient>(create: (_) => GithubClient()),
        // El Cliente HTTP ahora escucha al cerebro.
        ProxyProvider<SystemController, VidraHttpClient>(
          create: (_) => VidraHttpClient(
            baseUrl: 'http://127.0.0.1:5000', // Valor inicial de descarte
            defaultHeaders: {},
            token: null,
          ),
          update: (_, systemCtrl, client) {
            // MUTACIÓN EN CALIENTE: Actualizamos las propiedades sin destruir el objeto.
            // Si el puerto aún no existe, usamos 5000 por defecto.
            client!.baseUrl =
                'http://127.0.0.1:${systemCtrl.backendPort ?? 5000}';
            client.token = systemCtrl.backendToken;
            return client;
          },
        ),
        Provider<SettingsRepository>(
          create: (_) => SettingsRepository(sharedPreferences),
        ),
        Provider<LocaleRepository>(create: (_) => LocaleRepository()),
        Provider<SharedPreferences>.value(value: sharedPreferences),
        // =====================================================================
        // CAPA 3: REPOSITORIOS DEPENDIENTES
        // =====================================================================
        ProxyProvider<VidraHttpClient, DownloadRepository>(
          update: (_, client, prev) => prev ?? DownloadRepository(client),
        ),
        // =====================================================================
        // CAPA 4: CONTROLADORES DE ESTADO (Gestión de la UI)
        // =====================================================================
        ChangeNotifierProxyProvider<SettingsRepository, SettingsController>(
          create: (context) =>
              SettingsController(context.read<SettingsRepository>()),
          update: (_, repo, prev) => prev ?? SettingsController(repo),
        ),
        ChangeNotifierProxyProvider2<
          LocaleRepository,
          SettingsController,
          LocaleController
        >(
          create: (context) => LocaleController(
            context.read<LocaleRepository>(),
            context.read<SettingsController>().appLanguage,
          ),
          update: (context, repo, settings, prev) {
            final currentLang = settings.appLanguage;
            if (prev != null && prev.currentLocaleCode != currentLang) {
              prev.setLocale(currentLang);
            }

            return prev ?? LocaleController(repo, currentLang);
          },
        ),
        // Nuestro Controlador de Descargas escucha al Sistema (Para encolar) y al Repositorio (Para ejecutar)
        ChangeNotifierProxyProvider2<
          DownloadRepository,
          SystemController,
          DownloadsController
        >(
          create: (context) => DownloadsController(
            context.read<DownloadRepository>(),
            context.read<SystemController>(),
          ),
          update: (_, repo, systemCtrl, prev) =>
              prev ?? DownloadsController(repo, systemCtrl),
        ),
        ChangeNotifierProxyProvider3<
          GithubClient,
          SystemController,
          SharedPreferences,
          UpdateController
        >(
          create: (context) => UpdateController(
            context.read<GithubClient>(),
            context.read<SystemController>(),
            context.read<SharedPreferences>(),
          ),
          update: (_, github, system, prefs, prev) =>
              prev ?? UpdateController(github, system, prefs),
        ),
      ],
      child: const App(),
    ),
  );
}

// ============================================================================
// PUNTO DE ENTRADA DEL ISOLATE (OVERLAY WINDOW)
// ============================================================================
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      home: const QuickShareOverlay(),
    ),
  );
}

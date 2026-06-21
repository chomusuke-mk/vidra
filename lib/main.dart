import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:vidra/app.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'core/network/vidra_http_client.dart';
import 'features/downloads/data/download_repository.dart';
import 'features/downloads/presentation/downloads_controller.dart';
import 'features/settings/data/settings_repository.dart';
import 'features/settings/presentation/settings_controller.dart';
import 'package:vidra/shared/utils/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  final sharedPreferences = await SharedPreferences.getInstance();
  await NotificationService.init();

  // ! TAL VEZ BORRAR LO SIGUIENTE
  /*
  final backendConfig = BackendConfig.fromEnv();
  final notificationManager = DownloadNotificationManager(
    languageResolver: () => preferencesModel.effectiveLanguage,
  );
  await notificationManager.initialize();

  unawaited(AppUpdateBootstrapper().run());
  final appLifecycleObserver = AppLifecycleObserver();

  final dataDir = await getApplicationSupportDirectory();
  final cacheDir = await getApplicationCacheDirectory();

  final pythonLauncher = SeriousPythonServerLauncher.instance;

  final downloadController = DownloadController(
    backendConfig: backendConfig,
    authToken: backendAuthToken.value,
    backendStateListenable: pythonLauncher.state,
    notificationManager: notificationManager,
    languageResolver: () => preferencesModel.effectiveLanguage,
    appLifecycleObserver: appLifecycleObserver,
  );

  pythonLauncher.launchInfo.addListener(() {
    final token = pythonLauncher.launchInfo.value?.token;
    if (token != null && token.trim().isNotEmpty) {
      downloadController.updateAuthToken(token);
    }
  });

  unawaited(
    pythonLauncher
        .ensureStarted(
          extraEnvironment: {
            'APP_ENV': "development",
            'API_TOKEN': "1234567890abcdef",
            'HOST': "",
            'PORT': 'info',
            'LOGS_PATH': p.join(cacheDir.path, 'backend', "logs"),
            'DATA_PATH': p.join(dataDir.path, 'backend'),
            'TEMP_PATH': p.join(cacheDir.path, 'backend'),
          },
        )
        .catchError((error, stackTrace) {
          debugPrint('Serious Python launcher error: $error');
          debugPrint(stackTrace.toString());
        }),
  );
  */
  runApp(
    MultiProvider(
      providers: [
        // =====================================================================
        // CAPA 1: INFRAESTRUCTURA BASE
        // =====================================================================
        Provider<VidraHttpClient>(
          create: (_) => VidraHttpClient(
            baseUrl: 'http://localhost:5000', // Reemplaza con tu URL o IP
            defaultHeaders: {},
            token: null,
          ),
        ),
        Provider<SettingsRepository>(
          create: (_) => SettingsRepository(sharedPreferences),
        ),
        Provider<LocaleRepository>(create: (_) => LocaleRepository()),
        // =====================================================================
        // CAPA 2: REPOSITORIOS DEPENDIENTES
        // =====================================================================
        ProxyProvider<VidraHttpClient, DownloadRepository>(
          update: (_, client, _) => DownloadRepository(client),
        ),
        // =====================================================================
        // CAPA 3: CONTROLADORES DE ESTADO (Gestión de la UI)
        // =====================================================================
        // Settings Controller (Se inicializa primero porque tiene el idioma guardado)
        ChangeNotifierProxyProvider<SettingsRepository, SettingsController>(
          create: (context) =>
              SettingsController(context.read<SettingsRepository>()),
          update: (_, repo, prev) => prev ?? SettingsController(repo),
        ),
        // Locale Controller (El pegamento mágico: Escucha a SettingsController)
        ChangeNotifierProxyProvider2<
          LocaleRepository,
          SettingsController,
          LocaleController
        >(
          create: (context) => LocaleController(
            context.read<LocaleRepository>(),
            context
                .read<SettingsController>()
                .appLanguage, // Le inyectamos el idioma inicial
          ),
          update: (context, repo, settings, prev) {
            final currentLang = settings.appLanguage;

            // Si el controlador ya existía y el usuario cambió el idioma en Settings,
            // le avisamos para que descargue y fusione el nuevo JSON.
            if (prev != null && prev.currentLocaleCode != currentLang) {
              prev.setLocale(currentLang);
            }

            return prev ?? LocaleController(repo, currentLang);
          },
        ),
        // Downloads Controller
        ChangeNotifierProxyProvider<DownloadRepository, DownloadsController>(
          create: (context) =>
              DownloadsController(context.read<DownloadRepository>()),
          update: (_, repo, prev) => prev ?? DownloadsController(repo),
        ),
        // ! TAL VEZ BORRAR LO SIGUIENTE
        /*
        Provider<BackendConfig>.value(value: backendConfig),
        ChangeNotifierProvider<PreferencesModel>.value(value: preferencesModel),
        ChangeNotifierProvider<AppLifecycleObserver>.value(
          value: appLifecycleObserver,
        ),
        Provider<DownloadNotificationManager>.value(value: notificationManager),
        ChangeNotifierProvider<InitialPermissionsController>(
          create: (_) => InitialPermissionsController(),
        ),
        ChangeNotifierProvider<DownloadController>.value(
          value: downloadController,
        ),
        ChangeNotifierProvider<PendingDownloadInbox>(
          create: (_) {
            final inbox = PendingDownloadInbox();
            unawaited(inbox.pullFromNative());
            return inbox;
          },
        ),
        ProxyProvider3<
          DownloadController,
          PreferencesModel,
          PendingDownloadInbox,
          ShareIntentCoordinator
        >(
          update: (_, downloadController, prefsModel, pendingInbox, previous) {
            final coordinator =
                previous ??
                ShareIntentCoordinator(
                  downloadController: downloadController,
                  preferencesModel: prefsModel,
                  pendingDownloadInbox: pendingInbox,
                  notificationManager: notificationManager,
                );
            if (!coordinator.isInitialized) {
              coordinator.initialize();
            }
            return coordinator;
          },
          dispose: (_, coordinator) => coordinator.dispose(),
        ),
        */
      ],
      child: const App(),
    ),
  );
}

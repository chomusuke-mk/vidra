import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:vidra/config/backend_auth_token.dart';
import 'package:vidra/config/backend_config.dart';
import 'package:vidra/i18n/i18n.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/share/share_intent_coordinator.dart';
import 'package:vidra/state/app_lifecycle_observer.dart';
import 'package:vidra/state/app_update_bootstrapper.dart';
import 'package:vidra/state/download_controller.dart';
import 'package:vidra/state/initial_permissions_controller.dart';
import 'package:vidra/state/notifications/download_notification_manager.dart';
import 'package:vidra/state/pending_download_inbox.dart';
import 'package:vidra/state/serious_python_server_launcher.dart';
import 'package:vidra/ui/screens/home/home_screen.dart';
import 'package:vidra/ui/screens/settings/settings_screen.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  I18n.configure(fallbackLocale: dotenv.maybeGet('FALLBACK_LANGUAGE'));
  await I18n.preloadAll();
  final backendConfig = BackendConfig.fromEnv();
  final backendAuthToken = BackendAuthToken.resolve(dotenv);
  final preferencesModel = PreferencesModel();
  final preferenceLocalizations = I18n.preferenceLocalizations();
  await preferencesModel.initializePreferences(
    localizedPreferences: preferenceLocalizations,
  );
  if (kDebugMode) {
    debugPrint(
      'FFmpeg bootstrap: resolvedExecutable=${Platform.resolvedExecutable}',
    );
    final ffmpegPath = await preferencesModel.preferences
        .ensureBundledFfmpegLocation();
    debugPrint('FFmpeg bootstrap: ffmpeg_location=$ffmpegPath');
  }
  final notificationManager = DownloadNotificationManager(
    languageResolver: () => preferencesModel.effectiveLanguage,
  );
  await notificationManager.initialize();

  unawaited(AppUpdateBootstrapper().run());
  final appLifecycleObserver = AppLifecycleObserver();

  final supportDir = await getApplicationSupportDirectory();
  final cacheDir = await getApplicationCacheDirectory();
  final backendDataDir = p.join(supportDir.path, 'backend');
  final backendStatusFile = p.join(backendDataDir, 'startup_status.json');
  final backendLockFile = p.join(backendDataDir, 'vidra.start.lock');
  final backendLogFile = p.join(backendDataDir, 'release_logs.txt');

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
            'VIDRA_SERVER_TOKEN': backendAuthToken.value,
            'VIDRA_SERVER_DATA': backendDataDir,
            'VIDRA_SERVER_CACHE': p.join(cacheDir.path, 'backend'),
            'VIDRA_SERVER_LOG_LEVEL': 'info',
            'VIDRA_ENABLE_PREVIEW_API': '0',
            'VIDRA_SERVER_DEBUG': '1',
            'VIDRA_SERVER_VERBOSE': '1',
            'VIDRA_SERVER_STATUS_FILE': backendStatusFile,
            'VIDRA_SERVER_LOCK_FILE': backendLockFile,
            'VIDRA_SERVER_LOG_FILE': backendLogFile,
          },
        )
        .catchError((error, stackTrace) {
          debugPrint('Serious Python launcher error: $error');
          debugPrint(stackTrace.toString());
        }),
  );

  runApp(
    MultiProvider(
      providers: [
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
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  ShareIntentCoordinator? _shareCoordinator;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final coordinator = context.read<ShareIntentCoordinator>();
    if (_shareCoordinator != coordinator) {
      _shareCoordinator?.detachNavigatorKey(_navigatorKey);
      _shareCoordinator = coordinator;
      coordinator.attachNavigatorKey(_navigatorKey);
    }
  }

  @override
  void dispose() {
    _shareCoordinator?.detachNavigatorKey(_navigatorKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preferencesModel = context.watch<PreferencesModel>();
    final isDark = preferencesModel.isDarkModeEnabled;
    final backendConfig = context.read<BackendConfig>();
    final appLocale = _localeFromCode(preferencesModel.effectiveLanguage);

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: backendConfig.name,
      locale: appLocale,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      initialRoute: '/',
      localizationsDelegates: [
        VidraLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        LocaleNamesLocalizationsDelegate(),
      ],
      supportedLocales: VidraLocalizations.supportedLocales,
      routes: {
        '/': (context) => const HomeScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}

Locale _localeFromCode(String code) {
  final safeCode = code.trim().isEmpty ? 'en' : code;
  final segments = safeCode
      .split(RegExp('[-_]'))
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);
  if (segments.isEmpty) {
    return const Locale('en');
  }
  if (segments.length == 1) {
    return Locale(segments.first.toLowerCase());
  }
  if (segments.length == 2) {
    return Locale(segments[0].toLowerCase(), segments[1].toUpperCase());
  }
  return Locale.fromSubtags(
    languageCode: segments[0].toLowerCase(),
    scriptCode: segments[1],
    countryCode: segments[2].toUpperCase(),
  );
}

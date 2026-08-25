import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/core/network/vidra_http_client.dart';
import 'package:vidra/core/theme/app_theme.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/system/presentation/system_details_screen.dart';
import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _MockHttpClient();
  }
}

class _MockHttpClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();
  @override
  bool autoUncompress = true;
}

class _MockHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();
  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
}

class _MockHttpHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _MockHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  int get contentLength => 0;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final transparentPng = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ];
    return Stream<List<int>>.value(transparentPng).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class TestSystemController extends ChangeNotifier
    with WidgetsBindingObserver
    implements SystemController {
  SystemState _state = SystemState.ready;
  @override
  SystemState get state => _state;

  void setState(SystemState s) {
    _state = s;
    notifyListeners();
  }

  @override
  int? get backendPort => 5000;
  @override
  String? get backendToken => 'test_token';
  @override
  String? get serverLogsFilePath => '/tmp/test_server_logs.log';
  @override
  Future<void> get whenPortReady => Future.value();
  @override
  Future<void> stopBackendForUpdate() async {}
  @override
  Future<void> resumeInitialization() async {}
  @override
  void enqueueDownload(String url, Map<String, dynamic> options) {}
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}
}

class TestUpdateController extends ChangeNotifier implements UpdateController {
  @override
  bool get hasAvailableUpdates => false;
  @override
  bool get hasShownSessionUpdateBubble => false;
  @override
  bool get isAutoDownloadingMissing => false;
  @override
  double get missingModulesProgress => 0.0;
  @override
  bool get isCheckingUpdates => false;
  @override
  bool get hasPendingChecks => false;

  @override
  void markSessionUpdateBubbleShown() {}

  @override
  UpdateState getState(ComponentType type) {
    return UpdateState(
      status: ComponentStatus.upToDate,
      version: '1.0.0',
    );
  }

  @override
  Future<bool> checkForUpdates(
      {bool manualCall = true, ComponentType? specificType}) async {
    return false;
  }

  @override
  Future<void> downloadAndInstall(ComponentType type) async {}

  @override
  Future<bool> downloadAndInstallInternal(ComponentType type, UpdateInfo info,
          {Function(double progress)? onDownloadProgress,
          bool manageBackendLifecycle = true}) async =>
      true;

  @override
  Future<void> retryMissingModulesDownload() async {}

  @override
  LinuxPackageType getLinuxPackageType() => LinuxPackageType.deb;
}

class TestVidraHttpClient extends Fake implements VidraHttpClient {
  @override
  Future<String> getLogs({String? id}) async => 'Mock App Logs Output';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _MockHttpOverrides();

  late LocaleController localeCtrl;
  late TestSystemController testSystemCtrl;
  late TestUpdateController testUpdateCtrl;
  late TestVidraHttpClient testHttpClient;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'locale': 'es',
      'has_seen_system_tutorial': true,
      'has_seen_main_tutorial': true,
    });
    prefs = await SharedPreferences.getInstance();
    localeCtrl = LocaleController(LocaleRepository(), 'es');

    testSystemCtrl = TestSystemController();
    testUpdateCtrl = TestUpdateController();
    testHttpClient = TestVidraHttpClient();
  });

  Widget buildThemedApp({
    ThemeData? theme,
    required Widget child,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
        ChangeNotifierProvider<SystemController>.value(value: testSystemCtrl),
        ChangeNotifierProvider<UpdateController>.value(value: testUpdateCtrl),
        Provider<VidraHttpClient>.value(value: testHttpClient),
        Provider<SharedPreferences>.value(value: prefs),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        home: Scaffold(
          body: child,
        ),
      ),
    );
  }

  group('R2: SystemDetailsScreen Fit-Content BottomSheet Layout', () {
    testWidgets('SystemDetailsScreen.show displays fit-content modal bottom sheet', (tester) async {
      await tester.pumpWidget(
        buildThemedApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => SystemDetailsScreen.show(context),
              child: const Text('Open System Details'),
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap to open
      await tester.tap(find.text('Open System Details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Expect SystemDetailsScreen is mounted
      expect(find.byType(SystemDetailsScreen), findsOneWidget);

      // Verify fit-content structure: ClipRRect with surfaceContainer
      expect(find.byType(ClipRRect), findsWidgets);
      expect(find.byType(SingleChildScrollView), findsOneWidget);

      // Verify close button pops dialog
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(SystemDetailsScreen), findsNothing);
    });

    testWidgets('SystemDetailsScreen root Column uses MainAxisSize.min and SingleChildScrollView is flexible', (tester) async {
      await tester.pumpWidget(
        buildThemedApp(
          child: const SystemDetailsScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Root column uses MainAxisSize.min
      final columnFinder = find.descendant(
        of: find.byType(ConstrainedBox),
        matching: find.byType(Column),
      );
      expect(columnFinder, findsWidgets);
      final Column rootColumn = tester.widget(columnFinder.first);
      expect(rootColumn.mainAxisSize, equals(MainAxisSize.min));

      // Flexible wrapping SingleChildScrollView
      expect(find.byType(Flexible), findsWidgets);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });

  group('R3: User-Friendly Engine Status Texts with i18n', () {
    testWidgets('SystemState.ready displays localized "Motor de aplicaciones: conectado" and "Todo esta funcionando normalmente" in Spanish', (tester) async {
      testSystemCtrl.setState(SystemState.ready);
      localeCtrl.setLocale('es');

      await tester.pumpWidget(
        buildThemedApp(
          child: const SystemDetailsScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Motor de aplicaciones: conectado'), findsOneWidget);
      expect(find.text('Todo esta funcionando normalmente'), findsOneWidget);
      expect(find.textContaining('Puerto:'), findsNothing);
    });

    testWidgets('SystemState.ready displays localized "App Engine: Connected" and "Everything is running normally" in English', (tester) async {
      testSystemCtrl.setState(SystemState.ready);
      localeCtrl.setLocale('en');

      await tester.pumpWidget(
        buildThemedApp(
          child: const SystemDetailsScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('App Engine: Connected'), findsOneWidget);
      expect(find.text('Everything is running normally'), findsOneWidget);
      expect(find.textContaining('Puerto:'), findsNothing);
    });

    testWidgets('Degraded states display friendly localized titles and subtitles', (tester) async {
      localeCtrl.setLocale('es');

      // 1. startingBackend
      testSystemCtrl.setState(SystemState.startingBackend);
      await tester.pumpWidget(buildThemedApp(child: const SystemDetailsScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('App Engine: Iniciando...'), findsOneWidget);

      // 2. initializing
      testSystemCtrl.setState(SystemState.initializing);
      await tester.pumpWidget(buildThemedApp(child: const SystemDetailsScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('App Engine: inicializando...'), findsOneWidget);

      // 3. retrying
      testSystemCtrl.setState(SystemState.retrying);
      await tester.pumpWidget(buildThemedApp(child: const SystemDetailsScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('App Engine: Reconectando...'), findsOneWidget);

      // 4. missingPermissions
      testSystemCtrl.setState(SystemState.missingPermissions);
      await tester.pumpWidget(buildThemedApp(child: const SystemDetailsScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('App Engine: permisos necesarios'), findsOneWidget);

      // 5. missingResources
      testSystemCtrl.setState(SystemState.missingResources);
      await tester.pumpWidget(buildThemedApp(child: const SystemDetailsScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('App Engine: componentes faltantes'), findsOneWidget);

      // 6. fatalError
      testSystemCtrl.setState(SystemState.fatalError);
      await tester.pumpWidget(buildThemedApp(child: const SystemDetailsScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Motor de aplicaciones: error'), findsOneWidget);
    });

    testWidgets('Logs action buttons use localized strings instead of hardcoded raw text', (tester) async {
      localeCtrl.setLocale('es');
      testSystemCtrl.setState(SystemState.ready);

      await tester.pumpWidget(
        buildThemedApp(
          child: const SystemDetailsScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final locale = localeCtrl.localeStrings;
      expect(find.text(locale.sdAppLogs), findsOneWidget);
      expect(find.text(locale.sdPythonServerLogs), findsOneWidget);
    });
  });

  group('R4: Official Component Logo Assets', () {
    testWidgets('Update cards render official logo images for Vidra App, yt-dlp, and EJS', (tester) async {
      await tester.pumpWidget(
        buildThemedApp(
          child: const SystemDetailsScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Find Image widgets in update cards
      final imageWidgets = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(imageWidgets.length, equals(3));

      // Verify asset providers
      final assetImages = imageWidgets.map((img) => img.image).whereType<AssetImage>().toList();
      expect(assetImages.length, equals(3));

      final assetNames = assetImages.map((img) => img.assetName).toList();
      expect(assetNames, contains('assets/icon/icon.png'));
      expect(assetNames, contains('assets/icon/yt-dlp.png'));
      expect(assetNames, contains('assets/icon/javascript.png'));

      // Verify dimensions (width: 24, height: 24)
      for (final img in imageWidgets) {
        expect(img.width, equals(24));
        expect(img.height, equals(24));
      }
    });
  });
}

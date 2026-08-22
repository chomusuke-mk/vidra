import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/core/network/github_client.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/system/presentation/widgets/system_status_update_bubble.dart';
import 'package:vidra/features/updates/domain/update_info.dart';
import 'package:vidra/features/updates/presentation/update_controller.dart';

class FakeSystemController extends ChangeNotifier
    with WidgetsBindingObserver
    implements SystemController {
  @override
  SystemState get state => SystemState.ready;
  @override
  int? get backendPort => 5000;
  @override
  String? get backendToken => 'test_token';
  @override
  String? get serverLogsFilePath => '/path/to/logs';
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

class FakeGithubClient implements GithubClient {
  @override
  Future<UpdateInfo?> getLatestReleaseInfo({
    required ComponentType type,
    required UpdateChannel channel,
    required String targetAssetName,
    bool isPrefixMatch = false,
  }) async => null;

  @override
  Future<bool> downloadFile({
    required String url,
    required String savePath,
    Function(int received, int total)? onProgress,
  }) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeCtrl;
  late FakeSystemController fakeSystemCtrl;
  late FakeGithubClient fakeGithub;
  late Directory tempDir;

  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'Vidra',
      packageName: 'com.vidra.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('bubble_test_');
    const MethodChannel pathChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (MethodCall methodCall) async {
      return tempDir.path;
    });

    localeCtrl = LocaleController(LocaleRepository(), 'en');
    await localeCtrl.whenReady;
    fakeSystemCtrl = FakeSystemController();
    fakeGithub = FakeGithubClient();
  });

  tearDown(() {
    const MethodChannel pathChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Widget createTestWidget(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
        ChangeNotifierProvider<SystemController>.value(value: fakeSystemCtrl),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: child,
        ),
      ),
    );
  }

  group('System Status Update Bubble (R5)', () {
    testWidgets(
        '1. Renders localized bubble elements (title, body, Show button, Dismiss button)',
        (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const SystemStatusUpdateBubble(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(localeCtrl.localeStrings.ssiBubbleTitle),
        findsOneWidget,
      );
      expect(
        find.text(localeCtrl.localeStrings.ssiBubbleMessage),
        findsOneWidget,
      );
      expect(
        find.text(localeCtrl.localeStrings.ssiBubbleButtonShow),
        findsOneWidget,
      );
      expect(
        find.text(localeCtrl.localeStrings.ssiBubbleButtonDismiss),
        findsOneWidget,
      );
    });

    testWidgets('2. Tapping Dismiss button triggers onDismiss callback',
        (tester) async {
      bool dismissed = false;

      await tester.pumpWidget(
        createTestWidget(
          SystemStatusUpdateBubble(
            onDismiss: () => dismissed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.text(localeCtrl.localeStrings.ssiBubbleButtonDismiss));
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
    });

    testWidgets('3. Tapping Show button triggers onShow callback',
        (tester) async {
      bool showed = false;

      await tester.pumpWidget(
        createTestWidget(
          SystemStatusUpdateBubble(
            onShow: () => showed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(localeCtrl.localeStrings.ssiBubbleButtonShow));
      await tester.pumpAndSettle();

      expect(showed, isTrue);
    });

    test('4. Session scoping: Bubble is shown at most once per session',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final controller = UpdateController(fakeGithub, fakeSystemCtrl, prefs);

      // Initially session bubble has not been shown
      expect(controller.hasShownSessionUpdateBubble, isFalse);

      // Marking as shown updates the in-memory session flag
      controller.markSessionUpdateBubbleShown();
      expect(controller.hasShownSessionUpdateBubble, isTrue);
    });
  });
}

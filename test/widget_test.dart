import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidra/config/backend_config.dart';
import 'package:vidra/i18n/i18n.dart';
import 'package:vidra/main.dart';
import 'package:vidra/models/preferences_model.dart';
import 'package:vidra/state/download_controller.dart';
import 'package:vidra/state/serious_python_server_launcher.dart';

const String _testToken = 'test-token';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await I18n.preloadAll();
  });

  testWidgets('renders home screen with provider', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferencesModel = PreferencesModel();
    await preferencesModel.initializePreferences();
    await preferencesModel.setPreferenceValue(
      preferencesModel.preferences.language,
      'es',
    );
    addTearDown(preferencesModel.dispose);

    final backendConfig = BackendConfig(
      name: 'Test Backend',
      description: 'Test description',
      baseUri: Uri.parse('https://example.com/'),
      apiBaseUri: Uri.parse('https://example.com/api/'),
      overviewSocketUri: Uri.parse('wss://example.com/ws/overview'),
      jobSocketBaseUri: Uri.parse('wss://example.com/ws/jobs/'),
      metadata: const {},
      timeout: const Duration(seconds: 5),
    );
    final downloadController = _StubDownloadController(
      backendConfig: backendConfig,
    );
    addTearDown(downloadController.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<BackendConfig>.value(value: backendConfig),
          ChangeNotifierProvider<PreferencesModel>.value(
            value: preferencesModel,
          ),
          ChangeNotifierProvider<DownloadController>.value(
            value: downloadController,
          ),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });
}

class _StubDownloadController extends DownloadController {
  _StubDownloadController({required super.backendConfig})
    : super(
        authToken: _testToken,
        backendStateListenable: ValueNotifier<BackendState>(
          BackendState.running,
        ),
      );

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refreshJobs() async {}
}

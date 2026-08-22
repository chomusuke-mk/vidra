import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/locales/data/locale_repository.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/updates/presentation/widgets/linux_deb_update_dialog.dart';
import 'package:vidra/features/updates/presentation/widgets/linux_appimage_update_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeCtrl;

  setUp(() async {
    localeCtrl = LocaleController(LocaleRepository(), 'en');
    await localeCtrl.whenReady;
  });

  Widget createTestDialog(Widget dialog) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleController>.value(value: localeCtrl),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: dialog,
        ),
      ),
    );
  }

  group('Platform Update Resolver & Linux Dialogs (R3)', () {
    testWidgets(
        '1. Linux DEB Update Dialog renders command and copies to clipboard',
        (tester) async {
      String? copiedString;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform,
              (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          copiedString = (methodCall.arguments as Map)['text'];
        }
        return null;
      });

      await tester.pumpWidget(
        createTestDialog(
          const LinuxDebUpdateDialog(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
          find.text(localeCtrl.localeStrings.sdLinuxDebTitle), findsOneWidget);
      expect(
          find.textContaining(
              'sudo apt update && sudo apt install --only-upgrade vidra'),
          findsOneWidget);

      // Tap Copy Command button
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();

      expect(copiedString,
          equals('sudo apt update && sudo apt install --only-upgrade vidra'));
    });

    testWidgets(
        '2. Linux AppImage Update Dialog renders instructions and dismisses',
        (tester) async {
      bool dismissed = false;

      await tester.pumpWidget(
        createTestDialog(
          LinuxAppImageUpdateDialog(
            onDismiss: () => dismissed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(localeCtrl.localeStrings.sdLinuxAppImageTitle),
          findsOneWidget);
      expect(find.text(localeCtrl.localeStrings.sdClose), findsOneWidget);

      await tester.tap(find.text(localeCtrl.localeStrings.sdClose));
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
    });

    testWidgets('3. Linux DEB Dialog dismiss triggers onDismiss callback',
        (tester) async {
      bool dismissed = false;

      await tester.pumpWidget(
        createTestDialog(
          LinuxDebUpdateDialog(
            onDismiss: () => dismissed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(localeCtrl.localeStrings.sdClose), findsOneWidget);
      await tester.tap(find.text(localeCtrl.localeStrings.sdClose));
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
    });
  });
}

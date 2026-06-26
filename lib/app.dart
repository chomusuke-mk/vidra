import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/downloads/presentation/downloads_screen.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/features/downloads/presentation/share_wrapper.dart';
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/onboarding/presentation/permissions_screen.dart';
import 'package:vidra/shared/utils/toast_utils.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsCtrl = context.watch<SettingsController>();
    if (!settingsCtrl.isInitialized) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Vidra",
      locale: Locale(settingsCtrl.appLanguage),
      scaffoldMessengerKey: ToastUtils.messengerKey,
      themeMode: settingsCtrl.appTheme,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      initialRoute: '/',
      home: const MainRouter(),
    );
  }
}

// ============================================================================
// ENRUTADOR PRINCIPAL (Vigila el estado del sistema)
// ============================================================================
class MainRouter extends StatelessWidget {
  const MainRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final sysState = context.watch<SystemController>().state;

    if (sysState == SystemState.missingPermissions) {
      return const PermissionsScreen();
    }

    return const ShareIntentWrapper(child: DownloadsScreen());
  }
}

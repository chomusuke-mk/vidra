import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/downloads/presentation/downloads_screen.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'package:vidra/features/downloads/presentation/share_wrapper.dart';
import 'shared/utils/toast_utils.dart';

// Importamos el motor de sistema y la pantalla de permisos
import 'package:vidra/features/system/domain/system_state.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';
import 'package:vidra/features/onboarding/presentation/permissions_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. Esperamos a que Settings se inicialice (necesario para el idioma y tema)
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
    // Observamos el estado actual del Cerebro (SystemController)
    final sysState = context.watch<SystemController>().state;

    // Si el motor detecta que faltan permisos, bloqueamos la UI con la pantalla de Onboarding
    if (sysState == SystemState.missingPermissions) {
      return const PermissionsScreen();
    }

    // Si todo está bien (iniciando, buscando recursos, o listo),
    // mostramos la app principal.
    // Nota: Si faltan recursos o hay error de Python, la app principal SÍ se muestra,
    // pero el 'SystemStatusIndicator' en el AppBar se pondrá ROJO para avisar al usuario.
    return const ShareIntentWrapper(child: DownloadsScreen());
  }
}

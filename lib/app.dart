import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vidra/features/downloads/presentation/downloads_screen.dart';
import 'package:vidra/features/settings/presentation/settings_controller.dart';
import 'shared/utils/toast_utils.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsCtrl = context.watch<SettingsController>();
    if (!settingsCtrl.isInitialized) {
      return const MaterialApp(
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
      home: const DownloadsScreen(),
    );
  }
}

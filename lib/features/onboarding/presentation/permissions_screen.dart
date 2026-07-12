import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_screen_overlay/flutter_screen_overlay.dart';
import 'package:vidra/features/locales/presentation/locale_controller.dart';
import 'package:vidra/features/system/presentation/system_controller.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

// Usamos WidgetsBindingObserver para saber cuando el usuario vuelve de "Ajustes de Android"
class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  bool _storageGranted = false;
  bool _overlayGranted = false;
  bool _notifGranted = false;
  bool _installGranted = false;
  bool _batteryOptimizationGranted = false;

  bool _isChecking = true;
  late int _androidSdkVersion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Se dispara automáticamente cuando el usuario vuelve de la app de Configuración
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAllPermissions();
    }
  }

  Future<void> _initPermissions() async {
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      _androidSdkVersion = info.version.sdkInt;
    } else {
      _androidSdkVersion = 0;
    }
    await _checkAllPermissions();
  }

  Future<void> _checkAllPermissions() async {
    setState(() => _isChecking = true);

    if (_androidSdkVersion >= 30) {
      _storageGranted = await Permission.manageExternalStorage.isGranted;
    } else {
      _storageGranted = await Permission.storage.isGranted;
    }

    _overlayGranted = await FlutterScreenOverlay.isPermissionGranted();

    if (_androidSdkVersion >= 33) {
      _notifGranted = await Permission.notification.isGranted;
    } else {
      _notifGranted = true;
    }

    _installGranted = await Permission.requestInstallPackages.isGranted;
    _batteryOptimizationGranted =
        await Permission.ignoreBatteryOptimizations.isGranted;
    setState(() => _isChecking = false);
  }

  // --- LÓGICA DE SOLICITUDES ---
  Future<void> _requestStorage() async {
    if (_androidSdkVersion >= 30) {
      await Permission.manageExternalStorage.request();
    } else {
      await Permission.storage.request();
    }
    _checkAllPermissions();
  }

  Future<void> _requestOverlay() async {
    await FlutterScreenOverlay.requestPermission();
    // No llamamos a _checkAll() aquí porque FlutterScreenOverlay manda a Settings.
    // El didChangeAppLifecycleState lo atrapará al volver.
  }

  Future<void> _requestBatteryOptimization() async {
    await Permission.ignoreBatteryOptimizations.request();
    // No llamamos a _checkAll() aquí porque manda a Settings.
    // El didChangeAppLifecycleState lo atrapará al volver.
  }

  Future<void> _requestNotifications() async {
    await Permission.notification.request();
    _checkAllPermissions();
  }

  Future<void> _requestInstallPackages() async {
    await Permission.requestInstallPackages.request();
    // También manda a Settings, lo atrapará el observer al volver.
  }

  bool get _allMandatoryGranted =>
      _storageGranted &&
      _overlayGranted &&
      _notifGranted &&
      _batteryOptimizationGranted;

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleController>().localeStrings;
    return Scaffold(
      body: SafeArea(
        child: _isChecking
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.security, size: 64, color: Colors.blue),
                    const SizedBox(height: 16),
                    Text(
                      locale.pTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      locale.pDescription,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 32),

                    Expanded(
                      child: ListView(
                        children: [
                          _buildPermissionTile(
                            title: locale.pStorage,
                            subtitle: locale.pStorageDesc,
                            icon: Icons.folder_special,
                            isGranted: _storageGranted,
                            onRequest: _requestStorage,
                            grantedText: locale.pButtonGrant,
                          ),
                          const SizedBox(height: 12),
                          _buildPermissionTile(
                            title: locale.pOverlay,
                            subtitle: locale.pOverlayDesc,
                            icon: Icons.layers,
                            isGranted: _overlayGranted,
                            onRequest: _requestOverlay,
                            grantedText: locale.pButtonGrant,
                          ),
                          const SizedBox(height: 12),
                          _buildPermissionTile(
                            title: locale.pBattery,
                            subtitle: locale.pBatteryDesc,
                            icon: Icons.battery_saver,
                            isGranted: _batteryOptimizationGranted,
                            onRequest: _requestBatteryOptimization,
                            grantedText: locale.pButtonGrant,
                          ),
                          const SizedBox(height: 12),
                          if (_androidSdkVersion >= 33) ...[
                            _buildPermissionTile(
                              title: locale.pNotification,
                              subtitle: locale.pNotificationDesc,
                              icon: Icons.notifications_active,
                              isGranted: _notifGranted,
                              onRequest: _requestNotifications,
                              grantedText: locale.pButtonGrant,
                            ),
                            const SizedBox(height: 12),
                          ],
                          _buildPermissionTile(
                            title: locale.pInstall,
                            subtitle: locale.pInstallDesc,
                            icon: Icons.system_update,
                            isGranted: _installGranted,
                            onRequest: _requestInstallPackages,
                            grantedText: locale.pButtonGrant,
                          ),
                        ],
                      ),
                    ),

                    // BOTÓN CONTINUAR
                    FilledButton(
                      onPressed: _allMandatoryGranted
                          ? () {
                              // ¡Todos los permisos listos! Le decimos al cerebro que continúe arrancando
                              context
                                  .read<SystemController>()
                                  .resumeInitialization();
                            }
                          : null, // Deshabilitado si falta algún permiso obligatorio
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16.0),
                        child: Text(
                          locale.pButtonContinue,
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildPermissionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isGranted,
    required VoidCallback onRequest,
    required String grantedText,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isGranted
            ? Colors.green.withValues(alpha: 0.1)
            : Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(
          color: isGranted
              ? Colors.green
              : Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 4),
            leading: Icon(
              icon,
              color: isGranted ? Colors.green : Colors.blue,
              size: 32,
            ),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(subtitle, style: const TextStyle(fontSize: 12)),
            ),
            trailing: isGranted
                ? const Icon(Icons.check_circle, color: Colors.green, size: 28)
                : null,
          ),
          if (!isGranted)
            Padding(
              padding: const EdgeInsets.only(right: 16.0, bottom: 12.0),
              child: Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: onRequest,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    minimumSize: const Size(0, 36),
                  ),
                  child: Text(grantedText),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

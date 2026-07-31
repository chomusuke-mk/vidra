import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init({String? iconPath}) async {
    // 1. Configuración Android
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // 2. Configuración Apple (iOS / macOS)
    const DarwinInitializationSettings darwinSettings =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );

    // 3. Configuración Windows
    WindowsInitializationSettings windowsSettings =
        WindowsInitializationSettings(
          appName: 'Vidra',
          appUserModelId: 'dev.chomusuke.vidra',
          guid: 'f64fa50b-b4ea-45d9-92f9-c4a54ee64213',
          iconPath: iconPath,
        );

    // 4. Configuración Linux
    final LinuxInitializationSettings linuxSettings =
        LinuxInitializationSettings(
          defaultActionName: 'Open Vidra',
          defaultIcon: AssetsLinuxIcon('assets/icon/icon.png'),
          defaultSuppressSound: false,
        );

    // Combinar todas las configuraciones
    final InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      windows: windowsSettings,
      linux: linuxSettings,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveBackgroundNotificationResponse: null,
      onDidReceiveNotificationResponse: null,
    );
  }

  /// Construye los detalles específicos por plataforma, incluyendo la imagen si existe
  static NotificationDetails _buildPlatformDetails({
    required int notificationId,
    required String channelId,
    required String channelName,
    String? channelDescription,
    Importance importance = Importance.defaultImportance,
    Priority priority = Priority.defaultPriority,
    bool showProgress = false,
    double? progress = 0,
    String? progressLabel,
    String? progressSpeed,
    bool silence = false,
    bool ongoing = false,
    String? imagePath,
    Color? color,
    String? body,
    String? title,
    bool? bigPicture,
  }) {
    imagePath = imagePath == null || imagePath.isEmpty ? null : imagePath;
    // --- ANDROID ---
    AndroidBitmap<Object>? largeIcon;
    if (imagePath != null) {
      largeIcon = FilePathAndroidBitmap(imagePath);
    }
    StyleInformation? androidStyleInfo;
    if (imagePath != null && bigPicture == true) {
      androidStyleInfo = BigPictureStyleInformation(
        FilePathAndroidBitmap(imagePath),
        hideExpandedLargeIcon: true,
      );
    } else {
      androidStyleInfo = BigTextStyleInformation(
        body ?? '',
        htmlFormatBigText: false,
        contentTitle: null,
        htmlFormatContentTitle: false,
        summaryText: null,
        htmlFormatSummaryText: false,
      );
    }
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: importance,
          priority: priority,
          showProgress: showProgress,
          maxProgress: 1000,
          progress: progress != null ? (progress * 1000).toInt() : 0,
          indeterminate: showProgress && progress == null,
          onlyAlertOnce: silence,
          ongoing: ongoing,
          color: color,
          largeIcon: largeIcon,
          subText: progressLabel,
          styleInformation: androidStyleInfo,
        );

    // --- APPLE (iOS / macOS) ---
    List<DarwinNotificationAttachment> darwinAttachments = [];
    if (imagePath != null) {
      // En Apple pasamos el archivo como un adjunto local
      darwinAttachments.add(DarwinNotificationAttachment(imagePath));
    }

    final DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      attachments: darwinAttachments,
      presentAlert: !silence,
      presentSound: !silence,
      presentBadge: !silence,
    );

    // --- LINUX ---
    final linuxIconPath = imagePath != null
        ? FilePathLinuxIcon(imagePath)
        : null;
    LinuxNotificationDetails linuxDetails = LinuxNotificationDetails(
      icon: linuxIconPath,
      suppressSound: silence,
      resident: ongoing,
    );

    // --- WINDOWS ---
    List<WindowsImage> windowsImages = [];
    // Solo inyectamos la imagen grande si NO es un progreso.
    if (imagePath != null) {
      windowsImages.add(
        WindowsImage(
          Uri.file(imagePath),
          altText: '$title Image',
          placement: bigPicture == true
              ? WindowsImagePlacement.hero
              : WindowsImagePlacement.appLogoOverride,
        ),
      );
    }
    List<WindowsProgressBar> windowsProgressBars = [];
    if (showProgress) {
      windowsProgressBars.add(
        WindowsProgressBar(
          id: 'vidra_progress_bar_$notificationId',
          status: "{progressSpeed}",
          value: progress,
          label: progressLabel ?? '',
        ),
      );
    }
    final WindowsNotificationDetails windowsDetails =
        WindowsNotificationDetails(
          images: windowsImages,
          progressBars: windowsProgressBars,
          duration: ongoing
              ? WindowsNotificationDuration.long
              : WindowsNotificationDuration.short,
          bindings: {
            "progressSpeed": progressSpeed ?? "",
            "body": body ?? "",
            "title": title ?? "",
          },
          //audio: silence ? WindowsNotificationAudio.silent() : null,
        );

    // Retornamos el empaquetado cross-platform
    return NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
      linux: linuxDetails,
      windows: windowsDetails,
    );
  }

  /// Muestra o actualiza una notificación de progreso
  static Future<void> showProgress({
    required int id,
    required String title,
    required String body,
    required double? progress,
    String? progressSpeed,
    String? imagePath,
    String? progressLabel,
    Color? color,
  }) async {
    imagePath = imagePath == null || imagePath.isEmpty ? null : imagePath;
    progressLabel = progressLabel == null || progressLabel.isEmpty
        ? null
        : progressLabel;
    progressSpeed = progressSpeed == null || progressSpeed.isEmpty
        ? null
        : progressSpeed;
    if (Platform.isWindows) {
      final windowsImpl = _plugin
          .resolvePlatformSpecificImplementation<
            FlutterLocalNotificationsWindows
          >();
      if (windowsImpl != null) {
        try {
          final progressBar = WindowsProgressBar(
            id: 'vidra_progress_bar_$id',
            status: "{progressSpeed}",
            value: progress,
            label: progressLabel ?? '',
          );
          final updateResultProgress = await windowsImpl.updateProgressBar(
            notificationId: id,
            progressBar: progressBar,
          );
          final updateResultBindings = await windowsImpl.updateBindings(
            id: id,
            bindings: {
              "body": body,
              "title": title,
              "progressSpeed": progressSpeed ?? "",
            },
          );
          if (updateResultProgress == NotificationUpdateResult.success &&
              updateResultBindings == NotificationUpdateResult.success) {
            return;
          }
        } catch (e) {
          debugPrint('Error updating Windows progress notification: $e');
        }
      }
    }

    final details = _buildPlatformDetails(
      notificationId: id,
      channelId: 'download_channel',
      channelName: 'Downloads in Progress',
      channelDescription: 'Shows the progress of active downloads',
      importance: Importance.high,
      priority: Priority.low,
      showProgress: true,
      progress: progress,
      progressSpeed: progressSpeed,
      silence: true,
      ongoing: true,
      imagePath: imagePath,
      color: color,
      body: body,
      title: title,
      progressLabel: progressLabel,
    );

    if (!Platform.isWindows && !Platform.isAndroid) {
      if (progressLabel != null && progressSpeed != null) {
        body += '\n$progressLabel - $progressSpeed';
      } else if (progressLabel != null) {
        body += '\n$progressLabel';
      } else if (progressSpeed != null) {
        body += '\n$progressSpeed';
      }
    }
    if (Platform.isWindows) {
      title = "{title}";
      body = "{body}";
    }

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  /// Muestra notificaciones estáticas (Completado, Error, Esperando)
  static Future<void> showState({
    required int id,
    required String title,
    required String body,
    bool? bigPicture = false,
    Color? color,
    String? imagePath,
  }) async {
    final details = _buildPlatformDetails(
      notificationId: id,
      channelId: 'download_state_channel',
      channelName: 'Download Events',
      importance: Importance.high,
      priority: Priority.high,
      silence: false,
      imagePath: imagePath,
      color: color,
      bigPicture: bigPicture,
    );

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  /// Elimina una notificación
  static Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } catch (e) {
      debugPrint('Error canceling notification $id: $e');
    }
  }
  // =====================================================================
  // MAGIA NATIVA: FOREGROUND SERVICE
  // =====================================================================

  /// Convierte la app en un servicio nativo intocable por Android
  static Future<void> keepAppAlive() async {
    if (!Platform.isAndroid) return;

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidImpl == null) {
      debugPrint(
        'Error: No se pudo obtener la implementación específica de Android.',
      );
      return;
    }

    androidImpl.requestNotificationsPermission();

    await androidImpl.startForegroundService(
      id: 6969, // ID fijo para el foreground service
      title: null,
      body: 'Vidra Background Service',
      startType: AndroidServiceStartType.startRedeliverIntent,
      notificationDetails: const AndroidNotificationDetails(
        'vidra_bg_channel', // Un canal distinto para el servicio
        'Download in Background',
        channelDescription: 'Keep Downloads Running in Background',
        importance: Importance.low, // Importancia baja para que no suene
        priority: Priority.low,
        playSound: false,
        enableVibration: false,
        enableLights: false,
        channelShowBadge: false,
        silent: true, // No suena ni vibra
        visibility: NotificationVisibility.secret,
        ongoing: true, // No se puede deslizar para borrar
        autoCancel: false, // No se puede borrar automáticamente
        icon: '@mipmap/ic_launcher', // Icono de la app
      ),
    );
  }

  /// Permite que Android vuelva a suspender la app cuando ya no hay descargas
  static Future<void> letAppSleep() async {
    if (!Platform.isAndroid) return;

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidImpl?.stopForegroundService();
  }
}

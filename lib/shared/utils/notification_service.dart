import 'package:flutter/rendering.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
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
    const WindowsInitializationSettings windowsSettings =
        WindowsInitializationSettings(
          appName: 'Vidra',
          appUserModelId: 'com.vidra.app',
          guid: '12345678-1234-5678-1234-567812345678',
          iconPath: 'assets/icon/icon.ico',
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
    bool silence = false,
    bool ongoing = false,
    String? imagePath,
    Color? color,
    String? rawBody,
  }) {
    // --- ANDROID ---
    AndroidBitmap<Object>? largeIcon;
    if (imagePath != null && imagePath.isNotEmpty) {
      largeIcon = FilePathAndroidBitmap(
        imagePath,
      ); // Carga directa y ultra-rápida desde disco
    }

    // Configuración del estilo multilínea para Android
    StyleInformation? androidStyleInfo;
    if (showProgress) {
      // BigTextStyleInformation fuerza al sistema operativo a romper las limitaciones de espacio de una sola línea
      // permitiendo procesar caracteres de escape como '\n'.
      androidStyleInfo = BigTextStyleInformation(
        rawBody ?? '',
        htmlFormatBigText: false,
        contentTitle:
            null, // Mantiene el título original pasado en plugin.show()
        htmlFormatContentTitle: false,
        summaryText:
            null, // Evita inyectar metadatos adicionales que saturen la UI de la notificación
        htmlFormatSummaryText: false,
      );
    } else if (imagePath != null) {
      // Mantenemos tu lógica previa para las vistas de estado estáticas que se expanden a pantalla completa con la miniatura
      androidStyleInfo = BigPictureStyleInformation(
        FilePathAndroidBitmap(imagePath),
        hideExpandedLargeIcon: true,
      );
    }

    final AndroidNotificationDetails
    androidDetails = AndroidNotificationDetails(
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
      colorized: color != null, // Solo aplica el color si no es nulo
      largeIcon: largeIcon, // Imagen a la derecha
      subText: progressLabel, // Texto pequeño debajo del título
      // Opcional: bigPictureStyle para que la imagen se expanda si deslizan la notificación
      styleInformation: androidStyleInfo,
    );

    // --- APPLE (iOS / macOS) ---
    List<DarwinNotificationAttachment> darwinAttachments = [];
    if (imagePath != null && imagePath.isNotEmpty) {
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
    final linuxIconPath = imagePath != null && imagePath.isNotEmpty
        ? FilePathLinuxIcon(imagePath)
        : null;
    LinuxNotificationDetails linuxDetails = LinuxNotificationDetails(
      icon: linuxIconPath,
      suppressSound: silence,
      resident: ongoing,
    );

    // --- WINDOWS ---
    List<WindowsImage> windowsImages = [];

    // CAMBIO CLAVE 1: Sutileza en la imagen.
    // Solo inyectamos la imagen grande si NO es un progreso.
    if (imagePath != null && imagePath.isNotEmpty && !showProgress) {
      windowsImages.add(
        WindowsImage(Uri.file(imagePath), altText: 'Thumbnail of the file'),
      );
    }
    List<WindowsProgressBar> windowsProgressBars = [];
    if (showProgress) {
      windowsProgressBars.add(
        WindowsProgressBar(
          id: 'vidra_progress_bar_$notificationId',
          status: progress == null
              ? 'Processing...'
              : '${(progress * 100).toStringAsFixed(0)}%',
          value: progress,
          label: progressLabel,
        ),
      );
    }
    final WindowsNotificationDetails windowsDetails =
        WindowsNotificationDetails(
          images: windowsImages,
          progressBars: windowsProgressBars,
          scenario: null,
          audio: silence ? WindowsNotificationAudio.silent() : null,
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
    String? imagePath,
    String? progressLabel,
    Color? color,
  }) async {
    final details = _buildPlatformDetails(
      notificationId: id,
      channelId: 'download_channel',
      channelName: 'Downloads in Progress',
      channelDescription: 'Shows the progress of active downloads',
      importance: Importance.low, // Evita popups molestos cada 2 segundos
      priority: Priority.low,
      showProgress: true,
      progress: progress,
      silence: true, // Magia: actualiza en silencio
      ongoing: true, // No se puede deslizar
      imagePath: imagePath,
      color: color,
      rawBody: body,
      progressLabel: progressLabel,
    );

    if (!Platform.isAndroid && !Platform.isWindows) {
      body = progressLabel != null && progressLabel.isNotEmpty
          ? '$progressLabel\n$body'
          : body;
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
    Color? color,
    String? imagePath,
  }) async {
    final details = _buildPlatformDetails(
      notificationId: id,
      channelId: 'download_state_channel',
      channelName: 'Download Events',
      importance: Importance.high,
      priority: Priority.high,
      silence: false, // Queremos que suene/vibre para avisar
      imagePath: imagePath,
      color: color,
      rawBody: body,
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

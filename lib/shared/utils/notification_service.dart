import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
          defaultSuppressSound: true,
        );

    // Combinar todas las configuraciones
    final InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      windows: windowsSettings,
      linux: linuxSettings,
    );

    await _plugin.initialize(settings: initSettings);
  }

  /// Construye los detalles específicos por plataforma, incluyendo la imagen si existe
  static NotificationDetails _buildPlatformDetails({
    required String channelId,
    required String channelName,
    String? channelDescription,
    Importance importance = Importance.defaultImportance,
    Priority priority = Priority.defaultPriority,
    bool showProgress = false,
    int maxProgress = 0,
    int progress = 0,
    bool onlyAlertOnce = false,
    bool ongoing = false,
    bool isError = false,
    String? imagePath,
  }) {
    // --- ANDROID ---
    AndroidBitmap<Object>? largeIcon;
    if (imagePath != null && imagePath.isNotEmpty) {
      largeIcon = FilePathAndroidBitmap(
        imagePath,
      ); // Carga directa y ultra-rápida desde disco
    }

    final AndroidNotificationDetails
    androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: importance,
      priority: priority,
      showProgress: showProgress,
      maxProgress: maxProgress,
      progress: progress,
      onlyAlertOnce: onlyAlertOnce,
      ongoing: ongoing,
      largeIcon: largeIcon, // Imagen a la derecha
      icon: isError ? '@android:drawable/ic_dialog_alert' : null,
      // Opcional: bigPictureStyle para que la imagen se expanda si deslizan la notificación
      styleInformation: imagePath != null && showProgress == false
          ? BigPictureStyleInformation(
              FilePathAndroidBitmap(imagePath),
              hideExpandedLargeIcon: true,
            )
          : null,
    );

    // --- APPLE (iOS / macOS) ---
    List<DarwinNotificationAttachment> darwinAttachments = [];
    if (imagePath != null && imagePath.isNotEmpty) {
      // En Apple pasamos el archivo como un adjunto local
      darwinAttachments.add(DarwinNotificationAttachment(imagePath));
    }

    final DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      attachments: darwinAttachments,
    );

    // --- LINUX ---
    LinuxNotificationDetails? linuxDetails;
    if (imagePath != null && imagePath.isNotEmpty) {
      linuxDetails = LinuxNotificationDetails(
        icon: FilePathLinuxIcon(imagePath),
      );
    }

    // Retornamos el empaquetado cross-platform
    return NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
      linux: linuxDetails,
    );
  }

  /// Muestra o actualiza una notificación de progreso
  static Future<void> showProgress({
    required int id,
    required String title,
    required String body,
    required int progress,
    required int maxProgress,
    String? imagePath,
  }) async {
    final details = _buildPlatformDetails(
      channelId: 'download_channel',
      channelName: 'Descargas en Progreso',
      channelDescription: 'Muestra el progreso de las descargas activas',
      importance: Importance.low, // Evita popups molestos cada 2 segundos
      priority: Priority.low,
      showProgress: true,
      maxProgress: maxProgress,
      progress: progress,
      onlyAlertOnce: true, // Magia: actualiza en silencio
      ongoing: true, // No se puede deslizar
      imagePath: imagePath,
    );

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
    bool isError = false,
    String? imagePath,
  }) async {
    final details = _buildPlatformDetails(
      channelId: 'download_state_channel',
      channelName: 'Eventos de Descarga',
      importance: Importance.high,
      priority: Priority.high,
      onlyAlertOnce: false, // Queremos que suene/vibre para avisar
      isError: isError,
      imagePath: imagePath,
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
    await _plugin.cancel(id: id);
  }
}

enum SystemState {
  initializing,        // App arrancando, evaluando el entorno
  missingPermissions,  // Bloqueado: Faltan permisos críticos (Overlay, Notificaciones)
  missingResources,    // Bloqueado: No se encontró yt-dlp o yt-dlp-ejs en el disco
  startingBackend,     // Todo en orden: Buscando puerto y levantando Python
  ready,               // Operativo: Python respondió al Ping HTTP 200 OK
  retrying,            // Alerta: Python no responde, el Watchdog está intentando revivirlo
  fatalError           // Crítico: No se pudo encontrar un puerto o Python crashea en bucle
}
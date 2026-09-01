import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:vidra/features/locales/domain/locale.dart';

void main() {
  group('Locale keys and strings', () {
    test('en.jsonc and es.jsonc contain all keys required by AppStringKey', () async {
      final enFile = File('i18n/en.jsonc');
      expect(enFile.existsSync(), isTrue);

      final enRaw = enFile.readAsStringSync();
      final enMap = (jsonc.decode(enRaw) as Map).cast<String, dynamic>().map(
            (k, v) => MapEntry(k, v.toString()),
          );

      final appStrings = AppStringKey();
      // Should not throw when asserting all keys present in en.jsonc
      await expectLater(
        appStrings.updateFromJson(enMap, assertAllKeysPresent: true),
        completes,
      );

      // Verify fatal error getters return non-empty strings
      expect(appStrings.feTitle, equals('Fatal System Error'));
      expect(
        appStrings.feMessage,
        equals(
          'The download engine failed to load after an update. Please restart the application.',
        ),
      );
      expect(appStrings.feRestartButton, equals('Restart Application'));
      expect(appStrings.feViewLogsButton, equals('View Logs'));

      // Verify Quick Settings & Cut Video getters in English
      expect(appStrings.dQuickSettings, equals('Quick Settings'));
      expect(appStrings.qsTitle, equals('Quick Settings'));
      expect(appStrings.qsClose, equals('Close'));
      expect(appStrings.qsAudio, equals('Audio'));
      expect(appStrings.dCutVideo, equals('Cut Video'));
      expect(appStrings.cvTitle, equals('Cut Video'));
      expect(appStrings.cvClose, equals('Close'));
      expect(
        appStrings.cvDescription,
        equals('Removes segments from SponsorBlock categories.'),
      );

      // Verify Overlay & Permission getters in English
      expect(
        appStrings.shwOverlayDeniedDownloading,
        equals('Overlay permission denied, downloading directly'),
      );
      expect(appStrings.pOptional, equals('Optional'));

      // Verify Tutorial Quick Settings getters in English
      expect(appStrings.tuPPQuickSettings, equals('Quick Settings'));
      expect(
        appStrings.tuPPQuickSettingsDesc,
        equals(
          'Open this menu to quickly adjust download options on the fly without leaving the main screen.',
        ),
      );

      // Verify Startup missing module & Bubble & Linux Update getters in English
      expect(appStrings.dEngineDownloading,
          equals('Downloading download engine...'));
      expect(appStrings.dEngineDownloadingDesc,
          equals('Downloading required core modules (yt-dlp & yt-dlp-ejs). Please wait...'));
      expect(appStrings.dDownloadingEngineError,
          equals('Error downloading engine modules. Please check your internet connection.'));
      expect(appStrings.ssiBubbleTitle, equals('Update Available'));
      expect(appStrings.ssiBubbleMessage,
          equals('Updates are available for Vidra components. Tap Show to review and install.'));
      expect(appStrings.ssiBubbleButtonShow, equals('Display'));
      expect(appStrings.ssiBubbleButtonDismiss, equals('Dismiss'));
      expect(appStrings.sdLinuxDebTitle, equals('Update Vidra (DEB Package)'));
      expect(appStrings.sdCopyCommand, equals('Copy Command'));
      expect(appStrings.sdCommandCopied,
          equals('Command copied to clipboard'));
      // Verify Engine status getters in English
      expect(appStrings.sdAppEngine, equals('App Engine'));
      expect(appStrings.sdAppEngineConnected, equals('App Engine: Connected'));
      expect(appStrings.sdAllWorkingNormally, equals('Everything is running normally'));
      expect(appStrings.sdAppEngineStarting, equals('App Engine: Starting...'));
      expect(appStrings.sdAppEngineInitializing, equals('App Engine: Initializing...'));
      expect(appStrings.sdAppEngineReconnecting, equals('App Engine: Reconnecting...'));
      expect(appStrings.sdAppEngineMissingPermissions, equals('App Engine: Permissions Required'));
      expect(appStrings.sdAppEngineMissingResources, equals('App Engine: Missing Components'));
      expect(appStrings.sdAppEngineError, equals('App Engine: Error'));
      expect(appStrings.sdStateReady, equals('Connected'));
      expect(appStrings.sdStateInitializing, equals('Initializing...'));
      expect(appStrings.sdStateStartingBackend, equals('Starting Engine...'));
      expect(appStrings.sdStateRetrying, equals('Reconnecting...'));
      expect(appStrings.sdStateMissingPermissions, equals('Missing Permissions'));
      expect(appStrings.sdStateMissingResources, equals('Missing Components'));
      expect(appStrings.sdStateFatalError, equals('Fatal Error'));

      // Verify Cookies from WebView getters in English
      expect(appStrings.sCookiesFromWebview, equals('Cookies from WebView'));
      expect(
        appStrings.sCookiesFromWebviewDesc,
        equals(
          'Enable this option to extract cookies from the WebView. This is useful for sites that require login or have region restrictions.',
        ),
      );
      expect(appStrings.sOpenWebview, equals('Open WebView'));
      expect(appStrings.sViewCurrentCookies, equals('View current cookies'));
      expect(appStrings.sCookiesListTitle, equals('Current Cookies'));
      expect(appStrings.sNoCookiesFound, equals('No cookie files found'));
      expect(appStrings.wvBrowseToGenerateCookies, equals('Browse to generate cookies and bypass anti-bots'));
      expect(appStrings.wvNotSupported, equals('Webview is not supported on this platform'));
      expect(appStrings.wvShortcuts, equals('Shortcuts'));
      expect(appStrings.wvGo, equals('Go'));
      expect(appStrings.wvBack, equals('Back'));
      expect(appStrings.wvForward, equals('Forward'));
      expect(appStrings.wvRefresh, equals('Refresh'));
      expect(appStrings.wvManageCookies, equals('Manage cookies'));
      expect(appStrings.dcActionUseCookies, equals('Use cookies'));

      // Verify es.jsonc
      final esFile = File('i18n/es.jsonc');
      expect(esFile.existsSync(), isTrue);
      final esRaw = esFile.readAsStringSync();
      final esMap = (jsonc.decode(esRaw) as Map).cast<String, dynamic>().map(
            (k, v) => MapEntry(k, v.toString()),
          );

      final esStrings = AppStringKey();
      await esStrings.updateFromJson(enMap);
      await esStrings.updateFromJson(esMap);

      expect(esStrings.feTitle, equals('Error fatal del sistema'));
      expect(
        esStrings.feMessage,
        equals(
          'El motor de descargas no pudo cargarse tras la actualización. Por favor, reinicia la aplicación.',
        ),
      );
      expect(esStrings.feRestartButton, equals('Reiniciar aplicación'));
      expect(esStrings.feViewLogsButton, equals('Ver registros'));

      // Verify Quick Settings & Cut Video getters in Spanish
      expect(esStrings.dQuickSettings, equals('Configuración rápida'));
      expect(esStrings.qsTitle, equals('Configuración Rápida'));
      expect(esStrings.qsClose, equals('Cerrar'));
      expect(esStrings.qsAudio, equals('Audio'));
      expect(esStrings.dCutVideo, equals('Cortar vídeo'));
      expect(esStrings.cvTitle, equals('Cortar vídeo'));
      expect(esStrings.cvClose, equals('Cerrar'));
      expect(
        esStrings.cvDescription,
        equals('Elimina segmentos de las categorías de SponsorBlock.'),
      );

      // Verify Overlay & Permission getters in Spanish
      expect(
        esStrings.shwOverlayDeniedDownloading,
        equals('Permiso de superposición denegado, descargando directamente'),
      );
      expect(esStrings.pOptional, equals('Opcional'));

      // Verify Tutorial Quick Settings getters in Spanish
      expect(esStrings.tuPPQuickSettings, equals('Configuración rápida'));
      expect(
        esStrings.tuPPQuickSettingsDesc,
        equals(
          'Abra este menú para ajustar rápidamente las opciones de descarga sobre la marcha sin salir de la pantalla principal.',
        ),
      );

      // Verify Startup missing module & Bubble & Linux Update getters in Spanish
      expect(esStrings.dEngineDownloading,
          equals('Descargando motor de descargas...'));
      expect(esStrings.dEngineDownloadingDesc,
          equals('Descargando módulos principales requeridos (yt-dlp y yt-dlp-ejs). Por favor, espere...'));
      expect(esStrings.dDownloadingEngineError,
          equals('Error al descargar los módulos del motor. Por favor verifique su conexión a Internet.'));
      expect(esStrings.ssiBubbleTitle, equals('Actualización disponible'));
      expect(esStrings.ssiBubbleMessage,
          equals('Hay actualizaciones disponibles para los componentes de Vidra. Toca Ver para revisarlas e instalarlas.'));
      expect(esStrings.ssiBubbleButtonShow, equals('Mostrar'));
      expect(esStrings.ssiBubbleButtonDismiss, equals('Descartar'));
      expect(esStrings.sdLinuxDebTitle, equals('Actualizar Vidra (Paquete DEB)'));
      expect(esStrings.sdCopyCommand, equals('Copiar comando'));
      expect(esStrings.sdCommandCopied,
          equals('Comando copiado al portapapeles'));
      expect(
          esStrings.sdLinuxAppImageTitle, equals('Actualizar Vidra (AppImage)'));

      // Verify Engine status getters in Spanish
      expect(esStrings.sdAppEngine, equals('Motor de aplicaciones'));
      expect(esStrings.sdAppEngineConnected, equals('Motor de aplicaciones: conectado'));
      expect(esStrings.sdAllWorkingNormally, equals('Todo esta funcionando normalmente'));
      expect(esStrings.sdAppEngineStarting, equals('App Engine: Iniciando...'));
      expect(esStrings.sdAppEngineInitializing, equals('App Engine: inicializando...'));
      expect(esStrings.sdAppEngineReconnecting, equals('App Engine: Reconectando...'));
      expect(esStrings.sdAppEngineMissingPermissions, equals('App Engine: permisos necesarios'));
      expect(esStrings.sdAppEngineMissingResources, equals('App Engine: componentes faltantes'));
      expect(esStrings.sdAppEngineError, equals('Motor de aplicaciones: error'));
      expect(esStrings.sdStateReady, equals('Conectado'));
      expect(esStrings.sdStateInitializing, equals('Inicializando...'));
      expect(esStrings.sdStateStartingBackend, equals('Arrancando el motor...'));
      expect(esStrings.sdStateRetrying, equals('Reconectando...'));
      expect(esStrings.sdStateMissingPermissions, equals('Permisos faltantes'));
      expect(esStrings.sdStateMissingResources, equals('Componentes faltantes'));
      expect(esStrings.sdStateFatalError, equals('Error fatal'));

      // Verify Cookies from WebView getters in Spanish
      expect(esStrings.sCookiesFromWebview, equals('Cookies de WebView'));
      expect(
        esStrings.sCookiesFromWebviewDesc,
        equals(
          'Habilite esta opción para extraer cookies de WebView. Esto es útil para sitios que requieren iniciar sesión o tienen restricciones regionales.',
        ),
      );
      expect(esStrings.sOpenWebview, equals('Abrir vista web'));
      expect(esStrings.sViewCurrentCookies, equals('Ver cookies actuales'));
      expect(esStrings.sCookiesListTitle, equals('Cookies actuales'));
      expect(esStrings.sNoCookiesFound, equals('No se encontraron archivos de cookies'));
      expect(esStrings.wvBrowseToGenerateCookies, equals('Navega para generar cookies y evitar los anti-bots'));
      expect(esStrings.wvNotSupported, equals('Webview no es compatible con esta plataforma'));
      expect(esStrings.wvShortcuts, equals('Atajos'));
      expect(esStrings.wvGo, equals('Ir'));
      expect(esStrings.wvBack, equals('Atrás'));
      expect(esStrings.wvForward, equals('Adelante'));
      expect(esStrings.wvRefresh, equals('Refrescar'));
      expect(esStrings.wvManageCookies, equals('Administrar cookies'));
      expect(esStrings.dcActionUseCookies, equals('Utilizar cookies'));
    });
  });
}

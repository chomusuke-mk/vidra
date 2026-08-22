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

      // Verify Quick Settings getters in English
      expect(appStrings.dQuickSettings, equals('Quick Settings'));
      expect(appStrings.qsTitle, equals('Quick Settings'));
      expect(appStrings.qsClose, equals('Close'));
      expect(appStrings.qsAudio, equals('Audio'));

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
      expect(appStrings.ssiBubbleButtonShow, equals('Show'));
      expect(appStrings.ssiBubbleButtonDismiss, equals('Dismiss'));
      expect(appStrings.sdLinuxDebTitle, equals('Update Vidra (DEB Package)'));
      expect(appStrings.sdCopyCommand, equals('Copy Command'));
      expect(appStrings.sdCommandCopied,
          equals('Command copied to clipboard'));
      expect(
          appStrings.sdLinuxAppImageTitle, equals('Update Vidra (AppImage)'));

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

      // Verify Quick Settings getters in Spanish
      expect(esStrings.dQuickSettings, equals('Configuración rápida'));
      expect(esStrings.qsTitle, equals('Configuración Rápida'));
      expect(esStrings.qsClose, equals('Cerrar'));
      expect(esStrings.qsAudio, equals('Audio'));

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
          equals('Error al descargar módulos del motor. Revisa tu conexión a internet.'));
      expect(esStrings.ssiBubbleTitle, equals('Actualización disponible'));
      expect(esStrings.ssiBubbleMessage,
          equals('Hay actualizaciones disponibles para los componentes de Vidra. Toca Ver para revisarlas e instalarlas.'));
      expect(esStrings.ssiBubbleButtonShow, equals('Ver'));
      expect(esStrings.ssiBubbleButtonDismiss, equals('Descartar'));
      expect(esStrings.sdLinuxDebTitle, equals('Actualizar Vidra (Paquete DEB)'));
      expect(esStrings.sdCopyCommand, equals('Copiar comando'));
      expect(esStrings.sdCommandCopied,
          equals('Comando copiado al portapapeles'));
      expect(
          esStrings.sdLinuxAppImageTitle, equals('Actualizar Vidra (AppImage)'));
    });
  });
}

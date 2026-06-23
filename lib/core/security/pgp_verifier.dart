import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:openpgp/openpgp.dart';
import 'package:flutter/foundation.dart';

class PgpVerifier {
  /// Valida un binario físico contra su archivo SHA256SUMS y su firma .sig
  /// Devuelve [true] solo si es matemáticamente seguro ejecutarlo.
  static Future<bool> verifyBinary({
    required File binaryFile,
    required File sumsFile,
    required File sigFile,
    required String publicKey,
    required String expectedBinaryName,
  }) async {
    try {
      // 1. Validar la firma PGP del archivo SHA256SUMS (Detached Signature)
      final sumsContent = await sumsFile.readAsString();
      final sigContent = await sigFile.readAsString();

      // Verifica matemáticamente que la firma (.sig) pertenece al texto (sums)
      // y fue generada por el dueño de la llave pública.
      final isValidSignature = await OpenPGP.verify(
        sumsContent,
        sigContent,
        publicKey,
      );

      if (!isValidSignature) {
        debugPrint(
          '⚠️ ALERTA DE SEGURIDAD: La firma PGP es inválida o fue falsificada.',
        );
        return false;
      }

      // 2. Calcular el SHA-256 del binario físico (Streaming para cuidar la RAM)
      final stream = binaryFile.openRead();
      final digest = await sha256
          .bind(stream)
          .first; // Absorbe el archivo pedazo a pedazo
      final actualHash = digest.toString();

      // 3. Buscar el hash esperado dentro del texto ya verificado
      // Formato típico de sums: "hash_largo_1234 *yt-dlp" o "hash  yt-dlp_macos"
      final lines = sumsContent.split('\n');
      String? expectedHash;

      for (var line in lines) {
        if (line.contains(expectedBinaryName)) {
          // Extraemos el hash (la primera cadena de texto antes de los espacios)
          expectedHash = line.split(RegExp(r'\s+')).first;
          break;
        }
      }

      if (expectedHash == null) {
        debugPrint(
          '⚠️ ALERTA: El binario "$expectedBinaryName" no está listado en el SHA256SUMS protegido.',
        );
        return false;
      }

      // 4. Choque de Hashes (El momento de la verdad)
      if (actualHash != expectedHash) {
        debugPrint(
          '⚠️ ALERTA DE CORRUPCIÓN: Hash alterado. ($actualHash != $expectedHash)',
        );
        return false;
      }

      debugPrint('✅ Verificación estricta superada. Binario 100% seguro.');
      return true;
    } catch (e) {
      debugPrint('Error catastrófico en la verificación PGP/SHA: $e');
      return false; // Ante la duda, bloqueamos.
    }
  }
}

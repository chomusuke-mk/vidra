import 'package:vidra/core/network/vidra_http_client.dart';
import 'package:vidra/features/downloads/domain/download.dart';

class DownloadRepository {
  final VidraHttpClient _client;

  DownloadRepository(this._client);

  Future<List<Download>> getAllDownloads() async {
    final response = await _client.getDownloads();

    // Convertimos la respuesta del server Python en objetos Download
    if (response is List) {
      return response.map((e) => Download.fromJson(e)).toList();
    }
    return [];
  }

  /// Obtiene el estado completo de una descarga específica y sus sub-descargas
  Future<Download?> getDownloadById(String id) async {
    final response = await _client.getDownloads(id: id);

    // Si el backend devuelve un solo objeto
    if (response is Map<String, dynamic>) {
      return Download.fromJson(response);
    }

    return null;
  }

  Future<String> addDownload(
    String url, {
    Map<String, dynamic> options = const {},
  }) async {
    return await _client.addDownload(url: url, options: options);
  }

  // --- Acciones de Control ---
  Future<void> pauseDownload(String id) =>
      _client.updateDownload(id: id, action: 'pause');
  Future<void> resumeDownload(String id) =>
      _client.updateDownload(id: id, action: 'resume');
  Future<void> cancelDownload(String id) =>
      _client.updateDownload(id: id, action: 'cancel');
  Future<void> retryDownload(String id) =>
      _client.updateDownload(id: id, action: 'retry');
  Future<void> deleteDownload(String id) =>
      _client.updateDownload(id: id, action: 'delete');

  // --- Reactividad (Server-Sent Events mapeados a clases Dart) ---

  /// Para la pantalla principal (deltas generales)
  Stream<List<Delta>> watchGlobalProgress() {
    return _client.subscribeToDeltas().map((jsonList) {
      // Transformamos cada diccionario del array en un objeto Delta
      return jsonList
          .map((json) => Delta.fromJson(json as Map<String, dynamic>))
          .toList();
    });
  }

  /// Para la pantalla de detalle (sub_deltas de una descarga específica)
  Stream<List<Delta>> watchDetailedProgress(String id) {
    return _client.subscribeToDeltas(id: id).map((jsonList) {
      return jsonList
          .map((json) => Delta.fromJson(json as Map<String, dynamic>))
          .toList();
    });
  }

  // --- Otras operaciones ---
  // Cambia esto:
  Future<List<SubDownload>> getEntries(String id) async {
    final response = await _client.getEntriesToSelect(id: id);
    return response.map((e) => SubDownload.fromJson(e)).toList();
  }

  // Este se queda casi igual, pero aseguramos el tipado de la lista
  Future<void> submitSelectedEntries(String id, List<String> entries) =>
      _client.selectEntries(id: id, entries: entries);
  Future<String> fetchLogs(String? id) => _client.getLogs(id: id);
  // --- Health Check ---
  Future<bool> checkHealth() => _client.healthCheck();
}

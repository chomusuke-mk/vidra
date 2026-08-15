import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class VidraHttpClient {
  String baseUrl;
  String? token;

  final Map<String, String> defaultHeaders;
  final Duration timeout;
  final http.Client _client;

  VidraHttpClient({
    required this.baseUrl,
    required this.defaultHeaders,
    this.timeout = const Duration(seconds: 30),
    this.token,
    http.Client? client,
  }) : _client = client ?? http.Client();

  // --- Cabeceras base para todas las peticiones ---
  Map<String, String> get _headers {
    return {
      ...defaultHeaders,
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // --- GET / (Health Check) ---
  Future<bool> healthCheck() async {
    final uri = Uri.parse('$baseUrl/');

    try {
      // Un timeout muy corto porque al ser localhost debería responder en 10ms.
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == 'ok';
      }
    } catch (e) {
      return false; // Python está colgado o apagado
    }
    return false;
  }

  // --- PATCH /ota (Control de Módulos OTA Hot-Reload) ---
  Future<bool> otaAction(String action) async {
    final uri = Uri.parse(
      '$baseUrl/ota',
    ).replace(queryParameters: {'action': action});

    try {
      final response = await _client
          .patch(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> otaLoad() => otaAction('load');
  Future<bool> otaUnload() => otaAction('unload');

  // --- GET /logs ---
  Future<String> getLogs({String? id}) async {
    final uri = Uri.parse(
      '$baseUrl/logs',
    ).replace(queryParameters: id != null ? {'id': id} : null);

    final response = await _client.get(uri, headers: _headers).timeout(timeout);

    if (response.statusCode == 200) return response.body;
    throw Exception(
      'Error obtaining logs: ${response.statusCode} - ${response.body}',
    );
  }

  // --- GET /downloads ---
  Future<dynamic> getDownloads({String? id}) async {
    final uri = Uri.parse(
      '$baseUrl/downloads',
    ).replace(queryParameters: id != null ? {'id': id} : null);

    final response = await _client.get(uri, headers: _headers).timeout(timeout);

    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception(
      'Error obtaining downloads: ${response.statusCode} - ${response.body}',
    );
  }

  // --- POST /downloads ---
  Future<String> addDownload({
    required String url,
    Map<String, dynamic> options = const {},
  }) async {
    final uri = Uri.parse('$baseUrl/downloads');

    final response = await _client
        .post(
          uri,
          headers: _headers,
          body: jsonEncode({'url': url, 'options': options}),
        )
        .timeout(timeout);

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['id'].toString();
    }
    throw Exception(
      'Error adding download: ${response.statusCode} - ${response.body}',
    );
  }

  // --- PATCH /downloads ---
  Future<void> updateDownload({
    required String id,
    required String action,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/downloads',
    ).replace(queryParameters: {'id': id, 'action': action});

    final response = await _client
        .patch(uri, headers: _headers)
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception(
        'Error in action $action: ${response.statusCode} - ${response.body}',
      );
    }
  }

  // --- GET /select-entries ---
  Future<List<dynamic>> getEntriesToSelect({required String id}) async {
    final uri = Uri.parse(
      '$baseUrl/select-entries',
    ).replace(queryParameters: {'id': id});

    final response = await _client.get(uri, headers: _headers).timeout(timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) {
        return data['entries'] ?? [];
      }
      return [];
    }
    throw Exception(
      'Error obtaining entries: ${response.statusCode} - ${response.body}',
    );
  }

  // --- POST /select-entries ---
  Future<void> selectEntries({
    required String id,
    required List<dynamic> entries,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/select-entries',
    ).replace(queryParameters: {'id': id});

    final response = await _client
        .post(uri, headers: _headers, body: jsonEncode({'entries': entries}))
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception(
        'Error selecting entries: ${response.statusCode} - ${response.body}',
      );
    }
  }

  // --- GET /subscribe (Server-Sent Events) ---
  Stream<List<dynamic>> subscribeToDeltas({String? id}) async* {
    final uri = Uri.parse(
      '$baseUrl/subscribe',
    ).replace(queryParameters: id != null ? {'id': id} : null);

    final request = http.Request('GET', uri)..headers.addAll(_headers);

    final response = await _client.send(request);

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      throw Exception(
        'Error connecting to stream: ${response.statusCode} - $errorBody',
      );
    }

    // Procesamos el stream de texto línea por línea buscando los eventos SSE
    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.startsWith(':')) continue;
      if (line.startsWith('data: ')) {
        final payload = line.substring(6).trim();
        if (payload.isNotEmpty) {
          yield jsonDecode(payload) as List<dynamic>;
        }
      }
    }
  }  
}

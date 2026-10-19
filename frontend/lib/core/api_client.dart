import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int statusCode;

  const ApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}

class ApiClient {
  static const _storage = FlutterSecureStorage();
  static const _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      final uri = Uri.tryParse(_configuredBaseUrl);
      if (kReleaseMode &&
          (uri == null || uri.scheme != 'https' || uri.host.isEmpty)) {
        throw StateError(
          'API_BASE_URL deve ser uma URL HTTPS válida na versão de produção.',
        );
      }
      return _configuredBaseUrl;
    }
    if (kReleaseMode) {
      throw StateError(
        'Defina API_BASE_URL HTTPS ao compilar a versão de produção.',
      );
    }
    if (kIsWeb) return 'http://localhost:3333';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3333';
    }
    return 'http://localhost:3333';
  }

  Future<String?> get token => _storage.read(key: 'access_token');

  Future<void> saveToken(String value) =>
      _storage.write(key: 'access_token', value: value);

  Future<void> clearToken() => _storage.delete(key: 'access_token');

  Future<Map<String, dynamic>> get(String path) async {
    final value = await _send('GET', path);
    if (value is Map<String, dynamic>) return value;
    throw const FormatException('Resposta inesperada do servidor.');
  }

  Future<List<dynamic>> getList(String path) async {
    final value = await _send('GET', path);
    if (value is List<dynamic>) return value;
    throw const FormatException('Resposta inesperada do servidor.');
  }

  Future<List<Map<String, dynamic>>> getMapList(String path) async =>
      decodeMapList(await _send('GET', path));

  static List<Map<String, dynamic>> decodeMapList(dynamic value) {
    if (value is! List) {
      throw const FormatException('Resposta inesperada do servidor.');
    }
    final result = <Map<String, dynamic>>[];
    for (final item in value) {
      if (item is! Map) {
        throw const FormatException('Resposta inesperada do servidor.');
      }
      result.add(Map<String, dynamic>.from(item));
    }
    return result;
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final value = await _send('POST', path, body: body);
    if (value is Map<String, dynamic>) return value;
    throw const FormatException('Resposta inesperada do servidor.');
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final value = await _send('PATCH', path, body: body);
    if (value is Map<String, dynamic>) return value;
    throw const FormatException('Resposta inesperada do servidor.');
  }

  Future<void> delete(String path) async {
    await _send('DELETE', path, expectJson: false);
  }

  Future<void> uploadReceipt(
    String transactionId,
    Uint8List bytes,
    String mimeType,
  ) async {
    final accessToken = await token;
    if (accessToken == null) {
      throw const ApiException('Autenticação necessária.', 401);
    }
    final response = await http.put(
      Uri.parse('$baseUrl/transactions/$transactionId/receipt'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': mimeType,
      },
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiException(response);
    }
  }

  Future<Uint8List> downloadReceipt(String transactionId) async {
    final accessToken = await token;
    if (accessToken == null) {
      throw const ApiException('Autenticação necessária.', 401);
    }
    final response = await http.get(
      Uri.parse('$baseUrl/transactions/$transactionId/receipt'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiException(response);
    }
    return response.bodyBytes;
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool expectJson = true,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final accessToken = await token;
    if (accessToken != null) headers['Authorization'] = 'Bearer $accessToken';
    final uri = Uri.parse('$baseUrl$path');
    final encodedBody = body == null ? null : jsonEncode(body);

    final response = switch (method) {
      'GET' => await http.get(uri, headers: headers),
      'POST' => await http.post(uri, headers: headers, body: encodedBody),
      'PATCH' => await http.patch(uri, headers: headers, body: encodedBody),
      'DELETE' => await http.delete(uri, headers: headers),
      _ => throw ArgumentError.value(
        method,
        'method',
        'Método HTTP não suportado',
      ),
    };

    final dynamic decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(_errorMessage(decoded), response.statusCode);
    }
    return expectJson ? decoded : <String, dynamic>{};
  }

  ApiException _apiException(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      decoded = null;
    }
    return ApiException(_errorMessage(decoded), response.statusCode);
  }

  String _errorMessage(dynamic decoded) => decoded is Map<String, dynamic>
      ? decoded['error']?.toString() ?? 'Falha na comunicação com o servidor.'
      : 'Falha na comunicação com o servidor.';
}

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Client REST vers le plugin Solar Quotes (namespace solar-quotes/v1).
/// Auth : Application Passwords WordPress en Basic auth — HTTPS obligatoire.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  String _baseUrl = '';
  String _user = '';
  String _appPassword = '';

  bool get isConfigured =>
      _baseUrl.isNotEmpty && _user.isNotEmpty && _appPassword.isNotEmpty;

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse(
        '$_baseUrl/wp-json/solar-quotes/v1$path',
      ).replace(queryParameters: query);

  Map<String, String> get _headers => {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$_user:$_appPassword'))}',
        'Content-Type': 'application/json',
      };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('base_url') ?? '';
    _user = prefs.getString('user') ?? '';
    _appPassword = prefs.getString('app_password') ?? '';
  }

  Future<void> saveCredentials({
    required String baseUrl,
    required String user,
    required String appPassword,
  }) async {
    _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');
    _user = user.trim();
    _appPassword = appPassword.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('base_url', _baseUrl);
    await prefs.setString('user', _user);
    await prefs.setString('app_password', _appPassword);
  }

  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('base_url');
    await prefs.remove('user');
    await prefs.remove('app_password');
    _baseUrl = '';
    _user = '';
    _appPassword = '';
  }

  Future<dynamic> _handle(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return Future.value(jsonDecode(utf8.decode(r.bodyBytes)));
    }
    String message = 'Erreur ${r.statusCode}';
    try {
      final body = jsonDecode(utf8.decode(r.bodyBytes));
      if (body is Map && body['message'] != null) {
        message = body['message'].toString();
      }
    } catch (_) {}
    throw ApiException(r.statusCode, message);
  }

  Future<dynamic> get(String path, [Map<String, String>? query]) async =>
      _handle(await http.get(_uri(path, query), headers: _headers));

  Future<dynamic> post(String path, [Object? body]) async =>
      _handle(await http.post(_uri(path),
          headers: _headers, body: body == null ? null : jsonEncode(body)));

  Future<dynamic> put(String path, Object body) async =>
      _handle(await http.put(_uri(path),
          headers: _headers, body: jsonEncode(body)));

  Future<dynamic> delete(String path) async =>
      _handle(await http.delete(_uri(path), headers: _headers));
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

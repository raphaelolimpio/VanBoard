import '../core/api_client.dart';

class AuthController {
  AuthController({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _api.post(
      '/auth/login',
      body: {'email': email.trim(), 'password': password},
    );
    await _api.saveToken(response['token'] as String);
    return _withCompanyId(response['user'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> activateDriver({
    required String code,
    required String password,
  }) async {
    final response = await _api.post(
      '/auth/driver-invitations/accept',
      body: {'code': code.trim(), 'password': password},
    );
    await _api.saveToken(response['token'] as String);
    return _withCompanyId(response['user'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> registerOwner({
    required String name,
    required String email,
    required String password,
    required String companyName,
  }) async {
    final response = await _api.post(
      '/auth/register-owner',
      body: {
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        'companyName': companyName.trim(),
      },
    );
    await _api.saveToken(response['token'] as String);
    return _withCompanyId(response['user'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>?> restoreSession() async {
    if (await _api.token == null) return null;
    try {
      return _withCompanyId(await _api.get('/auth/me'));
    } on ApiException catch (error) {
      if (error.statusCode == 401) await _api.clearToken();
      rethrow;
    }
  }

  Future<void> logout() => _api.clearToken();

  Map<String, dynamic> _withCompanyId(Map<String, dynamic> user) {
    final company = user['company'] as Map<String, dynamic>?;
    final companies = user['companies'] as List<dynamic>?;
    final companyId =
        company?['id'] ??
        (companies?.isNotEmpty == true
            ? (companies!.first as Map<String, dynamic>)['id']
            : null);
    final result = {...user};
    if (companyId != null) result['companyId'] = companyId;
    return result;
  }
}

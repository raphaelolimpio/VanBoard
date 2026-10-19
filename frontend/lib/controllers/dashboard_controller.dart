import '../core/api_client.dart';

class DashboardController {
  DashboardController({required this.companyId, ApiClient? api})
    : _api = api ?? ApiClient();

  final String companyId;
  final ApiClient _api;

  Future<Map<String, dynamic>> fetchDashboard({
    DateTime? from,
    DateTime? to,
    String? purpose,
  }) {
    final query = <String, String>{
      if (from != null) 'from': _dateParameter(from),
      if (to != null) 'to': _dateParameter(to),
      if (purpose != null && purpose != 'TODOS') 'purpose': purpose,
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    return _api.get('/companies/$companyId/dashboard$suffix');
  }

  String _dateParameter(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> createVehicle({
    required String plate,
    required String model,
    required int capacity,
    required String purpose,
  }) async {
    await _api.post(
      '/vehicles',
      body: {
        'companyId': companyId,
        'plate': plate,
        'model': model,
        'capacity': capacity,
        'purposes': [purpose],
      },
    );
  }
}

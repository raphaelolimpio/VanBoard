import '../core/api_client.dart';

class VehicleDetailController {
  VehicleDetailController({required this.vehicleId, ApiClient? api})
    : _api = api ?? ApiClient();

  final String vehicleId;
  final ApiClient _api;

  Future<Map<String, dynamic>> fetchContext() =>
      _api.get('/vehicles/$vehicleId/context');

  Future<void> updateStatus(String newStatus) async {
    await _api.patch(
      '/vehicles/$vehicleId/status',
      body: {'status': newStatus},
    );
  }

  Future<void> markManualAttendance(String studentId, String direction) async {
    await _api.post(
      '/vehicles/$vehicleId/manual-attendance',
      body: {'studentId': studentId, 'direction': direction},
    );
  }
}

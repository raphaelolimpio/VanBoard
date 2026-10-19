import 'package:flutter/material.dart';

import '../core/api_client.dart';
import 'vehicle_operations_screen.dart';

class OperationalAlertsScreen extends StatefulWidget {
  const OperationalAlertsScreen({super.key, required this.companyId});

  final String companyId;

  @override
  State<OperationalAlertsScreen> createState() =>
      _OperationalAlertsScreenState();
}

class _OperationalAlertsScreenState extends State<OperationalAlertsScreen> {
  final _api = ApiClient();
  List<dynamic> _alerts = [];
  List<dynamic> _documents = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _api.get(
        '/companies/${widget.companyId}/operational-alerts',
      );
      if (mounted) {
        setState(() {
          _alerts = result['alerts'] as List? ?? const [];
          _documents = result['expiringDocuments'] as List? ?? const [];
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openVehicle(Map<String, dynamic> vehicle) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => VehicleOperationsScreen(
          vehicleId: vehicle['id'].toString(),
          vehicleLabel: '${vehicle['plate']} • ${vehicle['model']}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Alertas operacionais'),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                TextButton(
                  onPressed: _load,
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Alertas em andamento',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (_alerts.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.check_circle_outline),
                    title: Text('Nenhum alerta operacional aberto.'),
                  ),
                ..._alerts.map((raw) {
                  final alert = Map<String, dynamic>.from(raw as Map);
                  final vehicle = Map<String, dynamic>.from(
                    alert['vehicle'] as Map,
                  );
                  return Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.warning_amber,
                        color: Colors.orange,
                      ),
                      title: Text(alert['message'].toString()),
                      subtitle: Text(
                        '${vehicle['plate']} • ${alert['createdAt']}',
                      ),
                      onTap: () => _openVehicle(vehicle),
                    ),
                  );
                }),
                const SizedBox(height: 20),
                Text(
                  'Documentos vencidos ou próximos do vencimento',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (_documents.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.verified_outlined),
                    title: Text('Nenhum vencimento nos próximos 30 dias.'),
                  ),
                ..._documents.map((raw) {
                  final document = Map<String, dynamic>.from(raw as Map);
                  final vehicle = Map<String, dynamic>.from(
                    document['vehicle'] as Map,
                  );
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        document['expiryStatus'] == 'VENCIDO'
                            ? Icons.error_outline
                            : Icons.event_busy_outlined,
                        color: Colors.orange,
                      ),
                      title: Text(document['name'].toString()),
                      subtitle: Text(
                        '${vehicle['plate']} • ${document['expiryStatus']} • '
                        '${document['expiresAt']}',
                      ),
                      onTap: () => _openVehicle(vehicle),
                    ),
                  );
                }),
              ],
            ),
          ),
  );
}

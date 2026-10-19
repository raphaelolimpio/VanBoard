import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/api_client.dart';

class VehicleOperationsScreen extends StatefulWidget {
  const VehicleOperationsScreen({
    super.key,
    required this.vehicleId,
    required this.vehicleLabel,
  });

  final String vehicleId;
  final String vehicleLabel;

  @override
  State<VehicleOperationsScreen> createState() =>
      _VehicleOperationsScreenState();
}

class _VehicleOperationsScreenState extends State<VehicleOperationsScreen> {
  final _api = ApiClient();
  Map<String, dynamic> _data = {};
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
        '/vehicles/${widget.vehicleId}/operations',
      );
      if (mounted) setState(() => _data = result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addDocument() async {
    final document = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _VehicleDocumentDialog(),
    );
    if (document == null) return;
    try {
      await _api.post(
        '/vehicles/${widget.vehicleId}/documents',
        body: document,
      );
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _deleteDocument(Map<String, dynamic> document) async {
    try {
      await _api.delete(
        '/vehicles/${widget.vehicleId}/documents/${document['id']}',
      );
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _acknowledgeAlert(Map<String, dynamic> alert) async {
    try {
      await _api.post(
        '/vehicles/${widget.vehicleId}/alerts/${alert['id']}/acknowledge',
      );
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.vehicleLabel)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.vehicleLabel)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!),
              TextButton(onPressed: _load, child: const Text('Tentar novamente')),
            ],
          ),
        ),
      );
    }

    final documents = _data['documents'] as List? ?? const [];
    final inspections = _data['inspections'] as List? ?? const [];
    final locations = (_data['locationSamples'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList()
      ..sort(
        (a, b) => DateTime.parse(
          a['createdAt'].toString(),
        ).compareTo(DateTime.parse(b['createdAt'].toString())),
      );
    final alerts = _data['alerts'] as List? ?? const [];
    final points = locations
        .map(
          (sample) => LatLng(
            (sample['latitude'] as num).toDouble(),
            (sample['longitude'] as num).toDouble(),
          ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.vehicleLabel),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: _addDocument,
            icon: const Icon(Icons.note_add_outlined),
            tooltip: 'Cadastrar documento',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text('Alertas', style: Theme.of(context).textTheme.titleLarge),
            if (alerts.isEmpty)
              const ListTile(
                leading: Icon(Icons.check_circle_outline),
                title: Text('Nenhum alerta operacional aberto.'),
              ),
            ...alerts.map((raw) {
              final alert = Map<String, dynamic>.from(raw as Map);
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.warning_amber, color: Colors.orange),
                  title: Text(alert['message'].toString()),
                  subtitle: Text(alert['createdAt'].toString()),
                  trailing: alert['acknowledgedAt'] == null
                      ? IconButton(
                          tooltip: 'Reconhecer alerta',
                          onPressed: () => _acknowledgeAlert(alert),
                          icon: const Icon(Icons.done),
                        )
                      : const Chip(label: Text('Reconhecido')),
                ),
              );
            }),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Documentos e validades',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: _addDocument,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (documents.isEmpty)
              const ListTile(
                title: Text('Nenhum documento cadastrado para esta van.'),
              ),
            ...documents.map((raw) {
              final document = Map<String, dynamic>.from(raw as Map);
              final status = document['expiryStatus']?.toString() ?? 'VALIDO';
              return Card(
                child: ListTile(
                  leading: Icon(
                    status == 'VALIDO'
                        ? Icons.description_outlined
                        : Icons.warning_amber,
                    color: status == 'VALIDO' ? null : Colors.orange,
                  ),
                  title: Text(document['name'].toString()),
                  subtitle: Text(
                    '${document['category']} • vence em ${_date(document['expiresAt'])} • $status',
                  ),
                  trailing: IconButton(
                    tooltip: 'Remover documento',
                    onPressed: () => _deleteDocument(document),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            Text('Inspeções recentes', style: Theme.of(context).textTheme.titleLarge),
            if (inspections.isEmpty)
              const ListTile(title: Text('Ainda não há inspeções registradas.')),
            ...inspections.map((raw) {
              final inspection = Map<String, dynamic>.from(raw as Map);
              return Card(
                child: ListTile(
                  leading: Icon(
                    inspection['blocked'] == true
                        ? Icons.cancel_outlined
                        : Icons.verified_outlined,
                    color: inspection['blocked'] == true
                        ? Colors.red
                        : Colors.green,
                  ),
                  title: Text(
                    inspection['blocked'] == true
                        ? 'Inspeção reprovada'
                        : 'Inspeção aprovada',
                  ),
                  subtitle: Text(
                    '${inspection['driver']?['name'] ?? 'Motorista'} • '
                    '${inspection['createdAt']}'
                    '${inspection['notes'] == null ? '' : '\n${inspection['notes']}'}',
                  ),
                  isThreeLine: inspection['notes'] != null,
                ),
              );
            }),
            const SizedBox(height: 12),
            Text('Histórico GPS • últimas 24 horas', style: Theme.of(context).textTheme.titleLarge),
            if (points.isEmpty)
              const ListTile(
                title: Text('Sem posições GPS armazenadas nas últimas 24 horas.'),
              )
            else
              SizedBox(
                height: 260,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: points.last,
                      initialZoom: 13,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'board_van',
                      ),
                      if (points.length > 1)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: points,
                              color: Colors.blue,
                              strokeWidth: 4,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: points.last,
                            width: 44,
                            height: 44,
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.red,
                              size: 36,
                            ),
                          ),
                        ],
                      ),
                      const RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution('© OpenStreetMap contributors'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'O trajeto mostra posições registradas, não uma rota viária calculada.',
            ),
          ],
        ),
      ),
    );
  }

  String _date(Object? value) {
    final date = DateTime.parse(value.toString()).toLocal();
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

class _VehicleDocumentDialog extends StatefulWidget {
  const _VehicleDocumentDialog();

  @override
  State<_VehicleDocumentDialog> createState() => _VehicleDocumentDialogState();
}

class _VehicleDocumentDialogState extends State<_VehicleDocumentDialog> {
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _notes = TextEditingController();
  DateTime _expiresAt = DateTime.now().add(const Duration(days: 365));

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _expiresAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date != null) setState(() => _expiresAt = date);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Cadastrar documento'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nome do documento'),
          ),
          TextField(
            controller: _category,
            decoration: const InputDecoration(
              labelText: 'Categoria (ex.: licenciamento)',
            ),
          ),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Observações'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Data de validade'),
            subtitle: Text(
              '${_expiresAt.day.toString().padLeft(2, '0')}/'
              '${_expiresAt.month.toString().padLeft(2, '0')}/${_expiresAt.year}',
            ),
            trailing: const Icon(Icons.calendar_month),
            onTap: _chooseDate,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (_name.text.trim().isEmpty || _category.text.trim().isEmpty) {
            return;
          }
          Navigator.pop(context, {
            'name': _name.text.trim(),
            'category': _category.text.trim(),
            'notes': _notes.text.trim(),
            'expiresAt': _expiresAt.toIso8601String(),
          });
        },
        child: const Text('Salvar'),
      ),
    ],
  );
}

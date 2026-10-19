import 'package:flutter/material.dart';

import '../components/add_vehicle_dialog.dart';
import '../components/empty_state.dart';
import '../core/api_client.dart';
import '../core/theme/app_text_style.dart';
import 'dynamic_vehicle_detail.screen.dart';

class FleetScreen extends StatefulWidget {
  const FleetScreen({super.key, required this.companyId, this.api});

  final String companyId;
  final ApiClient? api;

  @override
  State<FleetScreen> createState() => _FleetScreenState();
}

class _FleetScreenState extends State<FleetScreen> {
  late final _api = widget.api ?? ApiClient();
  List<dynamic> _vehicles = [];
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
      final vehicles = await _api.getList(
        '/companies/${widget.companyId}/vehicles',
      );
      if (mounted) setState(() => _vehicles = vehicles);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addVehicle() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => AddVehicleDialog(
        onSave:
            ({
              required plate,
              required model,
              required capacity,
              required purpose,
            }) async {
              await _api.post(
                '/vehicles',
                body: {
                  'companyId': widget.companyId,
                  'plate': plate,
                  'model': model,
                  'capacity': capacity,
                  'purposes': [purpose],
                },
              );
            },
      ),
    );
    if (added == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Frota'),
        actions: [
          IconButton(
            tooltip: 'Atualizar frota',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
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
          : _vehicles.isEmpty
          ? EmptyState(
              icon: Icons.directions_bus_outlined,
              title: 'Sua frota começa aqui',
              description:
                  'Cadastre os veículos para organizar motoristas, '
                  'rotas e custos por van.',
              actionLabel: 'Cadastrar veículo',
              onAction: _addVehicle,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontalPadding = constraints.maxWidth > 760
                      ? 28.0
                      : 16.0;
                  return ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      20,
                      horizontalPadding,
                      100,
                    ),
                    itemCount: _vehicles.length,
                    itemBuilder: (context, index) {
                      final v = Map<String, dynamic>.from(
                        _vehicles[index] as Map,
                      );
                      final purposes = (v['purposes'] as List?) ?? [];
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 8,
                          ),
                          leading: const CircleAvatar(
                            child: Icon(Icons.directions_bus_outlined),
                          ),
                          title: Text(
                            '${v['model']} (${v['plate']})',
                            style: AppTextStyles.titleMedium,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                'Motorista: ${v['defaultDriver']?['name'] ?? 'Não definido'}',
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  Chip(
                                    label: Text(v['status']?.toString() ?? '—'),
                                  ),
                                  ...purposes.map(
                                    (p) => Chip(label: Text(p.toString())),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DynamicVehicleDetailScreen(
                                  vehicleId: v['id'],
                                ),
                              ),
                            );
                            _load();
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
      floatingActionButton: _loading || _vehicles.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _addVehicle,
              icon: const Icon(Icons.add),
              label: const Text('Novo veículo'),
            ),
    );
  }
}

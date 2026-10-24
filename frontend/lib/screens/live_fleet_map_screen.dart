import 'package:board_van/screens/dynamic_vehicle_detail.screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../core/api_client.dart';

class LiveFleetMapScreen extends StatefulWidget {
  const LiveFleetMapScreen({
    super.key,
    required this.vehicles,
    required this.companyName,
  });

  final List<Map<String, dynamic>> vehicles;
  final String companyName;

  @override
  State<LiveFleetMapScreen> createState() => _LiveFleetMapScreenState();
}

class _LiveFleetMapScreenState extends State<LiveFleetMapScreen> {
  static const _storage = FlutterSecureStorage();
  final _api = ApiClient();
  late final Map<String, Map<String, dynamic>> _vehicles;
  io.Socket? _socket;

  String _filtroStatus = 'TODOS';

  @override
  void initState() {
    super.initState();
    _vehicles = {
      for (final vehicle in widget.vehicles)
        vehicle['id'].toString(): Map<String, dynamic>.from(vehicle),
    };
    _connect();
  }

  Future<void> _connect() async {
    final token = await _storage.read(key: 'access_token');
    if (!mounted || token == null) return;
    final socket = io.io(
      _api.baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .build(),
    );
    socket.on('location:update', (dynamic payload) {
      if (!mounted || payload is! Map) return;
      final id = payload['vehicleId']?.toString();
      if (id == null || !_vehicles.containsKey(id)) return;
      setState(() {
        _vehicles[id]!['location'] = {
          'latitude': payload['latitude'],
          'longitude': payload['longitude'],
          'heading': payload['heading'],
          'updatedAt': payload['updatedAt'],
        };
      });
    });
    socket.connect();
    _socket = socket;
  }

  @override
  void dispose() {
    _socket?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locatedVehicles = _vehicles.values.where((vehicle) {
      final location = vehicle['location'];
      final hasLocation =
          location is Map &&
          location['latitude'] is num &&
          location['longitude'] is num;
      if (!hasLocation) return false;
      if (_filtroStatus != 'TODOS' && vehicle['status'] != _filtroStatus)
        return false;
      return true;
    }).toList();
    final center = locatedVehicles.isNotEmpty
        ? LatLng(
            (locatedVehicles.first['location']['latitude'] as num).toDouble(),
            (locatedVehicles.first['location']['longitude'] as num).toDouble(),
          )
        : const LatLng(-10.184, -48.333);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.companyName} • Frota ao vivo'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: DropdownButton<String>(
              value: _filtroStatus,
              dropdownColor: Theme.of(context).colorScheme.surface,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'TODOS', child: Text('Todas as vans')),
                DropdownMenuItem(value: 'RODANDO', child: Text('🟢 Em rota')),
                DropdownMenuItem(value: 'PARADO', child: Text('🔵 Paradas')),
                DropdownMenuItem(
                  value: 'MANUTENCAO',
                  child: Text('🟠 Oficina'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _filtroStatus = value;
                  });
                }
              },
            ),
          ),
        ],
      ),

      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(initialCenter: center, initialZoom: 12),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'board_van',
                ),
                MarkerLayer(
                  markers: locatedVehicles.map((vehicle) {
                    final location = vehicle['location'] as Map;
                    return Marker(
                      point: LatLng(
                        (location['latitude'] as num).toDouble(),
                        (location['longitude'] as num).toDouble(),
                      ),
                      width: 120,
                      height: 60,
                      child: GestureDetector(
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            builder: (ctx) => Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${vehicle['plate']} • ${vehicle['model']}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Motorista: ${vehicle['defaultDriver']?['name'] ?? 'Nenhum'}',
                                  ),
                                  Text('Estado: ${vehicle['status']}'),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        // Certifique-se de importar o ecrã DynamicVehicleDetailScreen no topo do ficheiro
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                DynamicVehicleDetailScreen(
                                                  vehicleId: vehicle['id']
                                                      .toString(),
                                                ),
                                          ),
                                        );
                                      },
                                      child: const Text('Ver detalhes da van'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        child: Column(
                          children: [
                            const Icon(
                              Icons.directions_bus,
                              color: Colors.indigo,
                              size: 30,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              color: Colors.white.withValues(alpha: 0.9),
                              child: Text(
                                vehicle['plate'].toString(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (locatedVehicles.isEmpty)
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              const Flexible(
                                child: Text(
                                  'As vans aparecerão aqui quando uma rota '
                                  'ativa compartilhar localização.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      '© OpenStreetMap contributors',
                      onTap: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${locatedVehicles.length} de ${_vehicles.length} veículos com localização',
                ),
                const SizedBox(height: 4),
                const Text(
                  'A localização só é compartilhada durante uma rota ativa.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

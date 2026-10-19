import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/api_client.dart';

class StudentTrackingScreen extends StatefulWidget {
  const StudentTrackingScreen({super.key});

  @override
  State<StudentTrackingScreen> createState() => _StudentTrackingScreenState();
}

class _StudentTrackingScreenState extends State<StudentTrackingScreen> {
  final _api = ApiClient();
  final _code = TextEditingController();
  Map<String, dynamic>? _tracking;
  Timer? _refreshTimer;
  bool _requestInProgress = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _lookup({bool silent = false}) async {
    if (_requestInProgress) return;
    final code = _code.text.trim();
    if (code.isEmpty) {
      if (!silent) {
        setState(() => _error = 'Informe o código recebido da empresa.');
      }
      return;
    }
    if (!silent) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    _requestInProgress = true;
    try {
      final result = await _api.get(
        '/public/student-tracking/${Uri.encodeComponent(code)}',
      );
      if (mounted) {
        setState(() {
          _tracking = result;
          _error = null;
        });
        _refreshTimer ??= Timer.periodic(
          const Duration(seconds: 30),
          (_) => _lookup(silent: true),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          if (!silent) _tracking = null;
        });
      }
    } finally {
      _requestInProgress = false;
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = _tracking?['location'] as Map<String, dynamic>?;
    final point = location == null
        ? null
        : LatLng(
            (location['latitude'] as num).toDouble(),
            (location['longitude'] as num).toDouble(),
          );
    final status = _tracking?['status']?.toString();
    return Scaffold(
      appBar: AppBar(title: const Text('Acompanhar aluno')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Acompanhamento temporário',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Use o código compartilhado pela empresa. O acesso é individual, '
            'temporário e pode ser revogado pelo responsável pelo transporte.',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _code,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _lookup(),
            decoration: InputDecoration(
              labelText: 'Código de acompanhamento',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: _loading ? null : _lookup,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loading ? null : _lookup,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Consultar acompanhamento'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_tracking != null) ...[
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tracking!['studentName']?.toString() ?? 'Aluno',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      status == 'EM_ROTA'
                          ? 'Serviço em andamento'
                          : 'Nenhum serviço ativo no momento',
                    ),
                    if (_tracking!['route'] != null) ...[
                      const SizedBox(height: 6),
                      Text('Serviço: ${_tracking!['route']}'),
                    ],
                    if (_tracking!['vehicle'] case final Map<String, dynamic> v)
                      Text('Veículo: ${v['model']} • ${v['plate']}'),
                  ],
                ),
              ),
            ),
            if (point != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 260,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: FlutterMap(
                    options: MapOptions(initialCenter: point, initialZoom: 14),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'board_van',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: point,
                            width: 48,
                            height: 48,
                            child: const Icon(
                              Icons.directions_bus,
                              color: Colors.deepOrange,
                              size: 40,
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
              Text(
                'Última posição recebida: ${location!['updatedAt']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else if (status == 'EM_ROTA') ...[
              const SizedBox(height: 12),
              const Text(
                'A van está em rota, mas não recebemos uma posição recente. '
                'O mapa será atualizado quando o motorista voltar a transmitir GPS.',
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'O mapa atualiza a cada 30 segundos quando aberto e mostra a '
              'última posição recebida; não representa ETA nem previsão de chegada.',
            ),
          ],
        ],
      ),
    );
  }
}

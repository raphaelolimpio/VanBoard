
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../core/api_client.dart';

const _weekdayShortNames = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

LocationSettings driverLocationSettingsFor(
  TargetPlatform platform, {
  bool isWeb = kIsWeb,
}) {
  if (isWeb) {
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
  }
  return switch (platform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Rota ativa • BoardVan',
          notificationText:
              'A localização da van está sendo compartilhada com a empresa.',
          notificationChannelName: 'Rastreamento da rota',
          setOngoing: true,
        ),
      ),
      TargetPlatform.iOS => AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      ),
      _ => const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    };
}

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({
    super.key,
    required this.user,
    required this.onLogout,
  });

  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen>
    with WidgetsBindingObserver {
  final _api = ApiClient();
  Map<String, dynamic>? _data;
  String? _error;
  String? _locationError;
  bool _loading = true;
  String? _trackingRunId;
  LatLng? _livePosition;
  StreamSubscription<Position>? _positionSubscription;
  io.Socket? _socket;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _connectSocket();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshLocationAfterResume();
    }
  }

  Future<void> _refreshLocationAfterResume() async {
    final runId = _trackingRunId;
    if (runId == null) return;
    try {
      final position = await Geolocator.getCurrentPosition();
      if (!mounted || _trackingRunId != runId) return;
      await _sendPosition(runId, position);
    } catch (error) {
      if (mounted && _trackingRunId == runId) {
        setState(() => _locationError = 'Falha ao atualizar a localização: $error');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSubscription?.cancel();
    _socket?.dispose();
    super.dispose();
  }

  Future<void> _connectSocket() async {
    final token = await _api.token;
    if (!mounted || token == null) return;
    final socket = io.io(
      _api.baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .build(),
    );
    socket.on('emergency:offer', (dynamic _) {
      _showMessage('Uma van precisa de apoio. Confira a oferta recebida.');
      _load();
    });
    socket.on('emergency:created', (dynamic _) {
      _showMessage('Ocorrência informada na frota.');
      _load();
    });
    socket.on('emergency:accepted', (dynamic _) => _load());
    socket.connect();
    _socket = socket;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.get('/driver/me');
      if (!mounted) return;
      setState(() => _data = data);
      final activeRuns = (data['activeRuns'] as List?) ?? const [];
      if (activeRuns.isEmpty) {
        await _stopTracking();
      } else {
        await _startTracking(activeRuns.first['id'].toString());
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _showMessage(
        'Ative o serviço de localização do aparelho para iniciar a rota.',
      );
      return false;
    }
    var permission = await Geolocator.checkPermission();
    final requiresBackgroundPermission =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (requiresBackgroundPermission &&
        permission != LocationPermission.always) {
      if (!mounted) return false;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Localização durante a rota'),
          content: const Text(
            'Enquanto uma rota estiver ativa, o BoardVan compartilha a posição da van com a empresa mesmo quando a tela estiver bloqueada. O compartilhamento termina ao encerrar a rota.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Agora não'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return false;
    }
    if (permission == LocationPermission.denied ||
        (requiresBackgroundPermission &&
            permission == LocationPermission.whileInUse)) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _showMessage(
        permission == LocationPermission.deniedForever
            ? 'Permita o acesso à localização nas configurações do aparelho.'
            : 'A permissão de localização é necessária durante a rota.',
      );
      return false;
    }
    if (requiresBackgroundPermission && permission != LocationPermission.always) {
      _showMessage(
        'Para compartilhar a rota com a tela bloqueada, permita a localização "Sempre" ou "O tempo todo" nas configurações do aparelho.',
      );
      return false;
    }
    return true;
  }

  Future<void> _startTracking(String runId) async {
    if (_trackingRunId == runId) return;
    if (!await _ensureLocationPermission()) return;
    await _positionSubscription?.cancel();
    _trackingRunId = runId;
    try {
      final current = await Geolocator.getCurrentPosition();
      await _sendPosition(runId, current);
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: driverLocationSettingsFor(defaultTargetPlatform),
          )          .listen(
          (position) {
            _sendPosition(runId, position);
            },
            onError: (Object error) {
              if (mounted) setState(() => _locationError = error.toString());
            },
          );
    } catch (error) {
      _trackingRunId = null;
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      if (mounted) {
        setState(() => _locationError = 'Falha ao obter localização: $error');
      }
    }
  }

  Future<void> _sendPosition(String runId, Position position) async {
    try {
      await _api.post(
        '/driver/runs/$runId/location',
        body: {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'heading': position.heading,
          'speed': position.speed,
        },
      );
      if (mounted && _trackingRunId == runId) {
        setState(() {
          _livePosition = LatLng(position.latitude, position.longitude);
          _locationError = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _locationError = error.toString());
    }
  }

  Future<void> _stopTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _trackingRunId = null;
    if (mounted) setState(() => _livePosition = null);
  }

  Future<void> _startRun(
    Map<String, dynamic> vehicle, {
    String? routeId,
    String? charterTripId,
  }) async {
    if (!await _ensureLocationPermission()) return;
    try {
      final inspection = await _requestInspection();
      if (inspection == null) return;
      final inspectionBody = <String, dynamic>{...inspection};
      if (charterTripId != null) {
        inspectionBody['charterTripId'] = charterTripId;
      }
      await _api.post(
        '/driver/vehicles/${vehicle['id']}/inspections',
        body: inspectionBody,
      );
      final body = <String, dynamic>{'vehicleId': vehicle['id']};
      if (routeId != null) body['routeId'] = routeId;
      if (charterTripId != null) body['charterTripId'] = charterTripId;
      await _api.post('/driver/runs/start', body: body);
      await _load();
      _showMessage('Rota iniciada. A localização está sendo compartilhada.');
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  Future<void> _endRun(Map<String, dynamic> run) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Encerrar rota?'),
        content: const Text('A localização ao vivo será interrompida.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar rota'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Encerrar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.post('/driver/runs/${run['id']}/end');
      await _stopTracking();
      await _load();
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  Future<void> _markAttendance(
    Map<String, dynamic> run,
    Map<String, dynamic> assignment,
    String direction,
  ) async {
    try {
      await _api.post(
        '/driver/runs/${run['id']}/attendance',
        body: {'studentId': assignment['studentId'], 'direction': direction},
      );
      await _load();
      _showMessage('Presença de ${assignment['student']['name']} registrada.');
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  Future<void> _updateCharterPassenger(
    String tripId,
    Map<String, dynamic> passenger,
    String status,
  ) async {
    try {
      await _api.patch(
        '/trips/$tripId/passengers/${passenger['id']}/status',
        body: {'status': status},
      );
      await _load();
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  Future<void> _requestHelp(
    Map<String, dynamic> run,
    Map<String, dynamic> assignment,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Solicitar van substituta?'),
        content: Text(
          'Será enviada uma solicitação para buscar ${assignment['student']['name']} nesta viagem. '
          'A van titular do aluno não será alterada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Solicitar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.post(
        '/driver/runs/${run['id']}/emergencies',
        body: {
          'studentId': assignment['studentId'],
          'description': 'Van indisponível durante a rota.',
        },
      );
      await _load();
      _showMessage('Solicitação enviada à van disponível mais próxima.');
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  Future<void> _respondOffer(
    Map<String, dynamic> offer,
    String response,
  ) async {
    try {
      if (response == 'ACCEPTED') {
        final vehicle = Map<String, dynamic>.from(offer['vehicle'] as Map);
        final inspection = await _requestInspection();
        if (inspection == null) return;
        await _api.post(
          '/driver/vehicles/${vehicle['id']}/inspections',
          body: {...inspection, 'offerId': offer['id']},
        );
      }
      await _api.post(
        '/driver/emergency-offers/${offer['id']}/respond',
        body: {'response': response},
      );
      await _load();
      _showMessage(
        response == 'ACCEPTED'
            ? 'Substituição aceita. O aluno foi incluído apenas nesta viagem.'
            : 'Oferta recusada.',
      );
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  Future<Map<String, dynamic>?> _requestInspection() =>
      showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => const _PreTripInspectionDialog(),
      );

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.user['name']?.toString() ?? 'Motorista';
    return Scaffold(
      appBar: AppBar(
        title: Text('Olá, $name'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
          IconButton(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
          ),
        ],
      ),
      body: _loading && _data == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _data == null
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
                  if (_locationError != null)
                    Card(
                      color: Colors.orange.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_locationError!),
                      ),
                    ),
                  _buildOffers(),
                  _buildRuns(),
                  _buildScheduledServices(),
                  _buildVehicles(),
                ],
              ),
            ),
    );
  }

  Widget _buildOffers() {
    final offers = (_data?['offers'] as List?) ?? const [];
    if (offers.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Solicitações de apoio',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        ...offers.map((raw) {
          final offer = Map<String, dynamic>.from(raw as Map);
          final request = offer['request'] as Map<String, dynamic>;
          final student = request['student'] as Map<String, dynamic>;
          final distance = (offer['distanceMeters'] as num?)?.round();
          return Card(
            color: Colors.amber.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Buscar ${student['name']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Van parada ${request['brokenVehicle']['plate']} • ${student['pickupAddr']}',
                  ),
                  if (distance != null)
                    Text('A aproximadamente $distance m da sua van'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: () => _respondOffer(offer, 'ACCEPTED'),
                        child: const Text('Aceitar'),
                      ),
                      OutlinedButton(
                        onPressed: () => _respondOffer(offer, 'DECLINED'),
                        child: const Text('Recusar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildRuns() {
    final runs = (_data?['activeRuns'] as List?) ?? const [];
    if (runs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Rota em andamento',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        ...runs.map((raw) => _buildRun(Map<String, dynamic>.from(raw as Map))),
      ],
    );
  }

  Widget _buildRun(Map<String, dynamic> run) {
    final assignments = ((run['assignments'] as List?) ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final route = run['route'] as Map<String, dynamic>?;
    final routeStops = (route?['stopsOrder'] as List? ?? const [])
        .map((stop) => stop.toString())
        .toList();
    assignments.sort((a, b) {
      int stopIndex(Map<String, dynamic> assignment) {
        final address = assignment['student']['pickupAddr'].toString();
        final exact = routeStops.indexOf(address);
        if (exact >= 0) return exact;
        final partial = routeStops.indexWhere(
          (stop) =>
              stop.isNotEmpty &&
              (address.contains(stop) || stop.contains(address)),
        );
        return partial >= 0 ? partial : routeStops.length;
      }

      return stopIndex(a).compareTo(stopIndex(b));
    });
    final routePoints = assignments
        .map((assignment) => assignment['student'] as Map<String, dynamic>)
        .where(
          (student) =>
              student['pickupLatitude'] is num &&
              student['pickupLongitude'] is num,
        )
        .map(
          (student) => LatLng(
            (student['pickupLatitude'] as num).toDouble(),
            (student['pickupLongitude'] as num).toDouble(),
          ),
        )
        .toList();
    final location = run['vehicle']['location'] as Map<String, dynamic>?;
    final center =
        _livePosition ??
        (routePoints.isNotEmpty
            ? routePoints.first
            : location != null
            ? LatLng(
                (location['latitude'] as num).toDouble(),
                (location['longitude'] as num).toDouble(),
              )
            : const LatLng(-10.184, -48.333));
    final trip = run['charterTrip'] as Map<String, dynamic>?;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${run['vehicle']['model']} • ${run['vehicle']['plate']}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            Text(
              route?['name']?.toString() ??
                  (trip == null
                      ? 'Serviço ${run['purpose']}'
                      : '${trip['origin']} → ${trip['destination']}'),
            ),
            if (route != null)
              Text('Horário: ${route['startTime']}–${route['endTime']}'),
            if (trip != null) ...[
              Text('Cliente: ${trip['clientName']} • ${trip['clientPhone']}'),
              Text(
                'Horário previsto: '
                '${_dateTimeLabel(DateTime.parse(trip['departureDate'].toString()).toLocal())} – '
                '${_dateTimeLabel(DateTime.parse(trip['returnDate'].toString()).toLocal())}',
              ),
              if (trip['notes'] != null && trip['notes'].toString().isNotEmpty)
                Text('Observações: ${trip['notes']}'),
              if ((trip['passengers'] as List? ?? const []).isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Manifesto de passageiros',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ...(trip['passengers'] as List).map((rawPassenger) {
                  final passenger = Map<String, dynamic>.from(
                    rawPassenger as Map,
                  );
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(passenger['name'].toString()),
                    subtitle: Text(
                      '${passenger['status']}'
                      '${passenger['pickupPoint'] == null ? '' : ' • ${passenger['pickupPoint']}'}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (status) => _updateCharterPassenger(
                        trip['id'].toString(),
                        passenger,
                        status,
                      ),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'EMBARCADO',
                          child: Text('Marcar embarcado'),
                        ),
                        PopupMenuItem(
                          value: 'DESEMBARCADO',
                          child: Text('Marcar desembarcado'),
                        ),
                        PopupMenuItem(
                          value: 'AUSENTE',
                          child: Text('Marcar ausente'),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
            if (routeStops.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text(
                'Paradas na ordem definida',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              ...routeStops.asMap().entries.map(
                (entry) => Text('${entry.key + 1}. ${entry.value}'),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              height: 190,
              child: FlutterMap(
                options: MapOptions(initialCenter: center, initialZoom: 14),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'board_van',
                  ),
                  if (routePoints.length > 1)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: routePoints,
                          color: Colors.indigo,
                          strokeWidth: 4,
                        ),
                      ],
                    ),
                  if (routePoints.isNotEmpty || _livePosition != null)
                    MarkerLayer(
                      markers: [
                        for (var index = 0; index < assignments.length; index++)
                          if (assignments[index]['student']['pickupLatitude']
                                  is num &&
                              assignments[index]['student']['pickupLongitude']
                                  is num)
                            Marker(
                              point: LatLng(
                                (assignments[index]['student']['pickupLatitude']
                                        as num)
                                    .toDouble(),
                                (assignments[index]['student']['pickupLongitude']
                                        as num)
                                    .toDouble(),
                              ),
                              width: 36,
                              height: 36,
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: Colors.white,
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        if (_livePosition != null)
                          Marker(
                            point: _livePosition!,
                            width: 48,
                            height: 48,
                            child: const Icon(
                              Icons.directions_bus,
                              color: Colors.indigo,
                              size: 38,
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
            const SizedBox(height: 10),
            if (assignments.isNotEmpty) ...[
              const Text(
                'Alunos desta viagem',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ...assignments.map((assignment) {
                final student = assignment['student'] as Map<String, dynamic>;
                final attendances =
                    (student['attendances'] as List?) ?? const [];
                bool boardedFor(String direction) => attendances.any(
                  (attendance) =>
                      attendance['serviceRunId'] == run['id'] &&
                      attendance['direction'] == direction,
                );
                final idaDone = boardedFor('IDA');
                final voltaDone = boardedFor('VOLTA');
                return Card(
                  color: assignment['temporary'] == true
                      ? Colors.amber.shade50
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    student['name'].toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${student['pickupAddr']} • ${student['schoolName']}',
                                  ),
                                  if (assignment['temporary'] == true)
                                    const Text(
                                      'Transferido apenas nesta viagem',
                                      style: TextStyle(
                                        color: Colors.deepOrange,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Solicitar apoio para este aluno',
                              onPressed: () => _requestHelp(run, assignment),
                              icon: const Icon(
                                Icons.warning_amber,
                                color: Colors.deepOrange,
                              ),
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: idaDone
                                  ? null
                                  : () =>
                                        _markAttendance(run, assignment, 'IDA'),
                              child: Text(
                                idaDone ? 'Ida registrada' : 'Chamada de ida',
                              ),
                            ),
                            OutlinedButton(
                              onPressed: voltaDone
                                  ? null
                                  : () => _markAttendance(
                                      run,
                                      assignment,
                                      'VOLTA',
                                    ),
                              child: Text(
                                voltaDone
                                    ? 'Volta registrada'
                                    : 'Chamada de volta',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ] else
              const Text('Esta viagem não possui alunos escolares vinculados.'),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () => _endRun(run),
                child: const Text('Encerrar rota'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicles() {
    final runs = (_data?['activeRuns'] as List?) ?? const [];
    if (runs.isNotEmpty) return const SizedBox.shrink();
    final vehicles = (_data?['vehicles'] as List?) ?? const [];
    if (vehicles.isEmpty) {
      if (((_data?['scheduledServices'] as List?) ?? const []).isNotEmpty) {
        return const SizedBox.shrink();
      }
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Nenhuma van foi atribuída a este motorista. Peça ao proprietário para fazer o cadastro.',
          ),
        ),
      );
    }
    final offers = (_data?['offers'] as List?) ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Próximas rotas e viagens',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        ...vehicles.map((raw) {
          final vehicle = Map<String, dynamic>.from(raw as Map);
          final routes = (vehicle['schoolRoutes'] as List?) ?? const [];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${vehicle['model']} • ${vehicle['plate']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ...routes.map((rawRoute) {
                    final route = Map<String, dynamic>.from(rawRoute as Map);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(route['name'].toString()),
                      subtitle: Text(
                        '${route['shift']} • ${route['startTime']}–${route['endTime']} • '
                        '${(route['daysOfWeek'] as List? ?? const []).map((day) => _weekdayShortNames[day as int]).join(', ')}',
                      ),
                      trailing: FilledButton(
                        onPressed: offers.isNotEmpty
                            ? null
                            : () => _startRun(
                                vehicle,
                                routeId: route['id'].toString(),
                              ),
                        child: const Text('Iniciar'),
                      ),
                    );
                  }),
                  if (routes.isEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: offers.isNotEmpty
                            ? null
                            : () => _startRun(vehicle),
                        child: const Text('Iniciar serviço'),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
        if (offers.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Responda à solicitação de apoio antes de iniciar outra rota.',
            ),
          ),
      ],
    );
  }

  Widget _buildScheduledServices() {
    final runs = (_data?['activeRuns'] as List?) ?? const [];
    final services = (_data?['scheduledServices'] as List?) ?? const [];
    if (runs.isNotEmpty || services.isEmpty) return const SizedBox.shrink();
    final offers = (_data?['offers'] as List?) ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Serviços escalados para você',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        ...services.map((raw) {
          final service = Map<String, dynamic>.from(raw as Map);
          final vehicle = Map<String, dynamic>.from(service['vehicle'] as Map);
          final departure = DateTime.parse(service['departureDate'].toString())
              .toLocal();
          final returned = DateTime.parse(service['returnDate'].toString())
              .toLocal();
          final value = double.tryParse('${service['agreedValue']}') ?? 0;
          return Card(
            child: ListTile(
              leading: Icon(
                service['type'] == 'EVENTOS' ? Icons.event : Icons.tour,
              ),
              title: Text('${service['origin']} → ${service['destination']}'),
              subtitle: Text(
                '${service['clientName']} • ${service['clientPhone']}\n'
                '${_dateTimeLabel(departure)} – ${_dateTimeLabel(returned)}\n'
                '${vehicle['plate']} • R\$ ${value.toStringAsFixed(2)}'
                '${service['notes'] == null || service['notes'].toString().isEmpty ? '' : '\n${service['notes']}'}',
              ),
              isThreeLine: true,
              trailing: FilledButton(
                onPressed:
                    offers.isNotEmpty ||
                        ['DANIFICADA', 'MANUTENCAO'].contains(vehicle['status'])
                    ? null
                    : () => _startRun(
                        vehicle,
                        charterTripId: service['id'].toString(),
                      ),
                child: const Text('Iniciar'),
              ),
            ),
          );
        }),
      ],
    );
  }

  String _dateTimeLabel(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year} ${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

class _PreTripInspectionDialog extends StatefulWidget {
  const _PreTripInspectionDialog();

  @override
  State<_PreTripInspectionDialog> createState() =>
      _PreTripInspectionDialogState();
}

class _PreTripInspectionDialogState extends State<_PreTripInspectionDialog> {
  final _notes = TextEditingController();
  bool _tiresOk = false;
  bool _lightsOk = false;
  bool _brakesOk = false;
  bool _documentsOk = false;
  bool _cleanlinessOk = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Inspeção pré-viagem'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Marque apenas itens que foram conferidos e estão em condições '
              'seguras. Uma reprovação impede o início da rota.',
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _tiresOk,
              title: const Text('Pneus e rodas'),
              onChanged: (value) => setState(() => _tiresOk = value ?? false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _lightsOk,
              title: const Text('Faróis e sinalização'),
              onChanged: (value) => setState(() => _lightsOk = value ?? false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _brakesOk,
              title: const Text('Freios'),
              onChanged: (value) => setState(() => _brakesOk = value ?? false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _documentsOk,
              title: const Text('Documentos do veículo'),
              onChanged: (value) =>
                  setState(() => _documentsOk = value ?? false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _cleanlinessOk,
              title: const Text('Limpeza e condições internas'),
              onChanged: (value) =>
                  setState(() => _cleanlinessOk = value ?? false),
            ),
            TextField(
              controller: _notes,
              maxLength: 500,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Observações (opcional)',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, {
          'tiresOk': _tiresOk,
          'lightsOk': _lightsOk,
          'brakesOk': _brakesOk,
          'documentsOk': _documentsOk,
          'cleanlinessOk': _cleanlinessOk,
          'notes': _notes.text.trim(),
        }),
        child: const Text('Registrar inspeção'),
      ),
    ],
  );
}

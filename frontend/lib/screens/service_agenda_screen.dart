import 'package:flutter/material.dart';

import '../components/empty_state.dart';
import '../core/api_client.dart';
import 'charter_trip_detail_screen.dart';

class ServiceAgendaScreen extends StatefulWidget {
  const ServiceAgendaScreen({super.key, required this.companyId, this.api});

  final String companyId;
  final ApiClient? api;

  @override
  State<ServiceAgendaScreen> createState() => _ServiceAgendaScreenState();
}

class _ServiceAgendaScreenState extends State<ServiceAgendaScreen> {
  late final _api = widget.api ?? ApiClient();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<dynamic> _trips = [];
  List<dynamic> _schoolRoutes = [];
  List<dynamic> _vehicles = [];
  List<dynamic> _drivers = [];
  bool _loading = true;
  String? _error;
  String _purpose = 'TODOS';

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _dateParameter(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String get _monthLabel {
    const months = [
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    return '${months[_month.month - 1]} de ${_month.year}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final firstDay = DateTime(_month.year, _month.month, 1);
      final lastDay = DateTime(_month.year, _month.month + 1, 0);
      final results = await Future.wait<dynamic>([
        _api.get(
          '/companies/${widget.companyId}/agenda'
          '?from=${_dateParameter(firstDay)}&to=${_dateParameter(lastDay)}',
        ),
        _api.getMapList('/companies/${widget.companyId}/vehicles'),
        _api.getMapList('/companies/${widget.companyId}/drivers'),
      ]);
      if (!mounted) return;
      setState(() {
        final agenda = Map<String, dynamic>.from(results[0] as Map);
        _trips = ApiClient.decodeMapList(agenda['trips'] ?? const []);
        _schoolRoutes = ApiClient.decodeMapList(
          agenda['schoolRoutes'] ?? const [],
        );
        _vehicles = ApiClient.decodeMapList(results[1]);
        _drivers = ApiClient.decodeMapList(results[2]);
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createTrip() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _TripFormDialog(
        vehicles: ApiClient.decodeMapList(_vehicles),
        drivers: ApiClient.decodeMapList(_drivers),
        onSave: (trip) =>
            _api.post('/trips', body: {'companyId': widget.companyId, ...trip}),
      ),
    );
    if (created == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final trips = _trips.where((raw) {
      final trip = Map<String, dynamic>.from(raw as Map);
      return _purpose == 'TODOS' || trip['type'] == _purpose;
    }).toList();
    final schoolRoutes = _purpose == 'TODOS' || _purpose == 'ESCOLAR'
        ? _schoolRoutes
        : const <dynamic>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda de serviços'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: () {
              setState(() => _month = DateTime(_month.year, _month.month - 1));
              _load();
            },
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Mês anterior',
          ),
          IconButton(
            onPressed: () {
              setState(() => _month = DateTime(_month.year, _month.month + 1));
              _load();
            },
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Próximo mês',
          ),
        ],
      ),
      floatingActionButton: trips.isEmpty && schoolRoutes.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _vehicles.isEmpty || _drivers.isEmpty
                  ? null
                  : _createTrip,
              icon: const Icon(Icons.add),
              label: const Text('Agendar serviço'),
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
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Text(
                        _monthLabel,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          initialValue: _purpose,
                          decoration: const InputDecoration(
                            labelText: 'Tipo de serviço',
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'TODOS',
                              child: Text('Todos'),
                            ),
                            DropdownMenuItem(
                              value: 'ESCOLAR',
                              child: Text('Escolar'),
                            ),
                            DropdownMenuItem(
                              value: 'TURISMO',
                              child: Text('Turismo'),
                            ),
                            DropdownMenuItem(
                              value: 'EVENTOS',
                              child: Text('Eventos'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _purpose = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: trips.isEmpty && schoolRoutes.isEmpty
                      ? EmptyState(
                          icon: Icons.calendar_month_outlined,
                          title: 'Nenhum serviço agendado neste mês.',
                          description: _vehicles.isEmpty || _drivers.isEmpty
                              ? 'Cadastre ao menos um veículo e um motorista '
                                    'para criar um serviço.'
                              : 'Agende um fretamento ou viagem para organizar '
                                    'a operação da sua equipe.',
                          actionLabel: 'Agendar serviço',
                          onAction: _vehicles.isEmpty || _drivers.isEmpty
                              ? null
                              : _createTrip,
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                          children: [
                            if (schoolRoutes.isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  'Rotas escolares recorrentes',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              ...schoolRoutes.map((raw) {
                                final route = Map<String, dynamic>.from(
                                  raw as Map,
                                );
                                final vehicle = Map<String, dynamic>.from(
                                  route['vehicle'] as Map,
                                );
                                final driverValue = vehicle['defaultDriver'];
                                final driver = driverValue is Map
                                    ? Map<String, dynamic>.from(driverValue)
                                    : null;
                                return Card(
                                  child: ListTile(
                                    leading: const Icon(Icons.school),
                                    title: Text(route['name'].toString()),
                                    subtitle: Text(
                                      '${route['shift']} • ${route['startTime']}–${route['endTime']}\n'
                                      '${vehicle['plate']} • ${driver?['name'] ?? 'Sem motorista titular'}\n'
                                      'Agenda recorrente por turno (sem data individual).',
                                    ),
                                    isThreeLine: true,
                                  ),
                                );
                              }),
                            ],
                            if (trips.isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  'Fretamentos e viagens do mês',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ...trips.map((trip) {
                              final tripMap = Map<String, dynamic>.from(
                                trip as Map,
                              );
                              final departure = DateTime.parse(
                                tripMap['departureDate'] as String,
                              ).toLocal();
                              final returned = DateTime.parse(
                                tripMap['returnDate'] as String,
                              ).toLocal();
                              final vehicle = Map<String, dynamic>.from(
                                tripMap['vehicle'] as Map,
                              );
                              final driverValue = tripMap['driver'];
                              final driver = driverValue is Map
                                  ? Map<String, dynamic>.from(driverValue)
                                  : null;
                              final type = tripMap['type'] as String;
                              final value =
                                  double.tryParse(
                                    '${tripMap['agreedValue']}',
                                  ) ??
                                  0;
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    child: Icon(
                                      type == 'EVENTOS'
                                          ? Icons.event
                                          : Icons.tour,
                                    ),
                                  ),
                                  title: Text(
                                    '${tripMap['origin']} → ${tripMap['destination']}',
                                  ),
                                  subtitle: Text(
                                    '${type == 'EVENTOS' ? 'Evento' : 'Turismo'} • '
                                    '${_dateTimeLabel(departure)} – ${_dateTimeLabel(returned)}\n'
                                    '${tripMap['clientName']} • ${vehicle['plate']} • '
                                    '${driver?['name'] ?? 'Sem motorista'}\n'
                                    'Status: ${_statusLabel(tripMap['status'])}',
                                  ),
                                  isThreeLine: true,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => CharterTripDetailScreen(
                                        companyId: widget.companyId,
                                        trip: tripMap,
                                      ),
                                    ),
                                  ),
                                  trailing: Text(
                                    'R\$ ${value.toStringAsFixed(2)}',
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  String _dateTimeLabel(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  String _statusLabel(String status) => switch (status) {
    'ORCAMENTO' => 'Orçamento',
    'AGENDADO' => 'Agendado',
    'EM_ANDAMENTO' => 'Em andamento',
    'CONCLUIDO' => 'Concluído',
    'CANCELADO' => 'Cancelado',
    _ => status,
  };
}

class _TripFormDialog extends StatefulWidget {
  const _TripFormDialog({
    required this.vehicles,
    required this.drivers,
    required this.onSave,
  });

  final List<Map<String, dynamic>> vehicles;
  final List<Map<String, dynamic>> drivers;
  final Future<void> Function(Map<String, dynamic> trip) onSave;

  @override
  State<_TripFormDialog> createState() => _TripFormDialogState();
}

class _TripFormDialogState extends State<_TripFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _client = TextEditingController();
  final _phone = TextEditingController();
  final _origin = TextEditingController();
  final _destination = TextEditingController();
  final _value = TextEditingController();
  final _notes = TextEditingController();
  DateTime _departure = DateTime.now().add(const Duration(days: 1));
  DateTime _return = DateTime.now().add(const Duration(days: 1, hours: 2));
  String _type = 'TURISMO';
  String? _vehicleId;
  String? _driverId;
  String? _error;
  bool _saving = false;

  static const _examples = <String, Map<String, String>>{
    'Passeio turístico': {
      'type': 'TURISMO',
      'origin': 'Hotel ou ponto de encontro',
      'destination': 'Roteiro turístico da cidade',
      'notes': 'Passeio com paradas em pontos turísticos.',
    },
    'Transfer aeroporto': {
      'type': 'TURISMO',
      'origin': 'Aeroporto',
      'destination': 'Hotel ou endereço do passageiro',
      'notes': 'Transfer privativo de chegada ou partida.',
    },
    'Transporte para evento': {
      'type': 'EVENTOS',
      'origin': 'Ponto de embarque combinado',
      'destination': 'Local do evento',
      'notes': 'Transporte de ida e retorno para evento.',
    },
  };

  @override
  void dispose() {
    _client.dispose();
    _phone.dispose();
    _origin.dispose();
    _destination.dispose();
    _value.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _eligibleVehicles => widget.vehicles
      .where((vehicle) => (vehicle['purposes'] as List? ?? []).contains(_type))
      .toList();

  Future<void> _chooseDate(bool isDeparture) async {
    final current = isDeparture ? _departure : _return;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    final updated = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (isDeparture) {
        _departure = updated;
        if (_return.isBefore(updated)) {
          _return = updated.add(const Duration(hours: 2));
        }
      } else {
        _return = updated;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_vehicleId == null || _driverId == null) {
      setState(() => _error = 'Selecione a van e o motorista escalado.');
      return;
    }
    if (_return.isBefore(_departure)) {
      setState(() => _error = 'O retorno não pode ocorrer antes da saída.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave({
        'vehicleId': _vehicleId,
        'driverId': _driverId,
        'type': _type,
        'clientName': _client.text.trim(),
        'clientPhone': _phone.text.trim(),
        'origin': _origin.text.trim(),
        'destination': _destination.text.trim(),
        'departureDate': _departure.toUtc().toIso8601String(),
        'returnDate': _return.toUtc().toIso8601String(),
        'agreedValue': double.parse(_value.text.replaceAll(',', '.')),
        'notes': _notes.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eligibleVehicles = _eligibleVehicles;
    if (_vehicleId != null &&
        !eligibleVehicles.any((item) => item['id'] == _vehicleId)) {
      _vehicleId = null;
    }
    return AlertDialog(
      title: const Text('Agendar serviço'),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.65,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(
                      labelText: 'Modelo de serviço',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'TURISMO',
                        child: Text('Turismo / transfer'),
                      ),
                      DropdownMenuItem(
                        value: 'EVENTOS',
                        child: Text('Evento / fretamento'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _type = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 6,
                      children: _examples.entries.map((example) {
                        return ActionChip(
                          label: Text(example.key),
                          onPressed: () {
                            final data = example.value;
                            setState(() {
                              _type = data['type']!;
                              _origin.text = data['origin']!;
                              _destination.text = data['destination']!;
                              _notes.text = data['notes']!;
                              _vehicleId = null;
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  _field(_client, 'Cliente / contratante'),
                  _field(
                    _phone,
                    'Telefone do cliente',
                    keyboard: TextInputType.phone,
                  ),
                  _field(_origin, 'Origem'),
                  _field(_destination, 'Destino'),
                  DropdownButtonFormField<String>(
                    initialValue: _vehicleId,
                    decoration: const InputDecoration(
                      labelText: 'Van escalada',
                    ),
                    items: eligibleVehicles
                        .map(
                          (vehicle) => DropdownMenuItem<String>(
                            value: vehicle['id'] as String,
                            child: Text(
                              '${vehicle['plate']} • ${vehicle['model']}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _vehicleId = value),
                    validator: (value) =>
                        value == null ? 'Selecione uma van.' : null,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _driverId,
                    decoration: const InputDecoration(
                      labelText: 'Motorista escalado',
                    ),
                    items: widget.drivers
                        .map(
                          (driver) => DropdownMenuItem<String>(
                            value: driver['id'] as String,
                            child: Text(driver['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _driverId = value),
                    validator: (value) =>
                        value == null ? 'Selecione um motorista.' : null,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Saída'),
                    subtitle: Text(_dateTimeLabel(_departure)),
                    trailing: const Icon(Icons.calendar_month),
                    onTap: () => _chooseDate(true),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Retorno'),
                    subtitle: Text(_dateTimeLabel(_return)),
                    trailing: const Icon(Icons.calendar_month),
                    onTap: () => _chooseDate(false),
                  ),
                  _field(
                    _value,
                    'Valor combinado (R\$)',
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  _field(_notes, 'Observações', required: false),
                  if (_error != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Salvar na agenda'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboard,
    bool required = true,
  }) => TextFormField(
    controller: controller,
    keyboardType: keyboard,
    decoration: InputDecoration(labelText: label),
    validator: (value) {
      if (!required) return null;
      if (value == null || value.trim().isEmpty) return 'Campo obrigatório.';
      if (identical(controller, _value) &&
          double.tryParse(value.trim().replaceAll(',', '.')) == null) {
        return 'Informe um valor numérico.';
      }
      return null;
    },
  );

  String _dateTimeLabel(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year} ${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

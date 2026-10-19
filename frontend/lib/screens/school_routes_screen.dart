import 'package:flutter/material.dart';

import '../core/api_client.dart';

const _weekdayNames = [
  'Domingo',
  'Segunda',
  'Terça',
  'Quarta',
  'Quinta',
  'Sexta',
  'Sábado',
];

class SchoolRoutesScreen extends StatefulWidget {
  const SchoolRoutesScreen({
    super.key,
    required this.vehicleId,
    required this.initialRoutes,
  });

  final String vehicleId;
  final List<dynamic> initialRoutes;

  @override
  State<SchoolRoutesScreen> createState() => _SchoolRoutesScreenState();
}

class _SchoolRoutesScreenState extends State<SchoolRoutesScreen> {
  final _api = ApiClient();
  late List<dynamic> _routes = widget.initialRoutes;

  Future<void> _edit([Map<String, dynamic>? route]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _RouteFormDialog(vehicleId: widget.vehicleId, route: route),
    );
    if (saved == true) {
      final contextData = await _api.get(
        '/vehicles/${widget.vehicleId}/context',
      );
      final module = contextData['modules']['escolar'] as Map<String, dynamic>;
      if (mounted) setState(() => _routes = module['routes'] as List<dynamic>);
    }
  }

  Future<void> _delete(Map<String, dynamic> route) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir rota?'),
        content: Text(
          'A rota "${route['name']}" será removida. O histórico das viagens será preservado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.delete('/school-routes/${route['id']}');
      final contextData = await _api.get(
        '/vehicles/${widget.vehicleId}/context',
      );
      final module = contextData['modules']['escolar'] as Map<String, dynamic>;
      if (mounted) setState(() => _routes = module['routes'] as List<dynamic>);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rotas escolares'),
        actions: [
          IconButton(onPressed: () => _edit(), icon: const Icon(Icons.add)),
        ],
      ),
      body: _routes.isEmpty
          ? const Center(child: Text('Nenhuma rota cadastrada para esta van.'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: _routes.map((raw) {
                final route = Map<String, dynamic>.from(raw as Map);
                final stops = (route['stopsOrder'] as List? ?? const [])
                    .map((stop) => stop.toString())
                    .join(' → ');
                final weekdays = (route['daysOfWeek'] as List? ?? const [])
                    .map((day) => _weekdayNames[day as int])
                    .join(', ');
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.alt_route),
                    title: Text(route['name'].toString()),
                    subtitle: Text(
                      '${route['shift']} • ${route['startTime']}–${route['endTime']}'
                      '${weekdays.isEmpty ? '' : '\n$weekdays'}'
                      '${stops.isEmpty ? '' : '\n$stops'}',
                    ),
                    isThreeLine: stops.isNotEmpty || weekdays.isNotEmpty,
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'edit') _edit(route);
                        if (action == 'delete') _delete(route);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Editar')),
                        PopupMenuItem(value: 'delete', child: Text('Excluir')),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Nova rota'),
      ),
    );
  }
}

class _RouteFormDialog extends StatefulWidget {
  const _RouteFormDialog({required this.vehicleId, this.route});

  final String vehicleId;
  final Map<String, dynamic>? route;

  @override
  State<_RouteFormDialog> createState() => _RouteFormDialogState();
}

class _RouteFormDialogState extends State<_RouteFormDialog> {
  final _api = ApiClient();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _start;
  late final TextEditingController _end;
  late final TextEditingController _stops;
  late String _shift;
  late Set<int> _daysOfWeek;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final route = widget.route ?? {};
    _name = TextEditingController(text: route['name']?.toString() ?? '');
    _start = TextEditingController(text: route['startTime']?.toString() ?? '');
    _end = TextEditingController(text: route['endTime']?.toString() ?? '');
    _stops = TextEditingController(
      text: (route['stopsOrder'] as List? ?? const []).join('\n'),
    );
    _shift = route['shift']?.toString() ?? 'MANHA';
    _daysOfWeek = (route['daysOfWeek'] as List? ?? [1, 2, 3, 4, 5])
        .map((day) => day as int)
        .toSet();
  }

  @override
  void dispose() {
    _name.dispose();
    _start.dispose();
    _end.dispose();
    _stops.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'vehicleId': widget.vehicleId,
      'name': _name.text.trim(),
      'shift': _shift,
      'startTime': _start.text.trim(),
      'endTime': _end.text.trim(),
      'daysOfWeek': _daysOfWeek.toList()..sort(),
      'stopsOrder': _stops.text
          .split('\n')
          .map((stop) => stop.trim())
          .where((stop) => stop.isNotEmpty)
          .toList(),
    };
    try {
      if (widget.route == null) {
        await _api.post('/school-routes', body: body);
      } else {
        await _api.patch('/school-routes/${widget.route!['id']}', body: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.route == null ? 'Nova rota' : 'Editar rota'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(_name, 'Nome da rota'),
                DropdownButtonFormField<String>(
                  initialValue: _shift,
                  decoration: const InputDecoration(labelText: 'Turno'),
                  items: const [
                    DropdownMenuItem(value: 'MANHA', child: Text('Manhã')),
                    DropdownMenuItem(value: 'TARDE', child: Text('Tarde')),
                    DropdownMenuItem(value: 'NOITE', child: Text('Noite')),
                    DropdownMenuItem(
                      value: 'INTEGRAL',
                      child: Text('Integral'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _shift = value ?? _shift),
                ),
                _field(_start, 'Horário de início', hint: '06:30'),
                _field(_end, 'Horário previsto de término', hint: '07:30'),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('Dias de operação'),
                  ),
                ),
                Wrap(
                  spacing: 4,
                  children: List.generate(7, (day) {
                    final selected = _daysOfWeek.contains(day);
                    return FilterChip(
                      label: Text(_weekdayNames[day]),
                      selected: selected,
                      onSelected: (value) => setState(() {
                        if (value) {
                          _daysOfWeek.add(day);
                        } else {
                          _daysOfWeek.remove(day);
                        }
                      }),
                    );
                  }),
                ),
                if (_daysOfWeek.isEmpty)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Selecione pelo menos um dia.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                TextFormField(
                  controller: _stops,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Paradas na ordem da rota',
                    hintText: 'Endereço ou ponto de referência, um por linha',
                    alignLabelWithHint: true,
                  ),
                ),
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
              : const Text('Salvar'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
  }) => TextFormField(
    controller: controller,
    decoration: InputDecoration(labelText: label, hintText: hint),
    validator: (value) =>
        value == null || value.trim().isEmpty ? 'Campo obrigatório.' : null,
  );
}

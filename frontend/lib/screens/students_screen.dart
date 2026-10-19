import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/empty_state.dart';
import '../core/api_client.dart';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({
    super.key,
    required this.companyId,
    this.vehicles = const [],
  });

  final String companyId;
  final List<Map<String, dynamic>> vehicles;

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  final _api = ApiClient();
  List<dynamic> _students = [];
  List<Map<String, dynamic>> _vehicles = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _vehicles = widget.vehicles;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _api.getList(
        '/companies/${widget.companyId}/students',
      );
      final vehicles = widget.vehicles.isEmpty
          ? await _api.getList('/companies/${widget.companyId}/vehicles')
          : widget.vehicles;
      if (mounted) {
        setState(() {
          _students = result;
          _vehicles = vehicles
              .map((vehicle) => Map<String, dynamic>.from(vehicle as Map))
              .toList();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editStudent([Map<String, dynamic>? student]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _StudentFormDialog(
        companyId: widget.companyId,
        vehicles: _vehicles
            .where(
              (vehicle) =>
                  (vehicle['purposes'] as List? ?? []).contains('ESCOLAR'),
            )
            .toList(),
        student: student,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _deleteStudent(Map<String, dynamic> student) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desativar aluno?'),
        content: Text(
          '${student['name']} deixará de aparecer nas próximas listas de rota. O histórico será preservado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desativar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.delete('/students/${student['id']}');
      _load();
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createTrackingGrant(Map<String, dynamic> student) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Criar acesso familiar?'),
        content: Text(
          'Confirme que o responsável de ${student['name']} autorizou o '
          'compartilhamento temporário da localização da van. O código terá '
          'validade de 12 horas e poderá ser revogado a qualquer momento.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar autorização'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final result = await _api.post(
        '/students/${student['id']}/tracking-grants',
        body: {'consentConfirmed': true},
      );
      if (!mounted) return;
      final code = result['trackingCode'] as String;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Código de acompanhamento'),
          content: SelectableText(
            'Envie este código ao responsável. Ele poderá informá-lo na opção '
            '“Acompanhar com código” na tela de entrada. Expira em 12 horas.\n\n'
            '$code',
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copiar código'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Concluir'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<void> _revokeTrackingGrant(Map<String, dynamic> student) async {
    try {
      await _api.delete('/students/${student['id']}/tracking-grants');
      if (mounted) _showMessage('Acesso familiar revogado.');
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alunos'),
        actions: [
          IconButton(
            tooltip: 'Atualizar alunos',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Cadastrar aluno',
            onPressed: () => _editStudent(),
            icon: const Icon(Icons.person_add),
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
          : _students.isEmpty
          ? EmptyState(
              icon: Icons.school_outlined,
              title: 'Nenhum aluno cadastrado',
              description:
                  'Adicione os alunos e associe cada um à van escolar '
                  'responsável pelo trajeto.',
              actionLabel: 'Cadastrar aluno',
              onAction: _editStudent,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _students.length,
                itemBuilder: (context, index) {
                  final student = Map<String, dynamic>.from(_students[index]);
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.school)),
                      title: Text(student['name'] as String),
                      subtitle: Text(
                        '${student['schoolName']} • ${student['shift']} • '
                        '${student['vehicle']?['plate'] ?? 'Sem van'}',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'edit') _editStudent(student);
                          if (action == 'tracking') {
                            _createTrackingGrant(student);
                          }
                          if (action == 'revokeTracking') {
                            _revokeTrackingGrant(student);
                          }
                          if (action == 'delete') _deleteStudent(student);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Editar')),
                          PopupMenuItem(
                            value: 'tracking',
                            child: Text('Criar acesso familiar'),
                          ),
                          PopupMenuItem(
                            value: 'revokeTracking',
                            child: Text('Revogar acesso familiar'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Desativar'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: _loading || _students.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _editStudent(),
              icon: const Icon(Icons.add),
              label: const Text('Novo aluno'),
            ),
    );
  }
}

class _StudentFormDialog extends StatefulWidget {
  const _StudentFormDialog({
    required this.companyId,
    required this.vehicles,
    this.student,
  });

  final String companyId;
  final List<Map<String, dynamic>> vehicles;
  final Map<String, dynamic>? student;

  @override
  State<_StudentFormDialog> createState() => _StudentFormDialogState();
}

class _StudentFormDialogState extends State<_StudentFormDialog> {
  final _api = ApiClient();
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  late String _shift;
  late String _billingType;
  String? _vehicleId;
  bool _hasCellphone = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final student = widget.student ?? {};
    _fields = {
      'name': TextEditingController(text: student['name']?.toString() ?? ''),
      'guardian': TextEditingController(
        text: student['guardian']?.toString() ?? '',
      ),
      'phone': TextEditingController(text: student['phone']?.toString() ?? ''),
      'pickupAddr': TextEditingController(
        text: student['pickupAddr']?.toString() ?? '',
      ),
      'pickupLatitude': TextEditingController(
        text: student['pickupLatitude']?.toString() ?? '',
      ),
      'pickupLongitude': TextEditingController(
        text: student['pickupLongitude']?.toString() ?? '',
      ),
      'schoolName': TextEditingController(
        text: student['schoolName']?.toString() ?? '',
      ),
      'monthlyFee': TextEditingController(
        text: student['monthlyFee']?.toString() ?? '',
      ),
      'dueDay': TextEditingController(
        text: student['dueDay']?.toString() ?? '',
      ),
      'pricePerTrip': TextEditingController(
        text: student['pricePerTrip']?.toString() ?? '',
      ),
    };
    _shift = student['shift']?.toString() ?? 'MANHA';
    _billingType = student['billingType']?.toString() ?? 'MENSAL';
    _vehicleId = student['vehicleId']?.toString();
    _hasCellphone = student['hasCellphone'] != false;
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = <String, dynamic>{
      for (final entry in _fields.entries)
        if (entry.key != 'pickupLatitude' && entry.key != 'pickupLongitude')
          entry.key: entry.value.text.trim(),
      'pickupLatitude': _optionalCoordinate('pickupLatitude'),
      'pickupLongitude': _optionalCoordinate('pickupLongitude'),
      'companyId': widget.companyId,
      'vehicleId': _vehicleId,
      'shift': _shift,
      'billingType': _billingType,
      'hasCellphone': _hasCellphone,
    };
    try {
      if (widget.student == null) {
        await _api.post('/students', body: body);
      } else {
        await _api.patch('/students/${widget.student!['id']}', body: body);
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
    final editing = widget.student != null;
    return AlertDialog(
      title: Text(editing ? 'Editar aluno' : 'Cadastrar aluno'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _textField('name', 'Nome do aluno'),
                _textField('guardian', 'Responsável'),
                _textField(
                  'phone',
                  'Telefone do responsável',
                  keyboard: TextInputType.phone,
                ),
                _textField('pickupAddr', 'Endereço de embarque'),
                _coordinateField(
                  'pickupLatitude',
                  'Latitude do embarque',
                  -90,
                  90,
                ),
                _coordinateField(
                  'pickupLongitude',
                  'Longitude do embarque',
                  -180,
                  180,
                ),
                _textField('schoolName', 'Escola'),
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
                DropdownButtonFormField<String>(
                  initialValue: _vehicleId,
                  decoration: const InputDecoration(labelText: 'Van escolar'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Sem van atribuída'),
                    ),
                    ...widget.vehicles.map(
                      (vehicle) => DropdownMenuItem(
                        value: vehicle['id'] as String,
                        child: Text(
                          '${vehicle['plate']} • ${vehicle['model']}',
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _vehicleId = value),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _billingType,
                  decoration: const InputDecoration(labelText: 'Cobrança'),
                  items: const [
                    DropdownMenuItem(value: 'MENSAL', child: Text('Mensal')),
                    DropdownMenuItem(
                      value: 'POR_VIAGEM',
                      child: Text('Por viagem'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _billingType = value ?? _billingType),
                ),
                if (_billingType == 'MENSAL') ...[
                  _textField(
                    'monthlyFee',
                    'Mensalidade',
                    keyboard: TextInputType.number,
                  ),
                  _textField(
                    'dueDay',
                    'Dia de vencimento',
                    keyboard: TextInputType.number,
                  ),
                ] else
                  _textField(
                    'pricePerTrip',
                    'Valor por viagem',
                    keyboard: TextInputType.number,
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aluno possui celular para QR Code'),
                  value: _hasCellphone,
                  onChanged: (value) => setState(() => _hasCellphone = value),
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

  Widget _textField(String key, String label, {TextInputType? keyboard}) {
    return TextFormField(
      controller: _fields[key],
      keyboardType: keyboard,
      decoration: InputDecoration(labelText: label),
      validator: (value) =>
          value == null || value.trim().isEmpty ? 'Campo obrigatório.' : null,
    );
  }

  Widget _coordinateField(String key, String label, double min, double max) =>
      TextFormField(
        controller: _fields[key],
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: InputDecoration(labelText: label),
        validator: (value) {
          if (value == null || value.trim().isEmpty) return null;
          final coordinate = double.tryParse(value.trim());
          if (coordinate == null || coordinate < min || coordinate > max) {
            return 'Informe uma coordenada entre $min e $max.';
          }
          return null;
        },
      );

  double? _optionalCoordinate(String key) {
    final value = _fields[key]!.text.trim();
    return value.isEmpty ? null : double.parse(value);
  }
}

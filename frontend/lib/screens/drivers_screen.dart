import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/empty_state.dart';
import '../core/api_client.dart';

class DriversScreen extends StatefulWidget {
  const DriversScreen({
    super.key,
    required this.companyId,
    required this.vehicles,
  });

  final String companyId;
  final List<Map<String, dynamic>> vehicles;

  @override
  State<DriversScreen> createState() => _DriversScreenState();
}

class _DriversScreenState extends State<DriversScreen> {
  final _api = ApiClient();
  List<dynamic> _drivers = [];
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
      final drivers = await _api.getList(
        '/companies/${widget.companyId}/drivers',
      );
      if (mounted) setState(() => _drivers = drivers);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editDriver([Map<String, dynamic>? driver]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _DriverFormDialog(
        companyId: widget.companyId,
        vehicles: widget.vehicles,
        driver: driver,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _deleteDriver(Map<String, dynamic> driver) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desativar motorista?'),
        content: Text(
          '${driver['name']} perderá o acesso ao aplicativo e deixará de ser motorista titular. O histórico será preservado.',
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
      await _api.delete('/drivers/${driver['id']}');
      _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _resendInvitation(Map<String, dynamic> driver) async {
    try {
      final response = await _api.post('/drivers/${driver['id']}/invitations');
      if (!mounted) return;
      final code = response['activationCode'] as String;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Novo código de ativação'),
          content: SelectableText(
            'Compartilhe este código com ${driver['name']}. Ele expira em '
            '24 horas e invalida o código anterior.\n\n$code',
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
        title: const Text('Motoristas'),
        actions: [
          IconButton(
            tooltip: 'Atualizar motoristas',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Cadastrar motorista',
            onPressed: () => _editDriver(),
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
          : _drivers.isEmpty
          ? EmptyState(
              icon: Icons.badge_outlined,
              title: 'Cadastre seu primeiro motorista',
              description:
                  'Envie um convite seguro. O motorista cria a própria senha '
                  'e acessa somente os serviços escalados.',
              actionLabel: 'Cadastrar motorista',
              onAction: _editDriver,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _drivers.length,
                itemBuilder: (context, index) {
                  final driver = Map<String, dynamic>.from(_drivers[index]);
                  final vehicles = driver['vehicles'] as List? ?? [];
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.badge_outlined),
                      ),
                      title: Text(driver['name'] as String),
                      subtitle: Text(
                        '${driver['email']} • '
                        '${driver['invitationPending'] == true ? 'Aguardando ativação' : 'Conta ativada'} • '
                        '${vehicles.isEmpty ? 'Sem van titular' : vehicles.map((v) => v['plate']).join(', ')}',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'edit') _editDriver(driver);
                          if (action == 'invite') _resendInvitation(driver);
                          if (action == 'delete') _deleteDriver(driver);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Editar'),
                          ),
                          if (driver['invitationPending'] == true)
                            const PopupMenuItem(
                              value: 'invite',
                              child: Text('Gerar novo código'),
                            ),
                          const PopupMenuItem(
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
      floatingActionButton: _loading || _drivers.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _editDriver(),
              icon: const Icon(Icons.add),
              label: const Text('Novo motorista'),
            ),
    );
  }
}

class _DriverFormDialog extends StatefulWidget {
  const _DriverFormDialog({
    required this.companyId,
    required this.vehicles,
    this.driver,
  });

  final String companyId;
  final List<Map<String, dynamic>> vehicles;
  final Map<String, dynamic>? driver;

  @override
  State<_DriverFormDialog> createState() => _DriverFormDialogState();
}

class _DriverFormDialogState extends State<_DriverFormDialog> {
  final _api = ApiClient();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _cnh;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  final _password = TextEditingController();
  late String _category;
  String? _vehicleId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final driver = widget.driver ?? {};
    _name = TextEditingController(text: driver['name']?.toString() ?? '');
    _cnh = TextEditingController(text: driver['cnh']?.toString() ?? '');
    _phone = TextEditingController(text: driver['phone']?.toString() ?? '');
    _email = TextEditingController(text: driver['email']?.toString() ?? '');
    _category = driver['cnhCategory']?.toString() ?? 'D';
    final assignedVehicles = driver['vehicles'] as List? ?? [];
    _vehicleId = assignedVehicles.isEmpty
        ? null
        : assignedVehicles.first['id'] as String;
  }

  @override
  void dispose() {
    _name.dispose();
    _cnh.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'companyId': widget.companyId,
      'name': _name.text.trim(),
      'cnh': _cnh.text.trim(),
      'cnhCategory': _category,
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      if (widget.driver != null && _password.text.isNotEmpty)
        'password': _password.text,
      'vehicleId': _vehicleId,
    };
    try {
      if (widget.driver == null) {
        final invitation = await _api.post(
          '/companies/${widget.companyId}/driver-invitations',
          body: body,
        );
        if (!mounted) return;
        final code = invitation['activationCode'] as String;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Motorista cadastrado'),
            content: SelectableText(
              'Compartilhe este código com o motorista. Ele poderá criar a '
              'própria senha na tela de entrada. O código expira em 24 horas '
              'e só pode ser usado uma vez.\n\n$code',
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
      } else {
        await _api.patch('/drivers/${widget.driver!['id']}', body: body);
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
    final editing = widget.driver != null;
    return AlertDialog(
      title: Text(editing ? 'Editar motorista' : 'Cadastrar motorista'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(_name, 'Nome completo'),
                _field(_cnh, 'Número da CNH'),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(
                    labelText: 'Categoria da CNH',
                  ),
                  items: ['B', 'C', 'D', 'E']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _category = value ?? _category),
                ),
                _field(_phone, 'Telefone', keyboard: TextInputType.phone),
                _field(
                  _email,
                  'E-mail de acesso',
                  keyboard: TextInputType.emailAddress,
                ),
                if (editing)
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Nova senha (opcional)',
                    ),
                    validator: (value) {
                      if (value != null &&
                          value.isNotEmpty &&
                          value.length < 8) {
                        return 'Use pelo menos 8 caracteres.';
                      }
                      return null;
                    },
                  ),
                DropdownButtonFormField<String>(
                  initialValue: _vehicleId,
                  decoration: const InputDecoration(labelText: 'Van titular'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Sem van')),
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
    TextInputType? keyboard,
  }) => TextFormField(
    controller: controller,
    keyboardType: keyboard,
    decoration: InputDecoration(labelText: label),
    validator: (value) =>
        value == null || value.trim().isEmpty ? 'Campo obrigatório.' : null,
  );
}

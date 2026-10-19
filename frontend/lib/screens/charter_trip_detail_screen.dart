import 'package:flutter/material.dart';

import '../core/api_client.dart';

class CharterTripDetailScreen extends StatefulWidget {
  const CharterTripDetailScreen({
    super.key,
    required this.companyId,
    required this.trip,
  });

  final String companyId;
  final Map<String, dynamic> trip;

  @override
  State<CharterTripDetailScreen> createState() =>
      _CharterTripDetailScreenState();
}

class _CharterTripDetailScreenState extends State<CharterTripDetailScreen> {
  final _api = ApiClient();
  List<dynamic> _passengers = [];
  Map<String, dynamic> _financials = {};
  bool _loading = true;
  String? _error;

  String get _tripId => widget.trip['id'].toString();
  bool get _editable => widget.trip['status'] == 'AGENDADO';

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
      final results = await Future.wait<dynamic>([
        _api.getList('/trips/$_tripId/passengers'),
        _api.get('/trips/$_tripId/financial-summary'),
      ]);
      if (mounted) {
        setState(() {
          _passengers = results[0];
          _financials = results[1];
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addPassenger() async {
    final passenger = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _PassengerFormDialog(),
    );
    if (passenger == null) return;
    try {
      await _api.post('/trips/$_tripId/passengers', body: passenger);
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _setPassengerStatus(
    Map<String, dynamic> passenger,
    String status,
  ) async {
    try {
      await _api.patch(
        '/trips/$_tripId/passengers/${passenger['id']}/status',
        body: {'status': status},
      );
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _removePassenger(Map<String, dynamic> passenger) async {
    try {
      await _api.delete('/trips/$_tripId/passengers/${passenger['id']}');
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _addExpense() async {
    final expense = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _ExpenseFormDialog(),
    );
    if (expense == null) return;
    try {
      await _api.post(
        '/transactions',
        body: {
          'companyId': widget.companyId,
          'vehicleId': widget.trip['vehicleId'],
          'charterTripId': _tripId,
          'type': 'DESPESA',
          ...expense,
        },
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
    final revenue = (_financials['realizedRevenue'] as num?)?.toDouble() ?? 0;
    final expenses = (_financials['expenses'] as num?)?.toDouble() ?? 0;
    final margin = (_financials['margin'] as num?)?.toDouble() ?? 0;
    final transactions = _financials['transactions'] as List? ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes do fretamento')),
      floatingActionButton: _editable
          ? FloatingActionButton.extended(
              onPressed: _addPassenger,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Adicionar passageiro'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(onPressed: _load, child: const Text('Tentar novamente')),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  Card(
                    child: ListTile(
                      title: Text(
                        '${widget.trip['origin']} → ${widget.trip['destination']}',
                      ),
                      subtitle: Text(
                        '${widget.trip['clientName']} • ${widget.trip['status']}',
                      ),
                      leading: const Icon(Icons.route),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Resultado financeiro', style: Theme.of(context).textTheme.titleLarge),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _MoneyRow(label: 'Valor contratado', value: _money(_financials['agreedValue'])),
                          _MoneyRow(label: 'Receita realizada', value: _money(revenue)),
                          _MoneyRow(label: 'Despesas vinculadas', value: _money(expenses)),
                          const Divider(),
                          _MoneyRow(
                            label: 'Margem realizada',
                            value: _money(margin),
                            bold: true,
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              onPressed: _addExpense,
                              icon: const Icon(Icons.add),
                              label: const Text('Lançar custo nesta viagem'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Manifesto (${_passengers.length})',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  if (_passengers.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Nenhum passageiro incluído no manifesto.'),
                      ),
                    ),
                  ..._passengers.map((raw) {
                    final passenger = Map<String, dynamic>.from(raw as Map);
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_outline),
                        ),
                        title: Text(passenger['name'].toString()),
                        subtitle: Text(
                          [
                            passenger['status']?.toString() ?? 'AGUARDANDO',
                            if (passenger['pickupPoint'] != null)
                              passenger['pickupPoint'].toString(),
                          ].join(' • '),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'remove') {
                              _removePassenger(passenger);
                            } else {
                              _setPassengerStatus(passenger, value);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'EMBARCADO',
                              child: Text('Marcar embarcado'),
                            ),
                            const PopupMenuItem(
                              value: 'DESEMBARCADO',
                              child: Text('Marcar desembarcado'),
                            ),
                            const PopupMenuItem(
                              value: 'AUSENTE',
                              child: Text('Marcar ausente'),
                            ),
                            if (_editable)
                              const PopupMenuItem(
                                value: 'remove',
                                child: Text('Remover do manifesto'),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  Text('Lançamentos da viagem', style: Theme.of(context).textTheme.titleLarge),
                  if (transactions.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'A receita contratada será reconhecida ao concluir o serviço. Custos podem ser lançados acima.',
                        ),
                      ),
                    ),
                  ...transactions.map((raw) {
                    final transaction = Map<String, dynamic>.from(raw as Map);
                    final amount =
                        double.tryParse('${transaction['amount']}') ?? 0;
                    return ListTile(
                      leading: Icon(
                        transaction['type'] == 'DESPESA'
                            ? Icons.south_west
                            : Icons.north_east,
                      ),
                      title: Text(transaction['category'].toString()),
                      subtitle: Text(
                        transaction['description']?.toString() ?? '',
                      ),
                      trailing: Text(_money(amount)),
                    );
                  }),
                ],
              ),
            ),
    );
  }

  String _money(Object? value) {
    final amount = double.tryParse('$value') ?? 0;
    return 'R\$ ${amount.toStringAsFixed(2)}';
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    ),
  );
}

class _PassengerFormDialog extends StatefulWidget {
  const _PassengerFormDialog();

  @override
  State<_PassengerFormDialog> createState() => _PassengerFormDialogState();
}

class _PassengerFormDialogState extends State<_PassengerFormDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _pickup = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _pickup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Adicionar passageiro'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            onChanged: (_) => setState(() => _error = null),
            decoration: const InputDecoration(labelText: 'Nome'),
          ),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefone (opcional)')),
          TextField(controller: _pickup, decoration: const InputDecoration(labelText: 'Ponto de embarque (opcional)')),
          if (_error != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
          if (_name.text.trim().isEmpty) {
            setState(() => _error = 'Informe o nome do passageiro.');
            return;
          }
          Navigator.pop(context, {
                'name': _name.text.trim(),
                'phone': _phone.text.trim(),
                'pickupPoint': _pickup.text.trim(),
              });
        },
        child: const Text('Adicionar'),
      ),
    ],
  );
}

class _ExpenseFormDialog extends StatefulWidget {
  const _ExpenseFormDialog();

  @override
  State<_ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends State<_ExpenseFormDialog> {
  final _amount = TextEditingController();
  final _category = TextEditingController(text: 'COMBUSTIVEL');
  final _description = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _category.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Lançar custo da viagem'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _category,
            decoration: const InputDecoration(labelText: 'Categoria'),
          ),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Valor (R\$)'),
          ),
          TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Descrição'),
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
          final parsed = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
          if (parsed == null || parsed <= 0 || _category.text.trim().isEmpty) {
            return;
          }
          Navigator.pop(context, {
            'amount': parsed.toString(),
            'category': _category.text.trim(),
            'description': _description.text.trim(),
          });
        },
        child: const Text('Salvar custo'),
      ),
    ],
  );
}

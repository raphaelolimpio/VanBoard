import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';

class FinancialTransactionsScreen extends StatefulWidget {
  const FinancialTransactionsScreen({super.key, required this.companyId, this.api});

  final String companyId;
  final ApiClient? api;

  @override
  State<FinancialTransactionsScreen> createState() =>
      _FinancialTransactionsScreenState();
}

class _FinancialTransactionsScreenState
    extends State<FinancialTransactionsScreen> {
  late final _api = widget.api ?? ApiClient();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<dynamic> _transactions = [];
  List<dynamic> _vehicles = [];
  Map<String, dynamic> _summaryData = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _dateParameter(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final firstDay = DateTime(_month.year, _month.month);
      final lastDay = DateTime(_month.year, _month.month + 1, 0);
      final result = await Future.wait<dynamic>([
        _api.getMapList(
          '/companies/${widget.companyId}/transactions'
          '?from=${_dateParameter(firstDay)}&to=${_dateParameter(lastDay)}',
        ),
        _api.getMapList('/companies/${widget.companyId}/vehicles'),
        _api.get(
          '/companies/${widget.companyId}/transactions/summary'
          '?from=${_dateParameter(firstDay)}&to=${_dateParameter(lastDay)}',
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _transactions = ApiClient.decodeMapList(result[0]);
        _vehicles = ApiClient.decodeMapList(result[1]);
        _summaryData = Map<String, dynamic>.from(result[2] as Map);
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addEntry() async {
    final added = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FinancialEntryDialog(
        companyId: widget.companyId,
        vehicles: ApiClient.decodeMapList(_vehicles),
        onSave: (entry) => _api.post('/transactions', body: entry),
        onUploadReceipt: _api.uploadReceipt,
      ),
    );
    if (added == true) await _load();
  }

  Future<void> _showReceipt(String transactionId) async {
    try {
      final bytes = await _api.downloadReceipt(transactionId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: InteractiveViewer(
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
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
    final income = _amount(_summaryData['revenue']);
    final expenses = _amount(_summaryData['expenses']);
    final expenseGroups = ApiClient.decodeMapList(
      _summaryData['expensesByVehicle'] ?? const [],
    );
    final expensesByVehicle = {
      for (final group in expenseGroups)
        group['vehicleId'].toString(): _amount(group['amount']),
    };
    final unallocatedExpenses = _amount(_summaryData['unallocatedExpenses']);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Financeiro • ${_month.month.toString().padLeft(2, '0')}/${_month.year}',
        ),
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
            onPressed:
                _month.year == DateTime.now().year &&
                    _month.month == DateTime.now().month
                ? null
                : () {
                    setState(
                      () => _month = DateTime(_month.year, _month.month + 1),
                    );
                    _load();
                  },
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Próximo mês',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addEntry,
        icon: const Icon(Icons.add),
        label: const Text('Novo lançamento'),
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
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: 20,
                        runSpacing: 8,
                        children: [
                          _summary('Receitas', income, Colors.green),
                          _summary('Despesas', expenses, Colors.red),
                          _summary('Resultado', income - expenses, Colors.blue),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Despesas por van no período',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_vehicles.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Cadastre uma van para detalhar os custos.',
                        ),
                      ),
                    )
                  else
                    ..._vehicles.map((rawVehicle) {
                      final vehicle = Map<String, dynamic>.from(
                        rawVehicle as Map,
                      );
                      final amount =
                          expensesByVehicle[vehicle['id'].toString()] ?? 0;
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.local_shipping_outlined),
                          title: Text(
                            '${vehicle['plate']} • ${vehicle['model']}',
                          ),
                          subtitle: const Text(
                            'Combustível, manutenção e outros custos',
                          ),
                          trailing: Text(
                            'R\$ ${amount.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      );
                    }),
                  if (unallocatedExpenses > 0)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.business_outlined),
                        title: const Text('Despesas gerais da empresa'),
                        trailing: Text(
                          'R\$ ${unallocatedExpenses.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Lançamentos do período (${_summaryData['transactionCount'] ?? 0})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if ((_summaryData['transactionCount'] as num? ?? 0) > 200)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Exibindo os 200 lançamentos mais recentes; os totais incluem o período completo.',
                      ),
                    ),
                  if (_transactions.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Ainda não há lançamentos neste período.'),
                      ),
                    ),
                  ..._transactions.map((rawEntry) {
                    final entry = Map<String, dynamic>.from(rawEntry as Map);
                    final isIncome = entry['type'] == 'RECEITA';
                    final vehicleValue = entry['vehicle'];
                    final vehicle = vehicleValue is Map
                        ? Map<String, dynamic>.from(vehicleValue)
                        : null;
                    final receiptValue = entry['receipt'];
                    final receipt = receiptValue is Map
                        ? Map<String, dynamic>.from(receiptValue)
                        : null;
                    final date = DateTime.parse(entry['date'].toString())
                        .toLocal();
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          isIncome ? Icons.trending_up : Icons.trending_down,
                          color: isIncome ? Colors.green : Colors.red,
                        ),
                        title: Text(
                          entry['category'].toString().replaceAll('_', ' '),
                        ),
                        subtitle: Text(
                          '${date.day.toString().padLeft(2, '0')}/'
                          '${date.month.toString().padLeft(2, '0')}/'
                          '${date.year} • ${vehicle?['plate'] ?? 'Despesa/receita geral'}'
                          '${entry['description'] == null ? '' : '\n${entry['description']}'}',
                        ),
                        isThreeLine: entry['description'] != null,
                        trailing: SizedBox(
                          width: receipt == null ? 110 : 150,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (receipt != null)
                                IconButton(
                                  tooltip: 'Ver comprovante',
                                  onPressed: () =>
                                      _showReceipt(entry['id'].toString()),
                                  icon: const Icon(Icons.receipt_long_outlined),
                                ),
                              Flexible(
                                child: Text(
                                  '${isIncome ? '+' : '-'} R\$ ${_amount(entry['amount']).toStringAsFixed(2)}',
                                  style: TextStyle(
                                    color: isIncome
                                        ? Colors.green.shade700
                                        : Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }

  Widget _summary(String label, double amount, Color color) => SizedBox(
    width: 180,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        Text(
          'R\$ ${amount.toStringAsFixed(2)}',
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
      ],
    ),
  );

  double _amount(dynamic value) => double.tryParse('$value') ?? 0;
}

class _FinancialEntryDialog extends StatefulWidget {
  const _FinancialEntryDialog({
    required this.companyId,
    required this.vehicles,
    required this.onSave,
    required this.onUploadReceipt,
  });

  final String companyId;
  final List<Map<String, dynamic>> vehicles;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> entry)
  onSave;
  final Future<void> Function(
    String transactionId,
    Uint8List bytes,
    String mimeType,
  )
  onUploadReceipt;

  @override
  State<_FinancialEntryDialog> createState() => _FinancialEntryDialogState();
}

class _FinancialEntryDialogState extends State<_FinancialEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  Uint8List? _receiptBytes;
  String? _receiptName;
  String? _receiptMimeType;
  String? _savedTransactionId;
  String _type = 'DESPESA';
  String _category = 'COMBUSTIVEL';
  String? _vehicleId;
  String? _error;
  bool _saving = false;
  DateTime _date = DateTime.now();

  List<String> get _categories => _type == 'RECEITA'
      ? const ['MENSALIDADE_ESCOLAR', 'RECEITA_EXTRA', 'OUTROS']
      : const [
          'COMBUSTIVEL',
          'MANUTENCAO',
          'PNEUS',
          'SEGURO',
          'FOLHA_PAGAMENTO',
          'DESPESA_GERAL',
        ];

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected != null && mounted) {
      setState(() => _date = selected);
    }
  }

  Future<void> _chooseReceipt() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || !mounted) return;
    final file = result.files.single;
    if (file.size > 5 * 1024 * 1024) {
      setState(() => _error = 'O comprovante deve ter no máximo 5 MB.');
      return;
    }
    if (file.bytes == null) {
      setState(() => _error = 'Não foi possível ler o arquivo selecionado.');
      return;
    }
    final extension = file.extension?.toLowerCase();
    if (!['jpg', 'jpeg', 'png'].contains(extension)) {
      setState(() => _error = 'Selecione uma imagem JPG ou PNG.');
      return;
    }
    setState(() {
      _error = null;
      _receiptBytes = file.bytes;
      _receiptName = file.name;
      _receiptMimeType = extension == 'png' ? 'image/png' : 'image/jpeg';
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_type == 'DESPESA' &&
        const [
          'COMBUSTIVEL',
          'MANUTENCAO',
          'PNEUS',
          'SEGURO',
        ].contains(_category) &&
        _vehicleId == null) {
      setState(() => _error = 'Selecione a van para vincular esta despesa.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_savedTransactionId == null) {
        final created = await widget.onSave({
          'companyId': widget.companyId,
          'vehicleId': _vehicleId,
          'type': _type,
          'category': _category,
          'amount': double.parse(_amount.text.replaceAll(',', '.')),
          'description': _description.text.trim(),
          'date': DateTime(
            _date.year,
            _date.month,
            _date.day,
          ).toUtc().toIso8601String(),
        });
        _savedTransactionId = created['id']?.toString();
        if (_savedTransactionId == null || _savedTransactionId!.isEmpty) {
          throw const FormatException(
            'O lançamento foi criado sem um identificador.',
          );
        }
      }
      if (_receiptBytes != null && _receiptMimeType != null) {
        await widget.onUploadReceipt(
          _savedTransactionId!,
          _receiptBytes!,
          _receiptMimeType!,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _savedTransactionId == null
              ? error.toString()
              : 'Lançamento criado, mas o comprovante não foi enviado: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Novo lançamento'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: const [
                  DropdownMenuItem(value: 'RECEITA', child: Text('Receita')),
                  DropdownMenuItem(value: 'DESPESA', child: Text('Despesa')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _type = value;
                    _category = _categories.first;
                  });
                },
              ),
              DropdownButtonFormField<String>(
                key: ValueKey(_type),
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Categoria'),
                items: _categories
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.replaceAll('_', ' ')),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              DropdownButtonFormField<String>(
                initialValue: _vehicleId,
                decoration: const InputDecoration(
                  labelText: 'Veículo (opcional)',
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('Geral da empresa'),
                  ),
                  ...widget.vehicles.map(
                    (vehicle) => DropdownMenuItem<String>(
                      value: vehicle['id'] as String,
                      child: Text('${vehicle['plate']} • ${vehicle['model']}'),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _vehicleId = value),
                validator: (_) =>
                    _vehicleId == null &&
                        _type == 'DESPESA' &&
                        const [
                          'COMBUSTIVEL',
                          'MANUTENCAO',
                          'PNEUS',
                          'SEGURO',
                        ].contains(_category)
                    ? 'Selecione a van para este tipo de despesa.'
                    : null,
              ),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Valor (R\$)'),
                validator: (value) {
                  final amount = double.tryParse(
                    (value ?? '').replaceAll(',', '.'),
                  );
                  return amount == null || amount <= 0
                      ? 'Informe um valor maior que zero.'
                      : null;
                },
              ),
              TextField(
                controller: _description,
                decoration: const InputDecoration(
                  labelText: 'Descrição (opcional)',
                ),
              ),
              if (_type == 'DESPESA') ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _chooseReceipt,
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      _receiptName == null
                          ? 'Anexar comprovante (opcional)'
                          : _receiptName!,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Imagem JPG ou PNG, até 5 MB.'),
                ),
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Data do lançamento'),
                subtitle: Text(
                  '${_date.day.toString().padLeft(2, '0')}/'
                  '${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                ),
                trailing: const Icon(Icons.calendar_month),
                onTap: _chooseDate,
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
        onPressed: _saving
            ? null
            : () => Navigator.pop(context, _savedTransactionId != null),
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
            : Text(_savedTransactionId == null ? 'Salvar' : 'Tentar envio'),
      ),
    ],
  );
}

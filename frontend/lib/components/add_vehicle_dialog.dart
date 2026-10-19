import 'package:flutter/material.dart';

class AddVehicleDialog extends StatefulWidget {
  const AddVehicleDialog({super.key, required this.onSave});

  final Future<void> Function({
    required String plate,
    required String model,
    required int capacity,
    required String purpose,
  })
  onSave;

  @override
  State<AddVehicleDialog> createState() => _AddVehicleDialogState();
}

class _AddVehicleDialogState extends State<AddVehicleDialog> {
  final _plateController = TextEditingController();
  final _modelController = TextEditingController();
  final _capacityController = TextEditingController(text: '15');
  String _selectedPurpose = 'ESCOLAR';
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _plateController.dispose();
    _modelController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final capacity = int.tryParse(_capacityController.text);
    if (_modelController.text.trim().isEmpty ||
        _plateController.text.trim().isEmpty ||
        capacity == null ||
        capacity < 1) {
      setState(() => _error = 'Informe modelo, placa e capacidade válida.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        plate: _plateController.text.trim(),
        model: _modelController.text.trim(),
        capacity: capacity,
        purpose: _selectedPurpose,
      );
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
      title: const Text('Cadastrar Nova Van'),
      content: SizedBox(
        width: 460,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.6,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _modelController,
                  decoration: const InputDecoration(labelText: 'Modelo'),
                ),
                TextField(
                  controller: _plateController,
                  decoration: const InputDecoration(labelText: 'Placa'),
                ),
                TextField(
                  controller: _capacityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Capacidade'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _selectedPurpose,
                  decoration: const InputDecoration(labelText: 'Finalidade'),
                  items: const [
                    DropdownMenuItem(value: 'ESCOLAR', child: Text('Escolar')),
                    DropdownMenuItem(value: 'TURISMO', child: Text('Turismo')),
                    DropdownMenuItem(value: 'EVENTOS', child: Text('Eventos')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedPurpose = value);
                    }
                  },
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
}

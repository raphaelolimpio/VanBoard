import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import '../core/theme/app_colors.dart';
import 'student_tracking_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onAuthenticated});

  final ValueChanged<Map<String, dynamic>> onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _email = TextEditingController();
  final _activationCode = TextEditingController();
  final _password = TextEditingController();
  final _auth = AuthController();
  bool _registering = false;
  bool _activatingDriver = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _company.dispose();
    _email.dispose();
    _activationCode.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = _activatingDriver
          ? await _auth.activateDriver(
              code: _activationCode.text,
              password: _password.text,
            )
          : _registering
          ? await _auth.registerOwner(
              name: _name.text,
              email: _email.text,
              password: _password.text,
              companyName: _company.text,
            )
          : await _auth.login(email: _email.text, password: _password.text);
      if (mounted) widget.onAuthenticated(user);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.directions_bus_filled,
                        color: AppColors.primary,
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _activatingDriver
                            ? 'Ativar conta de motorista'
                            : _registering
                            ? 'Criar empresa'
                            : 'Entrar no BoardVan',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 24),
                      if (_activatingDriver) ...[
                        TextFormField(
                          controller: _activationCode,
                          decoration: const InputDecoration(
                            labelText: 'Código de ativação',
                          ),
                          validator: _required,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_registering) ...[
                        TextFormField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Seu nome',
                          ),
                          validator: _required,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _company,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Nome da empresa',
                          ),
                          validator: _required,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (!_activatingDriver) ...[
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'E-mail'),
                          validator: (value) {
                            if (value == null || !value.contains('@')) {
                              return 'Informe um e-mail válido.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: _activatingDriver
                              ? 'Crie sua senha'
                              : 'Senha',
                        ),
                        validator: (value) {
                          if (value == null || value.length < 8) {
                            return 'Use pelo menos 8 caracteres.';
                          }
                          return null;
                        },
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _activatingDriver
                                    ? 'Ativar e entrar'
                                    : _registering
                                    ? 'Criar conta da empresa'
                                    : 'Entrar',
                              ),
                      ),
                      if (!_activatingDriver)
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                  _registering = !_registering;
                                  _error = null;
                                }),
                          child: Text(
                            _registering
                                ? 'Já tenho uma conta'
                                : 'Cadastrar uma nova empresa',
                          ),
                        ),
                      if (!_registering && !_activatingDriver)
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                  _activatingDriver = true;
                                  _error = null;
                                }),
                          child: const Text('Tenho um código de motorista'),
                        ),
                      if (_activatingDriver)
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                  _activatingDriver = false;
                                  _error = null;
                                }),
                          child: const Text('Voltar para entrar'),
                        ),
                      if (!_registering && !_activatingDriver)
                        TextButton.icon(
                          onPressed: _loading
                              ? null
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const StudentTrackingScreen(),
                                  ),
                                ),
                          icon: const Icon(Icons.location_on_outlined),
                          label: const Text('Sou responsável • acompanhar'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Campo obrigatório.' : null;
}

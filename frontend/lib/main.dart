import 'package:flutter/material.dart';

import 'core/theme/app_colors.dart';
import 'controllers/auth_controller.dart';
import 'screens/auth_screen.dart';
import 'screens/company_dashboard_screen.dart';
import 'screens/driver_home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BoardVanApp());
}

class BoardVanApp extends StatelessWidget {
  const BoardVanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BoardVan Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: AppColors.primary,
              brightness: Brightness.light,
            ).copyWith(
              surface: AppColors.surface,
              surfaceContainerLowest: Colors.white,
              surfaceContainerLow: const Color(0xFFF8FAFC),
            ),
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 1,
          titleTextStyle: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE5EAF1)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          elevation: 3,
          extendedTextStyle: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      home: const SessionGate(),
    );
  }
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key, this.auth});

  final AuthController? auth;

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  late final _auth = widget.auth ?? AuthController();
  Map<String, dynamic>? _user;
  bool _restoreFailed = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _restoreFailed = false;
      });
    }
    try {
      _user = await _auth.restoreSession();
    } catch (_) {
      _user = null;
      _restoreFailed = true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await _auth.logout();
    if (mounted) setState(() => _user = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final user = _user;
    if (user == null) {
      if (_restoreFailed) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Não foi possível validar sua sessão. Verifique a conexão e tente novamente.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _restore,
                    child: const Text('Tentar novamente'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _restoreFailed = false),
                    child: const Text('Ir para o login'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return AuthScreen(
        onAuthenticated: (account) => setState(() => _user = account),
      );
    }
    if (user['role'] == 'DRIVER') {
      return DriverHomeScreen(user: user, onLogout: _logout);
    }
    final companyId = user['companyId']?.toString();
    if (companyId == null || companyId.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('Sua conta ainda não possui uma empresa vinculada.'),
        ),
      );
    }
    return CompanyDashboardScreen(
      companyId: companyId,
      user: user,
      onLogout: _logout,
    );
  }
}

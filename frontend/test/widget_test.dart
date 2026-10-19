import 'dart:async';

import 'package:board_van/components/add_vehicle_dialog.dart';
import 'package:board_van/components/empty_state.dart';
import 'package:board_van/controllers/dashboard_controller.dart';
import 'package:board_van/controllers/auth_controller.dart';
import 'package:board_van/core/api_client.dart';
import 'package:board_van/main.dart';
import 'package:board_van/screens/auth_screen.dart';
import 'package:board_van/screens/company_dashboard_screen.dart';
import 'package:board_van/screens/driver_home_screen.dart';
import 'package:board_van/screens/financial_transactions_screen.dart';
import 'package:board_van/screens/fleet_screen.dart';
import 'package:board_van/screens/service_agenda_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  testWidgets('estado vazio explica o próximo passo e executa a ação', (
    tester,
  ) async {
    var actionCalled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.directions_bus_outlined,
            title: 'Sua frota começa aqui',
            description: 'Cadastre os veículos para organizar as rotas.',
            actionLabel: 'Cadastrar veículo',
            onAction: () => actionCalled = true,
          ),
        ),
      ),
    );

    expect(find.text('Sua frota começa aqui'), findsOneWidget);
    expect(
      find.text('Cadastre os veículos para organizar as rotas.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cadastrar veículo'));
    expect(actionCalled, isTrue);
  });

  testWidgets('frota vazia encaminha para o cadastro de veículo', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FleetScreen(companyId: 'company-1', api: _ScreenApiClient()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sua frota começa aqui'), findsOneWidget);
    await tester.tap(find.text('Cadastrar veículo'));
    await tester.pumpAndSettle();

    expect(find.text('Cadastrar Nova Van'), findsOneWidget);
    expect(find.text('Placa'), findsOneWidget);
  });

  testWidgets('dashboard adapta cartões à largura mobile sem overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: CompanyDashboardScreen(
          companyId: 'company-1',
          user: {
            'name': 'Responsável',
            'company': {'name': 'Transportes Exemplo'},
          },
          onLogout: () async {},
          controller: _DashboardControllerStub(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Visão geral'), findsOneWidget);
    expect(find.text('Status da frota'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('session restore hides internal errors and retries cleanly', (
    tester,
  ) async {
    final auth = _RetryingAuthController();
    await tester.pumpWidget(MaterialApp(home: SessionGate(auth: auth)));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Não foi possível validar sua sessão. Verifique a conexão e tente novamente.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('sensitive'), findsNothing);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(find.text('Entrar no BoardVan'), findsOneWidget);
    expect(auth.restoreCalls, 2);
  });

  test('decodifica corretamente listas JSON de mapas', () {
    final result = ApiClient.decodeMapList([
      {'id': 'transaction-1', 'amount': 12.5},
    ]);

    expect(result, [
      {'id': 'transaction-1', 'amount': 12.5},
    ]);
  });

  test('rejeita uma resposta que não seja uma lista de objetos', () {
    expect(
      () => ApiClient.decodeMapList(['unexpected']),
      throwsFormatException,
    );
  });

  test('configura rastreamento em background por plataforma', () {
    final androidSettings = driverLocationSettingsFor(
      TargetPlatform.android,
      isWeb: false,
    );
    final iosSettings = driverLocationSettingsFor(
      TargetPlatform.iOS,
      isWeb: false,
    );

    expect(androidSettings, isA<AndroidSettings>());
    final android = androidSettings as AndroidSettings;
    expect(android.foregroundNotificationConfig?.setOngoing, isTrue);
    expect(iosSettings, isA<AppleSettings>());
    final ios = iosSettings as AppleSettings;
    expect(ios.allowBackgroundLocationUpdates, isTrue);
    expect(ios.showBackgroundLocationIndicator, isTrue);
  });

  testWidgets(
    'carrega agenda com listas JSON sem falhar em tempo de execução',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ServiceAgendaScreen(
            companyId: 'company-1',
            api: _ScreenApiClient(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Agenda de serviços'), findsOneWidget);
      expect(find.text('Nenhum serviço agendado neste mês.'), findsOneWidget);
    },
  );

  testWidgets('carrega resumo financeiro e custo por van', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialTransactionsScreen(
          companyId: 'company-1',
          api: _ScreenApiClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Despesas por van no período'), findsOneWidget);
    expect(find.text('R\$ 125.50'), findsNWidgets(2));
    expect(find.text('COMBUSTIVEL'), findsOneWidget);
  });

  testWidgets('exibe formulário de acesso sem autenticar automaticamente', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AuthScreen(onAuthenticated: (_) {})),
    );

    expect(find.text('Entrar no BoardVan'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Entrar'), findsOneWidget);
  });

  testWidgets('oferece ativação segura de conta de motorista', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AuthScreen(onAuthenticated: (_) {})),
    );

    await tester.tap(find.text('Tenho um código de motorista'));
    await tester.pumpAndSettle();

    expect(find.text('Ativar conta de motorista'), findsOneWidget);
    expect(find.text('Código de ativação'), findsOneWidget);
    expect(find.text('Ativar e entrar'), findsOneWidget);
  });

  testWidgets('abre acompanhamento familiar por código temporário', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AuthScreen(onAuthenticated: (_) {})),
    );

    await tester.tap(find.text('Sou responsável • acompanhar'));
    await tester.pumpAndSettle();

    expect(find.text('Acompanhar aluno'), findsOneWidget);
    expect(find.text('Código de acompanhamento'), findsOneWidget);
    expect(find.text('Consultar acompanhamento'), findsOneWidget);
  });

  testWidgets('salva a van e fecha o diálogo após a resposta assíncrona', (
    tester,
  ) async {
    final saveCompleter = Completer<void>();
    Map<String, dynamic>? savedVehicle;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showDialog<bool>(
                  context: context,
                  builder: (_) => AddVehicleDialog(
                    onSave:
                        ({
                          required String plate,
                          required String model,
                          required int capacity,
                          required String purpose,
                        }) async {
                          savedVehicle = {
                            'plate': plate,
                            'model': model,
                            'capacity': capacity,
                            'purpose': purpose,
                          };
                          await saveCompleter.future;
                        },
                  ),
                );
              },
              child: const Text('Abrir cadastro'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir cadastro'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Sprinter');
    await tester.enterText(find.byType(TextField).at(1), 'ABC1234');
    await tester.tap(find.text('Salvar'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    saveCompleter.complete();
    await tester.pumpAndSettle();

    expect(savedVehicle, {
      'plate': 'ABC1234',
      'model': 'Sprinter',
      'capacity': 15,
      'purpose': 'ESCOLAR',
    });
    expect(find.text('Cadastrar Nova Van'), findsNothing);
  });

  test('monta filtros de período e tipo na consulta do painel', () async {
    final api = _RecordingApiClient();
    final controller = DashboardController(companyId: 'company-1', api: api);

    await controller.fetchDashboard(
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 31),
      purpose: 'TURISMO',
    );

    expect(
      api.requestPath,
      '/companies/company-1/dashboard?from=2026-10-01&to=2026-10-31&purpose=TURISMO',
    );
  });
}

class _RecordingApiClient extends ApiClient {
  String? requestPath;

  @override
  Future<Map<String, dynamic>> get(String path) async {
    requestPath = path;
    return {};
  }
}

class _DashboardControllerStub extends DashboardController {
  _DashboardControllerStub() : super(companyId: 'company-1');

  @override
  Future<Map<String, dynamic>> fetchDashboard({
    DateTime? from,
    DateTime? to,
    String? purpose,
  }) async => {
    'financial': {'revenue': 0, 'expenses': 0, 'netProfit': 0},
    'turnoverRatePercent': 100,
    'financialByVehicle': <Map<String, dynamic>>[],
    'unallocatedExpenses': 0,
    'fleetStatus': {
      'RODANDO': 1,
      'PARADO': 0,
      'MANUTENCAO': 0,
      'DANIFICADA': 0,
    },
    'counts': {'students': 0, 'drivers': 0},
    'activeRuns': <dynamic>[],
    'emergencies': <dynamic>[],
    'vehicles': <dynamic>[],
  };
}

class _RetryingAuthController extends AuthController {
  int restoreCalls = 0;

  @override
  Future<Map<String, dynamic>?> restoreSession() async {
    restoreCalls++;
    if (restoreCalls == 1) {
      throw StateError('sensitive server response');
    }
    return null;
  }

  @override
  Future<void> logout() async {}
}

class _ScreenApiClient extends ApiClient {
  @override
  Future<List<dynamic>> getList(String path) async => <dynamic>[];

  @override
  Future<Map<String, dynamic>> get(String path) async {
    if (path.contains('/agenda?')) {
      return {'trips': <dynamic>[], 'schoolRoutes': <dynamic>[]};
    }
    if (path.contains('/transactions/summary?')) {
      return {
        'revenue': 0,
        'expenses': 125.5,
        'unallocatedExpenses': 0,
        'transactionCount': 1,
        'expensesByVehicle': [
          {'vehicleId': 'vehicle-1', 'amount': 125.5},
        ],
      };
    }
    return {};
  }

  @override
  Future<List<Map<String, dynamic>>> getMapList(String path) async {
    if (path.contains('/transactions?')) {
      return ApiClient.decodeMapList([
        {
          'id': 'transaction-1',
          'type': 'DESPESA',
          'category': 'COMBUSTIVEL',
          'amount': 125.5,
          'date': '2026-10-19T12:00:00.000Z',
          'description': 'Abastecimento',
          'vehicle': {'id': 'vehicle-1', 'plate': 'ABC1234', 'model': 'Van'},
          'receipt': null,
        },
      ]);
    }
    if (path.endsWith('/vehicles')) {
      return ApiClient.decodeMapList([
        {
          'id': 'vehicle-1',
          'plate': 'ABC1234',
          'model': 'Van',
          'purposes': ['ESCOLAR'],
        },
      ]);
    }
    return ApiClient.decodeMapList(<dynamic>[]);
  }
}

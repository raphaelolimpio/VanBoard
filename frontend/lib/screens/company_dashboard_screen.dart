import 'package:board_van/core/theme/app_text_style.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../controllers/dashboard_controller.dart';
import 'drivers_screen.dart';
import 'fleet_screen.dart';
import 'live_fleet_map_screen.dart';
import 'financial_transactions_screen.dart';
import 'service_agenda_screen.dart';
import 'students_screen.dart';
import 'operational_alerts_screen.dart';

class CompanyDashboardScreen extends StatefulWidget {
  final String companyId;
  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;
  final DashboardController? controller;
  const CompanyDashboardScreen({
    super.key,
    required this.companyId,
    required this.user,
    required this.onLogout,
    this.controller,
  });

  @override
  State<CompanyDashboardScreen> createState() => _CompanyDashboardScreenState();
}

class _CompanyDashboardScreenState extends State<CompanyDashboardScreen> {
  late final DashboardController _controller;
  Map<String, dynamic>? dashboardData;
  String? loadError;
  bool isLoading = true;
  String _period = '30_DIAS';
  String _purpose = 'TODOS';

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? DashboardController(companyId: widget.companyId);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      isLoading = true;
      loadError = null;
    });
    try {
      final now = DateTime.now();
      final DateTime? from = switch (_period) {
        'MES' => DateTime(now.year, now.month),
        'ANO' => DateTime(now.year),
        '30_DIAS' => DateTime(now.year, now.month, now.day - 29),
        _ => null,
      };
      final data = await _controller.fetchDashboard(
        from: from,
        to: _period == 'TODOS' ? null : now,
        purpose: _purpose,
      );
      if (!mounted) return;
      setState(() {
        dashboardData = data;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        loadError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('BoardVan'),
        actions: [
          IconButton(
            tooltip: 'Atualizar painel',
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: widget.onLogout,
          ),
        ],
      ),
      drawer: _buildNavigationDrawer(),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : dashboardData == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(loadError ?? 'Não foi possível carregar os dados.'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loadData,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildWelcomeHeader(),
                        const SizedBox(height: 20),
                        _buildFinancialHeader(),
                        const SizedBox(height: 16),
                        _buildAnalyticsFilters(),
                        const SizedBox(height: 16),
                        _buildVehicleFinancials(),
                        const SizedBox(height: 24),
                        const Text(
                          'Status da frota',
                          style: AppTextStyles.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        _buildFleetStatusGrid(),
                        const SizedBox(height: 12),
                        _buildCounts(),
                        if (loadError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'A atualização falhou: $loadError',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _buildActiveRuns(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildWelcomeHeader() {
    final companyName =
        widget.user['company']?['name']?.toString() ?? 'sua empresa';
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Visão geral',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Acompanhe a operação e os resultados de $companyName.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        );
        final action = OutlinedButton.icon(
          onPressed: _openAgenda,
          icon: const Icon(Icons.calendar_month_outlined),
          label: const Text('Agendar serviço'),
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 14), action],
          );
        }
        return Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: 16),
            action,
          ],
        );
      },
    );
  }

  void _openAgenda() {
    _pushPage(ServiceAgendaScreen(companyId: widget.companyId));
  }

  Widget _buildNavigationDrawer() {
    final vehicles = (dashboardData?['vehicles'] as List? ?? const [])
        .map((vehicle) => Map<String, dynamic>.from(vehicle as Map))
        .toList();

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryVariant],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.directions_bus, color: Colors.white, size: 36),
                const SizedBox(height: 12),
                Text(
                  widget.user['company']?['name']?.toString() ?? 'BoardVan',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.user['name']?.toString() ?? '',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          _navigationItem(
            icon: Icons.dashboard_outlined,
            label: 'Dashboard',
            selected: true,
            onTap: () => Navigator.pop(context),
          ),
          _navigationItem(
            icon: Icons.directions_bus_outlined,
            label: 'Frota',
            onTap: () => _openPage(FleetScreen(companyId: widget.companyId)),
          ),
          _navigationItem(
            icon: Icons.school_outlined,
            label: 'Alunos',
            onTap: () => _openPage(
              StudentsScreen(companyId: widget.companyId, vehicles: vehicles),
            ),
          ),
          _navigationItem(
            icon: Icons.badge_outlined,
            label: 'Motoristas',
            onTap: () => _openPage(
              DriversScreen(companyId: widget.companyId, vehicles: vehicles),
            ),
          ),
          _navigationItem(
            icon: Icons.map_outlined,
            label: 'Mapa ao vivo',
            onTap: () => _openPage(
              LiveFleetMapScreen(
                vehicles: vehicles,
                companyName:
                    widget.user['company']?['name']?.toString() ?? 'Frota',
              ),
            ),
          ),
          _navigationItem(
            icon: Icons.notifications_active_outlined,
            label: 'Alertas operacionais',
            onTap: () =>
                _openPage(OperationalAlertsScreen(companyId: widget.companyId)),
          ),
          _navigationItem(
            icon: Icons.calendar_month_outlined,
            label: 'Agenda de serviços',
            onTap: () =>
                _openPage(ServiceAgendaScreen(companyId: widget.companyId)),
          ),
          _navigationItem(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Lançamentos financeiros',
            onTap: () => _openPage(
              FinancialTransactionsScreen(companyId: widget.companyId),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navigationItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: selected,
      onTap: onTap,
    );
  }

  void _openPage(Widget page) {
    Navigator.pop(context);
    _pushPage(page);
  }

  void _pushPage(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page)).then((_) {
      if (mounted) _loadData();
    });
  }

  Widget _buildCounts() {
    final counts = dashboardData!['counts'] as Map<String, dynamic>;
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final columns = constraints.maxWidth >= 640 ? 3 : 2;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: width,
              child: _countCard(
                'Alunos ativos',
                counts['students'],
                Icons.school,
              ),
            ),
            SizedBox(
              width: width,
              child: _countCard(
                'Motoristas',
                counts['drivers'],
                Icons.badge_outlined,
              ),
            ),
            SizedBox(
              width: width,
              child: _countCard(
                'Rotas ativas',
                (dashboardData!['activeRuns'] as List).length,
                Icons.alt_route,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _countCard(String label, dynamic count, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(height: 8),
          Text(
            '$count',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    ),
  );

  Widget _buildAnalyticsFilters() => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _period,
              decoration: const InputDecoration(
                labelText: 'Período financeiro',
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: '30_DIAS',
                  child: Text('Últimos 30 dias'),
                ),
                DropdownMenuItem(value: 'MES', child: Text('Este mês')),
                DropdownMenuItem(value: 'ANO', child: Text('Este ano')),
                DropdownMenuItem(value: 'TODOS', child: Text('Todo o período')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _period = value);
                _loadData();
              },
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _purpose,
              decoration: const InputDecoration(
                labelText: 'Tipo de serviço',
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'TODOS', child: Text('Todos')),
                DropdownMenuItem(value: 'ESCOLAR', child: Text('Escolar')),
                DropdownMenuItem(value: 'TURISMO', child: Text('Turismo')),
                DropdownMenuItem(value: 'EVENTOS', child: Text('Eventos')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _purpose = value);
                _loadData();
              },
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildVehicleFinancials() {
    final financials =
        (dashboardData!['financialByVehicle'] as List? ?? const [])
            .cast<Map<String, dynamic>>();
    final unallocatedExpenses =
        (dashboardData!['unallocatedExpenses'] as num?)?.toDouble() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resultado financeiro por van',
              style: AppTextStyles.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Apurado pelos lançamentos vinculados a cada van. Despesas gerais '
              'sem veículo aparecem somente no filtro Todos.',
              style: AppTextStyles.bodySmall,
            ),
            if (financials.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Nenhuma van cadastrada para este filtro.'),
              )
            else
              ...financials.map((item) {
                final revenue = (item['revenue'] as num).toDouble();
                final expenses = (item['expenses'] as num).toDouble();
                final profit = (item['netProfit'] as num).toDouble();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.directions_bus),
                  title: Text('${item['plate']} • ${item['model']}'),
                  subtitle: Text(
                    'Receitas R\$ ${revenue.toStringAsFixed(2)} • '
                    'Despesas R\$ ${expenses.toStringAsFixed(2)}',
                  ),
                  trailing: Text(
                    'R\$ ${profit.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: profit >= 0 ? Colors.green.shade700 : Colors.red,
                    ),
                  ),
                );
              }),
            if (unallocatedExpenses > 0)
              Text(
                'Despesas gerais sem van vinculada: R\$ ${unallocatedExpenses.toStringAsFixed(2)}',
                style: AppTextStyles.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveRuns() {
    final runs = (dashboardData!['activeRuns'] as List?) ?? const [];
    final emergencies = (dashboardData!['emergencies'] as List?) ?? const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Operação agora', style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Text(
              '${runs.length} rota(s) em andamento • ${emergencies.length} ocorrência(s) aberta(s)',
            ),
            if (runs.isNotEmpty) ...[
              const Divider(),
              ...runs.map(
                (run) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.directions_bus,
                    color: AppColors.primary,
                  ),
                  title: Text(
                    '${run['vehicle']['plate']} • ${run['driver']['name']}',
                  ),
                  subtitle: Text(
                    run['route']?['name'] ??
                        '${run['charterTrip']?['origin'] ?? 'Viagem'} → ${run['charterTrip']?['destination'] ?? ''}',
                  ),
                ),
              ),
            ],
            if (emergencies.isNotEmpty) ...[
              const Divider(),
              ...emergencies.map(
                (issue) => Text(
                  'Apoio solicitado para ${issue['student']['name']} • van ${issue['brokenVehicle']['plate']}',
                  style: const TextStyle(color: Colors.deepOrange),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialHeader() {
    final fin = dashboardData!['financial'];
    final turnover = dashboardData!['turnoverRatePercent'];
    final revenue = (fin['revenue'] as num).toDouble();
    final expenses = (fin['expenses'] as num).toDouble();
    final netProfit = (fin['netProfit'] as num).toDouble();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryVariant],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
              const Text(
                'Resultado financeiro geral',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Rotatividade: $turnover%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Lucro líquido: R\$ ${netProfit.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 18,
            runSpacing: 4,
            children: [
              _financialSummary('Receitas', revenue),
              _financialSummary('Despesas', expenses),
            ],
          ),
        ],
      ),
    );
  }

  Widget _financialSummary(String label, double value) => Text(
    '$label  R\$ ${value.toStringAsFixed(2)}',
    style: const TextStyle(color: Colors.white),
  );

  Widget _buildFleetStatusGrid() {
    final status = dashboardData!['fleetStatus'];
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final columns = constraints.maxWidth >= 920 ? 4 : 2;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: width,
              child: _buildStatusCard(
                'Rodando',
                status['RODANDO'],
                AppColors.statusRodando,
                Icons.directions_bus,
              ),
            ),
            SizedBox(
              width: width,
              child: _buildStatusCard(
                'Parado',
                status['PARADO'],
                AppColors.statusParado,
                Icons.local_parking,
              ),
            ),
            SizedBox(
              width: width,
              child: _buildStatusCard(
                'Manutenção',
                status['MANUTENCAO'],
                AppColors.statusManutencao,
                Icons.build,
              ),
            ),
            SizedBox(
              width: width,
              child: _buildStatusCard(
                'Danificada',
                status['DANIFICADA'],
                AppColors.statusDanificada,
                Icons.warning_amber,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusCard(String label, int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 20,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: AppTextStyles.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

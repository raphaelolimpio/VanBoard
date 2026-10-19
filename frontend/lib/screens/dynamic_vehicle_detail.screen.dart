import 'package:board_van/core/theme/app_text_style.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

import '../components/custom_button.dart';
import '../components/custom_card.dart';
import '../controllers/vehicle_detail_controller.dart';
import 'school_routes_screen.dart';
import 'students_screen.dart';
import 'vehicle_operations_screen.dart';

class DynamicVehicleDetailScreen extends StatefulWidget {
  final String vehicleId;
  const DynamicVehicleDetailScreen({super.key, required this.vehicleId});

  @override
  State<DynamicVehicleDetailScreen> createState() =>
      _DynamicVehicleDetailScreenState();
}

class _DynamicVehicleDetailScreenState
    extends State<DynamicVehicleDetailScreen> {
  late final VehicleDetailController _controller;
  Map<String, dynamic>? vehicleContext;
  String? loadError;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = VehicleDetailController(vehicleId: widget.vehicleId);
    _loadContext();
  }

  Future<void> _loadContext() async {
    setState(() => isLoading = true);
    try {
      final data = await _controller.fetchContext();
      if (!mounted) return;
      setState(() {
        vehicleContext = data;
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

  Future<void> _updateStatus(String newStatus) async {
    try {
      await _controller.updateStatus(newStatus);
      await _loadContext();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (vehicleContext == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Veículo')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                loadError ?? 'Não foi possível carregar os dados do veículo.',
              ),
              TextButton(
                onPressed: _loadContext,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    final info = vehicleContext!['vehicleInfo'];
    final fin = vehicleContext!['financialSummary'];
    final modules = vehicleContext!['modules'] as Map<String, dynamic>;
    final List purposes = info['purposes'] ?? [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${info['model']} • ${info['plate']}'),
        actions: [
          IconButton(
            tooltip: 'Operação e manutenção',
            icon: const Icon(Icons.build_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => VehicleOperationsScreen(
                  vehicleId: widget.vehicleId,
                  vehicleLabel: '${info['plate']} • ${info['model']}',
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho unificado do Veículo
            CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Lucro Acumulado da Van',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            'R\$ ${fin['netProfit'].toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: fin['netProfit'] >= 0
                                  ? AppColors.statusRodando
                                  : AppColors.statusDanificada,
                            ),
                          ),
                        ],
                      ),
                      DropdownButton<String>(
                        value: info['status'],
                        items: const [
                          DropdownMenuItem(
                            value: 'RODANDO',
                            child: Text('🟢 Rodando'),
                          ),
                          DropdownMenuItem(
                            value: 'PARADO',
                            child: Text('🔵 Parado'),
                          ),
                          DropdownMenuItem(
                            value: 'MANUTENCAO',
                            child: Text('🟠 Manutenção'),
                          ),
                          DropdownMenuItem(
                            value: 'DANIFICADA',
                            child: Text('🔴 Danificada'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) _updateStatus(val);
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Text(
                    'Motorista Titular: ${info['defaultDriver']?['name'] ?? 'Sem motorista fixo'}',
                  ),
                  Text(
                    'Finalidade: ${purposes.join(', ')}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Renderização Condicional por Módulo
            if (modules.containsKey('escolar'))
              _buildSchoolModule(modules['escolar'], info),
            if (modules.containsKey('fretamento'))
              _buildTourismModule(modules['fretamento']),
          ],
        ),
      ),
    );
  }

  Widget _buildSchoolModule(
    Map<String, dynamic> escolar,
    Map<String, dynamic> info,
  ) {
    final List students = escolar['students'] ?? [];
    final List routes = escolar['routes'] ?? [];
    final info = vehicleContext!['vehicleInfo'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomCard(
          backgroundColor: Colors.amber.shade100,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text(
                        'Lotação de Alunos',
                        style: TextStyle(fontSize: 12),
                      ),
                      Text(
                        '${escolar['occupancyRate']}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Text(
                        'Receita Mensal Fixa',
                        style: TextStyle(fontSize: 12),
                      ),
                      Text(
                        'R\$ ${escolar['expectedMonthlyRevenue']}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  CustomButton(
                    label: 'QR Code da Van (Check-in)',
                    icon: Icons.qr_code_2,
                    backgroundColor: Colors.indigo,
                    onPressed: () => _showVanQrCodeModal(info),
                  ),
                  CustomButton(
                    label: 'Cadastrar Aluno',
                    icon: Icons.person_add,
                    backgroundColor: Colors.green.shade700,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StudentsScreen(
                          companyId: info['companyId'].toString(),
                        ),
                      ),
                    ).then((_) => _loadContext()),
                  ),
                  CustomButton(
                    label: 'Gerenciar Rotas (${routes.length})',
                    icon: Icons.alt_route,
                    backgroundColor: Colors.blueGrey,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SchoolRoutesScreen(
                          vehicleId: info['id'].toString(),
                          initialRoutes: routes,
                        ),
                      ),
                    ).then((_) => _loadContext()),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '📋 Lista de Chamada & Alunos',
          style: AppTextStyles.titleMedium,
        ),
        const SizedBox(height: 8),
        if (students.isEmpty)
          const CustomCard(child: Text('Nenhum aluno cadastrado nesta van.')),

        ...students.map((s) {
          final bool isPerTrip = s['billingType'] == 'POR_VIAGEM';
          final bool hasCell = s['hasCellphone'] ?? true;
          final List attendances = s['attendances'] ?? [];

          return CustomCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s['name'], style: AppTextStyles.titleMedium),
                          Text(
                            'Escola: ${s['schoolName']} • Tel: ${s['phone']}',
                            style: AppTextStyles.bodySmall,
                          ),
                          Text(
                            hasCell
                                ? 'QR Code disponível'
                                : 'Chamada manual pelo motorista',
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isPerTrip
                            ? Colors.purple.shade50
                            : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isPerTrip
                            ? '${s['tripCredits']} créd.'
                            : 'R\$ ${s['monthlyFee']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                const Text(
                  'Marcar Presença Hoje:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _markAttendance(s['id'], 'IDA'),
                      icon: const Icon(Icons.login, size: 16),
                      label: const Text('Ida', style: TextStyle(fontSize: 12)),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _markAttendance(s['id'], 'VOLTA'),
                      icon: const Icon(Icons.logout, size: 16),
                      label: const Text(
                        'Volta',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                if (attendances.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      '📅 Calendário de Viagens (${attendances.length})',
                      style: const TextStyle(fontSize: 13),
                    ),
                    children: attendances.map((a) {
                      return ListTile(
                        dense: true,
                        title: Text(
                          'Data: ${a['date'].toString().substring(0, 10)} • ${a['direction']}',
                        ),
                        subtitle: Text('Método: ${a['method']}'),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Future<void> _markAttendance(String studentId, String direction) async {
    try {
      await _controller.markManualAttendance(studentId, direction);
      await _loadContext();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  void _showVanQrCodeModal(Map<String, dynamic> info) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('QR Code da Van (${info['plate']})'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'O aluno lê este código ao entrar na van para confirmar o embarque.',
            ),
            SizedBox(height: 16),
            Icon(Icons.qr_code_2, size: 140, color: AppColors.primary),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _buildTourismModule(Map<String, dynamic> fretamento) {
    final List trips = fretamento['trips'] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomCard(
          backgroundColor: Colors.teal.shade100,
          child: Text(
            '📅 Viagens / Eventos Agendados: ${fretamento['upcomingTripsCount']}',
            style: AppTextStyles.titleMedium,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '🗺️ Agenda de Fretamentos e Turismo',
          style: AppTextStyles.titleMedium,
        ),
        const SizedBox(height: 8),
        ...trips.map(
          (t) => CustomCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Chip(label: Text(t['type'])),
                    Text(
                      'R\$ ${t['agreedValue']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Contratante: ${t['clientName']} (${t['clientPhone']})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('Rota: ${t['origin']} ➔ ${t['destination']}'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

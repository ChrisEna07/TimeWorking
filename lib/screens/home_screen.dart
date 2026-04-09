import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/app_config.dart';
import '../models/work_log.dart';
import '../services/supabase_service.dart';
import '../services/pdf_service.dart';
import '../services/notification_service.dart';
import 'login_screen.dart';
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabase = SupabaseService();
  final _notif = NotificationService();
  List<WorkLog> _unpaidLogs = [];
  bool _isLoading = true;

  double _customHourlyRate = AppConfig.hourlyRate;
  List<Map<String, dynamic>> _paymentHistory = [];

  DateTime _selectedDate = DateTime.now();
  TimeOfDay _startTime = TimeOfDay.now();
  TimeOfDay _endTime = TimeOfDay.now();
  final _breakController = TextEditingController(text: "0");

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadCustomRate();
    _loadData();
  }

  Future<void> _loadCustomRate() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _customHourlyRate = prefs.getDouble('custom_hourly_rate') ?? AppConfig.hourlyRate;
    });
  }

  Future<void> _saveCustomRate(double newRate) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('custom_hourly_rate', newRate);
    setState(() => _customHourlyRate = newRate);
  }

  Future<void> _requestPermissions() async {
    // Request notification permission
    Map<Permission, PermissionStatus> statuses = await [
      Permission.notification,
      Permission.scheduleExactAlarm,
    ].request();

    // Check if notification is granted
    if (statuses[Permission.notification] != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Por favor activa las notificaciones para el cronómetro.",
            ),
          ),
        );
      }
    }

    // Battery optimization is tricky but helpful for background service
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final logs = await _supabase.getUnpaidLogs();
      final history = await _supabase.getPaymentHistory();
      setState(() {
        _unpaidLogs = logs;
        _paymentHistory = history;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading data: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _selectTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  Future<void> _saveManualLog() async {
    final start = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _startTime.hour, _startTime.minute);
    final end = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _endTime.hour, _endTime.minute);
    
    if (end.isBefore(start)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("La hora de salida debe ser después de la de entrada")));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _supabase.addManualLog(
        startTime: start,
        endTime: end,
        breakDuration: int.tryParse(_breakController.text) ?? 0,
      );
      _loadData();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Jornada Guardada")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }


  Future<void> _showLogoutProtection(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          "Cerrar Sesión (Admin)",
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: "Clave de Administrador",
            labelStyle: TextStyle(color: Colors.white60),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text == "ChrizDev073008") {
                FlutterBackgroundService().invoke('stopService');
                await _supabase.signOut();
                if (!mounted) return;
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Clave Incorrecta"),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text("AUTORIZAR"),
          ),
        ],
      ),
    );
  }

  void _showHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          "Resumen de Pendientes",
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: _unpaidLogs.isEmpty
              ? const Center(
                  child: Text(
                    "No hay jornadas registradas.",
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _unpaidLogs.length,
                  separatorBuilder: (context, index) =>
                      Divider(color: Colors.white.withOpacity(0.1)),
                  itemBuilder: (context, index) {
                    final log = _unpaidLogs[index];
                    final dateStr = DateFormat(
                      'EEEE, d MMM',
                      'es',
                    ).format(log.startTime);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        dateStr,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      subtitle: Text(
                        "${DateFormat('hh:mm a').format(log.startTime)} - ${log.endTime != null ? DateFormat('hh:mm a').format(log.endTime!) : 'En curso'}\nPausa: ${log.breakDuration} min",
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  "${log.totalHours.toStringAsFixed(1)} h",
                                  style: GoogleFonts.outfit(
                                    color: AppConfig.primaryGreen,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _confirmSinglePaymentDialog(log),
                                  child: const Text("DÍA PAGO", style: TextStyle(color: AppConfig.gold, fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.white54, size: 20),
                              onPressed: () {
                                Navigator.pop(context);
                                _showEditLogDialog(log);
                              },
                            ),
                          ],
                        ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showPaymentHistory();
            },
            child: const Text(
              "VER PAGOS ANTERIORES",
              style: TextStyle(color: AppConfig.gold, fontSize: 10),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CERRAR"),
          ),
          if (_unpaidLogs.isNotEmpty)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConfig.primaryGreen,
              ),
              onPressed: () => _confirmPaymentDialog(),
              child: const Text(
                "PROCEDER AL PAGO SEMANAL",
                style: TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  void _showPaymentHistory() async {
    final payments = await _supabase.getPaymentHistory();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          "Historial de Pagos",
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: payments.isEmpty
              ? const Center(
                  child: Text(
                    "No hay registros de pago.",
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: payments.length,
                  separatorBuilder: (context, index) =>
                      Divider(color: Colors.white.withOpacity(0.05)),
                  itemBuilder: (context, index) {
                    final p = payments[index];
                    final date = DateTime.parse(p['payment_date']);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        NumberFormat.currency(
                          locale: 'es_CO',
                          symbol: '\$',
                          decimalDigits: 0,
                        ).format(p['amount']),
                        style: const TextStyle(
                          color: AppConfig.primaryGreen,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        "${DateFormat('d MMM yyyy').format(date)}\nNotas: ${p['notes'] ?? 'Sin notas'}",
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                      trailing: Text(
                        "${p['total_hours']} h",
                        style: const TextStyle(color: Colors.white70),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("VOLVER"),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSinglePaymentDialog(WorkLog log) async {
    final double dayAmount = log.totalHours * _customHourlyRate;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text("Confirmar Pago de este día", style: TextStyle(color: Colors.white)),
        content: Text(
          "Monto: ${NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0).format(dayAmount)}",
          style: const TextStyle(color: AppConfig.primaryGreen, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
          ElevatedButton(
            onPressed: () async {
              await _supabase.recordSinglePayment(
                logId: log.id!, 
                amount: dayAmount, 
                hours: log.totalHours, 
                notes: "Pago individual de fecha ${log.formattedDate}"
              );
              if (!mounted) return;
              Navigator.pop(context); // Cierra dialogo confirmacion
              Navigator.pop(context); // Cierra historial
              _loadData();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Día marcado como pagado")));
            },
            child: const Text("CONFIRMAR"),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPaymentDialog() async {
    final notesController = TextEditingController();
    final double totalPayableHours = _supabase.calculatePayableTotal(
      _unpaidLogs,
    );
    final double totalAmount = totalPayableHours * _customHourlyRate;

    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          "Finalizar Pago Semanal",
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Monto a pagar: ${NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0).format(totalAmount)}",
              style: const TextStyle(
                color: AppConfig.primaryGreen,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: notesController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Notas del Pago (Opcional)",
                labelStyle: TextStyle(color: Colors.white60),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            onPressed: () async {
              await _supabase.recordPayment(
                logIds: _unpaidLogs.map((l) => l.id!).toList(),
                amount: totalAmount,
                hours: totalPayableHours,
                notes: notesController.text,
              );
              if (!mounted) return;
              Navigator.pop(context);
              _loadData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Pago registrado en el historial"),
                ),
              );
            },
            child: const Text("CONFIRMAR PAGO"),
          ),
        ],
      ),
    );
  }

  Future<void> _showResetProtection(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          "RESETEAR TODO (Admin)",
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Se borrarán TODOS los registros de forma permanente.",
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: controller,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Clave Admin",
                labelStyle: TextStyle(color: Colors.white60),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (controller.text == "ChrizDev073008") {
                await _supabase.deleteAllLogs();
                if (!mounted) return;
                Navigator.pop(context);
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Registros borrados")),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Clave Incorrecta"),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text("BORRAR"),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditLogDialog(WorkLog log) async {
    DateTime editDate = log.startTime;
    TimeOfDay editStart = TimeOfDay.fromDateTime(log.startTime);
    TimeOfDay editEnd = TimeOfDay.fromDateTime(log.endTime!);
    final breakCtrl = TextEditingController(text: log.breakDuration.toString());

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text("Editar Jornada", style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text("Fecha", style: TextStyle(color: Colors.white70)),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(editDate), style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  final p = await showDatePicker(context: context, initialDate: editDate, firstDate: DateTime(2024), lastDate: DateTime.now());
                  if (p != null) setDialogState(() => editDate = p);
                },
              ),
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      title: const Text("Entrada", style: TextStyle(color: Colors.white70, fontSize: 12)),
                      subtitle: Text(editStart.format(context), style: const TextStyle(color: Colors.white)),
                      onTap: () async {
                        final p = await showTimePicker(context: context, initialTime: editStart);
                        if (p != null) setDialogState(() => editStart = p);
                      },
                    ),
                  ),
                  Expanded(
                    child: ListTile(
                      title: const Text("Salida", style: TextStyle(color: Colors.white70, fontSize: 12)),
                      subtitle: Text(editEnd.format(context), style: const TextStyle(color: Colors.white)),
                      onTap: () async {
                        final p = await showTimePicker(context: context, initialTime: editEnd);
                        if (p != null) setDialogState(() => editEnd = p);
                      },
                    ),
                  ),
                ],
              ),
              TextField(
                controller: breakCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: "Pausa (min)", labelStyle: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
            ElevatedButton(
              onPressed: () async {
                final start = DateTime(editDate.year, editDate.month, editDate.day, editStart.hour, editStart.minute);
                final end = DateTime(editDate.year, editDate.month, editDate.day, editEnd.hour, editEnd.minute);
                await _supabase.updateWorkLog(
                  logId: log.id!,
                  startTime: start,
                  endTime: end,
                  breakDuration: int.tryParse(breakCtrl.text) ?? 0,
                );
                if (!mounted) return;
                Navigator.pop(context);
                _loadData();
              },
              child: const Text("GUARDAR"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAdminSettings() async {
    final controller = TextEditingController();
    final rateController = TextEditingController(text: _customHourlyRate.toStringAsFixed(0));
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text("Ajustes de Administrador", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: "Clave Admin", labelStyle: TextStyle(color: Colors.white60)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
          ElevatedButton(
            onPressed: () {
              if (controller.text == "ChrizDev073008") {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1A1A1B),
                    title: const Text("Valor Hora de Trabajo", style: TextStyle(color: Colors.white)),
                    content: TextField(
                      controller: rateController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: "Nuevo Valor por Hora", labelStyle: TextStyle(color: Colors.white60)),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
                      ElevatedButton(
                        onPressed: () async {
                          final newRate = double.tryParse(rateController.text);
                          if (newRate != null) {
                            await _saveCustomRate(newRate);
                            if (!mounted) return;
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tarifa actualizada correctamente")));
                          }
                        },
                        child: const Text("ACTUALIZAR"),
                      ),
                    ],
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Clave Incorrecta"), backgroundColor: Colors.red));
              }
            },
            child: const Text("AUTORIZAR"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double totalPayableHours = _supabase.calculatePayableTotal(_unpaidLogs);
    final currencyFormatter = NumberFormat.currency(
      locale: 'es_CO',
      symbol: '\$',
      decimalDigits: 0,
    );
    
    // Stats calculation
    double weeklyTotal = 0;
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    for (var p in _paymentHistory) {
      final pDate = DateTime.parse(p['payment_date']);
      if (pDate.isAfter(startOfWeek)) {
        weeklyTotal += p['amount'];
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F0D),
      appBar: AppBar(
        title: Text(
          "TIMEWORKING",
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () => _showLogoutProtection(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.blueAccent),
            onPressed: _showAdminSettings,
            tooltip: "Ajustes de Admin",
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
            onPressed: () => _showResetProtection(context),
            tooltip: "Resetear Horas (Admin)",
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppConfig.primaryGreen),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              children: [
                _buildHeader(),
                const SizedBox(height: 25),
                _buildStatsCard(weeklyTotal, currencyFormatter),
                const SizedBox(height: 20),
                _buildManualInputPanel(),
                const SizedBox(height: 20),
                _buildSummaryCard(totalPayableHours, currencyFormatter),
                const SizedBox(height: 20),
                _buildActions(),
              ],
            ),
    );
  }

  Widget _buildStatsCard(double weeklyTotal, NumberFormat formatter) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart, color: Colors.blueAccent, size: 18),
              const SizedBox(width: 8),
              Text("ESTADÍSTICAS DE INGRESOS", style: GoogleFonts.outfit(fontSize: 10, color: Colors.white38, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "Semana Actual: ${formatter.format(weeklyTotal)}",
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          Text(
            "Basado en pagos procesados",
            style: GoogleFonts.outfit(fontSize: 9, color: Colors.white24),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Bienvenido,",
          style: GoogleFonts.outfit(fontSize: 16, color: Colors.white70),
        ),
        Text(
          _supabase.currentUserName,
          style: GoogleFonts.outfit(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildClockSection() {
    return _buildManualInputPanel();
  }

  Widget _buildManualInputPanel() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(35),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Text("REGISTRO DE JORNADA MANUAL", 
            style: GoogleFonts.outfit(color: AppConfig.primaryGreen, fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 13)),
          const SizedBox(height: 25),
          
          _inputTile(
            icon: Icons.calendar_today,
            label: "Fecha de la Jornada",
            value: DateFormat('EEEE, d MMMM', 'es').format(_selectedDate),
            onTap: _selectDate,
          ),
          const SizedBox(height: 15),
          
          Row(
            children: [
              Expanded(
                child: _inputTile(
                  icon: Icons.login,
                  label: "Hora Entrada",
                  value: _startTime.format(context),
                  onTap: () => _selectTime(true),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: _inputTile(
                  icon: Icons.logout,
                  label: "Hora Salida",
                  value: _endTime.format(context),
                  onTap: () => _selectTime(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          TextField(
            controller: _breakController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lunch_dining, color: AppConfig.gold),
              labelText: "Minutos de Almuerzo",
              labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            ),
          ),
          
          const SizedBox(height: 30),
          
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: _saveManualLog,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConfig.primaryGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text("GUARDAR JORNADA", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputTile({required IconData icon, required String label, required String value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            const SizedBox(height: 5),
            Row(
              children: [
                Icon(icon, color: AppConfig.primaryGreen, size: 16),
                const SizedBox(width: 8),
                Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(double hours, NumberFormat formatter) {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppConfig.primaryGreen.withOpacity(0.1), Colors.transparent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: AppConfig.primaryGreen.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "MONTO ESTIMADO PENDIENTE",
                style: GoogleFonts.outfit(
                  fontSize: 10,
                  color: Colors.white38,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 5),
                Text(
                  formatter.format(hours * _customHourlyRate),
                  style: GoogleFonts.outfit(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              const SizedBox(height: 5),
              Text(
                DateTime.now().weekday == DateTime.saturday
                    ? "(Sábado pasa a sig. semana)"
                    : "(Total horas netas)",
                style: GoogleFonts.outfit(
                  fontSize: 10,
                  color: DateTime.now().weekday == DateTime.saturday
                      ? AppConfig.gold
                      : AppConfig.primaryGreen.withOpacity(0.6),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              children: [
                const Text(
                  "HORAS",
                  style: TextStyle(fontSize: 9, color: Colors.white38),
                ),
                Text(
                  hours.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _actionButton(
                icon: Icons.history,
                label: "Historial",
                onTap: _showHistoryDialog,
                color: Colors.white.withOpacity(0.05),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _actionButton(
                icon: Icons.picture_as_pdf_outlined,
                label: "Reporte PDF",
                onTap: () => PdfService.generateAndShareReport(
                  _unpaidLogs,
                  _supabase.calculatePayableTotal(_unpaidLogs),
                  _customHourlyRate,
                ),
                color: AppConfig.gold.withOpacity(0.8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(
              child: _actionButton(
                icon: Icons.card_membership_outlined,
                label: "Suscripción",
                color: AppConfig.gold.withOpacity(0.15),
                onTap: _showSubscriptionDialog,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _actionButton(
                icon: Icons.support_agent_outlined,
                label: "Soporte",
                color: Colors.white.withOpacity(0.05),
                onTap: () => _launchWhatsApp('support'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showSubscriptionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Text("✨ Suscripción Premium", style: GoogleFonts.outfit(color: AppConfig.gold, fontWeight: FontWeight.bold)),
        content: Text(
          "Si estás interesado en adquirir una cuenta en la App de Gestión de ChrizDev, tiene un costo de \$30.000 pesos semanales.\n\nEsto cubre costos de servidor y despliegue, pero si quieres estar al día en tus cuentas sin sentir que pierdes dinero, ¡lo vale!",
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("LUEGO")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppConfig.gold),
            onPressed: () {
              Navigator.pop(context);
              _launchWhatsApp('sales');
            },
            child: const Text("QUIERO MI SUSCRIPCIÓN", style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _launchWhatsApp(String type) async {
    String msg = "";
    if (type == 'sales') {
      msg =
          "si estas interesado en adquirir una cuenta en la app de gestion de ChrizDev, tiene un costo de 30 mil pesos semanales esto por costos de servidor y despliegue pero si quieres estar al dia en tus cuentas sin sentir que pierdes dinero lo vale";
    } else {
      msg = "Hola ChrizDev, necesito soporte técnico con la app TimeWorking.";
    }

    final url =
        "https://wa.me/${AppConfig.adminPhone}?text=${Uri.encodeComponent(msg)}";
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(height: 10),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

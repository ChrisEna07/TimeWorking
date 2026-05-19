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
import '../services/local_db_service.dart';
import '../services/pdf_service.dart';
import '../services/notification_service.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _db = LocalDbService();
  final _notif = NotificationService();
  List<WorkLog> _unpaidLogs = [];
  bool _isLoading = true;

  double _customHourlyRate = AppConfig.hourlyRate;
  List<Map<String, dynamic>> _paymentHistory = [];

  // Manual Log Controllers & State
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _startTime = TimeOfDay.now();
  TimeOfDay _endTime = TimeOfDay.now();
  final _breakController = TextEditingController(text: "0");
  final _customHoursController = TextEditingController(text: "8.0");
  String _workMode = 'hours'; // 'hours', 'shift_8', 'shift_12', 'custom'

  // Real-Time shift stopwatch state
  WorkLog? _activeShift;
  bool _isOnBreak = false;
  Duration _elapsedTime = Duration.zero;
  Timer? _stopwatchTimer;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadCustomRate();
    _loadData();
    _checkActiveShift();

    // Listen to background service events to keep UI in sync
    FlutterBackgroundService().on('update').listen((event) {
      if (mounted) {
        _checkActiveShift();
      }
    });
  }

  @override
  void dispose() {
    _stopwatchTimer?.cancel();
    _breakController.dispose();
    _customHoursController.dispose();
    super.dispose();
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
    Map<Permission, PermissionStatus> statuses = await [
      Permission.notification,
      Permission.scheduleExactAlarm,
    ].request();

    if (statuses[Permission.notification] != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Por favor activa las notificaciones para el cronómetro."),
          ),
        );
      }
    }

    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final logs = await _db.getUnpaidLogs();
      final history = await _db.getPaymentHistory();
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

  Future<void> _checkActiveShift() async {
    final active = await _db.getActiveShift();
    final isOnBreak = active != null ? await _db.isCurrentlyOnBreak(active.id!) : false;
    
    if (active != null) {
      if (_stopwatchTimer == null) {
        _startStopwatchTimer(active.startTime, active.breakDuration, isOnBreak);
      }
    } else {
      _stopwatchTimer?.cancel();
      _stopwatchTimer = null;
    }

    if (mounted) {
      setState(() {
        _activeShift = active;
        _isOnBreak = isOnBreak;
      });
    }
  }

  void _startStopwatchTimer(DateTime startTime, int breakDurationMinutes, bool isOnBreak) {
    _stopwatchTimer?.cancel();
    _stopwatchTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) return;
      if (_activeShift == null) {
        timer.cancel();
        _stopwatchTimer = null;
        return;
      }

      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final currentIsOnBreak = prefs.getBool('is_on_break') ?? isOnBreak;
      final currentBreakDuration = prefs.getInt('active_break_duration') ?? breakDurationMinutes;

      Duration elapsed;
      if (currentIsOnBreak) {
        final breakStartStr = prefs.getString('active_break_start_time');
        if (breakStartStr != null) {
          final breakStart = DateTime.parse(breakStartStr).toLocal();
          elapsed = breakStart.difference(startTime) - Duration(minutes: currentBreakDuration);
        } else {
          elapsed = now.difference(startTime) - Duration(minutes: currentBreakDuration);
        }
      } else {
        elapsed = now.difference(startTime) - Duration(minutes: currentBreakDuration);
      }

      setState(() {
        _elapsedTime = elapsed < Duration.zero ? Duration.zero : elapsed;
        _isOnBreak = currentIsOnBreak;
      });
    });
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
    DateTime start;
    DateTime end;
    int breakDur = 0;
    double? customHours;

    if (_workMode == 'hours') {
      start = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _startTime.hour, _startTime.minute);
      end = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _endTime.hour, _endTime.minute);
      breakDur = int.tryParse(_breakController.text) ?? 0;
      
      if (end.isBefore(start)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("La hora de salida debe ser después de la de entrada")));
        return;
      }
    } else {
      start = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 8, 0); // 8:00 AM standard start
      if (_workMode == 'shift_8') {
        end = start.add(const Duration(hours: 8));
      } else if (_workMode == 'shift_12') {
        end = start.add(const Duration(hours: 12));
      } else {
        customHours = double.tryParse(_customHoursController.text) ?? 8.0;
        end = start.add(Duration(minutes: (customHours * 60).toInt()));
      }
    }

    setState(() => _isLoading = true);
    try {
      await _db.addManualLog(
        startTime: start,
        endTime: end,
        breakDuration: breakDur,
        workMode: _workMode,
        customHours: customHours,
      );
      _loadData();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Jornada Guardada")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showLogoutConfirmation(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          "Cerrar Sesión",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "¿Estás seguro de que deseas cerrar sesión?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            onPressed: () async {
              FlutterBackgroundService().invoke('stopService');
              await _db.signOut();
              if (!mounted) return;
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
            child: const Text("CERRAR SESIÓN"),
          ),
        ],
      ),
    );
  }

  Future<void> _showResetConfirmation(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          "Borrar Registros",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "Se borrarán todos tus registros de horas y pagos de forma permanente. Esta acción no se puede deshacer.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _db.deleteAllLogs();
              if (!mounted) return;
              Navigator.pop(context);
              _loadData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Registros borrados")),
              );
            },
            child: const Text("RESETEAR"),
          ),
        ],
      ),
    );
  }

  Future<void> _showHourlyRateSettings() async {
    final rateController = TextEditingController(text: _customHourlyRate.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
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

                    String detailStr = "";
                    if (log.workMode == 'hours') {
                      detailStr = "${DateFormat('hh:mm a').format(log.startTime)} - ${log.endTime != null ? DateFormat('hh:mm a').format(log.endTime!) : 'En curso'}\nPausa: ${log.breakDuration} min";
                    } else if (log.workMode == 'shift_8') {
                      detailStr = "Jornada de 8 Horas Fijas";
                    } else if (log.workMode == 'shift_12') {
                      detailStr = "Jornada de 12 Horas Fijas";
                    } else {
                      detailStr = "Jornada Personalizada: ${log.totalHours.toStringAsFixed(1)} Horas Fijas";
                    }

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
                        detailStr,
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
                "PROCEDER AL PAGO",
                style: TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  void _showPaymentHistory() async {
    final payments = await _db.getPaymentHistory();
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
              await _db.recordSinglePayment(
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
    final double totalPayableHours = _db.calculatePayableTotal(_unpaidLogs);
    final double totalAmount = totalPayableHours * _customHourlyRate;

    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          "Finalizar Pago",
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
              await _db.recordPayment(
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

  Future<void> _showEditLogDialog(WorkLog log) async {
    DateTime editDate = log.startTime;
    TimeOfDay editStart = TimeOfDay.fromDateTime(log.startTime);
    TimeOfDay editEnd = TimeOfDay.fromDateTime(log.endTime ?? log.startTime);
    final breakCtrl = TextEditingController(text: log.breakDuration.toString());
    final hoursCtrl = TextEditingController(text: log.customHours?.toString() ?? "8.0");
    String editMode = log.workMode;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text("Editar Jornada", style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  dropdownColor: const Color(0xFF1A1A1A),
                  value: editMode,
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: 'hours', child: Text("Por Horas")),
                    DropdownMenuItem(value: 'shift_8', child: Text("Día 8 Horas")),
                    DropdownMenuItem(value: 'shift_12', child: Text("Día 12 Horas")),
                    DropdownMenuItem(value: 'custom', child: Text("Día Personalizado")),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => editMode = val);
                  },
                ),
                const SizedBox(height: 10),
                ListTile(
                  title: const Text("Fecha", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(editDate), style: const TextStyle(color: Colors.white)),
                  onTap: () async {
                    final p = await showDatePicker(context: context, initialDate: editDate, firstDate: DateTime(2024), lastDate: DateTime.now());
                    if (p != null) setDialogState(() => editDate = p);
                  },
                ),
                if (editMode == 'hours') ...[
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
                ] else if (editMode == 'custom') ...[
                  TextField(
                    controller: hoursCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: "Horas de la Jornada", labelStyle: TextStyle(color: Colors.white54)),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
            ElevatedButton(
              onPressed: () async {
                final start = DateTime(editDate.year, editDate.month, editDate.day, editStart.hour, editStart.minute);
                DateTime end;
                double? customH;
                int breakM = 0;

                if (editMode == 'hours') {
                  end = DateTime(editDate.year, editDate.month, editDate.day, editEnd.hour, editEnd.minute);
                  breakM = int.tryParse(breakCtrl.text) ?? 0;
                } else if (editMode == 'shift_8') {
                  end = start.add(const Duration(hours: 8));
                } else if (editMode == 'shift_12') {
                  end = start.add(const Duration(hours: 12));
                } else {
                  customH = double.tryParse(hoursCtrl.text) ?? 8.0;
                  end = start.add(Duration(minutes: (customH * 60).toInt()));
                }

                await _db.updateWorkLog(
                  logId: log.id!,
                  startTime: start,
                  endTime: end,
                  breakDuration: breakM,
                  workMode: editMode,
                  customHours: customH,
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

  @override
  Widget build(BuildContext context) {
    double totalPayableHours = _db.calculatePayableTotal(_unpaidLogs);
    final currencyFormatter = NumberFormat.currency(
      locale: 'es_CO',
      symbol: '\$',
      decimalDigits: 0,
    );
    
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
          onPressed: () => _showLogoutConfirmation(context),
          tooltip: "Cerrar Sesión",
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.blueAccent),
            onPressed: _showHourlyRateSettings,
            tooltip: "Ajustes de Tarifa",
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
            onPressed: () => _showResetConfirmation(context),
            tooltip: "Resetear Horas",
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
                _buildRealTimeShiftCard(),
                const SizedBox(height: 20),
                _buildManualInputPanel(),
                const SizedBox(height: 20),
                _buildSummaryCard(totalPayableHours, currencyFormatter),
                const SizedBox(height: 20),
                _buildSocialBenefitsCard(totalPayableHours * _customHourlyRate, currencyFormatter),
                const SizedBox(height: 20),
                _buildActions(),
                const SizedBox(height: 40),
                _buildDeveloperSignature(),
                const SizedBox(height: 20),
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
          _db.currentUserName,
          style: GoogleFonts.outfit(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildRealTimeShiftCard() {
    final bool hasActive = _activeShift != null;
    
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: hasActive ? AppConfig.primaryGreen.withOpacity(0.05) : Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(35),
        border: Border.all(
          color: hasActive ? AppConfig.primaryGreen.withOpacity(0.3) : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "CRONÓMETRO DE JORNADA",
                style: GoogleFonts.outfit(
                  color: hasActive ? AppConfig.primaryGreen : Colors.white54,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  fontSize: 13,
                ),
              ),
              if (hasActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isOnBreak ? AppConfig.gold.withOpacity(0.2) : AppConfig.primaryGreen.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _isOnBreak ? "EN PAUSA" : "ACTIVO",
                    style: TextStyle(
                      color: _isOnBreak ? AppConfig.gold : AppConfig.primaryGreen,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (!hasActive) ...[
            const Icon(Icons.timer_outlined, color: Colors.white24, size: 50),
            const SizedBox(height: 15),
            const Text(
              "¿Comienzas a trabajar ahora?",
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 5),
            const Text(
              "Inicia tu cronómetro para calcular tus horas automáticamente en segundo plano.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white30, fontSize: 11),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConfig.primaryGreen,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: () async {
                  setState(() => _isLoading = true);
                  await _db.startShift();
                  await _checkActiveShift();
                  setState(() => _isLoading = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Jornada iniciada")),
                  );
                },
                icon: const Icon(Icons.play_arrow, color: Colors.white),
                label: const Text("INICIAR JORNADA", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ] else ...[
            Text(
              _formatDuration(_elapsedTime),
              style: GoogleFonts.outfit(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              "Inicio: ${DateFormat('hh:mm a').format(_activeShift!.startTime)}",
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 25),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _isOnBreak ? AppConfig.primaryGreen : AppConfig.gold,
                      side: BorderSide(color: _isOnBreak ? AppConfig.primaryGreen : AppConfig.gold),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    onPressed: () async {
                      await _db.togglePause(_activeShift!.id!, !_isOnBreak);
                      await _checkActiveShift();
                    },
                    icon: Icon(_isOnBreak ? Icons.play_arrow : Icons.pause),
                    label: Text(
                      _isOnBreak ? "REANUDAR" : "ALMUERZO",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    onPressed: () async {
                      setState(() => _isLoading = true);
                      await _db.endShift(_activeShift!.id!, _activeShift!.startTime);
                      await _checkActiveShift();
                      _loadData();
                      setState(() => _isLoading = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Jornada finalizada y guardada")),
                      );
                    },
                    icon: const Icon(Icons.stop, color: Colors.white),
                    label: const Text(
                      "TERMINAR",
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return "$hours:$minutes:$seconds";
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
          
          // MÓDULO DE MODOS DE JORNADA
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                _modeButton('hours', 'Por Horas'),
                _modeButton('shift_8', 'Día 8h'),
                _modeButton('shift_12', 'Día 12h'),
                _modeButton('custom', 'Personaliz.'),
              ],
            ),
          ),
          
          _inputTile(
            icon: Icons.calendar_today,
            label: "Fecha de la Jornada",
            value: DateFormat('EEEE, d MMMM', 'es').format(_selectedDate),
            onTap: _selectDate,
          ),
          const SizedBox(height: 15),
          
          if (_workMode == 'hours') ...[
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
          ] else if (_workMode == 'custom') ...[
            TextField(
              controller: _customHoursController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.hourglass_bottom, color: AppConfig.primaryGreen),
                labelText: "Horas de la Jornada Fija",
                labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: AppConfig.primaryGreen.withOpacity(0.05),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: AppConfig.primaryGreen.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: AppConfig.primaryGreen),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _workMode == 'shift_8' 
                          ? "Se registrará una jornada plana de 8.0 horas." 
                          : "Se registrará una jornada plana de 12.0 horas.",
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
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
              child: const Text("GUARDAR JORNADA", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeButton(String mode, String label) {
    final isSelected = _workMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _workMode = mode;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppConfig.primaryGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white54,
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
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

  Widget _buildSocialBenefitsCard(double baseSalary, NumberFormat formatter) {
    final prima = baseSalary * 0.0833;
    final cesantias = baseSalary * 0.0833;
    final intereses = cesantias * 0.12;
    final vacaciones = baseSalary * 0.0417;
    final totalPrestaciones = prima + cesantias + intereses + vacaciones;
    final totalConPrestaciones = baseSalary + totalPrestaciones;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: AppConfig.primaryGreen,
          collapsedIconColor: Colors.white54,
          title: Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, color: AppConfig.primaryGreen, size: 20),
              const SizedBox(width: 10),
              Text(
                "Prestaciones Sociales (Colombia)",
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          subtitle: Text(
            "Acumulado estimado: +${formatter.format(totalPrestaciones)}",
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
              child: Column(
                children: [
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 10),
                  _benefitRow("Prima de Servicios (8.33%)", prima, formatter),
                  const SizedBox(height: 8),
                  _benefitRow("Cesantías (8.33%)", cesantias, formatter),
                  const SizedBox(height: 8),
                  _benefitRow("Intereses sobre Cesantías (1.00%)", intereses, formatter),
                  const SizedBox(height: 8),
                  _benefitRow("Vacaciones (4.17%)", vacaciones, formatter),
                  const Padding(
                     padding: EdgeInsets.symmetric(vertical: 10),
                     child: Divider(color: Colors.white10),
                  ),
                  _benefitRow(
                    "Total Prestaciones (21.83%)", 
                    totalPrestaciones, 
                    formatter, 
                    isTotal: true, 
                    color: AppConfig.gold
                  ),
                  const SizedBox(height: 8),
                  _benefitRow(
                    "Total Neto + Prestaciones", 
                    totalConPrestaciones, 
                    formatter, 
                    isTotal: true, 
                    color: AppConfig.primaryGreen
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Nota: Estimaciones proporcionales según la legislación colombiana vigente. Pueden cambiar según las condiciones del contrato.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white24, fontSize: 9, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _benefitRow(String label, double value, NumberFormat formatter, {bool isTotal = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isTotal ? Colors.white : Colors.white70,
            fontSize: isTotal ? 12 : 11,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          formatter.format(value),
          style: TextStyle(
            color: color ?? (isTotal ? Colors.white : Colors.white),
            fontSize: isTotal ? 13 : 11,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
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
                  _db.calculatePayableTotal(_unpaidLogs),
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
        content: const Text(
          "Si estás interesado en adquirir una cuenta en la App de Gestión de ChrizDev, tiene un costo de \$30.000 pesos semanales.\n\nEsto cubre costos de servidor y despliegue, pero si quieres estar al día en tus cuentas sin sentir que pierdes dinero, ¡lo vale!",
          style: TextStyle(color: Colors.white70, fontSize: 14),
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

  Widget _buildDeveloperSignature() {
    return Center(
      child: GestureDetector(
        onTap: () async {
          final url = "https://christian-romero.vercel.app/index.html";
          if (await canLaunchUrl(Uri.parse(url))) {
            await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          }
        },
        child: Text(
          "Desarrollado por ChrizDev",
          style: GoogleFonts.outfit(
            color: Colors.white30,
            fontSize: 12,
            decoration: TextDecoration.underline,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

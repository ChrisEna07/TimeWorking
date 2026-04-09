import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
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
  WorkLog? _activeShift;
  List<WorkLog> _unpaidLogs = [];
  bool _isLoading = true;
  bool _isOnBreak = false;
  Timer? _timer;
  String _currentDuration = "00:00:00";
  String _currentTime = "";

  @override
  void initState() {
    super.initState();
    _loadData();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) => _refreshClocks());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final active = await _supabase.getActiveShift();
      final logs = await _supabase.getUnpaidLogs();
      bool onBreak = false;
      if (active != null) {
        onBreak = await _supabase.isCurrentlyOnBreak(active.id!);
      }
      setState(() {
        _activeShift = active;
        _unpaidLogs = logs;
        _isOnBreak = onBreak;
        _isLoading = false;
      });
      _refreshClocks();
    } catch (e) {
      debugPrint("Error loading data: $e");
      setState(() => _isLoading = false);
    }
  }

  void _refreshClocks() {
    final now = DateTime.now();
    setState(() {
      _currentTime = DateFormat('hh:mm:ss a').format(now);
    });

    if (_activeShift != null && !_isOnBreak) {
      final diff = now.difference(_activeShift!.startTime);
      // Subtract break duration (stored in activeShift model)
      final netDiff = diff - Duration(minutes: _activeShift!.breakDuration);
      
      final h = netDiff.inHours;
      final m = (netDiff.inMinutes % 60).toString().padLeft(2, '0');
      final s = (netDiff.inSeconds % 60).toString().padLeft(2, '0');
      
      setState(() {
        _currentDuration = "${h.toString().padLeft(2, '0')}:$m:$s";
      });

      // 12 HOUR ALERT
      if (h == 12 && netDiff.inMinutes % 60 == 0 && netDiff.inSeconds % 60 == 0) {
        _notif.showInstantNotification("¡Jornada de 12 horas!", "¿Deseas seguir trabajando o cerrar el día?");
      }
    }
  }

  Future<void> _startShift() async {
    try {
      final log = await _supabase.startShift();
      setState(() => _activeShift = log);
      _notif.showInstantNotification("Jornada Iniciada", "El cronómetro está corriendo.");
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _togglePause() async {
    if (_activeShift == null) return;
    try {
      bool targetState = !_isOnBreak;
      await _supabase.togglePause(_activeShift!.id!, targetState);
      setState(() => _isOnBreak = targetState);
      _loadData(); // To refresh break_duration
      _notif.showInstantNotification(
        targetState ? "Pausa Iniciada" : "Jornada Reanudada", 
        targetState ? "El tiempo de almuerzo no se contará para el pago." : "El cronómetro vuelve a correr."
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error en pausa: $e")));
    }
  }

  Future<void> _endShift() async {
    try {
      if (_isOnBreak) await _togglePause(); // Ensure we end break before ending shift
      await _supabase.endShift(_activeShift!.id!, _activeShift!.startTime);
      setState(() {
        _activeShift = null;
        _currentDuration = "00:00:00";
        _isOnBreak = false;
      });
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _showLogoutProtection(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text("Cerrar Sesión (Admin)", style: TextStyle(color: Colors.white)),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
          ElevatedButton(
            onPressed: () async {
              if (controller.text == "ChrizDev073008") {
                await _supabase.signOut();
                if (!mounted) return;
                Navigator.pop(context);
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
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

  void _showHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text("Resumen de Pendientes", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: _unpaidLogs.isEmpty 
            ? const Center(child: Text("No hay jornadas registradas.", style: TextStyle(color: Colors.white54)))
            : ListView.separated(
                shrinkWrap: true,
                itemCount: _unpaidLogs.length,
                separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.1)),
                itemBuilder: (context, index) {
                  final log = _unpaidLogs[index];
                  final dateStr = DateFormat('EEEE, d MMM', 'es').format(log.startTime);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(dateStr, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.white)),
                    subtitle: Text(
                      "${DateFormat('hh:mm a').format(log.startTime)} - ${log.endTime != null ? DateFormat('hh:mm a').format(log.endTime!) : 'En curso'}\nPausa: ${log.breakDuration} min",
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    trailing: Text("${log.totalHours.toStringAsFixed(1)} h", style: GoogleFonts.outfit(color: AppConfig.primaryGreen, fontWeight: FontWeight.bold)),
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
            child: const Text("VER PAGOS ANTERIORES", style: TextStyle(color: AppConfig.gold, fontSize: 10)),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CERRAR")),
          if (_unpaidLogs.isNotEmpty)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppConfig.primaryGreen),
              onPressed: () => _confirmPaymentDialog(),
              child: const Text("PROCEDER AL PAGO SEMANAL", style: TextStyle(fontSize: 10, color: Colors.white)),
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
        title: const Text("Historial de Pagos", style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: payments.isEmpty 
            ? const Center(child: Text("No hay registros de pago.", style: TextStyle(color: Colors.white54)))
            : ListView.separated(
                shrinkWrap: true,
                itemCount: payments.length,
                separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.05)),
                itemBuilder: (context, index) {
                  final p = payments[index];
                  final date = DateTime.parse(p['payment_date']);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0).format(p['amount']),
                      style: const TextStyle(color: AppConfig.primaryGreen, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      "${DateFormat('d MMM yyyy').format(date)}\nNotas: ${p['notes'] ?? 'Sin notas'}",
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    trailing: Text("${p['total_hours']} h", style: const TextStyle(color: Colors.white70)),
                  );
                },
              ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("VOLVER")),
        ],
      ),
    );
  }

  Future<void> _confirmPaymentDialog() async {
    final notesController = TextEditingController();
    final double totalPayableHours = _supabase.calculatePayableTotal(_unpaidLogs);
    final double totalAmount = totalPayableHours * AppConfig.hourlyRate;
    
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text("Finalizar Pago Semanal", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Monto a pagar: ${NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0).format(totalAmount)}",
              style: const TextStyle(color: AppConfig.primaryGreen, fontWeight: FontWeight.bold, fontSize: 18),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
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
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pago registrado en el historial")));
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
        title: const Text("RESETEAR TODO (Admin)", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Se borrarán TODOS los registros de forma permanente.", style: TextStyle(color: Colors.white70)),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (controller.text == "ChrizDev073008") {
                await _supabase.deleteAllLogs();
                if (!mounted) return;
                Navigator.pop(context);
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Registros borrados")));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Clave Incorrecta"), backgroundColor: Colors.red));
              }
            },
            child: const Text("BORRAR"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double totalPayableHours = _supabase.calculatePayableTotal(_unpaidLogs);
    final currencyFormatter = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F0D),
      appBar: AppBar(
        title: Text("TIMEWORKING", style: GoogleFonts.outfit(fontWeight: FontWeight.w900, letterSpacing: 2)),
        leading: IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () => _showLogoutProtection(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
            onPressed: () => _showResetProtection(context),
            tooltip: "Resetear Horas (Admin)",
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppConfig.primaryGreen))
        : ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            children: [
              _buildHeader(),
              const SizedBox(height: 25),
              _buildClockSection(),
              const SizedBox(height: 25),
              _buildSummaryCard(totalPayableHours, currencyFormatter),
              const SizedBox(height: 25),
              _buildActions(),
            ],
          ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Bienvenido,", style: GoogleFonts.outfit(fontSize: 16, color: Colors.white70)),
        Text(
          _supabase.currentUserName,
          style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildClockSection() {
    bool isWorking = _activeShift != null;
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(35),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isWorking ? (_isOnBreak ? "EN PAUSA (ALMUERZO)" : "EN JORNADA") : "SISTEMA LISTO",
                style: GoogleFonts.outfit(
                  color: _isOnBreak ? AppConfig.gold : (isWorking ? AppConfig.primaryGreen : Colors.white24), 
                  fontWeight: FontWeight.bold, 
                  letterSpacing: 2, 
                  fontSize: 12
                ),
              ),
              Text(_currentTime, style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 30),
          Text(
            _currentDuration,
            style: GoogleFonts.orbitron(
              fontSize: 48, 
              fontWeight: FontWeight.bold, 
              color: _isOnBreak ? Colors.white60 : Colors.white, 
              letterSpacing: 2
            ),
          ),
          const SizedBox(height: 40),
          if (isWorking) 
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 60,
                    child: ElevatedButton.icon(
                      onPressed: _togglePause,
                      icon: Icon(_isOnBreak ? Icons.play_arrow : Icons.pause),
                      label: Text(_isOnBreak ? "REANUDAR" : "ALMUERZO"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isOnBreak ? AppConfig.primaryGreen : AppConfig.gold.withOpacity(0.8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 60,
                    child: ElevatedButton.icon(
                      onPressed: _endShift,
                      icon: const Icon(Icons.stop),
                      label: const Text("PARAR"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent.withOpacity(0.8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                    ),
                  ),
                ),
              ],
            )
          else 
            SizedBox(
              width: double.infinity,
              height: 65,
              child: ElevatedButton(
                onPressed: _startShift,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConfig.primaryGreen,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text("INICIAR JORNADA", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.white)),
              ),
            ),
        ],
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
              Text("MONTO ESTIMADO PENDIENTE", style: GoogleFonts.outfit(fontSize: 10, color: Colors.white38, letterSpacing: 1)),
              const SizedBox(height: 5),
              Text(
                formatter.format(hours * AppConfig.hourlyRate),
                style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 5),
              Text("(Total horas netas)", style: GoogleFonts.outfit(fontSize: 10, color: AppConfig.primaryGreen.withOpacity(0.6))),
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
                const Text("HORAS", style: TextStyle(fontSize: 9, color: Colors.white38)),
                Text(hours.toStringAsFixed(1), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
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
                onTap: () => PdfService.generateAndShareReport(_unpaidLogs, _supabase.calculatePayableTotal(_unpaidLogs)),
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
                onTap: () => _launchWhatsApp('sales'),
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

  Future<void> _launchWhatsApp(String type) async {
    String msg = "";
    if (type == 'sales') {
      msg = "si estas interesado en adquirir una cuenta en la app de gestion de ChrizDev, tiene un costo de 30 mil pesos semanales esto por costos de servidor y despliegue pero si quieres estar al dia en tus cuentas sin sentir que pierdes dinero lo vale";
    } else {
      msg = "Hola ChrizDev, necesito soporte técnico con la app TimeWorking.";
    }
    
    final url = "https://wa.me/${AppConfig.adminPhone}?text=${Uri.encodeComponent(msg)}";
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Widget _actionButton({required IconData icon, required String label, required VoidCallback onTap, required Color color}) {
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
            Text(label, style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

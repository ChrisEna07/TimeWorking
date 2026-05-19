import 'dart:math';
import 'package:get_storage/get_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../models/work_log.dart';

class LocalDbService {
  static final LocalDbService _instance = LocalDbService._internal();
  factory LocalDbService() => _instance;
  LocalDbService._internal();

  final _box = GetStorage();

  bool get isAuthenticated => _box.read('current_user') != null;

  Map<String, dynamic>? get currentUser => _box.read('current_user');

  String? get currentUserId => currentUser?['id'];

  String get currentUserName => currentUser?['name'] ?? 'Usuario';

  Future<void> signIn(String email, String password) async {
    final List<dynamic> usersJson = _box.read('users') ?? [];
    final user = usersJson.firstWhere(
      (u) => u['email'] == email.trim() && u['password'] == password,
      orElse: () => null,
    );
    if (user == null) {
      throw Exception('Usuario o contraseña incorrectos');
    }
    await _box.write('current_user', user);
  }

  Future<void> signUp(String email, String password, String name) async {
    final List<dynamic> usersJson = _box.read('users') ?? [];
    final alreadyExists = usersJson.any((u) => u['email'] == email.trim());
    if (alreadyExists) {
      throw Exception('El correo ya está registrado');
    }
    final newUser = {
      'id': email.trim(),
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
    };
    usersJson.add(newUser);
    await _box.write('users', usersJson);
    // Auto sign in after sign up
    await _box.write('current_user', newUser);
  }

  Future<void> signOut() async {
    await _box.remove('current_user');
  }

  Future<void> recoverPassword(String email) async {
    final List<dynamic> usersJson = _box.read('users') ?? [];
    final exists = usersJson.any((u) => u['email'] == email.trim());
    if (!exists) {
      throw Exception('Usuario no encontrado');
    }
  }

  Future<void> updateWorkLog({
    required String logId,
    required DateTime startTime,
    required DateTime endTime,
    required int breakDuration,
    String workMode = 'hours',
    double? customHours,
  }) async {
    final List<dynamic> logsJson = _box.read('work_logs') ?? [];
    for (int i = 0; i < logsJson.length; i++) {
      if (logsJson[i]['id'] == logId) {
        logsJson[i]['start_time'] = startTime.toUtc().toIso8601String();
        logsJson[i]['end_time'] = endTime.toUtc().toIso8601String();
        logsJson[i]['break_duration'] = breakDuration;
        logsJson[i]['work_mode'] = workMode;
        logsJson[i]['custom_hours'] = customHours;
        break;
      }
    }
    await _box.write('work_logs', logsJson);
  }

  Future<WorkLog> addManualLog({
    required DateTime startTime,
    required DateTime endTime,
    required int breakDuration,
    String workMode = 'hours',
    double? customHours,
  }) async {
    final isSaturday = startTime.weekday == DateTime.saturday;
    final logId = 'log_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
    
    final newLog = WorkLog(
      id: logId,
      userId: currentUserId,
      startTime: startTime,
      endTime: endTime,
      isSaturday: isSaturday,
      breakDuration: breakDuration,
      workMode: workMode,
      customHours: customHours,
    );

    final List<dynamic> logsJson = _box.read('work_logs') ?? [];
    logsJson.add(newLog.toJson());
    await _box.write('work_logs', logsJson);

    return newLog;
  }

  Future<WorkLog> startShift() async {
    final now = DateTime.now();
    final isSaturday = now.weekday == DateTime.saturday;
    final logId = 'log_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';

    final newLog = WorkLog(
      id: logId,
      userId: currentUserId,
      startTime: now,
      isSaturday: isSaturday,
    );

    final List<dynamic> logsJson = _box.read('work_logs') ?? [];
    logsJson.add(newLog.toJson());
    await _box.write('work_logs', logsJson);

    // Write to SharedPreferences for Background Service isolate
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_start_time', now.toIso8601String());
    await prefs.setInt('active_break_duration', 0);
    await prefs.setBool('is_on_break', false);
    await prefs.setString('active_log_id', logId);

    // Start background service
    try {
      final service = FlutterBackgroundService();
      await service.startService();
    } catch (e) {
      print("Could not start background service: $e");
    }

    return newLog;
  }

  Future<WorkLog> endShift(String logId, DateTime startTime) async {
    final now = DateTime.now();
    final List<dynamic> logsJson = _box.read('work_logs') ?? [];
    Map<String, dynamic>? updatedLogJson;

    for (int i = 0; i < logsJson.length; i++) {
      if (logsJson[i]['id'] == logId) {
        // If it was paused when ending, calculate final break duration
        final breakStartStr = logsJson[i]['break_start_time'];
        if (breakStartStr != null) {
          final breakStart = DateTime.parse(breakStartStr).toLocal();
          final currentBreakDuration = logsJson[i]['break_duration'] ?? 0;
          final addedMinutes = now.difference(breakStart).inMinutes;
          logsJson[i]['break_start_time'] = null;
          logsJson[i]['break_duration'] = currentBreakDuration + addedMinutes;
        }

        logsJson[i]['end_time'] = now.toUtc().toIso8601String();
        updatedLogJson = logsJson[i];
        break;
      }
    }
    
    if (updatedLogJson == null) {
      throw Exception('Jornada no encontrada');
    }
    await _box.write('work_logs', logsJson);

    // Stop background service
    try {
      FlutterBackgroundService().invoke('stopService');
    } catch (e) {
      print("Could not stop background service: $e");
    }

    // Clean SharedPreferences keys
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_start_time');
    await prefs.remove('active_break_duration');
    await prefs.remove('is_on_break');
    await prefs.remove('active_log_id');
    await prefs.remove('active_break_start_time');

    return WorkLog.fromJson(updatedLogJson);
  }

  Future<void> togglePause(String logId, bool isPausing) async {
    final now = DateTime.now();
    final List<dynamic> logsJson = _box.read('work_logs') ?? [];
    int breakDur = 0;

    for (int i = 0; i < logsJson.length; i++) {
      if (logsJson[i]['id'] == logId) {
        if (isPausing) {
          logsJson[i]['break_start_time'] = now.toUtc().toIso8601String();
        } else {
          final breakStartStr = logsJson[i]['break_start_time'];
          if (breakStartStr != null) {
            final breakStart = DateTime.parse(breakStartStr).toLocal();
            final currentBreakDuration = logsJson[i]['break_duration'] ?? 0;
            final addedMinutes = now.difference(breakStart).inMinutes;
            logsJson[i]['break_start_time'] = null;
            logsJson[i]['break_duration'] = currentBreakDuration + addedMinutes;
            breakDur = currentBreakDuration + addedMinutes;
          }
        }
        break;
      }
    }
    await _box.write('work_logs', logsJson);

    // Sync with SharedPreferences for background service
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_on_break', isPausing);
    if (!isPausing) {
      await prefs.setInt('active_break_duration', breakDur);
    } else {
      await prefs.setString('active_break_start_time', now.toIso8601String());
    }
  }

  Future<WorkLog?> getActiveShift() async {
    final userId = currentUserId;
    if (userId == null) return null;

    final List<dynamic> logsJson = _box.read('work_logs') ?? [];
    final activeLog = logsJson.firstWhere(
      (log) => log['user_id'] == userId && log['end_time'] == null,
      orElse: () => null,
    );
    if (activeLog == null) return null;
    return WorkLog.fromJson(activeLog);
  }

  Future<bool> isCurrentlyOnBreak(String logId) async {
    final List<dynamic> logsJson = _box.read('work_logs') ?? [];
    final log = logsJson.firstWhere((l) => l['id'] == logId, orElse: () => null);
    if (log == null) return false;
    return log['break_start_time'] != null;
  }

  Future<List<WorkLog>> getUnpaidLogs() async {
    final userId = currentUserId;
    if (userId == null) return [];

    final List<dynamic> logsJson = _box.read('work_logs') ?? [];
    final unpaid = logsJson
        .where((log) => log['user_id'] == userId && log['is_paid'] == false)
        .map((log) => WorkLog.fromJson(log))
        .toList();

    // Sort descending by start time
    unpaid.sort((a, b) => b.startTime.compareTo(a.startTime));
    return unpaid;
  }

  double calculatePayableTotal(List<WorkLog> logs) {
    double total = 0;
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final startOfMonday = DateTime(monday.year, monday.month, monday.day);

    for (var log in logs) {
      if (log.isSaturday && log.startTime.isAfter(startOfMonday)) continue;
      total += log.totalHours;
    }
    return total;
  }

  Future<void> recordSinglePayment({
    required String logId,
    required double amount,
    required double hours,
    required String notes,
  }) async {
    final userId = currentUserId;
    if (userId == null) return;

    // Mark log as paid
    final List<dynamic> logsJson = _box.read('work_logs') ?? [];
    for (int i = 0; i < logsJson.length; i++) {
      if (logsJson[i]['id'] == logId) {
        logsJson[i]['is_paid'] = true;
        break;
      }
    }
    await _box.write('work_logs', logsJson);

    // Save payment history
    final List<dynamic> historyJson = _box.read('payment_history') ?? [];
    historyJson.add({
      'id': 'pay_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}',
      'user_id': userId,
      'amount': amount,
      'total_hours': hours,
      'notes': notes,
      'work_log_ids': [logId],
      'payment_date': DateTime.now().toIso8601String(),
    });
    await _box.write('payment_history', historyJson);
  }

  Future<void> recordPayment({
    required List<String> logIds,
    required double amount,
    required double hours,
    required String notes,
  }) async {
    final userId = currentUserId;
    if (userId == null) return;

    // Mark logs as paid
    final List<dynamic> logsJson = _box.read('work_logs') ?? [];
    for (int i = 0; i < logsJson.length; i++) {
      if (logIds.contains(logsJson[i]['id'])) {
        logsJson[i]['is_paid'] = true;
      }
    }
    await _box.write('work_logs', logsJson);

    // Save payment history
    final List<dynamic> historyJson = _box.read('payment_history') ?? [];
    historyJson.add({
      'id': 'pay_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}',
      'user_id': userId,
      'amount': amount,
      'total_hours': hours,
      'notes': notes,
      'work_log_ids': logIds,
      'payment_date': DateTime.now().toIso8601String(),
    });
    await _box.write('payment_history', historyJson);
  }

  Future<List<Map<String, dynamic>>> getPaymentHistory() async {
    final userId = currentUserId;
    if (userId == null) return [];

    final List<dynamic> historyJson = _box.read('payment_history') ?? [];
    final userPayments = historyJson
        .where((p) => p['user_id'] == userId)
        .map((p) => Map<String, dynamic>.from(p))
        .toList();

    // Sort descending by payment date
    userPayments.sort((a, b) => b['payment_date'].compareTo(a['payment_date']));
    return userPayments;
  }

  Future<void> deleteAllLogs() async {
    final userId = currentUserId;
    if (userId == null) return;

    final List<dynamic> logsJson = _box.read('work_logs') ?? [];
    logsJson.removeWhere((log) => log['user_id'] == userId);
    await _box.write('work_logs', logsJson);

    final List<dynamic> historyJson = _box.read('payment_history') ?? [];
    historyJson.removeWhere((p) => p['user_id'] == userId);
    await _box.write('payment_history', historyJson);
  }
}

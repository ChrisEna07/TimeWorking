import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/work_log.dart';
import '../config/app_config.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  final client = Supabase.instance.client;

  User? get currentUser => client.auth.currentUser;
  String? get currentUserId => currentUser?.id;
  String get currentUserName {
    final metadata = currentUser?.userMetadata;
    if (metadata == null) return 'Usuario';

    // Try different common keys for names
    return metadata['name'] ??
        metadata['full_name'] ??
        metadata['display_name'] ??
        metadata['username'] ??
        'Usuario';
  }

  bool get isAuthenticated => currentUser != null;

  Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signUp(String email, String password, String name) async {
    await client.auth.signUp(
      email: email,
      password: password,
      data: {'name': name},
    );
  }

  Future<void> signOut() async {
    await client.auth.signOut();
  }

  Future<void> recoverPassword(String email) async {
    await client.auth.resetPasswordForEmail(email);
  }

  Future<void> updateWorkLog({
    required String logId,
    required DateTime startTime,
    required DateTime endTime,
    required int breakDuration,
  }) async {
    await client.from('work_logs').update({
      'start_time': startTime.toUtc().toIso8601String(),
      'end_time': endTime.toUtc().toIso8601String(),
      'break_duration': breakDuration,
    }).eq('id', logId);
  }

  Future<WorkLog> addManualLog({
    required DateTime startTime,
    required DateTime endTime,
    required int breakDuration,
  }) async {
    final isSaturday = startTime.weekday == DateTime.saturday;
    
    final newLog = WorkLog(
      userId: currentUserId,
      startTime: startTime,
      endTime: endTime,
      isSaturday: isSaturday,
      breakDuration: breakDuration,
    );

    final response = await client
        .from('work_logs')
        .insert(newLog.toJson())
        .select()
        .single();

    return WorkLog.fromJson(response);
  }

  Future<WorkLog> startShift() async {
    final now = DateTime.now();
    final isSaturday = now.weekday == DateTime.saturday;

    final newLog = WorkLog(
      userId: currentUserId,
      startTime: now,
      isSaturday: isSaturday,
    );

    final response = await client
        .from('work_logs')
        .insert(newLog.toJson())
        .select()
        .single();

    return WorkLog.fromJson(response);
  }

  Future<WorkLog> endShift(String logId, DateTime startTime) async {
    final now = DateTime.now();

    final response = await client
        .from('work_logs')
        .update({'end_time': now.toUtc().toIso8601String()})
        .eq('id', logId)
        .select()
        .single();

    return WorkLog.fromJson(response);
  }

  Future<void> togglePause(String logId, bool isPausing) async {
    final now = DateTime.now();
    if (isPausing) {
      // Start break
      await client
          .from('work_logs')
          .update({'break_start_time': now.toUtc().toIso8601String()})
          .eq('id', logId);
    } else {
      // Resume from break - Calculate gap
      final response = await client
          .from('work_logs')
          .select('break_start_time, break_duration')
          .eq('id', logId)
          .single();
      final breakStart = DateTime.parse(response['break_start_time']).toLocal();
      final currentBreakDuration = response['break_duration'] ?? 0;

      final addedMinutes = now.difference(breakStart).inMinutes;

      await client
          .from('work_logs')
          .update({
            'break_start_time': null,
            'break_duration': currentBreakDuration + addedMinutes,
          })
          .eq('id', logId);
    }
  }

  Future<WorkLog?> getActiveShift() async {
    final userId = currentUserId;
    if (userId == null) return null;

    final response = await client
        .from('work_logs')
        .select()
        .eq('user_id', userId)
        .isFilter('end_time', null)
        .maybeSingle();

    if (response == null) return null;
    return WorkLog.fromJson(response);
  }

  Future<bool> isCurrentlyOnBreak(String logId) async {
    final response = await client
        .from('work_logs')
        .select('break_start_time')
        .eq('id', logId)
        .single();
    return response['break_start_time'] != null;
  }

  Future<List<WorkLog>> getUnpaidLogs() async {
    final userId = currentUserId;
    if (userId == null) return [];

    final response = await client
        .from('work_logs')
        .select()
        .eq('user_id', userId)
        .eq('is_paid', false)
        .order('start_time', ascending: false);

    return (response as List).map((json) => WorkLog.fromJson(json)).toList();
  }

  double calculatePayableTotal(List<WorkLog> logs) {
    double total = 0;
    final now = DateTime.now();
    // Monday of the current week
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final startOfMonday = DateTime(monday.year, monday.month, monday.day);

    for (var log in logs) {
      // If it's Saturday of the current week, it goes to next week's account
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

    await client.from('work_logs').update({'is_paid': true}).eq('id', logId);
    await client.from('payment_history').insert({
      'user_id': userId,
      'amount': amount,
      'total_hours': hours,
      'notes': notes,
      'work_log_ids': [logId],
      'payment_date': DateTime.now().toIso8601String(),
    });
  }

  Future<void> recordPayment({
    required List<String> logIds,
    required double amount,
    required double hours,
    required String notes,
  }) async {
    final userId = currentUserId;
    if (userId == null) return;

    await client
        .from('work_logs')
        .update({'is_paid': true})
        .filter('id', 'in', logIds);
    await client.from('payment_history').insert({
      'user_id': userId,
      'amount': amount,
      'total_hours': hours,
      'notes': notes,
      'work_log_ids': logIds,
      'payment_date': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getPaymentHistory() async {
    final userId = currentUserId;
    if (userId == null) return [];

    final response = await client
        .from('payment_history')
        .select()
        .eq('user_id', userId)
        .order('payment_date', ascending: false);

    return response;
  }

  Future<void> deleteAllLogs() async {
    final userId = currentUserId;
    if (userId == null) return;
    await client.from('work_logs').delete().eq('user_id', userId);
    await client.from('payment_history').delete().eq('user_id', userId);
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/work_log.dart';

class SupabaseService {
  final SupabaseClient client = Supabase.instance.client;

  // Singleton pattern
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  String? get currentUserId => client.auth.currentUser?.id;
  String get currentUserName => client.auth.currentUser?.userMetadata?['display_name'] ?? 'Usuario';
  bool get isAuthenticated => client.auth.currentUser != null;

  Future<AuthResponse> signUp(String email, String password, String name) async {
    return await client.auth.signUp(
      email: email,
      password: password,
      data: {'display_name': name},
    );
  }

  Future<AuthResponse> signIn(String email, String password) async {
    return await client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await client.auth.signOut();
  }

  Future<void> recoverPassword(String email) async {
    await client.auth.resetPasswordForEmail(email);
  }

  // Record start time
  Future<WorkLog> startShift() async {
    final now = DateTime.now();
    final isSaturday = now.weekday == DateTime.saturday;
    
    final newLog = WorkLog(
      userId: currentUserId, // Use the correct nullable ID
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

  // Record end time
  Future<WorkLog> endShift(String logId, DateTime startTime) async {
    final now = DateTime.now();
    final duration = now.difference(startTime);
    final hours = duration.inMinutes / 60.0;

    final response = await client
        .from('work_logs')
        .update({
          'end_time': now.toIso8601String(),
          'total_hours': hours,
        })
        .eq('id', logId)
        .select()
        .single();

    return WorkLog.fromJson(response);
  }

  // Get active shift (if any)
  Future<WorkLog?> getActiveShift() async {
    final response = await client
        .from('work_logs')
        .select()
        .filter('end_time', 'is', null)
        .maybeSingle();

    if (response == null) return null;
    return WorkLog.fromJson(response);
  }

  // Get logs for the current week context
  Future<List<WorkLog>> getUnpaidLogs() async {
    final response = await client
        .from('work_logs')
        .select()
        .eq('is_paid', false)
        .order('start_time', ascending: false);

    return (response as List).map((json) => WorkLog.fromJson(json)).toList();
  }

  // Calculate current week's total (Excluding current Saturday)
  double calculatePayableTotal(List<WorkLog> logs) {
    double total = 0;
    final now = DateTime.now();
    
    // Find the start of the current week (Monday)
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final startOfMonday = DateTime(monday.year, monday.month, monday.day);

    for (var log in logs) {
      // If it's Saturday and it's from the CURRENT week, skip it (it goes to next week)
      if (log.isSaturday && log.startTime.isAfter(startOfMonday)) {
        continue;
      }
      total += log.totalHours;
    }
    return total;
  }
  
  Future<void> markLogsAsPaid(List<String> ids) async {
    await client.from('work_logs').update({'is_paid': true}).filter('id', 'in', ids);
  }

  Future<void> recordPayment({
    required List<String> logIds,
    required double amount,
    required double hours,
    required String notes,
  }) async {
    final userId = currentUserId;
    if (userId == null) return;

    // 1. Mark logs as paid
    await markLogsAsPaid(logIds);

    // 2. Create history entry
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
        
    return response as List<Map<String, dynamic>>;
  }

  Future<void> deleteAllLogs() async {
    final userId = currentUserId;
    if (userId == null) return;
    await client.from('work_logs').delete().eq('user_id', userId);
  }
}

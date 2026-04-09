import 'package:intl/intl.dart';

class WorkLog {
  final String? id;
  final String? userId;
  final DateTime startTime;
  final DateTime? endTime;
  final double totalHours;
  final bool isSaturday;
  final bool isPaid;

  WorkLog({
    this.id,
    this.userId,
    required this.startTime,
    this.endTime,
    this.totalHours = 0.0,
    required this.isSaturday,
    this.isPaid = false,
  });

  factory WorkLog.fromJson(Map<String, dynamic> json) {
    return WorkLog(
      id: json['id'],
      userId: json['user_id'],
      startTime: DateTime.parse(json['start_time']).toLocal(),
      endTime: json['end_time'] != null ? DateTime.parse(json['end_time']).toLocal() : null,
      totalHours: (json['total_hours'] as num? ?? 0.0).toDouble(),
      isSaturday: json['is_saturday'] ?? false,
      isPaid: json['is_paid'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (userId != null && userId!.isNotEmpty) 'user_id': userId,
      'start_time': startTime.toUtc().toIso8601String(),
      'end_time': endTime?.toUtc().toIso8601String(),
      'total_hours': totalHours,
      'is_saturday': isSaturday,
      'is_paid': isPaid,
    };
  }

  String get formattedDate => DateFormat('dd/MM/yyyy').format(startTime);
  String get formattedStartTime => DateFormat('hh:mm a').format(startTime);
  String get formattedEndTime => endTime != null ? DateFormat('hh:mm a').format(endTime!) : '--:--';
  
  double get earnings => totalHours * 6000;
  
  String get formattedEarnings {
    final formatter = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);
    return formatter.format(earnings);
  }
}

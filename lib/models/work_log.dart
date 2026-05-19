import 'package:intl/intl.dart';
import '../config/app_config.dart';

class WorkLog {
  final String? id;
  final String? userId;
  final DateTime startTime;
  DateTime? endTime;
  final bool isSaturday;
  final bool isPaid;
  final int breakDuration; // In minutes
  final String workMode; // 'hours', 'shift_8', 'shift_12', 'custom'
  final double? customHours;

  WorkLog({
    this.id,
    this.userId,
    required this.startTime,
    this.endTime,
    required this.isSaturday,
    this.isPaid = false,
    this.breakDuration = 0,
    this.workMode = 'hours',
    this.customHours,
  });

  factory WorkLog.fromJson(Map<String, dynamic> json) {
    return WorkLog(
      id: json['id'],
      userId: json['user_id'],
      startTime: DateTime.parse(json['start_time']).toLocal(),
      endTime: json['end_time'] != null ? DateTime.parse(json['end_time']).toLocal() : null,
      isSaturday: json['is_saturday'] ?? false,
      isPaid: json['is_paid'] ?? false,
      breakDuration: json['break_duration'] ?? 0,
      workMode: json['work_mode'] ?? 'hours',
      customHours: json['custom_hours'] != null ? (json['custom_hours'] as num).toDouble() : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      'start_time': startTime.toUtc().toIso8601String(),
      if (endTime != null) 'end_time': endTime!.toUtc().toIso8601String(),
      'is_saturday': isSaturday,
      'is_paid': isPaid,
      'break_duration': breakDuration,
      'work_mode': workMode,
      if (customHours != null) 'custom_hours': customHours,
    };
  }

  double get totalHours {
    if (workMode == 'shift_8') return 8.0;
    if (workMode == 'shift_12') return 12.0;
    if (workMode == 'custom') return customHours ?? 0.0;

    if (endTime == null) return 0;
    final diff = endTime!.difference(startTime);
    // Use seconds for maximum precision (1 minute = 60s)
    final hours = diff.inSeconds / 3600.0;
    final netHours = hours - (breakDuration / 60.0);
    return netHours > 0 ? netHours : 0;
  }

  // Getters for PDF and UI
  String get formattedDate => DateFormat('dd/MM/yyyy').format(startTime);
  String get formattedStartTime => DateFormat('hh:mm a').format(startTime);
  String get formattedEndTime => endTime != null ? DateFormat('hh:mm a').format(endTime!) : '--:--';
  double get earnings => totalHours * AppConfig.hourlyRate;
}

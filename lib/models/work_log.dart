class WorkLog {
  final String? id;
  final String? userId;
  final DateTime startTime;
  DateTime? endTime;
  final bool isSaturday;
  final bool isPaid;
  final int breakDuration; // In minutes

  WorkLog({
    this.id,
    this.userId,
    required this.startTime,
    this.endTime,
    required this.isSaturday,
    this.isPaid = false,
    this.breakDuration = 0,
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (userId != null) 'user_id': userId,
      'start_time': startTime.toUtc().toIso8601String(),
      if (endTime != null) 'end_time': endTime!.toUtc().toIso8601String(),
      'is_saturday': isSaturday,
      'is_paid': isPaid,
      'break_duration': breakDuration,
    };
  }

  double get totalHours {
    if (endTime == null) return 0;
    final diff = endTime!.difference(startTime);
    final hours = diff.inMinutes / 60.0;
    final netHours = hours - (breakDuration / 60.0);
    return netHours > 0 ? netHours : 0;
  }
}

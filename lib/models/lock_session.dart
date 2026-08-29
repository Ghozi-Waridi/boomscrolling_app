import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single lock session
class LockSession {
  final String id;
  final String userId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int plannedDurationMinutes;
  final int? actualDurationMinutes;
  final bool completed;
  final bool forcedExit;
  final String reason; // focus, study, break, other
  final Map<String, dynamic> deviceInfo;
  final DateTime? syncedAt;
  final String? notes;

  LockSession({
    required this.id,
    required this.userId,
    required this.startedAt,
    this.endedAt,
    required this.plannedDurationMinutes,
    this.actualDurationMinutes,
    required this.completed,
    required this.forcedExit,
    required this.reason,
    required this.deviceInfo,
    this.syncedAt,
    this.notes,
  });

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'user_id': userId,
      'started_at': startedAt,
      'ended_at': endedAt,
      'planned_duration_minutes': plannedDurationMinutes,
      'actual_duration_minutes': actualDurationMinutes,
      'completed': completed,
      'forced_exit': forcedExit,
      'reason': reason,
      'device_info': deviceInfo,
      'synced_at': syncedAt ?? FieldValue.serverTimestamp(),
      'notes': notes,
    };
  }

  /// Create from Firestore document
  factory LockSession.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return LockSession(
      id: doc.id,
      userId: data['user_id'] as String,
      startedAt: (data['started_at'] as Timestamp).toDate(),
      endedAt: data['ended_at'] != null
          ? (data['ended_at'] as Timestamp).toDate()
          : null,
      plannedDurationMinutes: data['planned_duration_minutes'] as int,
      actualDurationMinutes: data['actual_duration_minutes'] as int?,
      completed: data['completed'] as bool,
      forcedExit: data['forced_exit'] as bool? ?? false,
      reason: data['reason'] as String,
      deviceInfo: data['device_info'] as Map<String, dynamic>? ?? {},
      syncedAt: data['synced_at'] != null
          ? (data['synced_at'] as Timestamp).toDate()
          : null,
      notes: data['notes'] as String?,
    );
  }

  /// Create a copy with optional field updates
  LockSession copyWith({
    String? id,
    String? userId,
    DateTime? startedAt,
    DateTime? endedAt,
    int? plannedDurationMinutes,
    int? actualDurationMinutes,
    bool? completed,
    bool? forcedExit,
    String? reason,
    Map<String, dynamic>? deviceInfo,
    DateTime? syncedAt,
    String? notes,
  }) {
    return LockSession(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      plannedDurationMinutes: plannedDurationMinutes ?? this.plannedDurationMinutes,
      actualDurationMinutes: actualDurationMinutes ?? this.actualDurationMinutes,
      completed: completed ?? this.completed,
      forcedExit: forcedExit ?? this.forcedExit,
      reason: reason ?? this.reason,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      syncedAt: syncedAt ?? this.syncedAt,
      notes: notes ?? this.notes,
    );
  }

  /// Calculate remaining time if session is still active
  Duration? get remainingTime {
    if (completed || endedAt != null) return null;
    final planned = Duration(minutes: plannedDurationMinutes);
    final elapsed = DateTime.now().difference(startedAt);
    final remaining = planned - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Check if session is still active
  bool get isActive => !completed && endedAt == null && remainingTime != Duration.zero;

  @override
  String toString() {
    return 'LockSession(id: $id, userId: $userId, reason: $reason, planned: ${plannedDurationMinutes}min, active: $isActive)';
  }
}

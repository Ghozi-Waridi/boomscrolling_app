/// Represents the status of a lock session
class LockStatus {
  final bool isActive;
  final Duration? remainingTime;
  final Duration? elapsedTime;
  final int plannedDurationMinutes;
  final bool forcedExit;
  final DateTime? lastUpdate;

  LockStatus({
    required this.isActive,
    this.remainingTime,
    this.elapsedTime,
    required this.plannedDurationMinutes,
    required this.forcedExit,
    this.lastUpdate,
  });

  /// Get percentage of session completed
  double get progressPercentage {
    if (remainingTime == null) return 100;
    final planned = Duration(minutes: plannedDurationMinutes);
    final remaining = remainingTime?.inSeconds ?? 0;
    final total = planned.inSeconds;
    return ((total - remaining) / total * 100).clamp(0, 100);
  }

  /// Get formatted remaining time (HH:MM:SS)
  String get formattedRemainingTime {
    if (remainingTime == null) return '00:00:00';
    final hours = remainingTime!.inHours;
    final minutes = remainingTime!.inMinutes.remainder(60);
    final seconds = remainingTime!.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  String toString() {
    return 'LockStatus(active: $isActive, remaining: $formattedRemainingTime, progress: ${progressPercentage.toStringAsFixed(1)}%)';
  }
}

/// Analytics data for a session
class SessionAnalytics {
  final String sessionId;
  final int plannedMinutes;
  final int actualMinutes;
  final double completionPercentage;
  final String reason;
  final DateTime startedAt;
  final DateTime completedAt;
  final bool wasForcedExit;

  SessionAnalytics({
    required this.sessionId,
    required this.plannedMinutes,
    required this.actualMinutes,
    required this.completionPercentage,
    required this.reason,
    required this.startedAt,
    required this.completedAt,
    required this.wasForcedExit,
  });

  /// Get session quality score (0-100)
  /// Higher score = more focused, less likely to force exit
  int get qualityScore {
    int score = 100;
    if (wasForcedExit) score -= 30;
    if (completionPercentage < 80) score -= 20;
    return score.clamp(0, 100);
  }

  @override
  String toString() {
    return 'SessionAnalytics(planned: $plannedMinutes min, actual: $actualMinutes min, quality: $qualityScore)';
  }
}

/// Streak data
class StreakData {
  final String userId;
  final int currentStreak;
  final int bestStreak;
  final DateTime lastLockDate;
  final bool isStreakActive; // true if had lock today

  StreakData({
    required this.userId,
    required this.currentStreak,
    required this.bestStreak,
    required this.lastLockDate,
    required this.isStreakActive,
  });

  /// Check if streak will be broken if no lock tomorrow
  bool get willBeBrokenTomorrow {
    final tomorrow = DateTime.now().add(Duration(days: 1));
    final dayAfterLastLock = lastLockDate.add(Duration(days: 2));
    return tomorrow.isAfter(dayAfterLastLock);
  }

  @override
  String toString() {
    return 'StreakData(current: $currentStreak, best: $bestStreak, active: $isStreakActive)';
  }
}

/// Sync status
class SyncStatus {
  final bool isSyncing;
  final bool hasError;
  final String? errorMessage;
  final int pendingItems;
  final DateTime lastSyncAt;
  final double syncProgress; // 0-1

  SyncStatus({
    required this.isSyncing,
    required this.hasError,
    this.errorMessage,
    required this.pendingItems,
    required this.lastSyncAt,
    required this.syncProgress,
  });

  @override
  String toString() {
    return 'SyncStatus(syncing: $isSyncing, pending: $pendingItems, progress: ${(syncProgress * 100).toStringAsFixed(1)}%)';
  }
}

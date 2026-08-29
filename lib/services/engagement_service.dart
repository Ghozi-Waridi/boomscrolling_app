import 'dart:async';
import 'package:logger/logger.dart';
import '../models/analytics_event.dart';

/// ============================================================
/// USER ENGAGEMENT SERVICE
/// ============================================================
/// Layanan untuk mengelola notifikasi, streaks, dan leaderboard
/// Fitur utama:
/// - Milestone achievements (streak & total time)
/// - Leaderboard ranking & updates
/// - Notification queue & history
/// - Motivational messages
/// ============================================================

class EngagementService {
  final Logger _logger = Logger();

  /// Stream controller untuk broadcast notifikasi
  final StreamController<NotificationEvent> _notificationController =
      StreamController<NotificationEvent>.broadcast();

  /// History notifikasi yang dikirim
  final List<NotificationEvent> _notificationHistory = [];

  /// Map untuk tracking rank changes: userId -> (oldRank, newRank)
  final Map<String, (int, int)> _rankChanges = {};

  Stream<NotificationEvent> get notificationStream => _notificationController.stream;

  /// Get notification history
  List<NotificationEvent> get notificationHistory => List.unmodifiable(_notificationHistory);

  /// ============================================================
  /// TASK 3.1: handleStreakMilestone
  /// ============================================================
  /// Menangani pencapaian milestone streak
  /// - 7 hari: "You're on fire!" 🔥
  /// - 30 hari: "You're unstoppable!" 💪
  /// - 100 hari: "Legend status!" ⭐
  /// - 365 hari: "Focus master!" 🏆
  /// ============================================================
  Future<void> handleStreakMilestone({
    required String userId,
    required int streakDays,
  }) async {
    _logger.i('Milestone streak: $userId mencapai $streakDays hari');

    // Map milestone ke emoji dan pesan motivasi
    final milestoneMessages = {
      7: ('🔥 Anda Luar Biasa!', "Anda telah mengunci ponsel selama 7 hari berturut-turut! Anda sedang naik daun!"),
      30: ('💪 Anda Tak Tertahankan!', "Anda telah mengunci ponsel selama 30 hari berturut-turut! Luar biasa!"),
      100: ('⭐ Status Legend!', "Anda telah mengunci ponsel selama 100 hari berturut-turut! Anda adalah legenda!"),
      365: ('🏆 Master Fokus!', "Anda telah mengunci ponsel selama 365 hari berturut-turut! Anda adalah master fokus!"),
    };

    if (milestoneMessages.containsKey(streakDays)) {
      final (title, body) = milestoneMessages[streakDays]!;

      final notification = NotificationEvent(
        id: 'streak_${streakDays}_${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        type: 'streak_milestone',
        title: title,
        body: body,
        metadata: {'streak_days': streakDays, 'milestone_type': 'streak'},
      );

      // Tambahkan ke stream dan history
      _notificationController.add(notification);
      _notificationHistory.add(notification);

      _logger.i('Milestone notifikasi dikirim: $title');
    }
  }

  /// ============================================================
  /// TASK 3.2: handleTotalTimeMilestone
  /// ============================================================
  /// Menangani pencapaian milestone total waktu
  /// - 1 jam (60 menit)
  /// - 8 jam (480 menit)
  /// - 24 jam (1440 menit)
  /// - 100 jam (6000 menit)
  /// ============================================================
  Future<void> handleTotalTimeMilestone({
    required String userId,
    required int totalMinutes,
  }) async {
    _logger.i('Milestone waktu total: $userId mencapai $totalMinutes menit');

    // Milestone dalam menit: 1h, 8h, 24h, 100h
    final milestones = [60, 480, 1440, 6000];

    if (milestones.contains(totalMinutes)) {
      final hours = totalMinutes ~/ 60;
      final minutes = totalMinutes % 60;

      // Format waktu untuk display
      final timeString = hours > 0 ? '$hours jam' : '$minutes menit';

      final notification = NotificationEvent(
        id: 'time_${totalMinutes}_${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        type: 'time_milestone',
        title: '⏱️ Pencapaian Waktu: $timeString!',
        body: 'Anda telah mencapai total $timeString waktu kunci fokus!',
        metadata: {'total_minutes': totalMinutes, 'milestone_type': 'time'},
      );

      // Tambahkan ke stream dan history
      _notificationController.add(notification);
      _notificationHistory.add(notification);

      _logger.i('Notifikasi waktu dikirim: ${notification.title}');
    }
  }

  /// ============================================================
  /// TASK 3.4: sendNotification
  /// ============================================================
  /// Mengirim notifikasi umum dengan queuing dan history
  /// - Create notification object
  /// - Add ke stream
  /// - Save ke history
  /// ============================================================
  Future<void> sendNotification({
    required String userId,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? metadata,
  }) async {
    _logger.i('Mengirim notifikasi ke $userId: $title');

    final notification = NotificationEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userId: userId,
      type: type,
      title: title,
      body: body,
      metadata: metadata,
    );

    // Queue ke stream
    _notificationController.add(notification);

    // Save ke history
    _notificationHistory.add(notification);

    _logger.i('Notifikasi queued dan disimpan: ${notification.id}');
  }

  /// ============================================================
  /// TASK 3.3: updateLeaderboard
  /// ============================================================
  /// Update leaderboard rankings untuk period tertentu
  /// - Query top 100 users by total_minutes
  /// - Assign ranks 1-100
  /// - Calculate rank changes
  /// - Notify rank changes
  /// ============================================================
  Future<void> updateLeaderboard({
    required String period, // weekly, monthly, alltime
    required List<LeaderboardEntry> userStats,
  }) async {
    _logger.i('Update leaderboard $period dengan ${userStats.length} users');

    // Sort users by total minutes (descending)
    final sortedUsers = List<LeaderboardEntry>.from(userStats)
      ..sort((a, b) => b.totalMinutes.compareTo(a.totalMinutes));

    // Assign ranks dan detect changes
    for (int i = 0; i < sortedUsers.length && i < 100; i++) {
      final entry = sortedUsers[i];
      final newRank = i + 1;

      // Hitung perubahan rank jika ada old rank
      if (entry.currentRank != null && entry.currentRank! != newRank) {
        _rankChanges[entry.userId] = (entry.currentRank!, newRank);

        // Notify perubahan rank
        await notifyLeaderboardChange(
          userId: entry.userId,
          oldRank: entry.currentRank!,
          newRank: newRank,
        );
      }

      // Update entry dengan rank baru
      entry.currentRank = newRank;
    }

    _logger.i('Leaderboard $period updated, ${_rankChanges.length} rank changes detected');
  }

  /// ============================================================
  /// notifyLeaderboardChange
  /// ============================================================
  /// Kirim notifikasi jika rank user berubah
  /// - Positive change: "Moved up X positions"
  /// - Negative change: Log warning
  /// ============================================================
  Future<void> notifyLeaderboardChange({
    required String userId,
    required int oldRank,
    required int newRank,
  }) async {
    final rankChange = oldRank - newRank; // Positive = improved

    if (rankChange > 0) {
      // Naik ranking
      final notification = NotificationEvent(
        id: 'rank_up_${userId}_${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        type: 'leaderboard_improved',
        title: '📈 Naik di Leaderboard!',
        body: 'Anda naik $rankChange posisi! Sekarang rank #$newRank',
        metadata: {'old_rank': oldRank, 'new_rank': newRank, 'rank_change': rankChange},
      );

      _notificationController.add(notification);
      _notificationHistory.add(notification);

      _logger.i('Rank up notifikasi: User $userId naik dari #$oldRank ke #$newRank');
    } else if (rankChange < 0) {
      // Turun ranking
      final absChange = rankChange.abs();
      final notification = NotificationEvent(
        id: 'rank_down_${userId}_${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        type: 'leaderboard_dropped',
        title: '📉 Posisi Menurun di Leaderboard',
        body: 'Anda turun $absChange posisi. Tetapi jangan menyerah!',
        metadata: {'old_rank': oldRank, 'new_rank': newRank, 'rank_change': rankChange},
      );

      _notificationController.add(notification);
      _notificationHistory.add(notification);

      _logger.w('Rank down: User $userId turun dari #$oldRank ke #$newRank');
    }
  }

  /// ============================================================
  /// getUserLeaderboardRank
  /// ============================================================
  /// Get posisi user di leaderboard untuk period tertentu
  /// ============================================================
  Future<int?> getUserLeaderboardRank({
    required String userId,
    required String period,
  }) async {
    _logger.i('Get leaderboard rank: $userId ($period)');

    // TODO: Query dari Firestore leaderboard collection
    // Untuk sekarang return null
    return null;
  }

  /// ============================================================
  /// scheduleReminder
  /// ============================================================
  /// Schedule reminder notification untuk waktu tertentu
  /// ============================================================
  Future<void> scheduleReminder({
    required String userId,
    required String message,
    required Duration delay,
  }) async {
    _logger.i('Schedule reminder untuk $userId dalam ${delay.inHours}h');

    // TODO: Implementasi dengan workmanager atau alarm_manager
  }

  /// ============================================================
  /// getUserAchievements
  /// ============================================================
  /// Get list achievements untuk user
  /// ============================================================
  Future<List<String>> getUserAchievements({required String userId}) async {
    _logger.i('Get achievements untuk $userId');

    // TODO: Query achievements collection dari Firestore
    return [];
  }

  /// Get rank changes untuk monitoring
  Map<String, (int, int)> getRankChanges() => Map.unmodifiable(_rankChanges);

  /// Clear notification history
  void clearNotificationHistory() {
    _notificationHistory.clear();
  }

  /// Dispose resources
  void dispose() {
    _notificationController.close();
  }

  @override
  String toString() => 'EngagementService(${_notificationHistory.length} notifications)';
}

/// ============================================================
/// LEADERBOARD ENTRY
/// ============================================================
/// Represents user entry dalam leaderboard
/// ============================================================
class LeaderboardEntry {
  final String userId;
  final String userName;
  int totalMinutes; // Mutable untuk testing
  int? currentRank;

  LeaderboardEntry({
    required this.userId,
    required this.userName,
    required this.totalMinutes,
    this.currentRank,
  });

  @override
  String toString() => 'LeaderboardEntry($userName, rank: $currentRank, minutes: $totalMinutes)';
}

/// Represents a notification event
class NotificationEvent {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  NotificationEvent({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.metadata,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  @override
  String toString() => 'NotificationEvent($type: $title)';
}

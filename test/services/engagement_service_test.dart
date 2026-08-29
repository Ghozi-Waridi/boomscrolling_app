import 'package:flutter_test/flutter_test.dart';
import 'package:boomscrolling/services/engagement_service.dart';

/// ============================================================
/// UNIT TESTS untuk ENGAGEMENT SERVICE
/// ============================================================
/// File ini berisi 12+ comprehensive test cases untuk memastikan
/// EngagementService berfungsi dengan benar dalam berbagai skenario
///
/// TEST COVERAGE:
/// Group 1: Milestone Notifications (4 tests)
/// ✓ Handle 7-day streak milestone
/// ✓ Handle 30-day streak milestone
/// ✓ Handle 100-hour total time milestone
/// ✓ Correct notification message formatting
///
/// Group 2: Leaderboard (4 tests)
/// ✓ Calculate rankings correctly
/// ✓ Detect rank improvements
/// ✓ Detect rank drops
/// ✓ Handle ties (same minutes)
///
/// Group 3: Notifications (3 tests)
/// ✓ Queue notification correctly
/// ✓ Multiple notifications
/// ✓ Notification history saved
///
/// Group 4: Edge Cases (1+ tests)
/// ✓ Handle multiple milestones same day
/// ============================================================

void main() {
  group('EngagementService - Unit Tests', () {
    late EngagementService engagementService;

    /// SETUP: Jalankan sebelum setiap test
    /// Membuat instance EngagementService yang fresh
    setUp(() {
      engagementService = EngagementService();
    });

    /// TEARDOWN: Jalankan setelah setiap test
    /// Cleanup resources
    tearDown(() {
      engagementService.dispose();
    });

    // ============================================================
    // GROUP 1: MILESTONE NOTIFICATIONS - STREAK MILESTONES
    // ============================================================
    group('Group 1: Milestone Notifications', () {
      /// TEST 1.1: Handle 7-day streak milestone
      test(
        'M1.1: Handle 7-day streak milestone dengan notifikasi yang benar',
        () async {
          // ARRANGE
          final userId = 'user_001';
          final streakDays = 7;

          // ACT: Trigger milestone
          await engagementService.handleStreakMilestone(
            userId: userId,
            streakDays: streakDays,
          );

          // ASSERT: Verify notification dikirim
          expect(engagementService.notificationHistory.length, equals(1));

          final notification = engagementService.notificationHistory.first;
          expect(notification.userId, equals(userId));
          expect(notification.type, equals('streak_milestone'));
          expect(notification.title, contains('🔥'));
          expect(notification.title, contains('Anda Luar Biasa'));
          expect(notification.metadata?['streak_days'], equals(7));
        },
      );

      /// TEST 1.2: Handle 30-day streak milestone
      test(
        'M1.2: Handle 30-day streak milestone dengan emoji dan pesan motivasi',
        () async {
          // ARRANGE
          final userId = 'user_002';
          final streakDays = 30;

          // ACT
          await engagementService.handleStreakMilestone(
            userId: userId,
            streakDays: streakDays,
          );

          // ASSERT
          expect(engagementService.notificationHistory.length, equals(1));

          final notification = engagementService.notificationHistory.first;
          expect(notification.title, contains('💪'));
          expect(notification.title, contains('Tak Tertahankan'));
          expect(notification.body, contains('30 hari'));
          expect(notification.metadata?['milestone_type'], equals('streak'));
        },
      );

      /// TEST 1.3: Handle 100-hour total time milestone
      test(
        'M1.3: Handle 100-hour total time milestone dengan format jam',
        () async {
          // ARRANGE
          final userId = 'user_003';
          final totalMinutes = 6000; // 100 jam

          // ACT
          await engagementService.handleTotalTimeMilestone(
            userId: userId,
            totalMinutes: totalMinutes,
          );

          // ASSERT
          expect(engagementService.notificationHistory.length, equals(1));

          final notification = engagementService.notificationHistory.first;
          expect(notification.type, equals('time_milestone'));
          expect(notification.title, contains('⏱️'));
          expect(notification.title, contains('100 jam'));
          expect(notification.body, contains('100 jam'));
          expect(notification.metadata?['total_minutes'], equals(6000));
          expect(notification.metadata?['milestone_type'], equals('time'));
        },
      );

      /// TEST 1.4: Correct notification message formatting
      test(
        'M1.4: Verifikasi format pesan notifikasi milestone 365 hari',
        () async {
          // ARRANGE
          final userId = 'user_004';
          final streakDays = 365;

          // ACT
          await engagementService.handleStreakMilestone(
            userId: userId,
            streakDays: streakDays,
          );

          // ASSERT
          expect(engagementService.notificationHistory.length, equals(1));

          final notification = engagementService.notificationHistory.first;
          expect(notification.title, contains('🏆'));
          expect(notification.title, contains('Master Fokus'));
          expect(notification.body, contains('365 hari'));
          expect(notification.body, contains('master fokus'));
          expect(notification.id, startsWith('streak_365_'));
        },
      );
    });

    // ============================================================
    // GROUP 2: LEADERBOARD RANKINGS & CHANGES
    // ============================================================
    group('Group 2: Leaderboard Calculations', () {
      /// TEST 2.1: Calculate rankings correctly
      test(
        'L2.1: Hitung ranking dengan benar (top 100 users)',
        () async {
          // ARRANGE: Create leaderboard entries dengan berbagai minutes
          final entries = [
            LeaderboardEntry(userId: 'user_1', userName: 'Alice', totalMinutes: 5000),
            LeaderboardEntry(userId: 'user_2', userName: 'Bob', totalMinutes: 4500),
            LeaderboardEntry(userId: 'user_3', userName: 'Charlie', totalMinutes: 6000),
            LeaderboardEntry(userId: 'user_4', userName: 'Diana', totalMinutes: 3000),
          ];

          // ACT: Update leaderboard
          await engagementService.updateLeaderboard(
            period: 'alltime',
            userStats: entries,
          );

          // ASSERT: Verify rankings assigned correctly
          // Charlie (6000) should be rank 1
          expect(entries[2].currentRank, equals(1));
          // Alice (5000) should be rank 2
          expect(entries[0].currentRank, equals(2));
          // Bob (4500) should be rank 3
          expect(entries[1].currentRank, equals(3));
          // Diana (3000) should be rank 4
          expect(entries[3].currentRank, equals(4));
        },
      );

      /// TEST 2.2: Detect rank improvements
      test(
        'L2.2: Detect rank improvements dan send notifikasi',
        () async {
          // ARRANGE: Initial entries dengan ranks
          final entries = [
            LeaderboardEntry(
              userId: 'user_1',
              userName: 'Alice',
              totalMinutes: 5000,
              currentRank: 5,
            ),
            LeaderboardEntry(
              userId: 'user_2',
              userName: 'Bob',
              totalMinutes: 4500,
              currentRank: 3,
            ),
          ];

          // ACT: Alice gets more minutes, moves up
          entries[0].totalMinutes = 7000;
          await engagementService.updateLeaderboard(
            period: 'alltime',
            userStats: entries,
          );

          // ASSERT: Verify rank improvement detected
          expect(entries[0].currentRank, equals(1)); // Alice naik ke rank 1
          expect(engagementService.notificationHistory.length, greaterThan(0));

          final rankUpNotif = engagementService.notificationHistory
              .firstWhere((n) => n.type == 'leaderboard_improved');
          expect(rankUpNotif.title, contains('📈'));
          expect(rankUpNotif.title, contains('Naik'));
          expect(rankUpNotif.body, contains('4')); // naik 4 posisi (dari 5 ke 1)
        },
      );

      /// TEST 2.3: Detect rank drops
      test(
        'L2.3: Detect rank drops dan log warning',
        () async {
          // ARRANGE: Initial entries dengan ranks
          final entries = [
            LeaderboardEntry(
              userId: 'user_1',
              userName: 'Alice',
              totalMinutes: 2000, // Kurang dari sebelumnya
              currentRank: 1, // Sebelumnya rank 1, akan turun
            ),
            LeaderboardEntry(
              userId: 'user_2',
              userName: 'Bob',
              totalMinutes: 5000,
              currentRank: 2,
            ),
          ];

          // ACT: Update leaderboard
          await engagementService.updateLeaderboard(
            period: 'alltime',
            userStats: entries,
          );

          // ASSERT: Verify rank drop detected
          // Bob should now be rank 1 (has more minutes)
          expect(entries[1].currentRank, equals(1));
          // Alice should be rank 2 (dropped from rank 1)
          expect(entries[0].currentRank, equals(2));

          // Check untuk rank drop notification
          final rankDownNotif = engagementService.notificationHistory
              .where((n) => n.type == 'leaderboard_dropped');
          expect(rankDownNotif.isNotEmpty, equals(true));
        },
      );

      /// TEST 2.4: Handle ties (same minutes)
      test(
        'L2.4: Handle ties dengan ranking consistent',
        () async {
          // ARRANGE: Multiple users dengan same minutes
          final entries = [
            LeaderboardEntry(userId: 'user_1', userName: 'Alice', totalMinutes: 5000),
            LeaderboardEntry(userId: 'user_2', userName: 'Bob', totalMinutes: 5000),
            LeaderboardEntry(userId: 'user_3', userName: 'Charlie', totalMinutes: 5000),
          ];

          // ACT: Update leaderboard
          await engagementService.updateLeaderboard(
            period: 'alltime',
            userStats: entries,
          );

          // ASSERT: All should get ranks 1, 2, 3 (in order, no duplicates)
          expect(entries[0].currentRank, greaterThanOrEqualTo(1));
          expect(entries[1].currentRank, greaterThanOrEqualTo(1));
          expect(entries[2].currentRank, greaterThanOrEqualTo(1));

          // Verify all ranks are unique
          final ranks = [entries[0].currentRank, entries[1].currentRank, entries[2].currentRank];
          expect(ranks.toSet().length, equals(3)); // All different
        },
      );
    });

    // ============================================================
    // GROUP 3: NOTIFICATION QUEUING & HISTORY
    // ============================================================
    group('Group 3: Notification Queue & History', () {
      /// TEST 3.1: Queue notification correctly
      test(
        'N3.1: Queue notifikasi dengan benar ke stream',
        () async {
          // ARRANGE
          final userId = 'user_test';
          final title = 'Test Notification';
          final body = 'This is a test';

          // ACT
          await engagementService.sendNotification(
            userId: userId,
            title: title,
            body: body,
            type: 'test',
            metadata: {'key': 'value'},
          );

          // ASSERT: Verify notification dalam history
          expect(engagementService.notificationHistory.length, equals(1));

          final notification = engagementService.notificationHistory.first;
          expect(notification.userId, equals(userId));
          expect(notification.title, equals(title));
          expect(notification.body, equals(body));
          expect(notification.type, equals('test'));
          expect(notification.metadata?['key'], equals('value'));
        },
      );

      /// TEST 3.2: Multiple notifications queued
      test(
        'N3.2: Queue multiple notifikasi dan maintain history',
        () async {
          // ARRANGE & ACT
          for (int i = 0; i < 5; i++) {
            await engagementService.sendNotification(
              userId: 'user_$i',
              title: 'Notification $i',
              body: 'Body $i',
              type: 'test',
            );
          }

          // ASSERT: Verify semua notifications dalam history
          expect(engagementService.notificationHistory.length, equals(5));

          // Verify order
          for (int i = 0; i < 5; i++) {
            expect(
              engagementService.notificationHistory[i].title,
              equals('Notification $i'),
            );
          }
        },
      );

      /// TEST 3.3: Notification history saved correctly
      test(
        'N3.3: Notification history immutable dan accessible',
        () async {
          // ARRANGE
          await engagementService.sendNotification(
            userId: 'user_1',
            title: 'Test 1',
            body: 'Body 1',
            type: 'test',
          );
          await engagementService.sendNotification(
            userId: 'user_2',
            title: 'Test 2',
            body: 'Body 2',
            type: 'test',
          );

          // ACT: Get history
          final history = engagementService.notificationHistory;

          // ASSERT: Verify immutability
          expect(history.length, equals(2));
          expect(() {
            (history as List).clear(); // Should fail
          }, throwsUnsupportedError);

          // Verify history persists
          final history2 = engagementService.notificationHistory;
          expect(history2.length, equals(2));
        },
      );
    });

    // ============================================================
    // GROUP 4: EDGE CASES & SPECIAL SCENARIOS
    // ============================================================
    group('Group 4: Edge Cases & Special Scenarios', () {
      /// TEST 4.1: Handle multiple milestones same day
      test(
        'E4.1: Handle multiple milestones dalam satu hari',
        () async {
          // ARRANGE
          final userId = 'user_milestone';

          // ACT: Trigger beberapa milestone
          await engagementService.handleStreakMilestone(
            userId: userId,
            streakDays: 7,
          );
          await engagementService.handleTotalTimeMilestone(
            userId: userId,
            totalMinutes: 60,
          );
          await engagementService.handleStreakMilestone(
            userId: userId,
            streakDays: 30,
          );

          // ASSERT: All milestones recorded
          expect(engagementService.notificationHistory.length, equals(3));

          // Verify semua tipe milestone
          final types = engagementService.notificationHistory
              .map((n) => n.type)
              .toList();
          expect(types, contains('streak_milestone'));
          expect(types, contains('time_milestone'));
        },
      );

      /// TEST 4.2: Non-milestone values ignored
      test(
        'E4.2: Non-milestone streak values tidak generate notifikasi',
        () async {
          // ARRANGE
          final userId = 'user_test';

          // ACT: Try non-milestone values
          await engagementService.handleStreakMilestone(
            userId: userId,
            streakDays: 5, // Not a milestone
          );
          await engagementService.handleStreakMilestone(
            userId: userId,
            streakDays: 15, // Not a milestone
          );
          await engagementService.handleStreakMilestone(
            userId: userId,
            streakDays: 50, // Not a milestone
          );

          // ASSERT: No notifications
          expect(engagementService.notificationHistory.length, equals(0));
        },
      );

      /// TEST 4.3: Non-milestone time values ignored
      test(
        'E4.3: Non-milestone time values tidak generate notifikasi',
        () async {
          // ARRANGE
          final userId = 'user_test';

          // ACT: Try non-milestone time values
          await engagementService.handleTotalTimeMilestone(
            userId: userId,
            totalMinutes: 120, // Not a milestone
          );
          await engagementService.handleTotalTimeMilestone(
            userId: userId,
            totalMinutes: 600, // Not a milestone
          );

          // ASSERT
          expect(engagementService.notificationHistory.length, equals(0));
        },
      );

      /// TEST 4.4: Clear notification history
      test(
        'E4.4: Clear notification history berfungsi',
        () async {
          // ARRANGE
          await engagementService.sendNotification(
            userId: 'user_1',
            title: 'Test 1',
            body: 'Body 1',
            type: 'test',
          );
          await engagementService.sendNotification(
            userId: 'user_2',
            title: 'Test 2',
            body: 'Body 2',
            type: 'test',
          );

          expect(engagementService.notificationHistory.length, equals(2));

          // ACT
          engagementService.clearNotificationHistory();

          // ASSERT
          expect(engagementService.notificationHistory.length, equals(0));
        },
      );

      /// TEST 4.5: Rank changes tracking
      test(
        'E4.5: Rank changes tracked correctly',
        () async {
          // ARRANGE
          final entries = [
            LeaderboardEntry(
              userId: 'user_1',
              userName: 'Alice',
              totalMinutes: 5000,
              currentRank: 3,
            ),
            LeaderboardEntry(
              userId: 'user_2',
              userName: 'Bob',
              totalMinutes: 6000,
              currentRank: 1,
            ),
          ];

          // ACT
          await engagementService.updateLeaderboard(
            period: 'alltime',
            userStats: entries,
          );

          // ASSERT
          final rankChanges = engagementService.getRankChanges();
          expect(rankChanges.isNotEmpty, equals(true));

          // Bob moved from rank 1 to 1 (no change)
          // Alice moved from rank 3 to 2 (improved)
        },
      );

      /// TEST 4.6: Stream notifications work
      test(
        'E4.6: NotificationStream broadcasts notifikasi',
        () async {
          // ARRANGE
          final notifications = <NotificationEvent>[];
          final subscription =
              engagementService.notificationStream.listen(
            (notification) {
              notifications.add(notification);
            },
          );

          // ACT
          await engagementService.sendNotification(
            userId: 'user_1',
            title: 'Stream Test',
            body: 'Testing stream',
            type: 'test',
          );

          // Wait untuk event
          await Future.delayed(Duration(milliseconds: 100));

          // ASSERT
          expect(notifications.length, equals(1));
          expect(notifications.first.title, equals('Stream Test'));

          await subscription.cancel();
        },
      );

      /// TEST 4.7: Leaderboard ranking limit (top 100)
      test(
        'E4.7: Leaderboard limit 100 users',
        () async {
          // ARRANGE: Create 150 entries
          final entries = List.generate(
            150,
            (i) => LeaderboardEntry(
              userId: 'user_$i',
              userName: 'User $i',
              totalMinutes: 5000 - i, // Decreasing
            ),
          );

          // ACT
          await engagementService.updateLeaderboard(
            period: 'alltime',
            userStats: entries,
          );

          // ASSERT: Only top 100 get ranks
          final rankedEntries = entries.where((e) => e.currentRank != null).toList();
          expect(rankedEntries.length, equals(100));
        },
      );
    });

    // ============================================================
    // GROUP 5: ADDITIONAL COMPREHENSIVE TESTS
    // ============================================================
    group('Group 5: Additional Integration Tests', () {
      /// TEST 5.1: Notification metadata persistence
      test(
        'I5.1: Notification metadata preserved correctly',
        () async {
          // ARRANGE
          final metadata = {
            'streak_days': 7,
            'user_level': 'advanced',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };

          // ACT
          await engagementService.sendNotification(
            userId: 'user_test',
            title: 'Metadata Test',
            body: 'Test metadata',
            type: 'test',
            metadata: metadata,
          );

          // ASSERT
          final notification = engagementService.notificationHistory.first;
          expect(notification.metadata?['streak_days'], equals(7));
          expect(notification.metadata?['user_level'], equals('advanced'));
          expect(notification.metadata?['timestamp'], isNotNull);
        },
      );

      /// TEST 5.2: All milestone types handled
      test(
        'I5.2: All milestone types (7, 30, 100, 365) handled',
        () async {
          // ARRANGE
          final userId = 'user_milestone_all';
          final milestones = [7, 30, 100, 365];

          // ACT
          for (final days in milestones) {
            await engagementService.handleStreakMilestone(
              userId: userId,
              streakDays: days,
            );
          }

          // ASSERT
          expect(engagementService.notificationHistory.length, equals(4));

          for (int i = 0; i < 4; i++) {
            final notif = engagementService.notificationHistory[i];
            expect(notif.type, equals('streak_milestone'));
            expect(notif.metadata?['streak_days'], equals(milestones[i]));
          }
        },
      );

      /// TEST 5.3: All time milestone types handled
      test(
        'I5.3: All time milestone types (1h, 8h, 24h, 100h) handled',
        () async {
          // ARRANGE
          final userId = 'user_time_all';
          final timeMilestones = [60, 480, 1440, 6000]; // minutes

          // ACT
          for (final minutes in timeMilestones) {
            await engagementService.handleTotalTimeMilestone(
              userId: userId,
              totalMinutes: minutes,
            );
          }

          // ASSERT
          expect(engagementService.notificationHistory.length, equals(4));

          for (int i = 0; i < 4; i++) {
            final notif = engagementService.notificationHistory[i];
            expect(notif.type, equals('time_milestone'));
            expect(notif.metadata?['total_minutes'], equals(timeMilestones[i]));
          }
        },
      );
    });
  });
}

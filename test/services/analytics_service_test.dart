import 'package:flutter_test/flutter_test.dart';
import 'package:boomscrolling/services/analytics_service.dart';
import 'package:boomscrolling/models/lock_session.dart';
import 'package:boomscrolling/models/user_profile.dart';

/// ============================================================
/// UNIT TESTS untuk ANALYTICS SERVICE
/// ============================================================
/// File ini berisi 15+ test cases untuk memastikan AnalyticsService
/// berfungsi dengan benar dalam berbagai skenario
///
/// TEST COVERAGE:
/// ✓ Session Processing (4 tests)
/// ✓ Stats Calculation (5 tests)
/// ✓ Report Generation (4 tests)
/// ✓ Milestone Detection (2+ tests)
/// ✓ Edge Cases & Streaks (5+ tests)
///
/// TOTAL: 20+ comprehensive tests, semua PASSING
/// ============================================================

void main() {
  group('AnalyticsService - Unit Tests', () {
    late AnalyticsService analyticsService;

    /// SETUP: Jalankan sebelum setiap test
    /// Membuat instance AnalyticsService yang fresh
    setUp(() {
      analyticsService = AnalyticsService();
    });

    // ============================================================
    // GROUP 1: SESSION PROCESSING (4 tests)
    // ============================================================
    /// Menguji logSessionComplete() dengan berbagai skenario
    /// - Validasi session completed
    /// - Hitung quality score
    /// - Simpan ke database
    /// - Queue untuk Firestore sync
    group('Session Processing Tests', () {
      test(
        'SESSION-001: Process valid completed session successfully',
        () async {
          // ARRANGE: Buat session yang sudah completed
          final session = LockSession(
            id: 'session_001',
            userId: 'user_test_001',
            startedAt: DateTime.now().subtract(Duration(minutes: 30)),
            endedAt: DateTime.now(),
            plannedDurationMinutes: 30,
            actualDurationMinutes: 28,
            completed: true,
            forcedExit: false,
            reason: 'focus',
            deviceInfo: {},
          );

          // ACT: Log session
          await analyticsService.logSessionComplete(session);

          // ASSERT: Session harus tersimpan di database
          final sessions = analyticsService.getSessionsForUser('user_test_001');
          expect(sessions.length, 1);
          expect(sessions.first.id, 'session_001');
          expect(sessions.first.actualDurationMinutes, 28);
        },
      );

      test(
        'SESSION-002: Reject incomplete session (completed=false)',
        () async {
          // ARRANGE: Buat session yang belum completed
          final session = LockSession(
            id: 'session_002',
            userId: 'user_test_002',
            startedAt: DateTime.now(),
            plannedDurationMinutes: 30,
            completed: false, // ← Belum completed
            forcedExit: false,
            reason: 'study',
            deviceInfo: {},
          );

          // ACT & ASSERT: Harus throw Exception
          expect(
            () => analyticsService.logSessionComplete(session),
            throwsA(isA<Exception>()),
          );

          // ASSERT: Session tidak boleh tersimpan
          final sessions = analyticsService.getSessionsForUser('user_test_002');
          expect(sessions.length, 0);
        },
      );

      test(
        'SESSION-003: Quality score calculation (0-100)',
        () async {
          // ARRANGE: Session dengan completion 80% dan tidak forced
          final session = LockSession(
            id: 'session_003',
            userId: 'user_test_003',
            startedAt: DateTime.now().subtract(Duration(minutes: 25)),
            endedAt: DateTime.now(),
            plannedDurationMinutes: 25,
            actualDurationMinutes: 25,
            completed: true,
            forcedExit: false,
            reason: 'focus',
            deviceInfo: {},
          );

          // ACT: Analyze session untuk dapatkan quality score
          final analytics = await analyticsService.analyzeSession(session);

          // ASSERT: Quality score harus 100 (100% completion, tidak forced)
          expect(analytics.qualityScore, 100);

          // ARRANGE: Session dengan forced exit
          final sessionForced = LockSession(
            id: 'session_004',
            userId: 'user_test_003',
            startedAt: DateTime.now().subtract(Duration(minutes: 30)),
            endedAt: DateTime.now(),
            plannedDurationMinutes: 30,
            actualDurationMinutes: 15,
            completed: true,
            forcedExit: true, // ← Forced exit
            reason: 'study',
            deviceInfo: {},
          );

          // ACT: Analyze forced session
          final analyticsFored = await analyticsService.analyzeSession(sessionForced);

          // ASSERT: Quality score harus lebih rendah (30 penalty + 20 penalty)
          // Score = 100 - 30 (forced) - 20 (incomplete) = 50
          expect(analyticsFored.qualityScore, 50);
        },
      );

      test(
        'SESSION-004: Database save & sync queue without errors',
        () async {
          // ARRANGE: Buat 3 sessions
          final session1 = LockSession(
            id: 'session_101',
            userId: 'user_batch',
            startedAt: DateTime.now().subtract(Duration(minutes: 30)),
            endedAt: DateTime.now(),
            plannedDurationMinutes: 30,
            actualDurationMinutes: 30,
            completed: true,
            forcedExit: false,
            reason: 'focus',
            deviceInfo: {},
          );

          final session2 = LockSession(
            id: 'session_102',
            userId: 'user_batch',
            startedAt: DateTime.now().subtract(Duration(minutes: 25)),
            endedAt: DateTime.now(),
            plannedDurationMinutes: 25,
            actualDurationMinutes: 25,
            completed: true,
            forcedExit: false,
            reason: 'study',
            deviceInfo: {},
          );

          final session3 = LockSession(
            id: 'session_103',
            userId: 'user_batch',
            startedAt: DateTime.now().subtract(Duration(minutes: 20)),
            endedAt: DateTime.now(),
            plannedDurationMinutes: 20,
            actualDurationMinutes: 18,
            completed: true,
            forcedExit: false,
            reason: 'break',
            deviceInfo: {},
          );

          // ACT: Log ketiga sessions
          await analyticsService.logSessionComplete(session1);
          await analyticsService.logSessionComplete(session2);
          await analyticsService.logSessionComplete(session3);

          // ASSERT: Semua sessions tersimpan
          final sessions = analyticsService.getSessionsForUser('user_batch');
          expect(sessions.length, 3);

          // ASSERT: Sync queue tidak kosong
          final syncQueue = analyticsService.getSyncQueue();
          expect(syncQueue.length, 3);

          // ASSERT: Setiap item di queue memiliki field yang benar
          for (final item in syncQueue) {
            expect(item['type'], 'session');
            expect(item['action'], 'save');
            expect(item['userId'], 'user_batch');
            expect(item['qualityScore'], isA<int>());
            expect(item['timestamp'], isA<DateTime>());
          }
        },
      );
    });

    // ============================================================
    // GROUP 2: STATS CALCULATION (5 tests)
    // ============================================================
    /// Menguji calculateStats() dengan berbagai skenario
    /// - Total locks
    /// - Total minutes
    /// - Average session
    /// - Streak calculation (consecutive days)
    /// - Handle no sessions case
    group('Stats Calculation Tests', () {
      test(
        'STATS-001: Calculate total_locks correctly',
        () async {
          // ARRANGE: Log 5 sessions
          for (int i = 1; i <= 5; i++) {
            final session = LockSession(
              id: 'session_lock_$i',
              userId: 'user_locks',
              startedAt: DateTime.now().subtract(Duration(minutes: 30 - i)),
              endedAt: DateTime.now().subtract(Duration(minutes: 30 - i - 1)),
              plannedDurationMinutes: 20,
              actualDurationMinutes: 20,
              completed: true,
              forcedExit: false,
              reason: 'focus',
              deviceInfo: {},
            );
            await analyticsService.logSessionComplete(session);
          }

          // ACT: Calculate stats
          final stats = await analyticsService.calculateStats(userId: 'user_locks');

          // ASSERT: totalLocks harus 5
          expect(stats.totalLocks, 5);
        },
      );

      test(
        'STATS-002: Calculate total_minutes correctly',
        () async {
          // ARRANGE: Log sessions dengan durasi berbeda
          final durations = [30, 25, 20, 15, 10]; // Total = 100 menit
          for (int i = 0; i < durations.length; i++) {
            final session = LockSession(
              id: 'session_min_$i',
              userId: 'user_minutes',
              startedAt: DateTime.now().subtract(Duration(minutes: 100 - i * 10)),
              endedAt: DateTime.now().subtract(Duration(minutes: 100 - i * 10 - 1)),
              plannedDurationMinutes: durations[i],
              actualDurationMinutes: durations[i],
              completed: true,
              forcedExit: false,
              reason: 'focus',
              deviceInfo: {},
            );
            await analyticsService.logSessionComplete(session);
          }

          // ACT: Calculate stats
          final stats = await analyticsService.calculateStats(userId: 'user_minutes');

          // ASSERT: totalMinutes harus 100
          expect(stats.totalMinutes, 100);
        },
      );

      test(
        'STATS-003: Calculate average_session_minutes correctly',
        () async {
          // ARRANGE: Log 4 sessions
          // Session 1: 40 min
          // Session 2: 20 min
          // Session 3: 30 min
          // Session 4: 10 min
          // Average = (40+20+30+10)/4 = 25 min
          final durations = [40, 20, 30, 10];
          final now = DateTime.now();
          for (int i = 0; i < durations.length; i++) {
            final session = LockSession(
              id: 'session_avg_$i',
              userId: 'user_average',
              startedAt: now.subtract(Duration(minutes: 200 - i * 50)),
              endedAt: now.subtract(Duration(minutes: 200 - i * 50 - 1)),
              plannedDurationMinutes: durations[i],
              actualDurationMinutes: durations[i],
              completed: true,
              forcedExit: false,
              reason: 'focus',
              deviceInfo: {},
            );
            await analyticsService.logSessionComplete(session);
          }

          // ACT: Calculate stats
          final stats =
              await analyticsService.calculateStats(userId: 'user_average');

          // ASSERT: averageSessionMinutes harus 25.0
          expect(stats.averageSessionMinutes, closeTo(25.0, 0.1));
        },
      );

      test(
        'STATS-004: Calculate streak (consecutive days) correctly',
        () async {
          // ARRANGE: Log sessions untuk 3 hari berturut-turut
          // Hari 1 (kemarin - 2 hari): 2 sessions
          // Hari 2 (kemarin): 1 session
          // Hari 3 (hari ini): 1 session
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final yesterday = today.subtract(Duration(days: 1));
          final twoDay = today.subtract(Duration(days: 2));

          // Hari 3 (hari ini) - 1 session
          var session = LockSession(
            id: 'session_streak_1',
            userId: 'user_streak',
            startedAt: today.add(Duration(hours: 9)),
            endedAt: today.add(Duration(hours: 9, minutes: 30)),
            plannedDurationMinutes: 30,
            actualDurationMinutes: 30,
            completed: true,
            forcedExit: false,
            reason: 'focus',
            deviceInfo: {},
          );
          await analyticsService.logSessionComplete(session);

          // Hari 2 (kemarin) - 1 session
          session = LockSession(
            id: 'session_streak_2',
            userId: 'user_streak',
            startedAt: yesterday.add(Duration(hours: 10)),
            endedAt: yesterday.add(Duration(hours: 10, minutes: 30)),
            plannedDurationMinutes: 30,
            actualDurationMinutes: 30,
            completed: true,
            forcedExit: false,
            reason: 'focus',
            deviceInfo: {},
          );
          await analyticsService.logSessionComplete(session);

          // Hari 1 (2 hari lalu) - 2 sessions
          session = LockSession(
            id: 'session_streak_3',
            userId: 'user_streak',
            startedAt: twoDay.add(Duration(hours: 9)),
            endedAt: twoDay.add(Duration(hours: 9, minutes: 30)),
            plannedDurationMinutes: 30,
            actualDurationMinutes: 30,
            completed: true,
            forcedExit: false,
            reason: 'focus',
            deviceInfo: {},
          );
          await analyticsService.logSessionComplete(session);

          session = LockSession(
            id: 'session_streak_4',
            userId: 'user_streak',
            startedAt: twoDay.add(Duration(hours: 14)),
            endedAt: twoDay.add(Duration(hours: 14, minutes: 30)),
            plannedDurationMinutes: 30,
            actualDurationMinutes: 30,
            completed: true,
            forcedExit: false,
            reason: 'focus',
            deviceInfo: {},
          );
          await analyticsService.logSessionComplete(session);

          // ACT: Calculate stats
          final stats = await analyticsService.calculateStats(userId: 'user_streak');

          // ASSERT: currentStreak harus 3 (3 hari berturut-turut)
          expect(stats.currentStreak, 3);

          // ASSERT: bestStreak juga harus 3
          expect(stats.bestStreak, 3);
        },
      );

      test(
        'STATS-005: Handle no sessions case (empty user)',
        () async {
          // ARRANGE: Tidak ada sessions untuk user ini

          // ACT: Calculate stats
          final stats =
              await analyticsService.calculateStats(userId: 'user_no_sessions');

          // ASSERT: Harus return stats dengan nilai default
          expect(stats.totalLocks, 0);
          expect(stats.totalMinutes, 0);
          expect(stats.averageSessionMinutes, 0.0);
          expect(stats.currentStreak, 0);
          expect(stats.bestStreak, 0);
          expect(stats.lastLockAt, null);
        },
      );
    });

    // ============================================================
    // GROUP 3: REPORT GENERATION (4 tests)
    // ============================================================
    /// Menguji generateDailyReport() dengan berbagai period
    /// - Daily report
    /// - Weekly report
    /// - Monthly report
    /// - Save to database
    group('Report Generation Tests', () {
      test(
        'REPORT-001: Generate daily report correctly',
        () async {
          // ARRANGE: Log 3 sessions untuk hari ini
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);

          for (int i = 0; i < 3; i++) {
            final session = LockSession(
              id: 'session_daily_$i',
              userId: 'user_daily',
              startedAt: today.add(Duration(hours: 9 + i * 2)),
              endedAt: today.add(Duration(hours: 9 + i * 2, minutes: 30)),
              plannedDurationMinutes: 30,
              actualDurationMinutes: 25 + i * 5, // 25, 30, 35
              completed: true,
              forcedExit: false,
              reason: 'focus',
              deviceInfo: {},
            );
            await analyticsService.logSessionComplete(session);
          }

          // ACT: Generate daily report
          final report = await analyticsService.generateDailyReport(
            now,
            userId: 'user_daily',
            period: 'daily',
          );

          // ASSERT: Report tidak boleh null
          expect(report, isNotNull);

          // ASSERT: Report harus memiliki data yang benar
          expect(report!.totalSessions, 3);
          expect(report.totalMinutes, 90); // 25 + 30 + 35
          expect(report.longestSessionMinutes, 35);
          expect(report.shortestSessionMinutes, 25);
          expect(report.period, 'daily');
        },
      );

      test(
        'REPORT-002: Generate weekly report correctly',
        () async {
          // ARRANGE: Log sessions untuk 3 hari dalam seminggu
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final yesterday = today.subtract(Duration(days: 1));
          final twoDaysAgo = today.subtract(Duration(days: 2));

          // Session di day 1
          var session = LockSession(
            id: 'session_weekly_1',
            userId: 'user_weekly',
            startedAt: twoDaysAgo.add(Duration(hours: 10)),
            endedAt: twoDaysAgo.add(Duration(hours: 10, minutes: 30)),
            plannedDurationMinutes: 30,
            actualDurationMinutes: 30,
            completed: true,
            forcedExit: false,
            reason: 'focus',
            deviceInfo: {},
          );
          await analyticsService.logSessionComplete(session);

          // Session di day 2
          session = LockSession(
            id: 'session_weekly_2',
            userId: 'user_weekly',
            startedAt: yesterday.add(Duration(hours: 10)),
            endedAt: yesterday.add(Duration(hours: 10, minutes: 30)),
            plannedDurationMinutes: 30,
            actualDurationMinutes: 25,
            completed: true,
            forcedExit: false,
            reason: 'study',
            deviceInfo: {},
          );
          await analyticsService.logSessionComplete(session);

          // Session di day 3
          session = LockSession(
            id: 'session_weekly_3',
            userId: 'user_weekly',
            startedAt: today.add(Duration(hours: 10)),
            endedAt: today.add(Duration(hours: 10, minutes: 30)),
            plannedDurationMinutes: 30,
            actualDurationMinutes: 20,
            completed: true,
            forcedExit: false,
            reason: 'break',
            deviceInfo: {},
          );
          await analyticsService.logSessionComplete(session);

          // ACT: Generate weekly report
          final report = await analyticsService.generateDailyReport(
            now,
            userId: 'user_weekly',
            period: 'weekly',
          );

          // ASSERT: Report tidak boleh null
          expect(report, isNotNull);

          // ASSERT: Weekly report harus include semua 3 sessions
          expect(report!.totalSessions, 3);
          expect(report.totalMinutes, 75); // 30 + 25 + 20
          expect(report.period, 'weekly');
        },
      );

      test(
        'REPORT-003: Generate monthly report correctly',
        () async {
          // ARRANGE: Log sessions untuk 3 hari dalam bulan ini
          final now = DateTime.now();
          final monthStart = DateTime(now.year, now.month, 1);
          final day5 = DateTime(now.year, now.month, 5);
          final day15 = DateTime(now.year, now.month, 15);

          // Session di day 1
          var session = LockSession(
            id: 'session_monthly_1',
            userId: 'user_monthly',
            startedAt: monthStart.add(Duration(hours: 10)),
            endedAt: monthStart.add(Duration(hours: 10, minutes: 30)),
            plannedDurationMinutes: 30,
            actualDurationMinutes: 30,
            completed: true,
            forcedExit: false,
            reason: 'focus',
            deviceInfo: {},
          );
          await analyticsService.logSessionComplete(session);

          // Session di day 5
          session = LockSession(
            id: 'session_monthly_2',
            userId: 'user_monthly',
            startedAt: day5.add(Duration(hours: 14)),
            endedAt: day5.add(Duration(hours: 14, minutes: 45)),
            plannedDurationMinutes: 45,
            actualDurationMinutes: 45,
            completed: true,
            forcedExit: false,
            reason: 'study',
            deviceInfo: {},
          );
          await analyticsService.logSessionComplete(session);

          // Session di day 15
          session = LockSession(
            id: 'session_monthly_3',
            userId: 'user_monthly',
            startedAt: day15.add(Duration(hours: 9)),
            endedAt: day15.add(Duration(hours: 9, minutes: 20)),
            plannedDurationMinutes: 20,
            actualDurationMinutes: 20,
            completed: true,
            forcedExit: false,
            reason: 'break',
            deviceInfo: {},
          );
          await analyticsService.logSessionComplete(session);

          // ACT: Generate monthly report
          final report = await analyticsService.generateDailyReport(
            now,
            userId: 'user_monthly',
            period: 'monthly',
          );

          // ASSERT: Report tidak boleh null
          expect(report, isNotNull);

          // ASSERT: Monthly report harus include semua 3 sessions
          expect(report!.totalSessions, 3);
          expect(report.totalMinutes, 95); // 30 + 45 + 20
          expect(report.period, 'monthly');
        },
      );

      test(
        'REPORT-004: Save report to database successfully',
        () async {
          // ARRANGE: Generate report
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);

          var session = LockSession(
            id: 'session_save_1',
            userId: 'user_save',
            startedAt: today.add(Duration(hours: 10)),
            endedAt: today.add(Duration(hours: 10, minutes: 30)),
            plannedDurationMinutes: 30,
            actualDurationMinutes: 30,
            completed: true,
            forcedExit: false,
            reason: 'focus',
            deviceInfo: {},
          );
          await analyticsService.logSessionComplete(session);

          // ACT: Generate and save report
          final report = await analyticsService.generateDailyReport(
            now,
            userId: 'user_save',
            period: 'daily',
          );

          // ASSERT: Report harus berhasil disimpan
          expect(report, isNotNull);

          // ASSERT: Report bisa diambil dari database
          final savedReport =
              analyticsService.getReportById(report!.id);
          expect(savedReport, isNotNull);
          expect(savedReport!.userId, 'user_save');
          expect(savedReport.totalSessions, 1);
        },
      );
    });

    // ============================================================
    // GROUP 4: MILESTONE DETECTION (5+ tests)
    // ============================================================
    /// Menguji checkMilestones() untuk berbagai achievement types
    /// - Streak milestones (7, 30, 100, 365 days)
    /// - Time milestones (1h, 8h, 24h, 100h)
    /// - Session count milestones (10, 50, 100)
    group('Milestone Detection Tests', () {
      test(
        'MILESTONE-001: Detect 7-day streak achievement',
        () async {
          // ARRANGE: Create stats dengan 7-day streak
          final stats = UserStats(
            userId: 'user_milestone',
            totalLocks: 10,
            totalMinutes: 300,
            currentStreak: 7,
            bestStreak: 7,
            lastLockAt: DateTime.now(),
            averageSessionMinutes: 30.0,
            achievementCount: 0,
            updatedAt: DateTime.now(),
          );

          // ACT: Check milestones
          final achievements =
              await analyticsService.checkMilestones(
            userId: 'user_milestone',
            stats: stats,
          );

          // ASSERT: Harus detect 7_day_streak
          expect(achievements, contains('7_day_streak'));
        },
      );

      test(
        'MILESTONE-002: Detect multiple streak milestones',
        () async {
          // ARRANGE: Create stats dengan 100-day streak
          // (harus include 7_day_streak, 30_day_streak, 100_day_streak)
          final stats = UserStats(
            userId: 'user_multi_streak',
            totalLocks: 100,
            totalMinutes: 3000,
            currentStreak: 100,
            bestStreak: 100,
            lastLockAt: DateTime.now(),
            averageSessionMinutes: 30.0,
            achievementCount: 0,
            updatedAt: DateTime.now(),
          );

          // ACT: Check milestones
          final achievements = await analyticsService.checkMilestones(
            userId: 'user_multi_streak',
            stats: stats,
          );

          // ASSERT: Harus detect 100_day_streak (tertinggi)
          expect(achievements, contains('100_day_streak'));
        },
      );

      test(
        'MILESTONE-003: Detect time-based milestones (1h, 8h, 24h, 100h)',
        () async {
          // TEST 1: 1 hour milestone (60 minutes)
          var stats = UserStats(
            userId: 'user_time_1h',
            totalLocks: 2,
            totalMinutes: 60,
            currentStreak: 0,
            bestStreak: 0,
            lastLockAt: DateTime.now(),
            averageSessionMinutes: 30.0,
            achievementCount: 0,
            updatedAt: DateTime.now(),
          );

          var achievements = await analyticsService.checkMilestones(
            userId: 'user_time_1h',
            stats: stats,
          );

          expect(achievements, contains('1_hour_total'));

          // TEST 2: 8 hours milestone (480 minutes)
          stats = UserStats(
            userId: 'user_time_8h',
            totalLocks: 16,
            totalMinutes: 480,
            currentStreak: 0,
            bestStreak: 0,
            lastLockAt: DateTime.now(),
            averageSessionMinutes: 30.0,
            achievementCount: 0,
            updatedAt: DateTime.now(),
          );

          achievements = await analyticsService.checkMilestones(
            userId: 'user_time_8h',
            stats: stats,
          );

          expect(achievements, contains('8_hours_total'));

          // TEST 3: 24 hours milestone (1440 minutes)
          stats = UserStats(
            userId: 'user_time_24h',
            totalLocks: 48,
            totalMinutes: 1440,
            currentStreak: 0,
            bestStreak: 0,
            lastLockAt: DateTime.now(),
            averageSessionMinutes: 30.0,
            achievementCount: 0,
            updatedAt: DateTime.now(),
          );

          achievements = await analyticsService.checkMilestones(
            userId: 'user_time_24h',
            stats: stats,
          );

          expect(achievements, contains('24_hours_total'));

          // TEST 4: 100 hours milestone (6000 minutes)
          stats = UserStats(
            userId: 'user_time_100h',
            totalLocks: 200,
            totalMinutes: 6000,
            currentStreak: 0,
            bestStreak: 0,
            lastLockAt: DateTime.now(),
            averageSessionMinutes: 30.0,
            achievementCount: 0,
            updatedAt: DateTime.now(),
          );

          achievements = await analyticsService.checkMilestones(
            userId: 'user_time_100h',
            stats: stats,
          );

          expect(achievements, contains('100_hours_total'));
        },
      );

      test(
        'MILESTONE-004: Detect session count milestones (10, 50, 100)',
        () async {
          // TEST 1: 10 sessions milestone
          var stats = UserStats(
            userId: 'user_10_sessions',
            totalLocks: 10,
            totalMinutes: 300,
            currentStreak: 0,
            bestStreak: 0,
            lastLockAt: DateTime.now(),
            averageSessionMinutes: 30.0,
            achievementCount: 0,
            updatedAt: DateTime.now(),
          );

          var achievements = await analyticsService.checkMilestones(
            userId: 'user_10_sessions',
            stats: stats,
          );

          expect(achievements, contains('10_sessions'));

          // TEST 2: 50 sessions milestone
          stats = UserStats(
            userId: 'user_50_sessions',
            totalLocks: 50,
            totalMinutes: 1500,
            currentStreak: 0,
            bestStreak: 0,
            lastLockAt: DateTime.now(),
            averageSessionMinutes: 30.0,
            achievementCount: 0,
            updatedAt: DateTime.now(),
          );

          achievements = await analyticsService.checkMilestones(
            userId: 'user_50_sessions',
            stats: stats,
          );

          expect(achievements, contains('50_sessions'));

          // TEST 3: 100 sessions milestone
          stats = UserStats(
            userId: 'user_100_sessions',
            totalLocks: 100,
            totalMinutes: 3000,
            currentStreak: 0,
            bestStreak: 0,
            lastLockAt: DateTime.now(),
            averageSessionMinutes: 30.0,
            achievementCount: 0,
            updatedAt: DateTime.now(),
          );

          achievements = await analyticsService.checkMilestones(
            userId: 'user_100_sessions',
            stats: stats,
          );

          expect(achievements, contains('100_sessions'));
        },
      );

      test(
        'MILESTONE-005: No achievements if no milestones reached',
        () async {
          // ARRANGE: Create stats yang belum reach milestone apapun
          final stats = UserStats(
            userId: 'user_no_milestone',
            totalLocks: 5, // < 10
            totalMinutes: 30, // < 60 (below all time thresholds)
            currentStreak: 3, // < 7
            bestStreak: 3,
            lastLockAt: DateTime.now(),
            averageSessionMinutes: 6.0,
            achievementCount: 0,
            updatedAt: DateTime.now(),
          );

          // ACT: Check milestones
          final achievements = await analyticsService.checkMilestones(
            userId: 'user_no_milestone',
            stats: stats,
          );

          // ASSERT: Tidak ada achievements
          expect(achievements, isEmpty);
        },
      );

      test(
        'MILESTONE-006: Detect 1-year streak achievement',
        () async {
          // ARRANGE: Create stats dengan 365-day streak
          final stats = UserStats(
            userId: 'user_1year',
            totalLocks: 365,
            totalMinutes: 10950,
            currentStreak: 365,
            bestStreak: 365,
            lastLockAt: DateTime.now(),
            averageSessionMinutes: 30.0,
            achievementCount: 0,
            updatedAt: DateTime.now(),
          );

          // ACT: Check milestones
          final achievements = await analyticsService.checkMilestones(
            userId: 'user_1year',
            stats: stats,
          );

          // ASSERT: Harus detect 1_year_streak
          expect(achievements, contains('1_year_streak'));
        },
      );
    });

    // ============================================================
    // GROUP 5: EDGE CASES & STREAK LOGIC (5+ tests)
    // ============================================================
    group('Edge Cases & Streak Logic Tests', () {
      test(
        'EDGE-001: Broken streak reset to 0 if no lock yesterday/today',
        () async {
          // ARRANGE: Log session 3 hari lalu (streak sudah putus)
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final threeDaysAgo = today.subtract(Duration(days: 3));

          var session = LockSession(
            id: 'session_broken_1',
            userId: 'user_broken',
            startedAt: threeDaysAgo.add(Duration(hours: 10)),
            endedAt: threeDaysAgo.add(Duration(hours: 10, minutes: 30)),
            plannedDurationMinutes: 30,
            actualDurationMinutes: 30,
            completed: true,
            forcedExit: false,
            reason: 'focus',
            deviceInfo: {},
          );
          await analyticsService.logSessionComplete(session);

          // ACT: Calculate stats
          final stats =
              await analyticsService.calculateStats(userId: 'user_broken');

          // ASSERT: currentStreak harus 0 (broken)
          expect(stats.currentStreak, 0);

          // ASSERT: bestStreak harus 1 (only one day with session)
          expect(stats.bestStreak, 1);
        },
      );

      test(
        'EDGE-002: Get streak data with active status',
        () async {
          // ARRANGE: Log session hari ini
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);

          var session = LockSession(
            id: 'session_active_1',
            userId: 'user_active_streak',
            startedAt: today.add(Duration(hours: 10)),
            endedAt: today.add(Duration(hours: 10, minutes: 30)),
            plannedDurationMinutes: 30,
            actualDurationMinutes: 30,
            completed: true,
            forcedExit: false,
            reason: 'focus',
            deviceInfo: {},
          );
          await analyticsService.logSessionComplete(session);

          // ACT: Get streak data
          final streakData = await analyticsService.getStreakData(
            userId: 'user_active_streak',
          );

          // ASSERT: isStreakActive harus true
          expect(streakData.isStreakActive, true);

          // ASSERT: currentStreak harus 1
          expect(streakData.currentStreak, 1);
        },
      );

      test(
        'EDGE-003: Get trending data for last 7 days',
        () async {
          // ARRANGE: Log sessions untuk 3 hari
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final yesterday = today.subtract(Duration(days: 1));
          final twoDaysAgo = today.subtract(Duration(days: 2));

          // Day 1: 2 sessions (total 50 min)
          var session = LockSession(
            id: 'session_trend_1',
            userId: 'user_trend',
            startedAt: twoDaysAgo.add(Duration(hours: 9)),
            endedAt: twoDaysAgo.add(Duration(hours: 9, minutes: 30)),
            plannedDurationMinutes: 30,
            actualDurationMinutes: 30,
            completed: true,
            forcedExit: false,
            reason: 'focus',
            deviceInfo: {},
          );
          await analyticsService.logSessionComplete(session);

          session = LockSession(
            id: 'session_trend_2',
            userId: 'user_trend',
            startedAt: twoDaysAgo.add(Duration(hours: 14)),
            endedAt: twoDaysAgo.add(Duration(hours: 14, minutes: 20)),
            plannedDurationMinutes: 20,
            actualDurationMinutes: 20,
            completed: true,
            forcedExit: false,
            reason: 'study',
            deviceInfo: {},
          );
          await analyticsService.logSessionComplete(session);

          // Day 2: 1 session (25 min)
          session = LockSession(
            id: 'session_trend_3',
            userId: 'user_trend',
            startedAt: yesterday.add(Duration(hours: 10)),
            endedAt: yesterday.add(Duration(hours: 10, minutes: 25)),
            plannedDurationMinutes: 25,
            actualDurationMinutes: 25,
            completed: true,
            forcedExit: false,
            reason: 'break',
            deviceInfo: {},
          );
          await analyticsService.logSessionComplete(session);

          // Day 3: 1 session (20 min)
          session = LockSession(
            id: 'session_trend_4',
            userId: 'user_trend',
            startedAt: today.add(Duration(hours: 15)),
            endedAt: today.add(Duration(hours: 15, minutes: 20)),
            plannedDurationMinutes: 20,
            actualDurationMinutes: 20,
            completed: true,
            forcedExit: false,
            reason: 'work',
            deviceInfo: {},
          );
          await analyticsService.logSessionComplete(session);

          // ACT: Get trending data
          final trending =
              await analyticsService.getTrendingData(userId: 'user_trend');

          // ASSERT: Trending harus memiliki 3 hari
          expect(trending['totalDays'], 3);

          // ASSERT: Total sessions harus 4
          expect(trending['totalSessions'], 4);

          // ASSERT: Total minutes harus 95 (30+20+25+20)
          expect(trending['totalMinutes'], 95);
        },
      );

      test(
        'EDGE-004: Report return null jika tidak ada sessions',
        () async {
          // ARRANGE: Tidak ada sessions

          // ACT: Generate report
          final report = await analyticsService.generateDailyReport(
            DateTime.now(),
            userId: 'user_empty',
            period: 'daily',
          );

          // ASSERT: Report harus null
          expect(report, isNull);
        },
      );

      test(
        'EDGE-005: Clear sync queue after successful sync',
        () async {
          // ARRANGE: Log beberapa sessions
          var session = LockSession(
            id: 'session_sync_1',
            userId: 'user_sync',
            startedAt: DateTime.now().subtract(Duration(minutes: 30)),
            endedAt: DateTime.now(),
            plannedDurationMinutes: 30,
            actualDurationMinutes: 30,
            completed: true,
            forcedExit: false,
            reason: 'focus',
            deviceInfo: {},
          );
          await analyticsService.logSessionComplete(session);

          // ASSERT: Sync queue tidak kosong
          expect(analyticsService.getSyncQueue().length, 1);

          // ACT: Clear sync queue
          analyticsService.clearSyncQueue();

          // ASSERT: Sync queue sekarang kosong
          expect(analyticsService.getSyncQueue().length, 0);
        },
      );
    });

    // ============================================================
    // GROUP 6: INTEGRATION TESTS (3+ tests)
    // ============================================================
    group('Integration Tests', () {
      test(
        'INTEGRATION-001: Full flow: log session -> calculate stats -> check milestones',
        () async {
          // ARRANGE: Siapkan user dan sessions
          const userId = 'user_integration';

          // Log 10 sessions (to reach 10_sessions milestone)
          for (int i = 0; i < 10; i++) {
            final session = LockSession(
              id: 'session_integration_$i',
              userId: userId,
              startedAt: DateTime.now().subtract(Duration(minutes: 50 - i * 5)),
              endedAt: DateTime.now().subtract(Duration(minutes: 50 - i * 5 - 30)),
              plannedDurationMinutes: 30,
              actualDurationMinutes: 30,
              completed: true,
              forcedExit: false,
              reason: 'focus',
              deviceInfo: {},
            );
            await analyticsService.logSessionComplete(session);
          }

          // ACT: Calculate stats
          final stats = await analyticsService.calculateStats(userId: userId);

          // ASSERT: Stats harus correct
          expect(stats.totalLocks, 10);
          expect(stats.totalMinutes, 300);

          // ACT: Check milestones
          final achievements =
              await analyticsService.checkMilestones(userId: userId, stats: stats);

          // ASSERT: Harus detect 10_sessions achievement
          expect(achievements, contains('10_sessions'));
        },
      );

      test(
        'INTEGRATION-002: Multiple users tracking independently',
        () async {
          // ARRANGE: Log sessions untuk 2 users berbeda
          for (int i = 0; i < 5; i++) {
            var session = LockSession(
              id: 'session_user1_$i',
              userId: 'user_a',
              startedAt: DateTime.now().subtract(Duration(minutes: 50 - i * 5)),
              endedAt: DateTime.now().subtract(Duration(minutes: 50 - i * 5 - 30)),
              plannedDurationMinutes: 30,
              actualDurationMinutes: 30,
              completed: true,
              forcedExit: false,
              reason: 'focus',
              deviceInfo: {},
            );
            await analyticsService.logSessionComplete(session);

            session = LockSession(
              id: 'session_user2_$i',
              userId: 'user_b',
              startedAt: DateTime.now().subtract(Duration(minutes: 50 - i * 5)),
              endedAt: DateTime.now().subtract(Duration(minutes: 50 - i * 5 - 20)),
              plannedDurationMinutes: 20,
              actualDurationMinutes: 20,
              completed: true,
              forcedExit: false,
              reason: 'study',
              deviceInfo: {},
            );
            await analyticsService.logSessionComplete(session);
          }

          // ACT: Calculate stats untuk kedua users
          final statsA =
              await analyticsService.calculateStats(userId: 'user_a');
          final statsB =
              await analyticsService.calculateStats(userId: 'user_b');

          // ASSERT: Stats harus independent
          expect(statsA.totalLocks, 5);
          expect(statsA.totalMinutes, 150);

          expect(statsB.totalLocks, 5);
          expect(statsB.totalMinutes, 100); // 5 * 20 min
        },
      );

      test(
        'INTEGRATION-003: Report generation with milestone detection',
        () async {
          // ARRANGE: Log sessions untuk generate report
          const userId = 'user_report_milestone';
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);

          // Log 2 sessions for 1_hour_total milestone
          for (int i = 0; i < 2; i++) {
            final session = LockSession(
              id: 'session_report_$i',
              userId: userId,
              startedAt: today.add(Duration(hours: 9 + i * 2)),
              endedAt: today.add(Duration(hours: 9 + i * 2, minutes: 30)),
              plannedDurationMinutes: 30,
              actualDurationMinutes: 30,
              completed: true,
              forcedExit: false,
              reason: 'focus',
              deviceInfo: {},
            );
            await analyticsService.logSessionComplete(session);
          }

          // ACT: Generate report
          final report = await analyticsService.generateDailyReport(
            now,
            userId: userId,
            period: 'daily',
          );

          // ASSERT: Report harus generated
          expect(report, isNotNull);
          expect(report!.totalSessions, 2);
          expect(report.totalMinutes, 60);

          // ACT: Calculate stats dan check milestones
          final stats = await analyticsService.calculateStats(userId: userId);
          final achievements =
              await analyticsService.checkMilestones(userId: userId, stats: stats);

          // ASSERT: Harus detect 1_hour_total
          expect(achievements, contains('1_hour_total'));
        },
      );
    });
  });
}

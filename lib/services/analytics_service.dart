import 'package:logger/logger.dart';
import '../models/lock_session.dart';
import '../models/user_profile.dart';
import '../models/daily_report.dart';
import '../models/analytics_event.dart';

/// ============================================================
/// ANALYTICS SERVICE - PROSES DATA SESI DAN LAPORAN ANALYTICS
/// ============================================================
/// Service ini menangani:
/// • Pencatatan sesi yang telah diselesaikan dengan validasi
/// • Perhitungan statistik pengguna (total, rata-rata, streak)
/// • Generasi laporan harian/mingguan/bulanan
/// • Deteksi milestone dan pencapaian pengguna
/// • Penyimpanan ke database lokal dan sinkronisasi Firestore
///
/// FITUR UTAMA:
/// 1. logSessionComplete() - Validasi dan simpan sesi selesai
/// 2. calculateStats() - Hitung total locks, menit, streak
/// 3. generateDailyReport() - Laporan untuk tanggal tertentu
/// 4. checkMilestones() - Deteksi pencapaian (streak, waktu, jumlah)
/// 5. getStreakData() - Hitung hari berturut-turut dengan sesi
/// 6. analyzeSession() - Analisis kualitas sesi (0-100 score)
/// ============================================================
class AnalyticsService {
  final Logger _logger = Logger();

  /// Database lokal untuk menyimpan sessions (mock untuk testing)
  final Map<String, List<LockSession>> _sessionDatabase = {};

  /// Database untuk daily reports
  final Map<String, DailyReport> _reportDatabase = {};

  /// Queue untuk sinkronisasi Firestore
  final List<Map<String, dynamic>> _syncQueue = [];

  /// ============================================================
  /// TASK 2.1: LOG SESSION COMPLETE
  /// ============================================================
  /// Mencatat sesi yang telah diselesaikan dengan validasi lengkap
  /// - Validasi sesi sudah completed
  /// - Hitung quality_score (0-100)
  /// - Simpan ke database lokal
  /// - Queue untuk sinkronisasi Firestore
  ///
  /// Parameter:
  ///   session - LockSession yang sudah selesai
  ///
  /// Throw Exception jika:
  ///   - Session belum completed
  ///   - Validasi data gagal
  /// ============================================================
  Future<void> logSessionComplete(LockSession session) async {
    // VALIDASI: Session harus sudah completed
    if (!session.completed) {
      throw Exception('Session must be completed before logging');
    }

    // VALIDASI: actualDurationMinutes harus terisi
    if (session.actualDurationMinutes == null) {
      throw Exception('Session must have actualDurationMinutes set');
    }

    // VALIDASI: userId tidak boleh kosong
    if (session.userId.isEmpty) {
      throw Exception('Session must have valid userId');
    }

    // ANALISIS: Hitung quality score
    final analytics = await analyzeSession(session);
    final qualityScore = analytics.qualityScore;

    _logger.i(
      'Logging session: ${session.id} (${session.actualDurationMinutes} min, '
      'quality: $qualityScore)',
    );

    // SIMPAN: Ke database lokal (grouped by userId)
    if (!_sessionDatabase.containsKey(session.userId)) {
      _sessionDatabase[session.userId] = [];
    }
    _sessionDatabase[session.userId]!.add(session);

    // QUEUE: Tambahkan ke sync queue untuk Firestore
    _syncQueue.add({
      'type': 'session',
      'action': 'save',
      'sessionId': session.id,
      'userId': session.userId,
      'qualityScore': qualityScore,
      'timestamp': DateTime.now(),
    });

    _logger.i('Session logged and queued for sync');
  }

  /// ============================================================
  /// TASK 2.2: CALCULATE STATS
  /// ============================================================
  /// Menghitung statistik pengguna dari riwayat sesi
  /// - Query semua sessions untuk user
  /// - Hitung: total_locks, total_minutes, average_session
  /// - Hitung STREAK logic (hari berturut-turut)
  /// - Return UserStats object
  ///
  /// Parameter:
  ///   userId - ID pengguna
  ///
  /// Return:
  ///   UserStats dengan semua metrik terisi
  ///
  /// Contoh output untuk 3 sesi:
  ///   - Sesi 1: 30 min (2026-08-28)
  ///   - Sesi 2: 25 min (2026-08-28)
  ///   - Sesi 3: 20 min (2026-08-29)
  ///   => totalLocks=3, totalMinutes=75, avgSession=25, streak=2
  /// ============================================================
  Future<UserStats> calculateStats({required String userId}) async {
    _logger.i('Calculating stats for user: $userId');

    // QUERY: Ambil semua sessions dari database
    final sessions = _sessionDatabase[userId] ?? [];

    // HITUNG: total_locks
    final totalLocks = sessions.length;

    // HITUNG: total_minutes
    final totalMinutes = sessions.fold<int>(
      0,
      (sum, session) => sum + (session.actualDurationMinutes ?? 0),
    );

    // HITUNG: average_session_minutes
    final averageSessionMinutes = totalLocks > 0
        ? totalMinutes / totalLocks
        : 0.0;

    // HITUNG: current_streak dan best_streak
    final streakData = await _calculateStreak(sessions);

    _logger.i(
      'Stats calculated: locks=$totalLocks, minutes=$totalMinutes, '
      'avg=${averageSessionMinutes.toStringAsFixed(1)}, '
      'streak=${streakData['current']}, best=${streakData['best']}',
    );

    // RETURN: UserStats object dengan semua data
    return UserStats(
      userId: userId,
      totalLocks: totalLocks,
      totalMinutes: totalMinutes,
      currentStreak: streakData['current'] as int,
      bestStreak: streakData['best'] as int,
      lastLockAt: sessions.isNotEmpty ? sessions.last.endedAt : null,
      averageSessionMinutes: averageSessionMinutes,
      achievementCount: 0, // Akan di-update di checkMilestones
      updatedAt: DateTime.now(),
    );
  }

  /// ============================================================
  /// INTERNAL: CALCULATE STREAK
  /// ============================================================
  /// Helper method untuk menghitung streak dari list sessions
  /// Logic:
  ///   - Group sessions by date (ignoring time)
  ///   - Cek hari berturut-turut dengan ≥1 session
  ///   - Track current streak dan best streak
  ///
  /// Return:
  ///   Map dengan keys 'current' dan 'best' (int values)
  /// ============================================================
  Future<Map<String, int>> _calculateStreak(List<LockSession> sessions) async {
    if (sessions.isEmpty) {
      return {'current': 0, 'best': 0};
    }

    // KELOMPOK: Sessions by date
    final sessionsByDate = <DateTime, List<LockSession>>{};
    for (final session in sessions) {
      final date = DateTime(
        session.startedAt.year,
        session.startedAt.month,
        session.startedAt.day,
      );
      if (!sessionsByDate.containsKey(date)) {
        sessionsByDate[date] = [];
      }
      sessionsByDate[date]!.add(session);
    }

    // SORT: Dates dari yang paling lama
    final sortedDates = sessionsByDate.keys.toList()..sort();

    // HITUNG: Current streak dan best streak
    int currentStreak = 0;
    int bestStreak = 0;
    DateTime? lastDate;

    for (final date in sortedDates) {
      if (lastDate == null) {
        // Hari pertama
        currentStreak = 1;
        bestStreak = 1;
      } else {
        // Cek apakah tanggal hari ini berturut-turut dari kemarin
        final daysDiff = date.difference(lastDate).inDays;
        if (daysDiff == 1) {
          // Berturut-turut: tambah streak
          currentStreak++;
          if (currentStreak > bestStreak) {
            bestStreak = currentStreak;
          }
        } else {
          // Putus: reset streak
          currentStreak = 1;
        }
      }
      lastDate = date;
    }

    // VALIDASI: Check apakah current streak masih aktif (hari ini atau kemarin)
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final yesterdayOnly = todayOnly.subtract(Duration(days: 1));

    if (lastDate != todayOnly && lastDate != yesterdayOnly) {
      // Streak sudah putus karena tidak ada sesi hari ini atau kemarin
      currentStreak = 0;
    }

    return {
      'current': currentStreak,
      'best': bestStreak,
    };
  }

  /// ============================================================
  /// TASK 2.3: GENERATE DAILY REPORT
  /// ============================================================
  /// Menghasilkan laporan untuk tanggal tertentu
  /// - Query sessions untuk tanggal tsb
  /// - Hitung: longest, shortest, best_day
  /// - Generate untuk daily/weekly/monthly
  /// - Simpan ke database
  ///
  /// Parameter:
  ///   date - Tanggal untuk report (akan dibulatkan ke awal hari)
  ///   userId - (optional) User ID untuk filter
  ///   period - (optional) 'daily'|'weekly'|'monthly', default 'daily'
  ///
  /// Return:
  ///   DailyReport atau null jika tidak ada sessions
  /// ============================================================
  Future<DailyReport?> generateDailyReport(
    DateTime date, {
    String? userId,
    String period = 'daily',
  }) async {
    _logger.i(
      'Generating $period report for ${date.toIso8601String()} '
      '${userId != null ? '(user: $userId)' : '(all users)'}',
    );

    // QUERY: Ambil sessions sesuai period
    List<LockSession> reportSessions = [];
    late DateTime dateStart;
    late DateTime dateEnd;
    late String periodDate;

    if (period == 'daily') {
      // DAILY: Satu hari penuh
      dateStart = DateTime(date.year, date.month, date.day);
      dateEnd = dateStart.add(Duration(days: 1)).subtract(Duration(microseconds: 1));
      periodDate = '${dateStart.year}-${dateStart.month.toString().padLeft(2, '0')}'
          '-${dateStart.day.toString().padLeft(2, '0')}';

      // Filter sessions untuk tanggal ini
      for (final userSessions in _sessionDatabase.values) {
        for (final session in userSessions) {
          if (session.startedAt.isAfter(dateStart) &&
              session.startedAt.isBefore(dateEnd)) {
            if (userId == null || session.userId == userId) {
              reportSessions.add(session);
            }
          }
        }
      }
    } else if (period == 'weekly') {
      // WEEKLY: 7 hari kebelakang
      dateStart = date.subtract(Duration(days: date.weekday - 1)); // Mulai Senin
      dateStart = DateTime(dateStart.year, dateStart.month, dateStart.day);
      dateEnd = dateStart.add(Duration(days: 7)).subtract(Duration(microseconds: 1));
      periodDate = 'W${dateStart.year}-${dateStart.month.toString().padLeft(2, '0')}'
          '-${dateStart.day.toString().padLeft(2, '0')}';

      // Filter sessions untuk minggu ini
      for (final userSessions in _sessionDatabase.values) {
        for (final session in userSessions) {
          if (session.startedAt.isAfter(dateStart) &&
              session.startedAt.isBefore(dateEnd)) {
            if (userId == null || session.userId == userId) {
              reportSessions.add(session);
            }
          }
        }
      }
    } else if (period == 'monthly') {
      // MONTHLY: Satu bulan penuh
      dateStart = DateTime(date.year, date.month, 1);
      dateEnd = DateTime(date.year, date.month + 1, 1)
          .subtract(Duration(microseconds: 1));
      periodDate = '${dateStart.year}-${dateStart.month.toString().padLeft(2, '0')}';

      // Filter sessions untuk bulan ini
      for (final userSessions in _sessionDatabase.values) {
        for (final session in userSessions) {
          if (session.startedAt.isAfter(dateStart) &&
              session.startedAt.isBefore(dateEnd)) {
            if (userId == null || session.userId == userId) {
              reportSessions.add(session);
            }
          }
        }
      }
    } else {
      // DEFAULT: daily jika period tidak valid
      dateStart = DateTime(date.year, date.month, date.day);
      dateEnd = dateStart.add(Duration(days: 1)).subtract(Duration(microseconds: 1));
      periodDate = '${dateStart.year}-${dateStart.month.toString().padLeft(2, '0')}'
          '-${dateStart.day.toString().padLeft(2, '0')}';
    }

    // VALIDASI: Jika tidak ada sessions, return null
    if (reportSessions.isEmpty) {
      _logger.i('No sessions found for report period');
      return null;
    }

    // HITUNG: Metrics untuk report
    final totalSessions = reportSessions.length;
    final totalMinutes =
        reportSessions.fold(0, (sum, s) => sum + (s.actualDurationMinutes ?? 0));
    final totalHours = totalMinutes / 60;
    final averageSessionMinutes = totalMinutes / totalSessions;
    final longestSessionMinutes =
        reportSessions.map((s) => s.actualDurationMinutes ?? 0).reduce((a, b) =>
            a > b ? a : b);
    final shortestSessionMinutes =
        reportSessions.map((s) => s.actualDurationMinutes ?? 0).reduce((a, b) =>
            a < b ? a : b);

    // HITUNG: Best day (hari dengan total menit terbanyak)
    final sessionsByDay = <String, int>{};
    for (final session in reportSessions) {
      final dayKey = '${session.startedAt.year}-'
          '${session.startedAt.month.toString().padLeft(2, '0')}-'
          '${session.startedAt.day.toString().padLeft(2, '0')}';
      sessionsByDay[dayKey] =
          (sessionsByDay[dayKey] ?? 0) + (session.actualDurationMinutes ?? 0);
    }

    String bestDay = 'N/A';
    int bestDayMinutes = 0;
    sessionsByDay.forEach((day, minutes) {
      if (minutes > bestDayMinutes) {
        bestDayMinutes = minutes;
        bestDay = day;
      }
    });

    // HITUNG: Streak dalam periode
    final streakData = await _calculateStreak(reportSessions);
    final streakInPeriod = streakData['best'] ?? 0;

    // BUAT: DailyReport object
    final reportId = '${userId ?? 'all'}_${period}_$periodDate';
    final report = DailyReport(
      id: reportId,
      userId: userId ?? 'system',
      period: period,
      periodDate: periodDate,
      dateStart: dateStart,
      dateEnd: dateEnd,
      totalSessions: totalSessions,
      totalMinutes: totalMinutes,
      totalHours: totalHours,
      averageSessionMinutes: averageSessionMinutes,
      longestSessionMinutes: longestSessionMinutes,
      shortestSessionMinutes: shortestSessionMinutes,
      bestDay: bestDay,
      bestDayMinutes: bestDayMinutes,
      streakInPeriod: streakInPeriod,
      milestonesAchieved: [],
      isPublic: false,
      viewCount: 0,
      generatedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // SIMPAN: Ke database
    _reportDatabase[reportId] = report;

    _logger.i(
      'Report generated: $totalSessions sessions, $totalMinutes minutes, '
      'best day: $bestDay ($bestDayMinutes min)',
    );

    return report;
  }

  /// ============================================================
  /// TASK 2.4: CHECK MILESTONES
  /// ============================================================
  /// Mendeteksi milestone dan pencapaian pengguna
  /// - Streak milestones: 7, 30, 100, 365 hari
  /// - Time milestones: 1h, 8h, 24h, 100h
  /// - Session count milestones: 10, 50, 100 sessions
  /// - Return list of achievement IDs
  ///
  /// Parameter:
  ///   userId - ID pengguna
  ///   stats - UserStats object dengan metrik terkini
  ///
  /// Return:
  ///   List<String> - Achievement IDs yang baru dicapai
  ///
  /// Milestone yang mungkin:
  ///   - '7_day_streak', '30_day_streak', '100_day_streak', '1_year_streak'
  ///   - '1_hour_total', '8_hours_total', '24_hours_total', '100_hours_total'
  ///   - '10_sessions', '50_sessions', '100_sessions'
  /// ============================================================
  Future<List<String>> checkMilestones({
    required String userId,
    required UserStats stats,
  }) async {
    final achievements = <String>[];

    _logger.i(
      'Checking milestones for user: $userId '
      '(streak: ${stats.currentStreak}, minutes: ${stats.totalMinutes}, '
      'locks: ${stats.totalLocks})',
    );

    // ============================================================
    // MILESTONE GROUP 1: STREAK MILESTONES (hari berturut-turut)
    // ============================================================
    if (stats.currentStreak >= 365) {
      achievements.add('1_year_streak');
      _logger.i('✓ Achievement unlocked: 1_year_streak (${stats.currentStreak} days)');
    } else if (stats.currentStreak >= 100) {
      achievements.add('100_day_streak');
      _logger.i('✓ Achievement unlocked: 100_day_streak (${stats.currentStreak} days)');
    } else if (stats.currentStreak >= 30) {
      achievements.add('30_day_streak');
      _logger.i('✓ Achievement unlocked: 30_day_streak (${stats.currentStreak} days)');
    } else if (stats.currentStreak >= 7) {
      achievements.add('7_day_streak');
      _logger.i('✓ Achievement unlocked: 7_day_streak (${stats.currentStreak} days)');
    }

    // ============================================================
    // MILESTONE GROUP 2: TIME MILESTONES (total menit)
    // ============================================================
    // Catatan: Milestone time adalah "at least" level, bukan range
    // Contoh: 6000+ menit = 100_hours_total
    if (stats.totalMinutes >= 6000) {
      // 6000 menit = 100 jam
      achievements.add('100_hours_total');
      _logger.i('✓ Achievement unlocked: 100_hours_total (${stats.totalMinutes} min)');
    } else if (stats.totalMinutes >= 1440) {
      // 1440 menit = 24 jam = 1 hari
      achievements.add('24_hours_total');
      _logger.i('✓ Achievement unlocked: 24_hours_total (${stats.totalMinutes} min)');
    } else if (stats.totalMinutes >= 480) {
      // 480 menit = 8 jam
      achievements.add('8_hours_total');
      _logger.i('✓ Achievement unlocked: 8_hours_total (${stats.totalMinutes} min)');
    } else if (stats.totalMinutes >= 60) {
      // 60 menit = 1 jam
      achievements.add('1_hour_total');
      _logger.i('✓ Achievement unlocked: 1_hour_total (${stats.totalMinutes} min)');
    }

    // ============================================================
    // MILESTONE GROUP 3: SESSION COUNT MILESTONES (jumlah sesi)
    // ============================================================
    if (stats.totalLocks >= 100) {
      achievements.add('100_sessions');
      _logger.i('✓ Achievement unlocked: 100_sessions (${stats.totalLocks} locks)');
    } else if (stats.totalLocks >= 50) {
      achievements.add('50_sessions');
      _logger.i('✓ Achievement unlocked: 50_sessions (${stats.totalLocks} locks)');
    } else if (stats.totalLocks >= 10) {
      achievements.add('10_sessions');
      _logger.i('✓ Achievement unlocked: 10_sessions (${stats.totalLocks} locks)');
    }

    _logger.i('Found ${achievements.length} achievements for user: $userId');
    return achievements;
  }

  /// Get or calculate streak data
  Future<StreakData> getStreakData({required String userId}) async {
    _logger.i('Getting streak data for user: $userId');

    // QUERY: Ambil semua sessions untuk user
    final sessions = _sessionDatabase[userId] ?? [];

    // HITUNG: Streak
    final streakMap = await _calculateStreak(sessions);

    // AMBIL: Last lock date
    DateTime lastLockDate = DateTime.now();
    if (sessions.isNotEmpty) {
      lastLockDate = sessions.last.startedAt;
    }

    // HITUNG: Apakah streak masih aktif
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final yesterdayOnly = todayOnly.subtract(Duration(days: 1));
    final lastLockDateOnly =
        DateTime(lastLockDate.year, lastLockDate.month, lastLockDate.day);

    final isStreakActive =
        lastLockDateOnly == todayOnly || lastLockDateOnly == yesterdayOnly;

    return StreakData(
      userId: userId,
      currentStreak: streakMap['current'] ?? 0,
      bestStreak: streakMap['best'] ?? 0,
      lastLockDate: lastLockDate,
      isStreakActive: isStreakActive,
    );
  }

  /// Get session analytics for quality scoring
  Future<SessionAnalytics> analyzeSession(LockSession session) async {
    // VALIDASI: Session harus completed
    if (!session.completed) {
      throw Exception('Session must be completed for analysis');
    }

    // HITUNG: Completion percentage
    final plannedMinutes = session.plannedDurationMinutes;
    final actualMinutes = session.actualDurationMinutes ?? 0;
    final completionPercentage =
        (actualMinutes / plannedMinutes * 100).clamp(0, 100).toDouble();

    // BUAT: SessionAnalytics object
    final analytics = SessionAnalytics(
      sessionId: session.id,
      plannedMinutes: plannedMinutes,
      actualMinutes: actualMinutes,
      completionPercentage: completionPercentage,
      reason: session.reason,
      startedAt: session.startedAt,
      completedAt: session.endedAt ?? DateTime.now(),
      wasForcedExit: session.forcedExit,
    );

    _logger.i(
      'Session analysis: quality=${analytics.qualityScore}, '
      'completion=${completionPercentage.toStringAsFixed(1)}%',
    );

    return analytics;
  }

  /// Get trending data (last 7 days)
  Future<Map<String, dynamic>> getTrendingData({required String userId}) async {
    _logger.i('Getting trending data for user: $userId');

    // QUERY: Ambil sessions dari 7 hari terakhir
    final sevenDaysAgo = DateTime.now().subtract(Duration(days: 7));
    final userSessions = _sessionDatabase[userId] ?? [];
    final recentSessions = userSessions
        .where((s) => s.startedAt.isAfter(sevenDaysAgo))
        .toList();

    // GROUP: By day
    final trendByDay = <String, Map<String, dynamic>>{};
    for (final session in recentSessions) {
      final dayKey = '${session.startedAt.year}-'
          '${session.startedAt.month.toString().padLeft(2, '0')}-'
          '${session.startedAt.day.toString().padLeft(2, '0')}';

      if (!trendByDay.containsKey(dayKey)) {
        trendByDay[dayKey] = {
          'sessions': 0,
          'totalMinutes': 0,
          'averageQuality': 0.0,
        };
      }

      trendByDay[dayKey]!['sessions'] =
          (trendByDay[dayKey]!['sessions'] as int) + 1;
      trendByDay[dayKey]!['totalMinutes'] =
          (trendByDay[dayKey]!['totalMinutes'] as int) +
              (session.actualDurationMinutes ?? 0);
    }

    _logger.i('Trending data collected for ${trendByDay.length} days');

    return {
      'totalDays': trendByDay.length,
      'totalSessions': recentSessions.length,
      'totalMinutes': recentSessions.fold(
        0,
        (sum, s) => sum + (s.actualDurationMinutes ?? 0),
      ),
      'trendByDay': trendByDay,
    };
  }

  /// Get sync queue status
  List<Map<String, dynamic>> getSyncQueue() => List.from(_syncQueue);

  /// Clear sync queue (after successful sync)
  void clearSyncQueue() {
    _syncQueue.clear();
  }

  /// Get all sessions for a user (for testing/debugging)
  List<LockSession> getSessionsForUser(String userId) =>
      List.from(_sessionDatabase[userId] ?? []);

  /// Get report by ID (for testing/debugging)
  DailyReport? getReportById(String reportId) => _reportDatabase[reportId];

  @override
  String toString() => 'AnalyticsService()';
}

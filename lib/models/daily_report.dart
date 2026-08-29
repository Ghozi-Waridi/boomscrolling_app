import 'package:cloud_firestore/cloud_firestore.dart';

/// Daily/weekly/monthly report
class DailyReport {
  final String id;
  final String userId;
  final String period; // daily, weekly, monthly
  final String periodDate; // YYYY-MM-DD for daily
  final DateTime dateStart;
  final DateTime dateEnd;
  final int totalSessions;
  final int totalMinutes;
  final double totalHours;
  final double averageSessionMinutes;
  final int longestSessionMinutes;
  final int shortestSessionMinutes;
  final String bestDay;
  final int bestDayMinutes;
  final int streakInPeriod;
  final List<String> milestonesAchieved;
  final bool isPublic;
  final String? shareToken;
  final int viewCount;
  final DateTime generatedAt;
  final DateTime updatedAt;

  DailyReport({
    required this.id,
    required this.userId,
    required this.period,
    required this.periodDate,
    required this.dateStart,
    required this.dateEnd,
    required this.totalSessions,
    required this.totalMinutes,
    required this.totalHours,
    required this.averageSessionMinutes,
    required this.longestSessionMinutes,
    required this.shortestSessionMinutes,
    required this.bestDay,
    required this.bestDayMinutes,
    required this.streakInPeriod,
    required this.milestonesAchieved,
    required this.isPublic,
    this.shareToken,
    required this.viewCount,
    required this.generatedAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'period': period,
      'period_date': periodDate,
      'date_start': dateStart,
      'date_end': dateEnd,
      'total_sessions': totalSessions,
      'total_minutes': totalMinutes,
      'total_hours': totalHours,
      'average_session_minutes': averageSessionMinutes,
      'longest_session_minutes': longestSessionMinutes,
      'shortest_session_minutes': shortestSessionMinutes,
      'best_day': bestDay,
      'best_day_minutes': bestDayMinutes,
      'streak_in_period': streakInPeriod,
      'milestones_achieved': milestonesAchieved,
      'is_public': isPublic,
      'share_token': shareToken,
      'view_count': viewCount,
      'generated_at': generatedAt,
      'updated_at': updatedAt,
    };
  }

  factory DailyReport.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return DailyReport(
      id: doc.id,
      userId: doc.reference.parent.parent!.id,
      period: data['period'] as String,
      periodDate: data['period_date'] as String,
      dateStart: (data['date_start'] as Timestamp).toDate(),
      dateEnd: (data['date_end'] as Timestamp).toDate(),
      totalSessions: data['total_sessions'] as int,
      totalMinutes: data['total_minutes'] as int,
      totalHours: (data['total_hours'] as num).toDouble(),
      averageSessionMinutes: (data['average_session_minutes'] as num).toDouble(),
      longestSessionMinutes: data['longest_session_minutes'] as int,
      shortestSessionMinutes: data['shortest_session_minutes'] as int,
      bestDay: data['best_day'] as String,
      bestDayMinutes: data['best_day_minutes'] as int,
      streakInPeriod: data['streak_in_period'] as int? ?? 0,
      milestonesAchieved: List<String>.from(data['milestones_achieved'] as List? ?? []),
      isPublic: data['is_public'] as bool? ?? false,
      shareToken: data['share_token'] as String?,
      viewCount: data['view_count'] as int? ?? 0,
      generatedAt: (data['generated_at'] as Timestamp).toDate(),
      updatedAt: (data['updated_at'] as Timestamp).toDate(),
    );
  }

  DailyReport copyWith({
    String? id,
    String? userId,
    String? period,
    String? periodDate,
    DateTime? dateStart,
    DateTime? dateEnd,
    int? totalSessions,
    int? totalMinutes,
    double? totalHours,
    double? averageSessionMinutes,
    int? longestSessionMinutes,
    int? shortestSessionMinutes,
    String? bestDay,
    int? bestDayMinutes,
    int? streakInPeriod,
    List<String>? milestonesAchieved,
    bool? isPublic,
    String? shareToken,
    int? viewCount,
    DateTime? generatedAt,
    DateTime? updatedAt,
  }) {
    return DailyReport(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      period: period ?? this.period,
      periodDate: periodDate ?? this.periodDate,
      dateStart: dateStart ?? this.dateStart,
      dateEnd: dateEnd ?? this.dateEnd,
      totalSessions: totalSessions ?? this.totalSessions,
      totalMinutes: totalMinutes ?? this.totalMinutes,
      totalHours: totalHours ?? this.totalHours,
      averageSessionMinutes: averageSessionMinutes ?? this.averageSessionMinutes,
      longestSessionMinutes: longestSessionMinutes ?? this.longestSessionMinutes,
      shortestSessionMinutes: shortestSessionMinutes ?? this.shortestSessionMinutes,
      bestDay: bestDay ?? this.bestDay,
      bestDayMinutes: bestDayMinutes ?? this.bestDayMinutes,
      streakInPeriod: streakInPeriod ?? this.streakInPeriod,
      milestonesAchieved: milestonesAchieved ?? this.milestonesAchieved,
      isPublic: isPublic ?? this.isPublic,
      shareToken: shareToken ?? this.shareToken,
      viewCount: viewCount ?? this.viewCount,
      generatedAt: generatedAt ?? this.generatedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'DailyReport(period: $period, totalMinutes: $totalMinutes, sessions: $totalSessions)';
  }
}

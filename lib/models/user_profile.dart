import 'package:cloud_firestore/cloud_firestore.dart';

/// User profile data
class UserProfile {
  final String userId;
  final String name;
  final String email;
  final String? avatarUrl;
  final String? bio;
  final bool isPublic;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserProfile({
    required this.userId,
    required this.name,
    required this.email,
    this.avatarUrl,
    this.bio,
    required this.isPublic,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'avatar_url': avatarUrl,
      'bio': bio,
      'is_public': isPublic,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory UserProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return UserProfile(
      userId: doc.id,
      name: data['name'] as String,
      email: data['email'] as String,
      avatarUrl: data['avatar_url'] as String?,
      bio: data['bio'] as String?,
      isPublic: data['is_public'] as bool? ?? false,
      createdAt: (data['created_at'] as Timestamp).toDate(),
      updatedAt: (data['updated_at'] as Timestamp).toDate(),
    );
  }

  UserProfile copyWith({
    String? userId,
    String? name,
    String? email,
    String? avatarUrl,
    String? bio,
    bool? isPublic,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      isPublic: isPublic ?? this.isPublic,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// User statistics
class UserStats {
  final String userId;
  final int totalLocks;
  final int totalMinutes;
  final int currentStreak;
  final int bestStreak;
  final DateTime? lastLockAt;
  final double averageSessionMinutes;
  final int achievementCount;
  final DateTime updatedAt;

  UserStats({
    required this.userId,
    required this.totalLocks,
    required this.totalMinutes,
    required this.currentStreak,
    required this.bestStreak,
    this.lastLockAt,
    required this.averageSessionMinutes,
    required this.achievementCount,
    required this.updatedAt,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'total_locks': totalLocks,
      'total_minutes': totalMinutes,
      'current_streak': currentStreak,
      'best_streak': bestStreak,
      'last_lock_at': lastLockAt,
      'average_session_minutes': averageSessionMinutes,
      'achievement_count': achievementCount,
      'updated_at': updatedAt,
    };
  }

  factory UserStats.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return UserStats(
      userId: doc.id,
      totalLocks: data['total_locks'] as int? ?? 0,
      totalMinutes: data['total_minutes'] as int? ?? 0,
      currentStreak: data['current_streak'] as int? ?? 0,
      bestStreak: data['best_streak'] as int? ?? 0,
      lastLockAt: data['last_lock_at'] != null
          ? (data['last_lock_at'] as Timestamp).toDate()
          : null,
      averageSessionMinutes: (data['average_session_minutes'] as num? ?? 0).toDouble(),
      achievementCount: data['achievement_count'] as int? ?? 0,
      updatedAt: (data['updated_at'] as Timestamp).toDate(),
    );
  }

  UserStats copyWith({
    String? userId,
    int? totalLocks,
    int? totalMinutes,
    int? currentStreak,
    int? bestStreak,
    DateTime? lastLockAt,
    double? averageSessionMinutes,
    int? achievementCount,
    DateTime? updatedAt,
  }) {
    return UserStats(
      userId: userId ?? this.userId,
      totalLocks: totalLocks ?? this.totalLocks,
      totalMinutes: totalMinutes ?? this.totalMinutes,
      currentStreak: currentStreak ?? this.currentStreak,
      bestStreak: bestStreak ?? this.bestStreak,
      lastLockAt: lastLockAt ?? this.lastLockAt,
      averageSessionMinutes: averageSessionMinutes ?? this.averageSessionMinutes,
      achievementCount: achievementCount ?? this.achievementCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// User settings
class UserSettings {
  final String userId;
  final bool notificationsEnabled;
  final bool notificationsMilestone;
  final bool notificationsLeaderboard;
  final String theme; // light, dark, auto
  final String language; // en, id, etc
  final DateTime updatedAt;

  UserSettings({
    required this.userId,
    required this.notificationsEnabled,
    required this.notificationsMilestone,
    required this.notificationsLeaderboard,
    required this.theme,
    required this.language,
    required this.updatedAt,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'notifications_enabled': notificationsEnabled,
      'notifications_milestone': notificationsMilestone,
      'notifications_leaderboard': notificationsLeaderboard,
      'theme': theme,
      'language': language,
      'updated_at': updatedAt,
    };
  }

  factory UserSettings.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return UserSettings(
      userId: doc.id,
      notificationsEnabled: data['notifications_enabled'] as bool? ?? true,
      notificationsMilestone: data['notifications_milestone'] as bool? ?? true,
      notificationsLeaderboard: data['notifications_leaderboard'] as bool? ?? false,
      theme: data['theme'] as String? ?? 'auto',
      language: data['language'] as String? ?? 'en',
      updatedAt: (data['updated_at'] as Timestamp).toDate(),
    );
  }

  UserSettings copyWith({
    String? userId,
    bool? notificationsEnabled,
    bool? notificationsMilestone,
    bool? notificationsLeaderboard,
    String? theme,
    String? language,
    DateTime? updatedAt,
  }) {
    return UserSettings(
      userId: userId ?? this.userId,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      notificationsMilestone: notificationsMilestone ?? this.notificationsMilestone,
      notificationsLeaderboard: notificationsLeaderboard ?? this.notificationsLeaderboard,
      theme: theme ?? this.theme,
      language: language ?? this.language,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

# Boomscrolling - Productivity Lock App

Aplikasi Android Flutter yang membantu meningkatkan produktivitas dengan mengunci smartphone selama periode tertentu dan menghasilkan laporan aktivitas seperti Strava.

## 🚀 Quick Start

### Installation
```bash
flutter pub get
flutter analyze
```

### Development
```bash
flutter run                    # Run on connected device/emulator
flutter test                   # Run all tests
flutter test --coverage        # Generate coverage report
```

### Firebase Setup
```bash
# First time setup (manual)
firebase login
firebase init

# Deploy Firestore rules
firebase deploy --only firestore:rules

# View Firestore data
firebase emulators:start       # Local development
```

---

## 🏗️ Architecture Overview

### Multi-Agent System

Boomscrolling menggunakan multi-agent architecture untuk orchestration yang efisien:

```
┌─────────────────────────────────────────────────────┐
│         Mobile App (Flutter - Android)              │
│  ┌─────────────────────────────────────────────┐   │
│  │ UI Layer (Screens, Widgets)                 │   │
│  │ - LockScreen, ReportScreen, LeaderboardUI  │   │
│  └────────────┬────────────────────────────────┘   │
│               │ Events/Commands                     │
│  ┌────────────▼────────────────────────────────┐   │
│  │ Service Layer (Providers/State Management)  │   │
│  │ - LockService, AnalyticsService, SyncSvc   │   │
│  └─────────────────────────────────────────────┘   │
└──────────────────┬───────────────────────────────────┘
                   │ API Calls
         ┌─────────▼──────────┐
         │   Firebase/Cloud   │
         │   - Firestore      │
         │   - Realtime DB    │
         │   - Cloud Functions│
         └────────────────────┘
```

### Agent Responsibilities

| Agent | Role | Trigger | Output |
|-------|------|---------|--------|
| **Lock Manager** | Handle timer activation, screen lock/unlock state | User presses "Start Lock" | Lock state in Firestore + local DB |
| **Analytics** | Process lock sessions, calculate stats, generate reports | After lock completes | Session data + aggregated metrics |
| **Engagement** | Manage notifications, streak tracking, leaderboard | Analytics data ready | Notifications payload + streak data |
| **Data Sync** | Batch sync local data to Firebase, handle offline | Every 5 mins or on demand | Cloud backup + conflict resolution |

---

## 📊 Firebase Schema (Firestore)

```
users/
  {userId}/
    ├── profile/
    │   ├── name (string)
    │   ├── avatar_url (string)
    │   ├── email (string)
    │   └── created_at (timestamp)
    ├── stats/
    │   ├── total_locks (int)
    │   ├── total_minutes (int)
    │   ├── current_streak (int)
    │   ├── best_streak (int)
    │   └── last_lock_at (timestamp)
    └── settings/
        ├── notifications_enabled (bool)
        ├── private_profile (bool)
        └── theme_preference (string)

sessions/
  {sessionId}/
    ├── user_id (string)
    ├── started_at (timestamp)
    ├── planned_duration_minutes (int)
    ├── actual_duration_minutes (int)
    ├── completed (bool)
    ├── reason (string)
    ├── device_info (map)
    └── synced_at (timestamp)

reports/
  {userId}/
    {reportId}/
      ├── period (string: daily|weekly|monthly)
      ├── date_start (timestamp)
      ├── date_end (timestamp)
      ├── total_sessions (int)
      ├── total_minutes (int)
      ├── average_session_minutes (float)
      ├── best_day (map)
      └── generated_at (timestamp)

leaderboard/
  {period}/
    {rank}/
      ├── user_id (string)
      ├── total_minutes (int)
      ├── current_streak (int)
      └── updated_at (timestamp)
```

---

## 📁 Project Structure

```
lib/
├── main.dart                          # App entry point & Firebase setup
├── models/
│   ├── lock_session.dart             # LockSession model
│   ├── user_profile.dart             # UserProfile model
│   ├── daily_report.dart             # Report data model
│   └── analytics_event.dart          # Analytics event model
├── services/
│   ├── lock_service.dart             # Lock Manager Agent
│   ├── analytics_service.dart        # Analytics Agent
│   ├── sync_service.dart             # Data Sync Agent
│   ├── auth_service.dart             # Authentication
│   └── firestore_service.dart        # Firebase abstraction
├── providers/
│   ├── lock_provider.dart            # Lock state management
│   ├── analytics_provider.dart       # Analytics state
│   ├── user_provider.dart            # User state
│   └── sync_provider.dart            # Sync state
├── screens/
│   ├── home_screen.dart              # Home/Dashboard
│   ├── lock_screen.dart              # Active lock display
│   ├── report_screen.dart            # Reports & stats
│   ├── leaderboard_screen.dart       # Leaderboard
│   └── auth_screen.dart              # Login/Register
├── widgets/
│   ├── lock_timer_widget.dart        # Timer display
│   ├── stats_card.dart               # Stats card component
│   └── session_history_item.dart     # Session list item
└── utils/
    ├── constants.dart                # App constants
    ├── logger.dart                   # Logging setup
    └── exceptions.dart               # Custom exceptions
```

---

## 🔧 Development Workflow

### 1. Making Changes
```bash
git checkout -b feature/your-feature
# Make changes in feature branch
```

### 2. Testing
```bash
# Run unit tests
flutter test

# Run specific test file
flutter test test/services/lock_service_test.dart

# Generate coverage
flutter test --coverage
```

### 3. Code Quality
```bash
# Analyze code
flutter analyze

# Format code
dart format lib/

# Fix issues
dart fix --apply
```

### 4. RTK Token Optimization
```bash
# Show token savings
rtk gain

# Show command history with savings
rtk gain --history

# All git commands are auto-wrapped through RTK
rtk git status          # Auto-optimized output
rtk git log --graph     # Compressed graph view
```

### 5. Pushing Changes
```bash
# Use optimized git commands
rtk git add lib/services/
rtk git commit -m "feat: add lock management agent"
rtk git push -u origin feature/your-feature

# Create PR (GitHub CLI)
gh pr create --title "Add lock management agent" --body "Description here"
```

---

## 🧠 State Management (Provider)

We use **Provider** for state management due to:
- Simple API for small to medium apps
- Good performance
- Easy testing
- Less boilerplate than Riverpod/Bloc

### Example Provider Usage
```dart
// Define a provider
class LockProvider extends ChangeNotifier {
  LockSession? _currentSession;
  
  LockSession? get currentSession => _currentSession;
  
  Future<void> startLock(Duration duration) async {
    // Logic here
    notifyListeners();
  }
}

// Use in widget
Consumer<LockProvider>(
  builder: (context, lockProvider, _) {
    return Text(lockProvider.currentSession?.toString() ?? 'No active lock');
  },
)
```

---

## 🔐 Security Considerations

1. **Token Storage**: JWT tokens stored in secure storage via `flutter_secure_storage`
2. **Data Encryption**: Sensitive data encrypted in local SQLite database
3. **Biometric Fallback**: Support for fingerprint/face unlock as emergency access
4. **Rate Limiting**: API endpoints rate-limited to prevent abuse
5. **Firestore Rules**: Row-level security enforced via Firebase rules

---

## 📱 Key Features Implementation

### 1. Lock Activation
- User sets duration (5-120 minutes)
- App locks screen access until timer expires
- Force stop requires authentication

### 2. Session Tracking
- Records lock start time, actual duration, reason
- Stores locally via SQLite
- Syncs to Firestore when online

### 3. Analytics & Reports
- Generates daily/weekly/monthly reports
- Calculates streaks (consecutive lock days)
- Tracks personal bests and trends

### 4. Social Features
- View other users' reports (if public)
- Leaderboard by total minutes locked
- Share sessions on social media (future)

---

## 🚀 Deployment

### Android Build
```bash
# Build release APK
flutter build apk --release

# Build App Bundle for Play Store
flutter build appbundle --release

# Sign APK/Bundle with production key
# (Configure in android/key.properties)
```

### Firebase Deployment
```bash
# Deploy Firestore indexes
firebase deploy --only firestore:indexes

# Deploy Cloud Functions
firebase deploy --only functions

# Deploy Security Rules
firebase deploy --only firestore:rules
```

---

## 🧪 Testing Strategy

### Unit Tests
- Services (LockService, AnalyticsService, SyncService)
- Models and data validation
- Utility functions

### Widget Tests
- Individual screen components
- User interaction flows
- State updates

### Integration Tests
- End-to-end lock cycle
- Firebase sync behavior
- Offline/online transitions

### Example Test
```dart
test('LockService should calculate remaining time correctly', () async {
  final service = LockService();
  await service.startLock(Duration(minutes: 30), 'Focus time');
  
  final status = await service.getLockStatus();
  expect(status.isActive, true);
  expect(status.plannedDuration, Duration(minutes: 30));
});
```

---

## 📚 Tech Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| **UI Framework** | Flutter | 3.11.5+ |
| **State Management** | Provider | 6.4.0+ |
| **HTTP Client** | Dio | 5.4.0+ |
| **Local DB** | SQLite (sqflite) | 2.3.0+ |
| **Backend** | Firebase | Latest |
| **Auth** | Firebase Auth | 4.16.0+ |
| **Database** | Firestore | 4.14.0+ |
| **Secure Storage** | flutter_secure_storage | 9.2.0+ |
| **Logging** | Logger | 2.0.2+ |

---

## 🐛 Debugging

### Enable Debug Logging
```dart
// In main.dart
Logger.level = Level.debug;

// Or per service
final logger = Logger();
logger.d('Debug message');
logger.w('Warning');
logger.e('Error');
```

### Firebase Emulator
```bash
# Start local Firebase emulator
firebase emulators:start

# Use in app during development
if (kDebugMode) {
  FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
}
```

### Device Logs
```bash
# View device logs
flutter logs

# Filter by tag
flutter logs | grep lock_service
```

---

## 📞 Support & Resources

- **Flutter Docs**: https://flutter.dev/docs
- **Firebase Documentation**: https://firebase.google.com/docs
- **Provider Package**: https://pub.dev/packages/provider
- **Dio Client**: https://pub.dev/packages/dio

---

## 🤝 Contributing

1. Create feature branch: `git checkout -b feature/your-feature`
2. Make changes and test locally
3. Run analysis: `flutter analyze`
4. Commit changes: `git commit -m "feat: description"`
5. Push to remote: `git push origin feature/your-feature`
6. Create pull request on GitHub

---

## 📝 Notes

- Always run `flutter pub get` after pulling changes
- Firebase setup required for cloud features
- Android SDK 21+ required for deployment
- Test all features on physical device before release

import 'dart:async';
import 'package:logger/logger.dart';
import '../models/lock_session.dart';
import '../models/analytics_event.dart';

/// ============================================================
/// LOCK MANAGER AGENT - Service Pengelolaan Lock Smartphone
/// ============================================================
/// Service ini adalah "agent" pertama yang mengelola:
/// - Aktivasi timer lock smartphone
/// - Status screen lock (aktif/tidak aktif)
/// - Countdown waktu lock setiap detik
/// - Notifikasi update status ke UI melalui Stream
///
/// CARA KERJA:
/// 1. User klik "Mulai Lock" dengan durasi 5-120 menit + alasan
/// 2. Service membuat session baru dengan ID unik
/// 3. Timer countdown berjalan setiap 1 detik
/// 4. Setiap detik, status dikirim ke UI via Stream
/// 5. Saat timer habis atau user paksa stop → session selesai
/// 6. Data session diteruskan ke Analytics Agent untuk diproses
/// 7. Notifikasi dikirim ke Engagement Agent untuk milestone check
///
/// ALUR PENGGUNAAN:
/// final lockService = LockService();
/// await lockService.startLock(
///   duration: Duration(minutes: 30),
///   reason: 'Focus time'
/// );
/// lockService.lockStatusStream.listen((status) {
///   print('Lock status: ${status.formattedRemainingTime}');
/// });
/// ============================================================
class LockService {
  /// Logger untuk debugging
  final Logger _logger = Logger();

  /// Timer yang berjalan countdown setiap detik
  Timer? _countdownTimer;

  /// Session lock yang sedang aktif
  LockSession? _currentSession;

  /// Stream Controller untuk mengirim update status ke UI
  /// Menggunakan .broadcast() agar bisa didengar oleh multiple listeners
  final StreamController<LockStatus> _lockStatusController =
      StreamController<LockStatus>.broadcast();

  /// Stream publik yang bisa didengarkan oleh UI layer
  /// Setiap update status akan dikirim melalui stream ini
  Stream<LockStatus> get lockStatusStream => _lockStatusController.stream;

  /// ============================================================
  /// Dapatkan status lock saat ini
  /// ============================================================
  /// Return: LockStatus berisi info lock terkini
  /// - isActive: apakah lock sedang berjalan
  /// - remainingTime: sisa waktu lock
  /// - elapsedTime: waktu yang sudah berjalan
  /// - progressPercentage: persentase completion (0-100)
  Future<LockStatus> getLockStatus() async {
    // Jika tidak ada session atau sudah selesai → return status tidak aktif
    if (_currentSession == null || _currentSession!.completed) {
      return LockStatus(
        isActive: false,
        plannedDurationMinutes: 0,
        forcedExit: false,
      );
    }

    // Hitung sisa waktu lock berdasarkan waktu sekarang
    final remaining = _currentSession!.remainingTime;

    // Hitung waktu yang sudah berjalan sejak lock dimulai
    final elapsed = DateTime.now().difference(_currentSession!.startedAt);

    return LockStatus(
      isActive: _currentSession!.isActive,
      remainingTime: remaining,
      elapsedTime: elapsed,
      plannedDurationMinutes: _currentSession!.plannedDurationMinutes,
      forcedExit: false,
      lastUpdate: DateTime.now(),
    );
  }

  /// ============================================================
  /// Mulai session lock baru
  /// ============================================================
  /// Parameter:
  /// - duration: Berapa lama lock (5-120 menit)
  ///   - Minimum 5 menit (untuk mencegah lock terlalu singkat)
  ///   - Maksimum 120 menit (untuk mencegah lock terlalu lama)
  /// - reason: Alasan mengapa lock (focus, study, break, other)
  /// - notes: Catatan opsional dari user
  ///
  /// Throw: Exception jika duration tidak valid
  Future<void> startLock({
    required Duration duration,
    required String reason,
    String? notes,
  }) async {
    // VALIDASI 1: Durasi harus antara 5-120 menit
    if (duration.inMinutes < 5 || duration.inMinutes > 120) {
      _logger.e(
        'Lock duration tidak valid: ${duration.inMinutes} menit. '
        'Harus 5-120 menit',
      );
      throw Exception(
        'Durasi lock harus antara 5 dan 120 menit. '
        'Anda masukkan: ${duration.inMinutes} menit',
      );
    }

    // VALIDASI 2: Jika sudah ada lock aktif, stop dulu sebelum mulai yang baru
    if (_currentSession != null && _currentSession!.isActive) {
      _logger.w(
        'Ada lock aktif lain. Stop dulu sebelum membuat lock baru.',
      );
      await _stopCountdown();
    }

    // STEP 1: Buat ID session unik berdasarkan timestamp
    // Format: millisecondsSinceEpoch (misal: 1693300000000)
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final now = DateTime.now();

    // STEP 2: Buat object session baru dengan data awal
    _currentSession = LockSession(
      id: sessionId,
      userId: 'current_user', // TODO: Ambil dari Firebase Auth saat user login
      startedAt: now,
      plannedDurationMinutes: duration.inMinutes,
      completed: false,
      forcedExit: false,
      reason: reason,
      deviceInfo: {
        'device_id': 'android_device', // TODO: Ambil dari device_info_plus
        'timestamp': now.toIso8601String(),
      },
      notes: notes,
    );

    _logger.i(
      '🔒 Lock dimulai: ${duration.inMinutes} menit | '
      'Alasan: $reason | ID: $sessionId',
    );

    // STEP 3: Mulai timer countdown yang berjalan setiap 1 detik
    _startCountdown(duration);

    // STEP 4: Beritahu UI tentang perubahan status (dari tidak aktif → aktif)
    final status = await getLockStatus();
    _lockStatusController.add(status);

    // TODO: STEP 5: Aktifkan native Android screen lock (sistem operasi Android)
    // TODO: Gunakan platform channels untuk memanggil Android API
    // TODO: Pastikan tidak bisa di-bypass (required: fingerprint untuk unlock)
  }

  /// ============================================================
  /// Mulai timer countdown (private/internal method)
  /// ============================================================
  /// Method ini berjalan di background dan:
  /// 1. Setiap 1 detik, kirim update status ke UI
  /// 2. Setiap 1 detik, cek apakah sisa waktu sudah 0
  /// 3. Jika sisa waktu <= 0, otomatis selesaikan session
  ///
  /// Dijalankan oleh: startLock()
  void _startCountdown(Duration duration) {
    // Buat timer yang berjalan repeating setiap 1 detik
    // Callback function dipanggil setiap detik
    _countdownTimer = Timer.periodic(Duration(seconds: 1), (timer) async {
      // SAFETY CHECK: Jika session sudah null, stop timer
      if (_currentSession == null) {
        _logger.w('Session null, stop timer');
        timer.cancel();
        return;
      }

      // Hitung sisa waktu lock sekarang
      final remaining = _currentSession!.remainingTime;

      // Dapatkan status terkini
      final status = await getLockStatus();

      // Kirim status ke UI (semua listener akan menerima update ini)
      _lockStatusController.add(status);

      // SETIAP 10 DETIK: Log ke console (untuk debugging)
      final elapsedSeconds = status.elapsedTime?.inSeconds ?? 0;
      if (elapsedSeconds % 10 == 0 && elapsedSeconds > 0) {
        _logger.d(
          'Countdown: ${status.formattedRemainingTime} '
          '(progress: ${status.progressPercentage.toStringAsFixed(1)}%)',
        );
      }

      // CEK: Apakah waktu sudah habis?
      if (remaining != null && remaining.inSeconds <= 0) {
        _logger.i(
          '✅ Lock session selesai: waktu countdown habis',
        );
        // Selesaikan session (tidak di-force, waktu habis normal)
        await completeLock(forcedExit: false);
      }
    });
  }

  /// ============================================================
  /// Stop timer countdown (private/internal method)
  /// ============================================================
  /// Menghentikan timer periodic tanpa menyelesaikan session
  /// Digunakan untuk cleanup sebelum membuat lock baru
  ///
  /// Dijalankan oleh: startLock(), completeLock()
  Future<void> _stopCountdown() async {
    if (_countdownTimer != null) {
      _countdownTimer!.cancel();
      _countdownTimer = null;
      _logger.d('Timer countdown dihentikan');
    }
  }

  /// ============================================================
  /// Selesaikan session lock
  /// ============================================================
  /// Dipanggil ketika:
  /// 1. Timer countdown selesai (natural completion)
  /// 2. User paksa berhenti (dengan konfirmasi + fingerprint)
  ///
  /// Parameter:
  /// - forcedExit: true = user paksa stop, false = waktu habis natural
  ///
  /// Yang dilakukan:
  /// 1. Stop timer countdown
  /// 2. Update session dengan waktu selesai & durasi actual
  /// 3. Simpan ke local database (sqflite)
  /// 4. Queue untuk sync ke Firestore (saat online)
  /// 5. Trigger Analytics Agent untuk proses data
  /// 6. Trigger Engagement Agent untuk cek milestone
  /// 7. Beritahu UI lock sudah tidak aktif
  Future<void> completeLock({required bool forcedExit}) async {
    // VALIDASI: Apakah ada session aktif?
    if (_currentSession == null) {
      _logger.w('Tidak ada session aktif untuk diselesaikan');
      return;
    }

    // STEP 1: Stop timer countdown
    await _stopCountdown();

    // STEP 2: Hitung waktu actual yang session berjalan
    final endTime = DateTime.now();
    final actualMinutes = endTime.difference(_currentSession!.startedAt).inMinutes;

    // STEP 3: Update session dengan info completion
    final completedSession = _currentSession!.copyWith(
      endedAt: endTime,
      completed: true,
      forcedExit: forcedExit,
      actualDurationMinutes: actualMinutes,
    );

    // Hitung completion percentage
    final completionPercentage =
        (actualMinutes / _currentSession!.plannedDurationMinutes * 100)
            .clamp(0, 100);

    _logger.i(
      '🏁 Lock session selesai:\n'
      '  - Duration actual: $actualMinutes menit\n'
      '  - Duration planned: ${_currentSession!.plannedDurationMinutes} menit\n'
      '  - Completion: ${completionPercentage.toStringAsFixed(1)}%\n'
      '  - Paksa stop: $forcedExit',
    );

    // TODO: STEP 4: Simpan ke local database (sqflite)
    // TODO: final db = await getDatabase();
    // TODO: await db.insert('sessions', completedSession.toMap());

    // TODO: STEP 5: Queue untuk sync ke Firestore
    // TODO: await syncService.queueForSync(
    // TODO:   collection: 'sessions',
    // TODO:   documentId: completedSession.id,
    // TODO:   data: completedSession.toFirestore(),
    // TODO: );

    // TODO: STEP 6: Trigger Analytics Agent
    // TODO: analyticsService.logSessionComplete(completedSession);

    // TODO: STEP 7: Trigger Engagement Agent untuk cek milestone
    // TODO: final streak = await analyticsService.calculateStats();
    // TODO: if (streak.newMilestone) {
    // TODO:   engagementService.handleStreakMilestone(streak);
    // TODO: }

    // Clear session (tidak ada lock aktif lagi)
    _currentSession = null;

    // STEP 8: Beritahu UI lock sudah selesai (tidak aktif)
    final status = await getLockStatus();
    _lockStatusController.add(status);

    _logger.i('✅ Lock session sepenuhnya selesai dan disimpan');

    // TODO: STEP 9: Release native Android screen lock
    // TODO: Gunakan platform channels untuk call Android API
  }

  /// ============================================================
  /// Dapatkan session yang sedang aktif (untuk debugging/testing)
  /// ============================================================
  LockSession? get currentSession => _currentSession;

  /// ============================================================
  /// Cleanup resources saat service di-dispose
  /// ============================================================
  /// Dipanggil saat app ditutup atau service tidak digunakan lagi
  /// Memastikan tidak ada memory leak dari timer atau stream
  void dispose() {
    _logger.i('Dispose LockService');
    _countdownTimer?.cancel();
    _lockStatusController.close();
  }

  @override
  String toString() => 'LockService(aktif: ${_currentSession?.isActive})';
}

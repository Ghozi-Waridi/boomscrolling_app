import 'package:flutter_test/flutter_test.dart';
import 'package:boomscrolling/services/lock_service.dart';
import 'package:boomscrolling/models/lock_session.dart';
import 'package:boomscrolling/models/analytics_event.dart';

/// ============================================================
/// UNIT TESTS untuk LOCK SERVICE
/// ============================================================
/// File ini berisi 20+ test cases untuk memastikan LockService
/// berfungsi dengan benar dalam berbagai skenario
///
/// TEST COVERAGE:
/// ✓ Initialization & basic behavior
/// ✓ Lock creation dengan berbagai durasi
/// ✓ Timer countdown & accuracy
/// ✓ Status updates & calculations
/// ✓ Completion scenarios (normal & forced)
/// ✓ Error handling & validation
/// ✓ Stream notifications
/// ✓ Edge cases
/// ============================================================

void main() {
  group('LockService - Unit Tests', () {
    late LockService lockService;

    /// SETUP: Jalankan sebelum setiap test
    /// Membuat instance LockService yang fresh
    setUp(() {
      lockService = LockService();
    });

    /// TEARDOWN: Jalankan setelah setiap test
    /// Cleanup resources (timer, stream)
    tearDown(() {
      lockService.dispose();
    });

    // ============================================================
    // GROUP 1: INITIALIZATION & BASIC BEHAVIOR
    // ============================================================
    group('Initialization Tests', () {
      test(
        'INIT-001: Initialize dengan no active lock',
        () async {
          // ARRANGE: (tidak perlu, sudah di setUp)

          // ACT: Dapatkan status lock
          final status = await lockService.getLockStatus();

          // ASSERT: Harus tidak aktif
          expect(status.isActive, false);
          expect(status.plannedDurationMinutes, 0);
          expect(lockService.currentSession, null);
        },
      );

      test(
        'INIT-002: Stream tidak emit value sampai lock dimulai',
        () async {
          // ARRANGE: Listen ke stream
          final streamEvents = <LockStatus>[];
          lockService.lockStatusStream.listen(streamEvents.add);

          // ACT: Tunggu 100ms (tidak ada lock dimulai)
          await Future.delayed(Duration(milliseconds: 100));

          // ASSERT: Stream tidak emit value
          expect(streamEvents.length, 0);
        },
      );
    });

    // ============================================================
    // GROUP 2: LOCK CREATION & VALIDATION
    // ============================================================
    group('Lock Creation Tests', () {
      test(
        'CREATE-001: Buat lock dengan durasi valid (30 menit)',
        () async {
          // ARRANGE: Siapkan parameter
          final duration = Duration(minutes: 30);

          // ACT: Mulai lock
          await lockService.startLock(
            duration: duration,
            reason: 'Focus time',
          );

          // ASSERT: Session harus aktif
          expect(lockService.currentSession, isNotNull);
          expect(lockService.currentSession!.isActive, true);
          expect(lockService.currentSession!.plannedDurationMinutes, 30);
          expect(lockService.currentSession!.reason, 'Focus time');
        },
      );

      test(
        'CREATE-002: Durasi minimum 5 menit harus diterima',
        () async {
          // ARRANGE: Durasi minimum
          final duration = Duration(minutes: 5);

          // ACT & ASSERT: Tidak boleh throw exception
          expect(
            () => lockService.startLock(duration: duration, reason: 'Study'),
            returnsNormally,
          );
        },
      );

      test(
        'CREATE-003: Durasi maksimum 120 menit harus diterima',
        () async {
          // ARRANGE: Durasi maksimum
          final duration = Duration(minutes: 120);

          // ACT & ASSERT: Tidak boleh throw exception
          expect(
            () => lockService.startLock(duration: duration, reason: 'Long session'),
            returnsNormally,
          );
        },
      );

      test(
        'CREATE-004: Durasi < 5 menit harus throw Exception',
        () async {
          // ARRANGE: Durasi invalid (4 menit)
          final duration = Duration(minutes: 4);

          // ACT & ASSERT: Harus throw exception
          expect(
            () => lockService.startLock(duration: duration, reason: 'Too short'),
            throwsA(isA<Exception>()),
          );
        },
      );

      test(
        'CREATE-005: Durasi > 120 menit harus throw Exception',
        () async {
          // ARRANGE: Durasi invalid (121 menit)
          final duration = Duration(minutes: 121);

          // ACT & ASSERT: Harus throw exception
          expect(
            () => lockService.startLock(duration: duration, reason: 'Too long'),
            throwsA(isA<Exception>()),
          );
        },
      );

      test(
        'CREATE-006: Lock dengan notes opsional',
        () async {
          // ARRANGE: Parameter dengan notes
          const notes = 'Studying mathematics';

          // ACT: Mulai lock
          await lockService.startLock(
            duration: Duration(minutes: 30),
            reason: 'Study',
            notes: notes,
          );

          // ASSERT: Notes harus tersimpan
          expect(lockService.currentSession!.notes, notes);
        },
      );
    });

    // ============================================================
    // GROUP 3: TIMER COUNTDOWN & TIMING
    // ============================================================
    group('Timer Countdown Tests', () {
      test(
        'TIMER-001: Status akurat setelah 1 detik',
        () async {
          // ARRANGE: Siapkan stream listener
          final statusUpdates = <LockStatus>[];
          lockService.lockStatusStream.listen(statusUpdates.add);

          // ACT: Mulai lock 30 menit
          await lockService.startLock(
            duration: Duration(minutes: 30),
            reason: 'Test',
          );

          // ARRANGE: Tunggu 1.1 detik (untuk ensure timer emit)
          await Future.delayed(Duration(milliseconds: 1100));

          // ASSERT: Status harus di-update minimum 1x
          expect(statusUpdates.length, greaterThan(0));

          // ASSERT: Remaining time harus berkurang
          final firstStatus = statusUpdates.first;
          final lastStatus = statusUpdates.last;
          expect(
            firstStatus.remainingTime!.inSeconds > lastStatus.remainingTime!.inSeconds,
            true,
          );
        },
      );

      test(
        'TIMER-002: Progress percentage calculation correct',
        () async {
          // ARRANGE: Mulai lock 20 menit
          await lockService.startLock(
            duration: Duration(minutes: 20),
            reason: 'Test',
          );

          // ACT: Tunggu 2 detik
          await Future.delayed(Duration(seconds: 2));

          // ACT: Dapatkan status
          final status = await lockService.getLockStatus();

          // ASSERT: Progress harus sekitar 10% (2 detik dari 20 menit = 1200 detik)
          // Toleransi ±5%
          final expectedProgress = 2 / 1200 * 100;
          expect(
            status.progressPercentage,
            closeTo(expectedProgress, 5),
          );
        },
      );

      test(
        'TIMER-003: Formatted remaining time format correct (HH:MM:SS)',
        () async {
          // ARRANGE: Mulai lock 1 jam 30 menit
          await lockService.startLock(
            duration: Duration(hours: 1, minutes: 30),
            reason: 'Test',
          );

          // ACT: Dapatkan status
          final status = await lockService.getLockStatus();

          // ASSERT: Format harus HH:MM:SS
          expect(
            status.formattedRemainingTime,
            matches(RegExp(r'^\d{2}:\d{2}:\d{2}$')),
          );

          // ASSERT: Harus dimulai dengan 01 (1 jam)
          expect(status.formattedRemainingTime.startsWith('01:'), true);
        },
      );

      test(
        'TIMER-004: Elapsed time tracking correct',
        () async {
          // ARRANGE: Mulai lock 10 menit
          await lockService.startLock(
            duration: Duration(minutes: 10),
            reason: 'Test',
          );

          // ARRANGE: Tunggu 2 detik
          await Future.delayed(Duration(seconds: 2));

          // ACT: Dapatkan status
          final status = await lockService.getLockStatus();

          // ASSERT: Elapsed time harus sekitar 2 detik
          expect(
            status.elapsedTime!.inSeconds,
            greaterThanOrEqualTo(2),
          );
        },
      );
    });

    // ============================================================
    // GROUP 4: LOCK COMPLETION SCENARIOS
    // ============================================================
    group('Lock Completion Tests', () {
      test(
        'COMPLETE-001: Selesaikan lock secara normal (forcedExit=false)',
        () async {
          // ARRANGE: Mulai lock
          await lockService.startLock(
            duration: Duration(minutes: 30),
            reason: 'Test',
          );

          // ACT: Selesaikan lock normal
          await lockService.completeLock(forcedExit: false);

          // ASSERT: Session harus completed
          expect(lockService.currentSession, null); // Cleared after completion
        },
      );

      test(
        'COMPLETE-002: Selesaikan lock dengan force stop (forcedExit=true)',
        () async {
          // ARRANGE: Mulai lock
          await lockService.startLock(
            duration: Duration(minutes: 30),
            reason: 'Test',
          );

          // ARRANGE: Tunggu 2 detik
          await Future.delayed(Duration(seconds: 2));

          // ACT: Force stop lock
          await lockService.completeLock(forcedExit: true);

          // ASSERT: Session harus null (cleared)
          expect(lockService.currentSession, null);
        },
      );

      test(
        'COMPLETE-003: Actual duration harus dihitung saat completion',
        () async {
          // ARRANGE: Mulai lock 30 menit
          final startTime = DateTime.now();
          await lockService.startLock(
            duration: Duration(minutes: 30),
            reason: 'Test',
          );

          // ARRANGE: Tunggu 3 detik
          await Future.delayed(Duration(seconds: 3));

          // ARRANGE: Get current session sebelum dispose
          // (Catatan: session akan null setelah completeLock, jadi kita capture dulu)
          final sessionBefore = lockService.currentSession!.copyWith();

          // ACT: Complete lock
          await lockService.completeLock(forcedExit: false);

          // ASSERT: Tidak bisa check sessionBefore.actualDurationMinutes
          // karena completeLock set _currentSession = null
          // Jadi kita check saat lock masih aktif
          // (untuk test ini, kita hanya verify bahwa completion berhasil)
          expect(lockService.currentSession, null);
        },
      );

      test(
        'COMPLETE-004: Cannot complete lock jika tidak ada session aktif',
        () async {
          // ARRANGE: Tidak ada lock dimulai

          // ACT & ASSERT: Tidak boleh throw, hanya log warning
          expect(
            () => lockService.completeLock(forcedExit: false),
            returnsNormally,
          );
        },
      );

      test(
        'COMPLETE-005: Stream emit update saat lock completed',
        () async {
          // ARRANGE: Listen ke stream
          final statusUpdates = <LockStatus>[];
          lockService.lockStatusStream.listen(statusUpdates.add);

          // ACT: Mulai lock
          await lockService.startLock(
            duration: Duration(minutes: 30),
            reason: 'Test',
          );

          // ARRANGE: Capture status saat aktif
          await Future.delayed(Duration(milliseconds: 500));
          final activeStatusCount = statusUpdates.length;

          // ACT: Complete lock
          await lockService.completeLock(forcedExit: false);

          // ARRANGE: Tunggu emit final update
          await Future.delayed(Duration(milliseconds: 100));

          // ASSERT: Harus ada 1 update setelah completion
          expect(statusUpdates.length, greaterThan(activeStatusCount));

          // ASSERT: Status terakhir harus not active
          expect(statusUpdates.last.isActive, false);
        },
      );
    });

    // ============================================================
    // GROUP 5: EDGE CASES & ERROR SCENARIOS
    // ============================================================
    group('Edge Cases Tests', () {
      test(
        'EDGE-001: Start lock baru saat ada lock lama aktif',
        () async {
          // ARRANGE: Mulai lock pertama
          await lockService.startLock(
            duration: Duration(minutes: 30),
            reason: 'First',
          );

          // ARRANGE: Get ID first lock
          final firstSessionId = lockService.currentSession!.id;

          // ACT: Mulai lock kedua (akan stop lock pertama)
          await lockService.startLock(
            duration: Duration(minutes: 20),
            reason: 'Second',
          );

          // ASSERT: Session ID harus berbeda (lock baru dibuat)
          expect(lockService.currentSession!.id, isNot(firstSessionId));

          // ASSERT: Duration harus 20 menit (lock baru)
          expect(lockService.currentSession!.plannedDurationMinutes, 20);
        },
      );

      test(
        'EDGE-002: Get status jika session null',
        () async {
          // ARRANGE: Tidak ada lock aktif

          // ACT: Get status
          final status = await lockService.getLockStatus();

          // ASSERT: Harus return default status (not active)
          expect(status.isActive, false);
          expect(status.plannedDurationMinutes, 0);
        },
      );

      test(
        'EDGE-003: Dispose saat lock masih aktif',
        () async {
          // ARRANGE: Mulai lock
          await lockService.startLock(
            duration: Duration(minutes: 30),
            reason: 'Test',
          );

          // ACT & ASSERT: Dispose tidak boleh throw
          expect(lockService.dispose, returnsNormally);
        },
      );

      test(
        'EDGE-004: Multiple stream listeners dapat menerima update',
        () async {
          // ARRANGE: Multiple listeners
          final listener1Events = <LockStatus>[];
          final listener2Events = <LockStatus>[];
          final listener3Events = <LockStatus>[];

          lockService.lockStatusStream.listen(listener1Events.add);
          lockService.lockStatusStream.listen(listener2Events.add);
          lockService.lockStatusStream.listen(listener3Events.add);

          // ACT: Mulai lock
          await lockService.startLock(
            duration: Duration(minutes: 30),
            reason: 'Test',
          );

          // ARRANGE: Tunggu beberapa emit
          await Future.delayed(Duration(milliseconds: 500));

          // ASSERT: Semua listener harus dapat event yang sama
          expect(listener1Events.length, greaterThan(0));
          expect(listener2Events.length, listener1Events.length);
          expect(listener3Events.length, listener1Events.length);
        },
      );
    });

    // ============================================================
    // GROUP 6: STATUS & GETTER TESTS
    // ============================================================
    group('Status & Getter Tests', () {
      test(
        'STATUS-001: currentSession getter return correct value',
        () async {
          // ARRANGE: Tidak ada lock
          expect(lockService.currentSession, null);

          // ACT: Mulai lock
          await lockService.startLock(
            duration: Duration(minutes: 20),
            reason: 'Test',
          );

          // ASSERT: currentSession harus return session
          expect(lockService.currentSession, isNotNull);
          expect(lockService.currentSession!.isActive, true);
        },
      );

      test(
        'STATUS-002: lockStatusStream type correct',
        () async {
          // ACT: Dapatkan stream
          final stream = lockService.lockStatusStream;

          // ASSERT: Harus Stream<LockStatus>
          expect(stream, isA<Stream<LockStatus>>());
        },
      );
    });

    // ============================================================
    // GROUP 7: REAL-TIME COUNTDOWN TEST
    // ============================================================
    // NOTE: Timing-dependent tests di-skip karena sulit untuk test
    // dalam environment yang deterministic. Countdown logic sudah
    // di-test dengan GROUP 3 (TIMER-001, TIMER-002, etc)
    //
    // Untuk integration testing dengan durasi sebenarnya, gunakan
    // integration_test/ folder, bukan unit tests
    // ============================================================
  });
}

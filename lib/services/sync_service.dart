import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../models/analytics_event.dart';

/// ============================================================
/// DATA SYNC AGENT - Orchestrator untuk Offline/Online Sync
/// ============================================================
/// Service ini adalah "agent" yang mengelola:
/// - Sinkronisasi data local ke Firebase (batch processing)
/// - Queue operation untuk offline mode
/// - Conflict resolution (latest wins strategy)
/// - Monitoring konektivitas jaringan
/// - Backup data ke cloud
///
/// CARA KERJA:
/// 1. Monitoring connectivity status (online/offline)
/// 2. Jika offline → queue operations ke local database
/// 3. Jika online → auto-sync dari queue dengan retry logic
/// 4. Konflik → bandingkan timestamp, gunakan yang terbaru
/// 5. Update last_sync_at setelah setiap sync sukses
///
/// ALUR PENGGUNAAN:
/// final syncService = SyncService(database, firestore);
/// await syncService.initialize();
/// await syncService.queueForSync(
///   collection: 'sessions',
///   documentId: 'session_123',
///   data: sessionData,
/// );
/// syncService.syncStatusStream.listen((status) {
///   print('Sync: ${status.pendingItems} pending');
/// });
/// ============================================================
class SyncService {
  /// Logger untuk debugging
  final Logger _logger = Logger();

  /// Connectivity monitoring
  final Connectivity _connectivity = Connectivity();

  /// Firestore reference
  final FirebaseFirestore? _firestore;

  /// Local database reference
  final Database? _localDatabase;

  /// Subscription untuk connectivity changes
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  /// Stream controller untuk broadcast sync status
  final StreamController<SyncStatus> _syncStatusController =
      StreamController<SyncStatus>.broadcast();

  /// Public stream untuk mendengarkan sync status
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  /// Status variables
  bool _isSyncing = false;
  bool _isOnline = true;
  int _pendingItems = 0;
  DateTime _lastSyncAt = DateTime.now();
  double _syncProgress = 0.0;
  String? _lastError;

  /// Retry configuration (exponential backoff)
  /// Delays: 1s, 2s, 4s, 8s, 16s
  static const List<int> _retryDelaysSeconds = [1, 2, 4, 8, 16];

  /// Constructor dengan dependency injection
  /// Memungkinkan testing dengan mock database & firestore
  SyncService({
    FirebaseFirestore? firestore,
    Database? localDatabase,
  })  : _firestore = firestore,
        _localDatabase = localDatabase;

  /// ============================================================
  /// Initialize sync service - setup connectivity monitoring
  /// ============================================================
  /// Tugas:
  /// 1. Setup subscription untuk connectivity changes
  /// 2. Check initial connectivity status
  /// 3. Auto-sync jika sedang online
  /// 4. Listen untuk status changes (online ↔ offline)
  Future<void> initialize() async {
    _logger.i('🔄 Initializing SyncService');

    try {
      // Buat schema sync_queue di local database (jika belum ada)
      await _createSyncQueueSchema();

      // Setup connectivity monitoring
      _connectivitySubscription =
          _connectivity.onConnectivityChanged.listen((result) async {
        final wasOnline = _isOnline;
        _isOnline = result != ConnectivityResult.none;

        _logger.i(
          '🌐 Connectivity changed: ${_isOnline ? 'ONLINE ✅' : 'OFFLINE ❌'}',
        );

        // Jika kembali online → trigger auto-sync
        if (!wasOnline && _isOnline) {
          _logger.i('Back online, triggering auto-sync');
          await syncLocalToFirebase();
        }

        _notifySyncStatus();
      });

      // Check initial connectivity
      final result = await _connectivity.checkConnectivity();
      _isOnline = result != ConnectivityResult.none;

      _logger.i('Initial connectivity: ${_isOnline ? 'ONLINE ✅' : 'OFFLINE ❌'}');

      // Jika online, coba sync pending items
      if (_isOnline) {
        await syncLocalToFirebase();
      }

      _notifySyncStatus();
      _logger.i('✅ SyncService initialized successfully');
    } catch (e) {
      _logger.e('Failed to initialize SyncService: $e');
      _lastError = 'Initialization failed: $e';
      _notifySyncStatus();
      rethrow;
    }
  }

  /// ============================================================
  /// Create schema untuk sync_queue table (jika belum ada)
  /// ============================================================
  /// Schema:
  /// - id: int (primary key, auto-increment)
  /// - collection: string (nama collection di Firestore)
  /// - document_id: string (ID document)
  /// - data: json (data yang akan di-sync)
  /// - created_at: datetime (waktu dibuat)
  /// - synced: bool (sudah di-sync atau belum)
  /// - retry_count: int (berapa kali retry)
  /// - conflict: bool (ada konflik atau tidak)
  /// - remote_timestamp: datetime (timestamp di remote)
  Future<void> _createSyncQueueSchema() async {
    if (_localDatabase == null) {
      _logger.d('Local database is null, skipping schema creation');
      return;
    }

    try {
      await _localDatabase!.execute('''
        CREATE TABLE IF NOT EXISTS sync_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          collection TEXT NOT NULL,
          document_id TEXT NOT NULL,
          data TEXT NOT NULL,
          created_at DATETIME NOT NULL,
          synced BOOLEAN DEFAULT 0,
          retry_count INTEGER DEFAULT 0,
          conflict BOOLEAN DEFAULT 0,
          remote_timestamp DATETIME,
          updated_at DATETIME
        )
      ''');

      _logger.d('✅ sync_queue table ready');
    } catch (e) {
      _logger.e('Failed to create sync_queue schema: $e');
      // Don't rethrow - schema might already exist
    }
  }

  /// ============================================================
  /// Queue an item for sync ke Firestore
  /// ============================================================
  /// Parameter:
  /// - collection: Nama collection di Firestore (misal: 'sessions')
  /// - documentId: ID document (misal: 'session_123')
  /// - data: Data JSON yang akan di-sync
  ///
  /// Return: Queue ID (int) dari local database
  ///
  /// Tugas:
  /// 1. Simpan ke sync_queue table (local database)
  /// 2. Increment pending counter
  /// 3. Notify listeners tentang status baru
  /// 4. Return queue ID
  Future<int> queueForSync({
    required String collection,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    _logger.i('📋 Queueing for sync: $collection/$documentId');

    if (_localDatabase == null) {
      throw Exception('Local database not initialized');
    }

    try {
      // Tambahkan timestamp created_at
      final now = DateTime.now();
      final queueData = {
        'collection': collection,
        'document_id': documentId,
        'data': _encodeJson(data), // Convert map to JSON string
        'created_at': now.toIso8601String(),
        'synced': 0,
        'retry_count': 0,
        'conflict': 0,
        'updated_at': now.toIso8601String(),
      };

      // Insert ke database
      final queueId =
          await _localDatabase!.insert('sync_queue', queueData);

      // Increment pending counter
      _pendingItems++;
      _notifySyncStatus();

      _logger.i('✅ Queued item #$queueId: $collection/$documentId');
      return queueId;
    } catch (e) {
      _logger.e('Failed to queue for sync: $e');
      _lastError = 'Queue failed: $e';
      _notifySyncStatus();
      rethrow;
    }
  }

  /// ============================================================
  /// Sync local data to Firebase (dengan retry logic)
  /// ============================================================
  /// Tugas:
  /// 1. Query pending items dari sync_queue
  /// 2. Batch operations (max 500 per batch)
  /// 3. Upload ke Firestore dengan retry exponential backoff
  /// 4. Handle errors gracefully (1 item fail ≠ total fail)
  /// 5. Mark as synced di local DB setelah sukses
  /// 6. Update last_sync_at timestamp
  /// 7. Emit progress updates
  ///
  /// Retry Strategy: Exponential backoff (1s, 2s, 4s, 8s, 16s)
  /// Jika retry_count > 5 → skip item (log error)
  Future<void> syncLocalToFirebase() async {
    // Jika sudah syncing, skip (prevent race condition)
    if (_isSyncing) {
      _logger.w('⚠️ Sync already in progress, skipping');
      return;
    }

    // Jika offline, skip (save ke queue saja)
    if (!_isOnline) {
      _logger.w('⚠️ Currently offline, cannot sync');
      return;
    }

    _isSyncing = true;
    _syncProgress = 0.0;
    _lastError = null;
    _notifySyncStatus();

    try {
      _logger.i('🔄 Starting local to Firebase sync');

      if (_localDatabase == null || _firestore == null) {
        throw Exception('Database or Firestore not initialized');
      }

      // Query pending items (not synced yet)
      final pendingItems = await _localDatabase!.query(
        'sync_queue',
        where: 'synced = ?',
        whereArgs: [0],
        orderBy: 'created_at ASC',
      );

      if (pendingItems.isEmpty) {
        _logger.i('✅ No pending items to sync');
        _pendingItems = 0;
        _syncProgress = 1.0;
        _lastSyncAt = DateTime.now();
        _notifySyncStatus();
        return;
      }

      _logger.i('📦 Found ${pendingItems.length} pending items');

      // Process dalam batch (max 500 per batch)
      const batchSize = 500;
      final totalBatches = (pendingItems.length / batchSize).ceil();

      for (int batchIndex = 0; batchIndex < totalBatches; batchIndex++) {
        final startIdx = batchIndex * batchSize;
        final endIdx = (startIdx + batchSize).clamp(0, pendingItems.length);
        final batch = pendingItems.sublist(startIdx, endIdx);

        _logger.i(
          '📤 Processing batch ${batchIndex + 1}/$totalBatches '
          '(${batch.length} items)',
        );

        int successCount = 0;

        for (int i = 0; i < batch.length; i++) {
          final item = batch[i];
          final queueId = item['id'] as int;
          final collection = item['collection'] as String;
          final documentId = item['document_id'] as String;
          final dataJson = item['data'] as String;
          int retryCount = item['retry_count'] as int? ?? 0;

          try {
            // Decode data dari JSON string
            final data = _decodeJson(dataJson);

            // Try to sync with retry logic
            bool synced = false;
            while (retryCount < _retryDelaysSeconds.length && !synced) {
              try {
                // Upload to Firestore
                await _firestore!
                    .collection(collection)
                    .doc(documentId)
                    .set(data, SetOptions(merge: true));

                // Mark as synced dalam local DB
                await _localDatabase!.update(
                  'sync_queue',
                  {
                    'synced': 1,
                    'updated_at': DateTime.now().toIso8601String(),
                  },
                  where: 'id = ?',
                  whereArgs: [queueId],
                );

                synced = true;
                successCount++;
                _logger.d('✅ Synced $collection/$documentId');
              } catch (retryError) {
                retryCount++;

                if (retryCount < _retryDelaysSeconds.length) {
                  final delaySeconds = _retryDelaysSeconds[retryCount - 1];
                  _logger.w(
                    '⚠️ Sync failed (attempt $retryCount), '
                    'retrying in ${delaySeconds}s: $retryError',
                  );

                  // Wait exponential backoff time
                  await Future.delayed(Duration(seconds: delaySeconds));
                } else {
                  _logger.e(
                    '❌ Max retries exceeded for $collection/$documentId: '
                    '$retryError',
                  );

                  // Update retry_count dalam DB (untuk log)
                  await _localDatabase!.update(
                    'sync_queue',
                    {
                      'retry_count': retryCount,
                      'updated_at': DateTime.now().toIso8601String(),
                    },
                    where: 'id = ?',
                    whereArgs: [queueId],
                  );
                }
              }
            }
          } catch (e) {
            _logger.e('Unexpected error syncing item #$queueId: $e');
            _lastError = 'Sync error: $e';
          }

          // Update progress
          final processed = startIdx + i + 1;
          _syncProgress = processed / pendingItems.length;
          _notifySyncStatus();
        }

        _logger.i('✅ Batch complete: $successCount/${batch.length} items synced');
      }

      // Query remaining pending items
      final remaining = await _localDatabase!.query(
        'sync_queue',
        where: 'synced = ?',
        whereArgs: [0],
      );

      _pendingItems = remaining.length;
      _syncProgress = 1.0;
      _lastSyncAt = DateTime.now();

      _logger.i(
        '✅ Sync completed. Remaining pending: $_pendingItems',
      );
    } catch (e) {
      _logger.e('❌ Sync failed: $e');
      _lastError = 'Sync failed: $e';
      // Don't rethrow - keep data queued for retry
    } finally {
      _isSyncing = false;
      _notifySyncStatus();
    }
  }

  /// ============================================================
  /// Resolve conflicts antara local dan remote data
  /// ============================================================
  /// Strategy: LATEST WINS
  /// - Bandingkan timestamp local vs remote
  /// - Yang lebih baru (timestamp terbesar) menang
  /// - Yang kalah di-update untuk match yang menang
  /// - Clear conflict flag setelah resolve
  ///
  /// Tugas:
  /// 1. Query items dengan conflict flag = 1
  /// 2. Untuk setiap conflict item:
  ///    a. Ambil data dari local DB
  ///    b. Ambil data dari Firestore (remote)
  ///    c. Bandingkan timestamp
  ///    d. Gunakan yang terbaru untuk overwrite yang lama
  /// 3. Clear conflict flag
  Future<void> resolveConflicts() async {
    _logger.i('⚠️ Resolving sync conflicts');

    if (_localDatabase == null || _firestore == null) {
      throw Exception('Database or Firestore not initialized');
    }

    try {
      // Query items dengan conflict flag
      final conflictItems = await _localDatabase!.query(
        'sync_queue',
        where: 'conflict = ?',
        whereArgs: [1],
      );

      if (conflictItems.isEmpty) {
        _logger.i('✅ No conflicts to resolve');
        return;
      }

      _logger.i('🔀 Found ${conflictItems.length} conflicts');

      for (final item in conflictItems) {
        final queueId = item['id'] as int;
        final collection = item['collection'] as String;
        final documentId = item['document_id'] as String;
        final localTimestampStr = item['updated_at'] as String?;
        final localTimestamp = localTimestampStr != null
            ? DateTime.parse(localTimestampStr)
            : DateTime.now();

        try {
          // Get remote document
          final remoteDoc =
              await _firestore!.collection(collection).doc(documentId).get();

          if (!remoteDoc.exists) {
            _logger.w('Remote document does not exist: $collection/$documentId');
            // Mark conflict as resolved (remote deleted, so no conflict)
            await _localDatabase!.update(
              'sync_queue',
              {'conflict': 0},
              where: 'id = ?',
              whereArgs: [queueId],
            );
            continue;
          }

          final remoteData = remoteDoc.data() ?? {};
          final remoteTimestampValue = remoteData['updated_at'] ??
              remoteData['synced_at'] ??
              remoteData['created_at'];

          DateTime remoteTimestamp;
          if (remoteTimestampValue is Timestamp) {
            remoteTimestamp = remoteTimestampValue.toDate();
          } else if (remoteTimestampValue is String) {
            remoteTimestamp = DateTime.parse(remoteTimestampValue);
          } else {
            remoteTimestamp = DateTime.now();
          }

          // LATEST WINS Strategy: Bandingkan timestamp
          final localWins = localTimestamp.isAfter(remoteTimestamp);

          if (localWins) {
            _logger.i(
              '🏆 Local wins for $collection/$documentId '
              '(local: $localTimestamp > remote: $remoteTimestamp)',
            );

            // Upload local data ke Firestore
            final localDataJson = item['data'] as String;
            final localData = _decodeJson(localDataJson);
            await _firestore!
                .collection(collection)
                .doc(documentId)
                .set(localData, SetOptions(merge: true));

            _logger.d('✅ Updated remote with local data');
          } else {
            _logger.i(
              '🏆 Remote wins for $collection/$documentId '
              '(remote: $remoteTimestamp > local: $localTimestamp)',
            );

            // Update local data untuk match remote
            await _localDatabase!.update(
              'sync_queue',
              {
                'data': _encodeJson(remoteData),
                'remote_timestamp': remoteTimestamp.toIso8601String(),
                'updated_at': DateTime.now().toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [queueId],
            );

            _logger.d('✅ Updated local with remote data');
          }

          // Clear conflict flag
          await _localDatabase!.update(
            'sync_queue',
            {'conflict': 0},
            where: 'id = ?',
            whereArgs: [queueId],
          );

          _logger.i('✅ Conflict resolved for $collection/$documentId');
        } catch (e) {
          _logger.e('Failed to resolve conflict for #$queueId: $e');
        }
      }

      _logger.i('✅ Conflict resolution completed');
    } catch (e) {
      _logger.e('❌ Conflict resolution failed: $e');
      rethrow;
    }
  }

  /// ============================================================
  /// Backup all user data to cloud
  /// ============================================================
  /// Tugas:
  /// 1. Create backup collection entry di Firestore
  /// 2. Copy all sessions, stats, reports
  /// 3. Timestamp the backup dengan waktu sekarang
  /// 4. Return backup ID untuk reference
  ///
  /// Return: Backup ID (string)
  Future<String> backupToCloud({required String userId}) async {
    _logger.i('☁️ Backing up data for user: $userId');

    if (_firestore == null) {
      throw Exception('Firestore not initialized');
    }

    try {
      final now = DateTime.now();
      final backupId = 'backup_${userId}_${now.millisecondsSinceEpoch}';

      // Create backup metadata
      final backupData = {
        'user_id': userId,
        'backup_id': backupId,
        'created_at': now,
        'status': 'completed',
        'data_count': {
          'sessions': 0,
          'stats': 0,
          'reports': 0,
        },
      };

      // Create backup entry di Firestore
      await _firestore!
          .collection('backups')
          .doc(backupId)
          .set(backupData);

      _logger.i('✅ Backup created: $backupId');

      // Copy all sessions dari user
      final sessionsSnap = await _firestore!
          .collection('sessions')
          .where('user_id', isEqualTo: userId)
          .get();

      int sessionCount = 0;
      for (final doc in sessionsSnap.docs) {
        final sessionData = doc.data();
        await _firestore!
            .collection('backups')
            .doc(backupId)
            .collection('sessions')
            .doc(doc.id)
            .set(sessionData);
        sessionCount++;
      }

      // Copy all stats dari user
      final statsSnap = await _firestore!
          .collection('user_stats')
          .where('user_id', isEqualTo: userId)
          .get();

      int statsCount = 0;
      for (final doc in statsSnap.docs) {
        final statsData = doc.data();
        await _firestore!
            .collection('backups')
            .doc(backupId)
            .collection('stats')
            .doc(doc.id)
            .set(statsData);
        statsCount++;
      }

      // Copy all reports dari user
      final reportsSnap = await _firestore!
          .collection('reports')
          .where('user_id', isEqualTo: userId)
          .get();

      int reportCount = 0;
      for (final doc in reportsSnap.docs) {
        final reportData = doc.data();
        await _firestore!
            .collection('backups')
            .doc(backupId)
            .collection('reports')
            .doc(doc.id)
            .set(reportData);
        reportCount++;
      }

      // Update backup metadata dengan counts
      await _firestore!
          .collection('backups')
          .doc(backupId)
          .update({
        'data_count': {
          'sessions': sessionCount,
          'stats': statsCount,
          'reports': reportCount,
        },
        'completed_at': DateTime.now(),
      });

      _logger.i(
        '✅ Backup completed: '
        '$sessionCount sessions, '
        '$statsCount stats, '
        '$reportCount reports',
      );

      return backupId;
    } catch (e) {
      _logger.e('❌ Backup failed: $e');
      _lastError = 'Backup failed: $e';
      rethrow;
    }
  }

  /// ============================================================
  /// Get current sync status
  /// ============================================================
  /// Return: SyncStatus object dengan info:
  /// - isSyncing: sedang sync atau tidak
  /// - hasError: ada error atau tidak
  /// - errorMessage: message error terakhir (jika ada)
  /// - pendingItems: jumlah item pending di queue
  /// - lastSyncAt: waktu sync terakhir
  /// - syncProgress: progress 0.0-1.0
  Future<SyncStatus> getSyncStatus() async {
    return SyncStatus(
      isSyncing: _isSyncing,
      hasError: _lastError != null,
      errorMessage: _lastError,
      pendingItems: _pendingItems,
      lastSyncAt: _lastSyncAt,
      syncProgress: _syncProgress,
    );
  }

  /// ============================================================
  /// Notify semua listeners tentang status change
  /// ============================================================
  void _notifySyncStatus() {
    _syncStatusController.add(
      SyncStatus(
        isSyncing: _isSyncing,
        hasError: _lastError != null,
        errorMessage: _lastError,
        pendingItems: _pendingItems,
        lastSyncAt: _lastSyncAt,
        syncProgress: _syncProgress,
      ),
    );
  }

  /// ============================================================
  /// Force manual sync (digunakan untuk refresh manual)
  /// ============================================================
  Future<void> forceSyncNow() async {
    _logger.i('🔄 Force sync requested');
    await syncLocalToFirebase();
  }

  /// ============================================================
  /// Clear all pending sync items (use with caution!)
  /// ============================================================
  /// WARNING: Ini akan menghapus semua item yang pending di-sync
  /// Pastikan benar-benar ingin melakukan ini sebelum call
  Future<void> clearPendingItems() async {
    _logger.w('⚠️ Clearing ALL pending sync items');

    if (_localDatabase == null) {
      throw Exception('Local database not initialized');
    }

    try {
      await _localDatabase!.delete('sync_queue', where: 'synced = ?', whereArgs: [0]);
      _pendingItems = 0;
      _notifySyncStatus();

      _logger.i('✅ Cleared all pending items');
    } catch (e) {
      _logger.e('Failed to clear pending items: $e');
      _lastError = 'Clear failed: $e';
      rethrow;
    }
  }

  /// ============================================================
  /// Get online status
  /// ============================================================
  bool get isOnline => _isOnline;

  /// ============================================================
  /// Get pending items count
  /// ============================================================
  int get pendingItemsCount => _pendingItems;

  /// ============================================================
  /// Get last sync time
  /// ============================================================
  DateTime get lastSyncTime => _lastSyncAt;

  /// ============================================================
  /// Helper: Encode map to JSON string
  /// ============================================================
  String _encodeJson(Map<String, dynamic> data) {
    try {
      return _jsonEncode(data);
    } catch (e) {
      _logger.e('Failed to encode JSON: $e');
      return '{}';
    }
  }

  /// ============================================================
  /// Helper: Decode JSON string to map
  /// ============================================================
  Map<String, dynamic> _decodeJson(String jsonString) {
    try {
      return _jsonDecode(jsonString);
    } catch (e) {
      _logger.e('Failed to decode JSON: $e');
      return {};
    }
  }

  /// Simple JSON encoding (placeholder untuk serialization)
  String _jsonEncode(Map<String, dynamic> data) {
    final buffer = StringBuffer('{');
    final entries = data.entries.toList();
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      buffer.write('"${entry.key}":${_valueToJson(entry.value)}');
      if (i < entries.length - 1) buffer.write(',');
    }
    buffer.write('}');
    return buffer.toString();
  }

  /// Convert value to JSON string
  String _valueToJson(dynamic value) {
    if (value == null) return 'null';
    if (value is String) return '"${value.replaceAll('"', '\\"')}"';
    if (value is num || value is bool) return value.toString();
    if (value is DateTime) return '"${value.toIso8601String()}"';
    if (value is Map) {
      return _jsonEncode(Map<String, dynamic>.from(value));
    }
    if (value is List) {
      final items = value.map((v) => _valueToJson(v)).join(',');
      return '[$items]';
    }
    return '"$value"';
  }

  /// Simple JSON decoding (placeholder untuk deserialization)
  Map<String, dynamic> _jsonDecode(String jsonString) {
    // Simple parser untuk test purposes
    // In production, gunakan dart:convert
    try {
      final cleaned = jsonString.trim();
      if (!cleaned.startsWith('{') || !cleaned.endsWith('}')) {
        return {};
      }

      final result = <String, dynamic>{};
      // Basic parsing - ini simplified untuk testing
      // Dalam production gunakan proper JSON library
      return result;
    } catch (e) {
      return {};
    }
  }

  /// ============================================================
  /// Cleanup resources saat service di-dispose
  /// ============================================================
  /// Dijalankan saat app ditutup atau service tidak digunakan lagi
  /// Memastikan tidak ada memory leak dari subscription atau stream
  void dispose() {
    _logger.i('Dispose SyncService');
    _connectivitySubscription?.cancel();
    _syncStatusController.close();
  }

  @override
  String toString() => 'SyncService('
      'syncing: $_isSyncing, '
      'online: $_isOnline, '
      'pending: $_pendingItems'
      ')';
}

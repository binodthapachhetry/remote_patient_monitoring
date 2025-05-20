import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/health_measurement.dart';

/// Manages SQLite database operations for local health data storage
/// Implements recommendations from architecture document for reliable local storage
class DatabaseHelper {
  // Singleton pattern
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();
  
  static Database? _database;
  
  /// Database name
  static const String dbName = 'health_data.db';
  
  /// Database version - increment when schema changes
  static const int dbVersion = 2;
  
  /// Table names
  static const String tableHealthMeasurements = 'health_measurements';
  static const String tableSyncBatches = 'sync_batches';
  
  /// Get database instance, initializing if needed
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }
  
  /// Initialize database with tables
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, dbName);
    
    debugPrint('Initializing database at $path');
    
    return await openDatabase(
      path,
      version: dbVersion,
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );
  }
  
  /// Create tables during initial database creation
  Future<void> _createDatabase(Database db, int version) async {
    debugPrint('Creating database tables (version $version)');
    
    // Health measurements table - stores all sensor readings
    await db.execute('''
      CREATE TABLE $tableHealthMeasurements (
        id TEXT PRIMARY KEY,
        participantId TEXT NOT NULL,
        deviceId TEXT NOT NULL,
        type TEXT NOT NULL,
        value REAL NOT NULL,
        unit TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        syncStatus TEXT NOT NULL,
        batchId TEXT,
        retryCount INTEGER DEFAULT 0,
        lastSyncAttempt INTEGER,
        metadata TEXT,
        checksum TEXT,
        key_version TEXT
      )
    ''');
    
    // Sync batches table - tracks batch transmission status
    await db.execute('''
      CREATE TABLE $tableSyncBatches (
        id TEXT PRIMARY KEY,
        createdAt INTEGER NOT NULL,
        messageCount INTEGER NOT NULL,
        status TEXT NOT NULL,
        lastAttempt INTEGER,
        retryCount INTEGER DEFAULT 0,
        sentAt INTEGER,
        errorMessage TEXT,
        size_bytes INTEGER DEFAULT 0,
        priority TEXT DEFAULT 'normal',
        pubsub_message_id TEXT,
        region TEXT DEFAULT 'us-central1',
        checksum TEXT,
        key_version TEXT
      )
    ''');
    
    // Create indexes for query optimization
    await db.execute(
      'CREATE INDEX idx_measurements_syncStatus ON $tableHealthMeasurements (syncStatus, timestamp)'
    );
    await db.execute(
      'CREATE INDEX idx_measurements_batchId ON $tableHealthMeasurements (batchId)'
    );
    await db.execute(
      'CREATE INDEX idx_batches_status ON $tableSyncBatches (status, createdAt)'
    );
  }
  
  /// Handle database upgrades between versions
  Future<void> _upgradeDatabase(Database db, int oldVersion, int newVersion) async {
    debugPrint('Upgrading database from v$oldVersion to v$newVersion');
    
    // Handle incremental upgrades as schema evolves
    if (oldVersion < 2) {
      // Add Pub/Sub related columns to sync_batches table
      await db.execute('''
        ALTER TABLE $tableSyncBatches 
        ADD COLUMN size_bytes INTEGER DEFAULT 0
      ''');
      
      await db.execute('''
        ALTER TABLE $tableSyncBatches 
        ADD COLUMN priority TEXT DEFAULT 'normal'
      ''');
      
      await db.execute('''
        ALTER TABLE $tableSyncBatches 
        ADD COLUMN pubsub_message_id TEXT
      ''');
    }
  }
  
  /// Insert a new health measurement
  Future<String> insertMeasurement(HealthMeasurement measurement) async {
    final db = await database;
    
    await db.insert(
      tableHealthMeasurements,
      measurement.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    debugPrint('Inserted measurement: ${measurement.id} (${measurement.type})');
    return measurement.id;
  }
  
  /// Get all pending measurements (not yet assigned to a batch)
  Future<List<HealthMeasurement>> getPendingMeasurements({int limit = 100}) async {
    final db = await database;
    
    final List<Map<String, dynamic>> maps = await db.query(
      tableHealthMeasurements,
      where: 'syncStatus = ?',
      whereArgs: ['pending'],
      orderBy: 'timestamp ASC',
      limit: limit,
    );
    
    return List.generate(maps.length, (i) {
      return HealthMeasurement.fromMap(maps[i]);
    });
  }
  
  /// Get measurements by batch ID
  Future<List<HealthMeasurement>> getMeasurementsByBatch(String batchId) async {
    final db = await database;
    
    final List<Map<String, dynamic>> maps = await db.query(
      tableHealthMeasurements,
      where: 'batchId = ?',
      whereArgs: [batchId],
      orderBy: 'timestamp ASC',
    );
    
    return List.generate(maps.length, (i) {
      return HealthMeasurement.fromMap(maps[i]);
    });
  }
  
  /// Update measurement sync status
  Future<void> updateMeasurementSyncStatus(
    String id, 
    String status, 
    {String? batchId}
  ) async {
    final db = await database;
    
    final values = <String, dynamic>{
      'syncStatus': status,
      'lastSyncAttempt': DateTime.now().millisecondsSinceEpoch,
    };
    
    if (batchId != null) {
      values['batchId'] = batchId;
    }
    
    await db.update(
      tableHealthMeasurements,
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  /// Update multiple measurements' sync status in a transaction
  Future<void> updateMeasurementBatch(
    List<String> ids, 
    String status, 
    String batchId
  ) async {
    final db = await database;
    
    await db.transaction((txn) async {
      final batch = txn.batch();
      
      for (final id in ids) {
        batch.update(
          tableHealthMeasurements,
          {
            'syncStatus': status,
            'batchId': batchId,
            'lastSyncAttempt': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      
      await batch.commit();
    });
    
    debugPrint('Updated batch of ${ids.length} measurements to status: $status');
  }
  
  /// Create a new sync batch
  Future<String> createSyncBatch(String batchId, int messageCount) async {
    final db = await database;
    
    await db.insert(
      tableSyncBatches,
      {
        'id': batchId,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'messageCount': messageCount,
        'status': 'pending',
        'size_bytes': 0, // Will be updated when measurements are added
        'priority': 'normal', // Default priority
        'retryCount': 0,
      },
    );
    
    return batchId;
  }
  
  /// Update batch status
  Future<void> updateBatchStatus(
    String batchId, 
    String status, 
    {String? errorMessage, String? pubsubMessageId}
  ) async {
    final db = await database;
    
    final values = <String, dynamic>{
      'status': status,
      'lastAttempt': DateTime.now().millisecondsSinceEpoch,
    };
    
    if (status == 'sent') {
      values['sentAt'] = DateTime.now().millisecondsSinceEpoch;
    }
    
    if (errorMessage != null) {
      values['errorMessage'] = errorMessage;
    }
    
    if (pubsubMessageId != null) {
      values['pubsub_message_id'] = pubsubMessageId;
    }
    
    await db.update(
      tableSyncBatches,
      values,
      where: 'id = ?',
      whereArgs: [batchId],
    );
    
    // If error message exists, increment the retry counter separately with raw SQL
    if (errorMessage != null && status != 'retry_scheduled' && status != 'retrying') {
      await db.rawUpdate(
        'UPDATE $tableSyncBatches SET retryCount = retryCount + 1 WHERE id = ?',
        [batchId]
      );
    }
  }
  
  /// Get all pending batches
  Future<List<Map<String, dynamic>>> getPendingBatches() async {
    final db = await database;
    
    return await db.query(
      tableSyncBatches,
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'priority DESC, createdAt ASC', // Process high priority batches first
    );
  }
  
  /// Get stats for sync status
  Future<Map<String, int>> getSyncStats() async {
    final db = await database;
    
    // Count measurements by sync status
    final measurementResults = await db.rawQuery('''
      SELECT syncStatus, COUNT(*) as count 
      FROM $tableHealthMeasurements 
      GROUP BY syncStatus
    ''');
    
    // Count batches by status
    final batchResults = await db.rawQuery('''
      SELECT status, COUNT(*) as count 
      FROM $tableSyncBatches 
      GROUP BY status
    ''');
    
    final stats = <String, int>{};
    
    for (final row in measurementResults) {
      stats['measurements_${row['syncStatus']}'] = row['count'] as int;
    }
    
    for (final row in batchResults) {
      stats['batches_${row['status']}'] = row['count'] as int;
    }
    
    return stats;
  }
  
  /// Purge old synced data to prevent unlimited growth
  /// Keeps data for specified duration (default 30 days)
  Future<int> purgeSyncedData({int keepDays = 30}) async {
    final db = await database;
    final cutoffTime = DateTime.now()
        .subtract(Duration(days: keepDays))
        .millisecondsSinceEpoch;
    
    // Delete old synced measurements
    final deletedCount = await db.delete(
      tableHealthMeasurements,
      where: 'syncStatus = ? AND timestamp < ?',
      whereArgs: ['sent', cutoffTime],
    );
    
    // Clean up batches
    await db.delete(
      tableSyncBatches,
      where: 'status = ? AND sentAt < ?',
      whereArgs: ['sent', cutoffTime],
    );
    
    debugPrint('Purged $deletedCount old synced measurements');
    return deletedCount;
  }
}

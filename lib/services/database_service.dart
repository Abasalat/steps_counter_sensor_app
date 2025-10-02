import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:steps_counter_sensor_app/data/models/step_data.dart';

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Save batch of step data to Firestore
  Future<void> saveStepData(List<StepData> dataBatch) async {
    if (dataBatch.isEmpty) return;

    try {
      // Firestore batch has a limit of 500 operations
      const batchLimit = 500;

      if (dataBatch.length <= batchLimit) {
        await _writeBatch(dataBatch);
      } else {
        // Split into multiple batches
        for (int i = 0; i < dataBatch.length; i += batchLimit) {
          final end = (i + batchLimit < dataBatch.length)
              ? i + batchLimit
              : dataBatch.length;
          final chunk = dataBatch.sublist(i, end);
          await _writeBatch(chunk);
        }
      }

      print('[DatabaseService] Saved ${dataBatch.length} entries');
    } catch (e) {
      print('[DatabaseService] Error saving data: $e');
      rethrow;
    }
  }

  /// Write a single batch to Firestore
  Future<void> _writeBatch(List<StepData> dataBatch) async {
    final batch = _firestore.batch();

    for (var data in dataBatch) {
      final docRef = _firestore.collection('steps').doc();
      batch.set(docRef, data.toJson());
    }

    await batch.commit();
  }

  /// Get step history for a user - SIMPLIFIED (no orderBy to avoid index)
  Stream<QuerySnapshot> getStepHistory(String userId, {int? limit}) {
    // Simple query - only filter by userId (no index needed)
    Query query = _firestore
        .collection('steps')
        .where('userId', isEqualTo: userId);

    if (limit != null) {
      query = query.limit(limit);
    }

    return query.snapshots();
  }

  /// Get daily aggregated steps - SIMPLIFIED (fetch all, filter in memory)
  Future<Map<String, int>> getDailySteps(
    String userId, {
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      // Fetch all user data (no complex query - no index needed)
      final snapshot = await _firestore
          .collection('steps')
          .where('userId', isEqualTo: userId)
          .get();

      // Filter and group in memory
      final dailySteps = <String, int>{};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final timestamp = DateTime.parse(data['timestamp']);

        // Filter by date range
        if (timestamp.isBefore(startDate) || timestamp.isAfter(endDate)) {
          continue;
        }

        final dateKey =
            '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
        final steps = (data['steps'] ?? 0) as int;

        dailySteps[dateKey] = (dailySteps[dateKey] ?? 0) + steps;
      }

      return dailySteps;
    } catch (e) {
      print('[DatabaseService] Error getting daily steps: $e');
      return {};
    }
  }

  /// Get total steps - SIMPLIFIED (fetch all, sum in memory)
  Future<int> getTotalSteps(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      // Fetch all user data
      final snapshot = await _firestore
          .collection('steps')
          .where('userId', isEqualTo: userId)
          .get();

      int total = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final timestamp = DateTime.parse(data['timestamp']);

        // Filter by date range
        if (startDate != null && timestamp.isBefore(startDate)) {
          continue;
        }
        if (endDate != null && timestamp.isAfter(endDate)) {
          continue;
        }

        total += (data['steps'] ?? 0) as int;
      }

      return total;
    } catch (e) {
      print('[DatabaseService] Error getting total steps: $e');
      return 0;
    }
  }

  /// Get step statistics for a user
  Future<Map<String, dynamic>> getStepStatistics(String userId) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final weekAgo = today.subtract(const Duration(days: 7));
      final monthAgo = today.subtract(const Duration(days: 30));

      // Fetch all data once
      final snapshot = await _firestore
          .collection('steps')
          .where('userId', isEqualTo: userId)
          .get();

      int todaySteps = 0;
      int weekSteps = 0;
      int monthSteps = 0;
      int allTimeSteps = 0;

      // Process all documents
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final timestamp = DateTime.parse(data['timestamp']);
        final steps = (data['steps'] ?? 0) as int;

        allTimeSteps += steps;

        if (timestamp.isAfter(today)) {
          todaySteps += steps;
        }

        if (timestamp.isAfter(weekAgo)) {
          weekSteps += steps;
        }

        if (timestamp.isAfter(monthAgo)) {
          monthSteps += steps;
        }
      }

      return {
        'today': todaySteps,
        'week': weekSteps,
        'month': monthSteps,
        'allTime': allTimeSteps,
        'dailyAverage': weekSteps > 0 ? weekSteps ~/ 7 : 0,
      };
    } catch (e) {
      print('[DatabaseService] Error getting statistics: $e');
      return {
        'today': 0,
        'week': 0,
        'month': 0,
        'allTime': 0,
        'dailyAverage': 0,
      };
    }
  }

  /// Delete old step data (data retention)
  Future<void> deleteOldData(String userId, {int daysToKeep = 90}) async {
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));

      // Fetch all user data
      final snapshot = await _firestore
          .collection('steps')
          .where('userId', isEqualTo: userId)
          .get();

      // Filter documents to delete
      final docsToDelete = snapshot.docs.where((doc) {
        final data = doc.data();
        final timestamp = DateTime.parse(data['timestamp']);
        return timestamp.isBefore(cutoffDate);
      }).toList();

      if (docsToDelete.isEmpty) {
        print('[DatabaseService] No old data to delete');
        return;
      }

      // Delete in batches
      final batch = _firestore.batch();
      int count = 0;

      for (var doc in docsToDelete) {
        batch.delete(doc.reference);
        count++;

        if (count >= 500) {
          await batch.commit();
          count = 0;
        }
      }

      if (count > 0) {
        await batch.commit();
      }

      print('[DatabaseService] Deleted ${docsToDelete.length} old entries');
    } catch (e) {
      print('[DatabaseService] Error deleting old data: $e');
    }
  }

  /// Check if user has any data
  Future<bool> hasData(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('steps')
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      print('[DatabaseService] Error checking data: $e');
      return false;
    }
  }
}

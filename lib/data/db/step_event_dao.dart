import 'package:sqflite/sqflite.dart';
import '../models/step_event.dart';
import 'app_database.dart';

class StepEventDao {
  final AppDatabase _dbProvider = AppDatabase();

  Future<int> insert(StepEventModel event) async {
    final db = await _dbProvider.database;
    return db.insert('step_events', event.toMap());
  }

  Future<int> insertMany(List<StepEventModel> events) async {
    final db = await _dbProvider.database;
    final batch = db.batch();
    for (final e in events) {
      batch.insert('step_events', e.toMap());
    }
    final results = await batch.commit(noResult: false);
    return results.length;
  }

  Future<List<StepEventModel>> getUnsynced({int limit = 200}) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      'step_events',
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'ts ASC',
      limit: limit,
    );
    return rows.map((r) => StepEventModel.fromMap(r)).toList();
  }

  Future<int> markSyncedByIds(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final db = await _dbProvider.database;
    final idList = ids.join(',');
    return db.rawUpdate(
      'UPDATE step_events SET synced = 1 WHERE id IN ($idList)',
    );
  }

  Future<int> purgeOlderThanDays(int days) async {
    final db = await _dbProvider.database;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final cutoff = nowMs - days * 24 * 60 * 60 * 1000;
    return db.delete('step_events', where: 'ts < ?', whereArgs: [cutoff]);
  }

  Future<int> countAll() async {
    final db = await _dbProvider.database;
    final res = await db.rawQuery('SELECT COUNT(*) as c FROM step_events');
    return (res.first['c'] as int?) ?? 0;
  }
}

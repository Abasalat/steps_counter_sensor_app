import '../db/step_event_dao.dart';
import '../models/step_event.dart';

class StepRepository {
  final StepEventDao _dao = StepEventDao();

  Future<void> addLocalEvent(String userId, int tsMs, int delta) async {
    final e = StepEventModel(
      userId: userId,
      ts: tsMs,
      steps: delta,
      synced: false,
    );
    await _dao.insert(e);
  }

  Future<List<StepEventModel>> loadUnsynced({int limit = 200}) =>
      _dao.getUnsynced(limit: limit);

  Future<void> markSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    await _dao.markSyncedByIds(ids);
  }

  Future<void> housekeeping() async {
    await _dao.purgeOlderThanDays(30);
  }

  Future<int> totalCount() => _dao.countAll();
}

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../data/models/step_event.dart';
import '../data/repositories/step_repository.dart';

class SyncService {
  final StepRepository _repo = StepRepository();
  Timer? _timer;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(AppConfig.syncInterval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    try {
      final unsynced = await _repo.loadUnsynced(limit: AppConfig.batchSize);
      if (unsynced.isEmpty) return;

      final payload = _toPayload(unsynced);
      final uri = Uri.parse('${AppConfig.apiBase}${AppConfig.ingestPath}');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        // For httpbin we always "succeed". In Phase 2, check actual response.
        await _repo.markSynced(unsynced.map((e) => e.id!).toList());
        await _repo.housekeeping();
      } else {
        // keep items unsynced; will retry next tick
      }
    } catch (_) {
      // network error -> retry next tick
    }
  }

  Map<String, dynamic> _toPayload(List<StepEventModel> batch) {
    return {
      'userId': AppConfig.userId,
      'events': batch.map((e) => {'ts': e.ts, 'steps': e.steps}).toList(),
      'device': {'platform': 'android'},
    };
  }
}

import 'dart:async';

typedef DebugStepCallback = void Function(int delta, DateTime ts);

class DebugStepGenerator {
  Timer? _timer;
  void start(DebugStepCallback onDelta) {
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      final delta = 1 + (DateTime.now().second % 5); // 1..5 steps
      onDelta(delta, DateTime.now());
    });
  }

  void stop() => _timer?.cancel();
}

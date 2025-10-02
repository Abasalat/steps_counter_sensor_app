// lib/services/pedometer_service.dart
import 'dart:async';
import 'package:pedometer/pedometer.dart';

typedef StepDeltaCallback = void Function(int delta, int counter, DateTime ts);

class PedometerService {
  StreamSubscription<StepCount>? _sub;
  int? _lastCounter;
  bool get isRunning => _sub != null;

  void start({
    required StepDeltaCallback onDelta,
    void Function()? onAnyEvent,
  }) {
    if (isRunning) return; // prevent duplicate listeners

    _sub = Pedometer.stepCountStream.listen(
      (StepCount event) {
        onAnyEvent?.call();

        final now = DateTime.now();
        final current = event.steps; // cumulative since boot
        final delta = (_lastCounter == null)
            ? 0
            : (current - _lastCounter!).clamp(
                0,
                1000,
              ); // clamp negatives/spikes
        _lastCounter = current;

        // Debug log helps with field testing
        // ignore: avoid_print
        print('[StepMonitor] counter=$current delta=$delta ts=$now');

        if (delta > 0) onDelta(delta, current, now);
      },
      onError: (e) {
        // ignore: avoid_print
        print('[StepMonitor] pedometer error: $e');
      },
      cancelOnError: false,
    );
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _lastCounter = null; // reset baseline next start
  }
}

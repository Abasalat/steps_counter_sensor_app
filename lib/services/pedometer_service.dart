import 'dart:async';
import 'package:pedometer/pedometer.dart';

typedef StepDeltaCallback = void Function(int delta, int counter, DateTime ts);

class PedometerService {
  StreamSubscription<StepCount>? _sub;
  int? _lastCounter;

  /// Start listening to pedometer. Calls [onAnyEvent] on every raw sensor event
  /// (even if delta == 0), and [onDelta] only when delta > 0.
  void start({
    required StepDeltaCallback onDelta,
    void Function()? onAnyEvent,
  }) {
    _sub = Pedometer.stepCountStream.listen(
      (StepCount event) {
        onAnyEvent?.call(); // <- mark that a real event arrived

        final now = DateTime.now();
        final current = event.steps; // cumulative since boot

        int delta;
        if (_lastCounter == null) {
          delta = 0; // baseline
        } else {
          final raw = current - _lastCounter!;
          delta = raw >= 0 ? raw : 0; // clamp on counter reset
        }
        _lastCounter = current;

        // Debug print
        // ignore: avoid_print
        print('[StepMonitor] counter=$current delta=$delta ts=$now');

        if (delta > 0) onDelta(delta, current, now);
      },
      onError: (e) {
        // ignore: avoid_print
        print('[StepMonitor] pedometer error: $e');
      },
    );
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _lastCounter = null; // <-- ensure fresh baseline next start
  }
}

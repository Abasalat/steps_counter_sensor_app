import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/pedometer_service.dart';
import '../../services/debug_step_generator.dart';
import '../../services/sync_service.dart';
import '../../services/permission_service.dart';
import '../../data/repositories/step_repository.dart';
import '../../core/config.dart' show AppConfig, AcquisitionMode;
import '../widgets/status_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _pedometer = PedometerService();
  final _debugGen = DebugStepGenerator();
  final _sync = SyncService();
  final _perm = PermissionService();
  final _repo = StepRepository();
  bool _usingDebug = false;

  AcquisitionMode _mode = AppConfig.defaultMode;
  bool _running = false;
  bool _receivedAnyRealEvent = false; // NEW

  int _totalSaved = 0;
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    _refreshCountsPeriodically();
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _pedometer.stop();
    _debugGen.stop();
    _sync.stop();
    super.dispose();
  }

  Future<void> _refreshCounts() async {
    final c = await _repo.totalCount();
    if (mounted) setState(() => _totalSaved = c);
  }

  void _refreshCountsPeriodically() {
    _uiTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshCounts(),
    );
  }

  Future<void> _start() async {
    if (_running) return;

    // Reset run-state
    _usingDebug = false;
    _receivedAnyRealEvent = false;

    // Permissions for real sensor (we still ask even if mode=simulatedOnly, harmless)
    final ok = await _perm.ensureActivityRecognition();
    if (!ok && mounted && _mode != AcquisitionMode.simulatedOnly) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Permission required')));
      return;
    }

    // Start according to mode
    switch (_mode) {
      case AcquisitionMode.simulatedOnly:
        _usingDebug = true;
        _debugGen.start((delta, ts) async {
          await _repo.addLocalEvent(
            AppConfig.userId,
            ts.millisecondsSinceEpoch,
            delta,
          );
        });
        break;

      case AcquisitionMode.realOnly:
        _pedometer.start(
          onDelta: (delta, counter, ts) async {
            await _repo.addLocalEvent(
              AppConfig.userId,
              ts.millisecondsSinceEpoch,
              delta,
            );
          },
          onAnyEvent: () {
            _receivedAnyRealEvent = true;
          },
        );
        break;

      case AcquisitionMode.auto:
        // Try real first; if no raw event in grace window, fall back to simulated
        _pedometer.start(
          onDelta: (delta, counter, ts) async {
            await _repo.addLocalEvent(
              AppConfig.userId,
              ts.millisecondsSinceEpoch,
              delta,
            );
          },
          onAnyEvent: () {
            _receivedAnyRealEvent = true;
          },
        );

        Future.delayed(AppConfig.autoFallbackGrace, () {
          if (!_receivedAnyRealEvent && !_usingDebug && mounted && _running) {
            // No real sensor events at all -> fallback to simulator
            _usingDebug = true;
            _debugGen.start((delta, ts) async {
              await _repo.addLocalEvent(
                AppConfig.userId,
                ts.millisecondsSinceEpoch,
                delta,
              );
            });
            setState(() {}); // refresh Source label
          }
        });
        break;
    }

    _sync.start();
    setState(() => _running = true);
  }

  void _stop() {
    if (!_running) return;
    _pedometer.stop(); // ensures _lastCounter reset
    _debugGen.stop(); // ensure simulator stops
    _sync.stop();
    _usingDebug = false;
    _receivedAnyRealEvent = false;
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Step Monitor (Phase 1)')),
      body: Column(
        children: [
          // Near the top of body:
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text('Mode:  '),
                DropdownButton<AcquisitionMode>(
                  value: _mode,
                  onChanged: _running
                      ? null
                      : (m) => setState(() => _mode = m!),
                  items: const [
                    DropdownMenuItem(
                      value: AcquisitionMode.auto,
                      child: Text('Auto'),
                    ),
                    DropdownMenuItem(
                      value: AcquisitionMode.realOnly,
                      child: Text('Real-only'),
                    ),
                    DropdownMenuItem(
                      value: AcquisitionMode.simulatedOnly,
                      child: Text('Simulated-only'),
                    ),
                  ],
                ),
                const Spacer(),
                Chip(
                  label: Text(
                    _usingDebug ? 'Source: SIMULATED' : 'Source: REAL',
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          StatusTile(title: 'User ID', value: AppConfig.userId),
          StatusTile(
            title: 'API (placeholder)',
            value: '${AppConfig.apiBase}${AppConfig.ingestPath}',
          ),
          StatusTile(
            title: 'Sync Interval',
            value: '${AppConfig.syncInterval.inSeconds}s',
          ),
          StatusTile(title: 'Total events (local)', value: '$_totalSaved'),
          StatusTile(
            title: 'Source',
            value: _usingDebug ? 'SIMULATED' : 'REAL SENSOR',
          ),

          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _running ? null : _start,
                    child: const Text('Start'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _running ? _stop : null,
                    child: const Text('Stop'),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Tap Start and walk/shake phone. On emulators, a debug generator will simulate steps.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

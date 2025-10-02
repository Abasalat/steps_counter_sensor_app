// lib/services/step_counter_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:steps_counter_sensor_app/data/models/step_data.dart';
import 'package:steps_counter_sensor_app/services/database_service.dart';
import 'package:uuid/uuid.dart';

class StepCounterService {
  // Singleton pattern
  static final StepCounterService _instance = StepCounterService._internal();
  factory StepCounterService() => _instance;
  StepCounterService._internal();

  // Stream controllers
  final StreamController<int> _stepCountController =
      StreamController<int>.broadcast();
  final StreamController<int> _stepDeltaController =
      StreamController<int>.broadcast();

  Stream<int> get stepCountStream => _stepCountController.stream;
  Stream<int> get stepDeltaStream => _stepDeltaController.stream;

  // Private state
  StreamSubscription<StepCount>? _subscription;
  Timer? _syncTimer;
  Timer? _batchTimer;

  int _sessionSteps = 0;
  int? _lastPedometerCounter;
  int? _sessionStartCounter;
  DateTime? _sessionStartTime;

  final DatabaseService _dbService = DatabaseService();
  final String _deviceId = const Uuid().v4();

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  String? _currentUserId;

  // Batch processing
  final List<StepData> _pendingBatch = [];
  static const int _batchSize = 10;
  static const Duration _syncInterval = Duration(seconds: 5);
  static const Duration _batchTimeout = Duration(seconds: 30);

  /// Start listening to step counter
  Future<void> startListening(String userId) async {
    if (_isRunning) {
      print('[StepCounter] Already running');
      return;
    }

    _currentUserId = userId;
    _isRunning = true;
    _sessionSteps = 0;
    _sessionStartTime = DateTime.now();
    _sessionStartCounter = null;
    _lastPedometerCounter = null;

    print('[StepCounter] Starting session for user: $userId');

    // Listen to pedometer
    _subscription = Pedometer.stepCountStream.listen(
      _onStepEvent,
      onError: _onStepError,
      cancelOnError: false,
    );

    // Start periodic sync timer
    _syncTimer = Timer.periodic(_syncInterval, (_) => _syncToCloud());

    // Start batch timeout timer
    _batchTimer = Timer.periodic(_batchTimeout, (_) {
      if (_pendingBatch.isNotEmpty) {
        print('[StepCounter] Batch timeout - forcing sync');
        _syncToCloud();
      }
    });

    print('[StepCounter] Service started successfully');
  }

  /// Stop listening and perform final sync
  Future<void> stopListening() async {
    if (!_isRunning) return;

    print('[StepCounter] Stopping session');
    _isRunning = false;

    // Cancel subscriptions
    await _subscription?.cancel();
    _subscription = null;

    _syncTimer?.cancel();
    _syncTimer = null;

    _batchTimer?.cancel();
    _batchTimer = null;

    // Final sync
    await _syncToCloud();

    // Save session summary
    if (_sessionSteps > 0 && _currentUserId != null) {
      await _saveSessionSummary();
    }

    // Reset state
    _sessionSteps = 0;
    _lastPedometerCounter = null;
    _sessionStartCounter = null;
    _sessionStartTime = null;
    _currentUserId = null;
    _pendingBatch.clear();

    print('[StepCounter] Service stopped');
  }

  /// Handle step count events from pedometer
  void _onStepEvent(StepCount event) {
    if (!_isRunning || _currentUserId == null) return;

    final currentCounter = event.steps;
    final now = DateTime.now();

    // Initialize baseline on first event
    if (_sessionStartCounter == null) {
      _sessionStartCounter = currentCounter;
      _lastPedometerCounter = currentCounter;
      print('[StepCounter] Baseline set: $currentCounter');
      return;
    }

    // Calculate delta (new steps since last event)
    int delta = currentCounter - (_lastPedometerCounter ?? currentCounter);

    // Handle negative deltas (shouldn't happen but pedometer can reset)
    if (delta < 0) {
      print(
        '[StepCounter] Warning: Negative delta detected. Resetting baseline.',
      );
      _sessionStartCounter = currentCounter;
      _lastPedometerCounter = currentCounter;
      return;
    }

    // Clamp unrealistic spikes (> 100 steps in one event)
    if (delta > 100) {
      print('[StepCounter] Warning: Spike detected ($delta). Clamping to 100.');
      delta = 100;
    }

    // Update state
    _lastPedometerCounter = currentCounter;

    if (delta > 0) {
      _sessionSteps += delta;

      // Emit events
      _stepCountController.add(_sessionSteps);
      _stepDeltaController.add(delta);

      // Create step data entry
      final stepData = StepData(
        userId: _currentUserId!,
        timestamp: now,
        steps: delta, // Store delta, not cumulative
        deviceId: _deviceId,
      );

      // Add to batch
      _addToBatch(stepData);

      print(
        '[StepCounter] Steps: $_sessionSteps (+$delta) | Counter: $currentCounter',
      );
    }
  }

  /// Handle pedometer errors
  void _onStepError(dynamic error) {
    print('[StepCounter] Pedometer error: $error');
    _stepCountController.addError(error);
  }

  /// Add step data to pending batch
  void _addToBatch(StepData data) {
    _pendingBatch.add(data);

    // Auto-sync when batch is full
    if (_pendingBatch.length >= _batchSize) {
      print('[StepCounter] Batch full - triggering sync');
      _syncToCloud();
    }
  }

  /// Sync pending batch to cloud
  Future<void> _syncToCloud() async {
    if (_pendingBatch.isEmpty) return;

    try {
      print(
        '[StepCounter] Syncing ${_pendingBatch.length} entries to cloud...',
      );

      // Save to cloud
      await _dbService.saveStepData(List.from(_pendingBatch));

      print('[StepCounter] ✓ Cloud sync successful');

      // Clear batch after successful sync
      _pendingBatch.clear();

      // Clear local storage since it's synced
      await _clearLocalStorage();
    } catch (e) {
      print('[StepCounter] ✗ Cloud sync failed: $e');

      // Save to local storage as backup
      await _saveToLocalStorage(_pendingBatch);

      // Keep batch for retry on next sync
    }
  }

  /// Save batch to local storage (fallback)
  Future<void> _saveToLocalStorage(List<StepData> batch) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> stored = prefs.getStringList('step_data') ?? [];

      for (final data in batch) {
        stored.add(jsonEncode(data.toJson()));
      }

      await prefs.setStringList('step_data', stored);
      print('[StepCounter] Saved ${batch.length} entries to local storage');
    } catch (e) {
      print('[StepCounter] Failed to save to local storage: $e');
    }
  }

  /// Clear local storage
  Future<void> _clearLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('step_data');
    } catch (e) {
      print('[StepCounter] Failed to clear local storage: $e');
    }
  }

  /// Save session summary
  Future<void> _saveSessionSummary() async {
    if (_sessionStartTime == null || _currentUserId == null) return;

    try {
      final summary = {
        'userId': _currentUserId,
        'startTime': _sessionStartTime!.toIso8601String(),
        'endTime': DateTime.now().toIso8601String(),
        'totalSteps': _sessionSteps,
        'deviceId': _deviceId,
      };

      final prefs = await SharedPreferences.getInstance();
      List<String> sessions = prefs.getStringList('session_history') ?? [];
      sessions.add(jsonEncode(summary));

      // Keep only last 30 sessions
      if (sessions.length > 30) {
        sessions = sessions.sublist(sessions.length - 30);
      }

      await prefs.setStringList('session_history', sessions);
      print('[StepCounter] Session summary saved: $_sessionSteps steps');
    } catch (e) {
      print('[StepCounter] Failed to save session summary: $e');
    }
  }

  /// Retry syncing any pending local data
  Future<void> retrySync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList('step_data') ?? [];

      if (stored.isEmpty) {
        print('[StepCounter] No pending data to sync');
        return;
      }

      print(
        '[StepCounter] Retrying sync for ${stored.length} local entries...',
      );

      final batch = stored
          .map((json) => StepData.fromJson(jsonDecode(json)))
          .toList();

      await _dbService.saveStepData(batch);
      await prefs.remove('step_data');

      print('[StepCounter] ✓ Retry sync successful');
    } catch (e) {
      print('[StepCounter] ✗ Retry sync failed: $e');
    }
  }

  /// Get current session stats
  Map<String, dynamic> getSessionStats() {
    return {
      'isRunning': _isRunning,
      'sessionSteps': _sessionSteps,
      'startTime': _sessionStartTime?.toIso8601String(),
      'duration': _sessionStartTime != null
          ? DateTime.now().difference(_sessionStartTime!).inMinutes
          : 0,
      'pendingSync': _pendingBatch.length,
    };
  }

  /// Dispose service
  void dispose() {
    stopListening();
    _stepCountController.close();
    _stepDeltaController.close();
  }
}

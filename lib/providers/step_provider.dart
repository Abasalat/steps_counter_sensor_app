import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:steps_counter_sensor_app/data/models/step_data.dart';
import 'package:steps_counter_sensor_app/services/database_service.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'dart:convert';

class StepProvider extends ChangeNotifier {
  // Session state
  int _sessionSteps = 0;
  int _sessionStartCounter = 0;
  int _lastCounter = 0;
  bool _isRunning = false;
  DateTime? _sessionStartTime;
  String? _currentUserId;

  // Stream subscriptions
  StreamSubscription<StepCount>? _subscription;
  Timer? _syncTimer;
  Timer? _batchTimer;

  // Services
  final DatabaseService _dbService = DatabaseService();
  final String _deviceId = const Uuid().v4();

  // Batch management
  final List<StepData> _pendingBatch = [];
  static const int _maxBatchSize = 10;
  static const Duration _syncInterval = Duration(seconds: 5);
  static const Duration _batchTimeout = Duration(seconds: 30);

  // Error tracking
  String? _lastError;
  int _syncFailureCount = 0;

  // Getters
  int get sessionSteps => _sessionSteps;
  bool get isRunning => _isRunning;
  String? get lastError => _lastError;
  DateTime? get sessionStartTime => _sessionStartTime;
  int get pendingSyncCount => _pendingBatch.length;

  // Add these variables to StepProvider class
  int _accumulatedSteps = 0;
  DateTime? _lastSaveTime;
  static const Duration _saveInterval = Duration(seconds: 5);
  static const int _saveThreshold = 10; // Save after accumulating 10 steps

  /// Start listening to pedometer
  void startListening(String userId) {
    if (_isRunning) {
      print('[StepProvider] Already running');
      return;
    }

    _currentUserId = userId;
    _isRunning = true;
    _sessionSteps = 0;
    _sessionStartCounter = 0;
    _lastCounter = 0;
    _sessionStartTime = DateTime.now();
    _lastError = null;
    _syncFailureCount = 0;

    print('[StepProvider] Starting session for user: $userId');

    // Subscribe to pedometer
    _subscription = Pedometer.stepCountStream.listen(
      _onStepEvent,
      onError: _onStepError,
      cancelOnError: false,
    );

    // Start periodic sync
    _syncTimer = Timer.periodic(_syncInterval, (_) => _syncToCloud());

    // Start batch timeout timer
    _batchTimer = Timer.periodic(_batchTimeout, (_) {
      if (_pendingBatch.isNotEmpty) {
        print('[StepProvider] Batch timeout - forcing sync');
        _syncToCloud();
      }
    });

    notifyListeners();
  }

  /// Stop listening and perform final sync
  Future<void> stopListening() async {
    if (!_isRunning) return;

    print('[StepProvider] Stopping session');
    _isRunning = false;

    // Cancel timers and subscriptions
    _subscription?.cancel();
    _subscription = null;

    _syncTimer?.cancel();
    _syncTimer = null;

    _batchTimer?.cancel();
    _batchTimer = null;

    // Final sync
    await _syncToCloud();

    // Save session summary
    if (_sessionSteps > 0) {
      await _saveSessionSummary();
    }

    // Reset state
    _sessionSteps = 0;
    _sessionStartCounter = 0;
    _lastCounter = 0;
    _sessionStartTime = null;
    _currentUserId = null;
    _pendingBatch.clear();

    print('[StepProvider] Session stopped');
    notifyListeners();
  }

  /// Handle step count events

  void _onStepEvent(StepCount event) {
    if (!_isRunning || _currentUserId == null) return;

    final currentCounter = event.steps;
    final now = DateTime.now();

    // Initialize baseline
    if (_sessionStartCounter == 0) {
      _sessionStartCounter = currentCounter;
      _lastCounter = currentCounter;
      _lastSaveTime = now;
      print('[StepProvider] Baseline set: $currentCounter');
      return;
    }

    // Calculate delta
    int delta = currentCounter - _lastCounter;

    // Handle edge cases
    if (delta < 0) {
      print('[StepProvider] Pedometer reset detected');
      _sessionStartCounter = currentCounter;
      _lastCounter = currentCounter;
      return;
    }

    if (delta > 100) {
      print('[StepProvider] Spike detected: $delta, clamping to 100');
      delta = 100;
    }

    // Update counters
    _lastCounter = currentCounter;

    if (delta > 0) {
      _sessionSteps += delta;
      _accumulatedSteps += delta; // Accumulate instead of immediate save

      // Check if we should save
      final timeSinceLastSave = _lastSaveTime == null
          ? _saveInterval
          : now.difference(_lastSaveTime!);

      final shouldSave =
          _accumulatedSteps >= _saveThreshold ||
          timeSinceLastSave >= _saveInterval;

      if (shouldSave && _accumulatedSteps > 0) {
        // Create step data entry with accumulated steps
        final stepData = StepData(
          userId: _currentUserId!,
          timestamp: now,
          steps: _accumulatedSteps, // Save accumulated steps
          deviceId: _deviceId,
        );

        _addToBatch(stepData);

        print('[StepProvider] Saved batch: $_accumulatedSteps steps');

        // Reset accumulator
        _accumulatedSteps = 0;
        _lastSaveTime = now;
      }

      print(
        '[StepProvider] Session: $_sessionSteps | Accumulated: $_accumulatedSteps',
      );
      notifyListeners();
    }
  }

  /// Handle pedometer errors
  void _onStepError(dynamic error) {
    print('[StepProvider] Pedometer error: $error');
    _lastError = error.toString();
    notifyListeners();
  }

  /// Add step data to batch
  void _addToBatch(StepData data) {
    _pendingBatch.add(data);

    // Store locally immediately (backup)
    //_storeLocally(data);

    // Auto-sync when batch is full
    if (_pendingBatch.length >= _maxBatchSize) {
      print('[StepProvider] Batch full - triggering sync');
      _syncToCloud();
    }
  }

  /// Sync batch to cloud
  Future<void> _syncToCloud() async {
    if (_pendingBatch.isEmpty) return;

    try {
      print('[StepProvider] Syncing ${_pendingBatch.length} entries...');

      // Copy batch for sync
      final batchToSync = List<StepData>.from(_pendingBatch);

      // Attempt cloud sync
      await _dbService.saveStepData(batchToSync);

      // Success - clear batch and local storage
      _pendingBatch.clear();
      _syncFailureCount = 0;
      // await _clearLocalStorage();

      // try to flush any older locally stored rows (if you decide to keep storing them)
      await _retryLocalStoreOnce();
      print('[StepProvider] ✓ Sync successful');
      print('[StepProvider] ✓ Sync successful');
    } catch (e) {
      _syncFailureCount++;
      _lastError = 'Sync failed: $e';
      print('[StepProvider] ✗ Sync failed ($e) - attempt $_syncFailureCount');

      // Keep batch for retry
      // Data is already in local storage as backup
    }
  }

  Future<void> _retryLocalStoreOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList('step_data') ?? [];
      if (stored.isEmpty) return;

      final batch = stored
          .map((json) => StepData.fromJson(jsonDecode(json)))
          .toList();

      await _dbService.saveStepData(batch);
      await prefs.remove('step_data');
      print('[StepProvider] ✓ Flushed local store');
    } catch (e) {
      print('[StepProvider] Local store flush failed: $e');
    }
  }

  /// Store single entry locally (backup)
  Future<void> _storeLocally(StepData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> stored = prefs.getStringList('step_data') ?? [];
      stored.add(jsonEncode(data.toJson()));

      // Prevent unbounded growth
      if (stored.length > 500) {
        stored = stored.sublist(stored.length - 500);
      }

      await prefs.setStringList('step_data', stored);
    } catch (e) {
      print('[StepProvider] Failed to store locally: $e');
    }
  }

  /// Clear local storage
  Future<void> _clearLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('step_data');
    } catch (e) {
      print('[StepProvider] Failed to clear local storage: $e');
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

      // Keep last 30 sessions
      if (sessions.length > 30) {
        sessions = sessions.sublist(sessions.length - 30);
      }

      await prefs.setStringList('session_history', sessions);
      print('[StepProvider] Session summary saved');
    } catch (e) {
      print('[StepProvider] Failed to save session: $e');
    }
  }

  /// Retry syncing pending data
  Future<void> retrySync() async {
    if (_pendingBatch.isNotEmpty) {
      await _syncToCloud();
      notifyListeners();
    }
  }

  /// Simulate step (for testing)
  void simulateStep() {
    if (!_isRunning || _currentUserId == null) return;

    // Simulate a single step delta
    _sessionSteps += 1;

    final stepData = StepData(
      userId: _currentUserId!,
      timestamp: DateTime.now(),
      steps: 1, // Single step
      deviceId: _deviceId,
    );

    _addToBatch(stepData);
    print('[StepProvider] Simulated step: $_sessionSteps');
    notifyListeners();
  }

  /// Get session statistics
  Map<String, dynamic> getSessionStats() {
    final duration = _sessionStartTime != null
        ? DateTime.now().difference(_sessionStartTime!)
        : Duration.zero;

    return {
      'isRunning': _isRunning,
      'sessionSteps': _sessionSteps,
      'startTime': _sessionStartTime?.toIso8601String(),
      'duration': duration.inMinutes,
      'pendingSync': _pendingBatch.length,
      'syncFailures': _syncFailureCount,
      'lastError': _lastError,
    };
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}

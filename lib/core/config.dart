enum AcquisitionMode { auto, realOnly, simulatedOnly }

class AppConfig {
  static const String userId = 'demoUser01';

  static const String apiBase = 'https://httpbin.org';
  static const String ingestPath = '/post';

  static const Duration syncInterval = Duration(seconds: 20);
  static const int batchSize = 100;

  // Default mode (you can change in UI)
  static const AcquisitionMode defaultMode = AcquisitionMode.auto;

  // Auto fallback wait window
  static const Duration autoFallbackGrace = Duration(seconds: 8);
}

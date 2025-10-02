class StepData {
  final String userId;
  final DateTime timestamp;
  final int steps;
  final String deviceId; // Optional: For device uniqueness

  StepData({
    required this.userId,
    required this.timestamp,
    required this.steps,
    required this.deviceId,
  });

  // To JSON for transmission/storage
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'timestamp': timestamp.toIso8601String(),
      'steps': steps,
      'deviceId': deviceId,
    };
  }

  // From JSON for deserialization
  factory StepData.fromJson(Map<String, dynamic> json) {
    return StepData(
      userId: json['userId'],
      timestamp: DateTime.parse(json['timestamp']),
      steps: json['steps'],
      deviceId: json['deviceId'],
    );
  }
}

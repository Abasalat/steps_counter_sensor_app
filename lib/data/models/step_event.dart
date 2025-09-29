class StepEventModel {
  final int? id; // auto-increment PK (sqlite)
  final String userId; // e.g., "demoUser01"
  final int ts; // epoch ms
  final int steps; // delta in this interval
  final bool synced; // queued vs uploaded

  StepEventModel({
    this.id,
    required this.userId,
    required this.ts,
    required this.steps,
    this.synced = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'user_id': userId,
    'ts': ts,
    'steps': steps,
    'synced': synced ? 1 : 0,
  };

  factory StepEventModel.fromMap(Map<String, dynamic> map) {
    return StepEventModel(
      id: map['id'] as int?,
      userId: map['user_id'] as String,
      ts: map['ts'] as int,
      steps: map['steps'] as int,
      synced: (map['synced'] as int) == 1,
    );
  }
}

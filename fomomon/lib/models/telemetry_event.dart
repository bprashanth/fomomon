enum TelemetryLevel { info, warning, error }

class TelemetryEvent {
  final DateTime timestamp;
  final TelemetryLevel level;
  final String pivot;
  final String message;
  final String? error;
  final Map<String, dynamic>? context;

  TelemetryEvent({
    required this.timestamp,
    required this.level,
    required this.pivot,
    required this.message,
    this.error,
    this.context,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'level': level.name,
    'pivot': pivot,
    'message': message,
    'error': error,
    'context': context,
  };
}

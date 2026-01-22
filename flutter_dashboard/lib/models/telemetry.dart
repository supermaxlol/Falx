/// Telemetry data model for MAVLink stream
class Telemetry {
  final double altitude;
  final double airspeed;
  final double batteryVoltage;
  final DateTime timestamp;

  Telemetry({
    required this.altitude,
    required this.airspeed,
    required this.batteryVoltage,
    required this.timestamp,
  });

  factory Telemetry.fromJson(Map<String, dynamic> json) {
    return Telemetry(
      altitude: (json['altitude'] as num?)?.toDouble() ?? 0.0,
      airspeed: (json['airspeed'] as num?)?.toDouble() ?? 0.0,
      batteryVoltage: (json['battery_voltage'] as num?)?.toDouble() ?? 0.0,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
    );
  }

  /// Check if battery is in critical state (below 21.0V for 6S)
  bool get isBatteryCritical => batteryVoltage < 21.0;

  /// Check if battery is in warning state (below 22.0V)
  bool get isBatteryWarning => batteryVoltage < 22.0 && !isBatteryCritical;

  /// Get battery percentage (approximate for 6S LiPo)
  /// 6S: 18V (empty) to 25.2V (full)
  double get batteryPercentage {
    const minVoltage = 18.0;
    const maxVoltage = 25.2;
    final percentage =
        ((batteryVoltage - minVoltage) / (maxVoltage - minVoltage)) * 100;
    return percentage.clamp(0.0, 100.0);
  }

  Telemetry copyWith({
    double? altitude,
    double? airspeed,
    double? batteryVoltage,
    DateTime? timestamp,
  }) {
    return Telemetry(
      altitude: altitude ?? this.altitude,
      airspeed: airspeed ?? this.airspeed,
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Alert message model for critical events
class AlertMessage {
  final String type;
  final String priority;
  final String message;
  final double threshold;
  final double currentVoltage;
  final DateTime timestamp;
  final String actionRequired;

  AlertMessage({
    required this.type,
    required this.priority,
    required this.message,
    required this.threshold,
    required this.currentVoltage,
    required this.timestamp,
    required this.actionRequired,
  });

  factory AlertMessage.fromJson(Map<String, dynamic> json) {
    return AlertMessage(
      type: json['type'] ?? 'UNKNOWN',
      priority: json['priority'] ?? 'LOW',
      message: json['message'] ?? '',
      threshold: (json['threshold'] as num?)?.toDouble() ?? 21.0,
      currentVoltage: (json['current_voltage'] as num?)?.toDouble() ?? 0.0,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      actionRequired: json['action_required'] ?? '',
    );
  }

  bool get isHighPriority => priority == 'HIGH';
}

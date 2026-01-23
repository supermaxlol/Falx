class Telemetry {
  final double batteryVoltage;
  final double altitude;
  final double latitude;
  final double longitude;
  final double heading;
  final double groundspeed;
  final DateTime timestamp;

  Telemetry({
    required this.batteryVoltage,
    required this.altitude,
    required this.latitude,
    required this.longitude,
    required this.heading,
    required this.groundspeed,
    required this.timestamp,
  });

  factory Telemetry.fromJson(Map<String, dynamic> json) {
    return Telemetry(
      batteryVoltage: (json['battery_voltage'] ?? json['batteryVoltage'] ?? 0.0).toDouble(),
      altitude: (json['altitude'] ?? json['alt'] ?? 0.0).toDouble(),
      latitude: (json['latitude'] ?? json['lat'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? json['lon'] ?? json['lng'] ?? 0.0).toDouble(),
      heading: (json['heading'] ?? json['yaw'] ?? 0.0).toDouble(),
      groundspeed: (json['groundspeed'] ?? json['ground_speed'] ?? json['speed'] ?? 0.0).toDouble(),
      timestamp: json['timestamp'] != null 
          ? DateTime.parse(json['timestamp']) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'battery_voltage': batteryVoltage,
      'altitude': altitude,
      'latitude': latitude,
      'longitude': longitude,
      'heading': heading,
      'groundspeed': groundspeed,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

enum AlertType {
  info,
  warning,
  error,
}

enum AlertPriority {
  low,
  medium,
  high,
  critical,
}

class AlertMessage {
  final String message;
  final AlertType type;
  final AlertPriority priority;
  final DateTime timestamp;
  final double currentVoltage;
  final double threshold;
  final String actionRequired;

  AlertMessage({
    required this.message,
    required this.type,
    required this.priority,
    required this.timestamp,
    required this.currentVoltage,
    required this.threshold,
    required this.actionRequired,
  });
}
class SensorReading {
  final int tdsRaw;
  final double tdsVoltage;
  final int mqRaw;
  final double mqVoltage;
  final int phRaw;
  final double phVoltage;
  final double? phValue;
  final DateTime timestamp;

  // Compatibility getters for legacy references
  double get mq135Ppm => tdsVoltage;
  double get mq3Ppm => mqVoltage;
  double get mq7Ppm => phVoltage;
  double get salivaPh => phValue ?? 7.0;
  double get salivaEc => tdsVoltage;

  SensorReading({
    required this.tdsRaw,
    required this.tdsVoltage,
    required this.mqRaw,
    required this.mqVoltage,
    required this.phRaw,
    required this.phVoltage,
    this.phValue,
    required this.timestamp,
  });

  factory SensorReading.fromJson(Map<String, dynamic> json) {
    DateTime parsedTime;
    try {
      final rawTs = json['timestamp'];
      if (rawTs != null && rawTs is String && rawTs != 'LIVE') {
        parsedTime = DateTime.parse(rawTs);
      } else {
        parsedTime = DateTime.now();
      }
    } catch (_) {
      parsedTime = DateTime.now();
    }

    return SensorReading(
      tdsRaw: (json['tds_raw'] as num?)?.toInt() ?? 0,
      tdsVoltage: (json['tds_voltage'] as num?)?.toDouble() ?? (json['saliva_ec'] as num?)?.toDouble() ?? 0.0,
      mqRaw: (json['mq_raw'] as num?)?.toInt() ?? 0,
      mqVoltage: (json['mq_voltage'] as num?)?.toDouble() ?? (json['mq3_ppm'] as num?)?.toDouble() ?? 0.0,
      phRaw: (json['ph_raw'] as num?)?.toInt() ?? 0,
      phVoltage: (json['ph_voltage'] as num?)?.toDouble() ?? 0.0,
      phValue: (json['ph'] as num?)?.toDouble() ?? (json['saliva_ph'] as num?)?.toDouble(),
      timestamp: parsedTime,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tds_raw': tdsRaw,
      'tds_voltage': tdsVoltage,
      'mq_raw': mqRaw,
      'mq_voltage': mqVoltage,
      'ph_raw': phRaw,
      'ph_voltage': phVoltage,
      if (phValue != null) 'ph': phValue,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

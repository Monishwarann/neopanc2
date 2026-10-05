import 'dart:async';
import 'package:flutter/material.dart';
import '../services/pancreasense_api_service.dart';

class LiveSensorDashboard extends StatefulWidget {
  const LiveSensorDashboard({Key? key}) : super(key: key);

  @override
  State<LiveSensorDashboard> createState() => _LiveSensorDashboardState();
}

class _LiveSensorDashboardState extends State<LiveSensorDashboard> {
  Timer? _pollingTimer;
  bool _isFastApiOnline = false;
  String _esp32Status = "DISCONNECTED";
  Map<String, dynamic>? _sensorData;

  @override
  void initState() {
    super.initState();
    _fetchTelemetry();
    // Poll FastAPI server every 1 second (1000ms) for real-time telemetry
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _fetchTelemetry();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchTelemetry() async {
    final payload = await PancreasenseApiService.fetchLatestSensorData();
    if (payload != null) {
      if (mounted) {
        setState(() {
          _isFastApiOnline = true;
          _esp32Status = payload['esp32_status'] ?? 'DISCONNECTED';
          _sensorData = payload['sensor'];
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isFastApiOnline = false;
          _esp32Status = 'DISCONNECTED';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tdsRaw = _sensorData?['tds_raw']?.toString() ?? '--';
    final tdsVolt = _sensorData?['tds_voltage'] != null
        ? (_sensorData!['tds_voltage'] as num).toStringAsFixed(3)
        : '--';

    final mqRaw = _sensorData?['mq_raw']?.toString() ?? '--';
    final mqVolt = _sensorData?['mq_voltage'] != null
        ? (_sensorData!['mq_voltage'] as num).toStringAsFixed(3)
        : '--';

    final phRaw = _sensorData?['ph_raw']?.toString() ?? '--';
    final phVolt = _sensorData?['ph_voltage'] != null
        ? (_sensorData!['ph_voltage'] as num).toStringAsFixed(3)
        : '--';

    final timestamp = _sensorData?['timestamp'] ?? 'Waiting for ESP32...';

    return Scaffold(
      appBar: AppBar(
        title: const Text('PancreaSense Telemetry Dashboard'),
        backgroundColor: Colors.indigo.shade900,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Connection Status Card
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: const Color(0xFF1E293B),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildBadge(
                          label: _isFastApiOnline ? "FastAPI: ONLINE" : "FastAPI: OFFLINE",
                          isOk: _isFastApiOnline,
                        ),
                        _buildBadge(
                          label: "ESP32: $_esp32Status",
                          isOk: _esp32Status == "CONNECTED",
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Last Received: $timestamp",
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              "Real-Time Live Sensor Telemetry",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // 2. TDS Sensor (GPIO 32)
            _buildMetricCard(
              gpio: "GPIO 32",
              name: "TDS Sensor",
              voltage: "$tdsVolt V",
              raw: "Raw ADC: $tdsRaw",
              color: Colors.blue,
              icon: Icons.water_drop,
            ),
            const SizedBox(height: 12),

            // 3. MQ Gas Sensor (GPIO 33)
            _buildMetricCard(
              gpio: "GPIO 33",
              name: "MQ Gas Sensor",
              voltage: "$mqVolt V",
              raw: "Raw ADC: $mqRaw",
              color: Colors.orange,
              icon: Icons.air,
            ),
            const SizedBox(height: 12),

            // 4. pH Sensor (GPIO 34)
            _buildMetricCard(
              gpio: "GPIO 34",
              name: "pH Sensor",
              voltage: "$phVolt V",
              raw: "Raw ADC: $phRaw",
              color: Colors.purple,
              icon: Icons.science,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge({required String label, required bool isOk}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isOk ? Colors.green.shade800 : Colors.red.shade800,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _buildMetricCard({
    required String gpio,
    required String name,
    required String voltage,
    required String raw,
    required Color color,
    required IconData icon,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.15),
              radius: 24,
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("$gpio — $name", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(raw, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
            Text(
              voltage,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

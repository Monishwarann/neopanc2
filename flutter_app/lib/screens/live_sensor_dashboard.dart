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
  bool _isServerOnline = false;
  Map<String, dynamic>? _sensorData;
  Map<String, dynamic>? _predictionData;

  @override
  void initState() {
    super.initState();
    _fetchData();
    // Poll FastAPI server every 3 seconds for live readings
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchData();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchData() async {
    final isHealthy = await PancreasenseApiService.checkServerHealth();
    if (isHealthy) {
      final payload = await PancreasenseApiService.fetchLatestPrediction();
      if (mounted) {
        setState(() {
          _isServerOnline = true;
          if (payload != null) {
            _sensorData = payload['sensors'];
            _predictionData = payload['prediction'];
          }
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isServerOnline = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final riskLevel = _predictionData?['risk_level'] ?? 'NO DATA';
    final pcriScore = _predictionData?['pcri_score']?.toString() ?? '--';
    final aiScore = _predictionData?['ai_score']?.toString() ?? '--';

    Color riskColor = Colors.grey;
    if (riskLevel == 'LOW RISK') riskColor = Colors.green;
    if (riskLevel == 'MODERATE RISK') riskColor = Colors.orange;
    if (riskLevel == 'HIGH RISK') riskColor = Colors.red;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PancreaSense Live Dashboard'),
        backgroundColor: Colors.teal.shade800,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Connection Status Banner
            Card(
              color: _isServerOnline ? Colors.green.shade50 : Colors.red.shade50,
              elevation: 2,
              child: ListTile(
                leading: Icon(
                  _isServerOnline ? Icons.wifi : Icons.wifi_off,
                  color: _isServerOnline ? Colors.green : Colors.red,
                ),
                title: Text(
                  _isServerOnline ? "FastAPI Server Connected" : "Server Disconnected",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isServerOnline ? Colors.green.shade900 : Colors.red.shade900,
                  ),
                ),
                subtitle: Text(_isServerOnline
                    ? "Listening on ${PancreasenseApiService.baseUrl}"
                    : "Make sure Python FastAPI is running on host 0.0.0.0:8000"),
              ),
            ),
            const SizedBox(height: 16),

            // 2. ML Prediction & Risk Result Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    const Text(
                      "Pancreatic Risk Assessment (PCRI)",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "$pcriScore %",
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        color: riskColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: riskColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        riskLevel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "AI Model Prediction Score: $aiScore %",
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. Live ESP32 Sensor Measurements
            const Text(
              "Live ESP32 Sensor Readings",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: _buildSensorCard(
                    title: "TDS / EC",
                    value: "${_sensorData?['tds_voltage']?.toString() ?? '--'} V",
                    raw: "Raw: ${_sensorData?['tds_raw'] ?? '--'}",
                    icon: Icons.water_drop,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildSensorCard(
                    title: "MQ Gas Sensor",
                    value: "${_sensorData?['mq_voltage']?.toString() ?? '--'} V",
                    raw: "Raw: ${_sensorData?['mq_raw'] ?? '--'}",
                    icon: Icons.air,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            _buildSensorCard(
              title: "Saliva pH Sensor",
              value: "${_sensorData?['ph']?.toString() ?? '--'} pH",
              raw: "Voltage: ${_sensorData?['ph_voltage']?.toString() ?? '--'} V",
              icon: Icons.science,
              color: Colors.purple,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorCard({
    required String title,
    required String value,
    required String raw,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 10),
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(raw, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class PancreasenseApiService {
  // *** ENTER YOUR LAPTOP IP ADDRESS HERE ***
  // Example: 'http://192.168.1.15:8000'
  static const String baseUrl = 'http://YOUR_LAPTOP_IP:8000'; // <-- EDIT THIS LINE

  // 1. Check Server Connection Status
  static Future<Map<String, dynamic>> checkSystemStatus() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/status'))
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {'fastapi_server_status': 'OFFLINE', 'esp32_connection_status': 'DISCONNECTED'};
    } catch (_) {
      return {'fastapi_server_status': 'OFFLINE', 'esp32_connection_status': 'DISCONNECTED'};
    }
  }

  // 2. Fetch Latest Sensor Telemetry (1-Second Refresh)
  static Future<Map<String, dynamic>?> fetchLatestSensorData() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/latest-sensor'))
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

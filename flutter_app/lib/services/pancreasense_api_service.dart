import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class PancreasenseApiService {
  // *** ENTER YOUR LAPTOP IP ADDRESS HERE ***
  // Example: 'http://192.168.1.15:8000'
  static const String baseUrl = 'http://YOUR_LAPTOP_IP:8000'; // <-- EDIT THIS LINE

  // 1. Check Server Connection Status
  static Future<bool> checkServerHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/status'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // 2. Fetch Latest Telemetry & ML Risk Prediction
  static Future<Map<String, dynamic>?> fetchLatestPrediction() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/latest-prediction'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

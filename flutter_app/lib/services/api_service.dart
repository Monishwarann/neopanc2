import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'stub_download.dart' if (dart.library.html) 'web_download.dart';
import '../models/sensor_reading.dart';
import '../models/patient.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ApiService {
  final String baseUrl;

  ApiService({required this.baseUrl});

  Future<Map<String, String>> _getHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final token = await user.getIdToken();
      return {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
    }
    return {'Content-Type': 'application/json'};
  }

  // Auth: Login
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: await _getHeaders(),
        body: jsonEncode({'username': username, 'password': password}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'message': 'Connection error to backend: $e'};
    }
  }

  // Auth: Register
  Future<Map<String, dynamic>> register(String username, String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/register'),
        headers: await _getHeaders(),
        body: jsonEncode({'username': username, 'email': email, 'password': password}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'message': 'Connection error to backend: $e'};
    }
  }

  // Fetch Latest Sensor Reading
  Future<SensorReading?> fetchLatestSensorReading(String userId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/telemetry/latest/$userId'), headers: await _getHeaders());
      if (response.statusCode == 200) {
        return SensorReading.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      print("Error fetching latest telemetry: $e");
    }
    return null;
  }

  // Fetch Live Prediction
  Future<Map<String, dynamic>?> fetchLivePrediction(String userId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/predict/live/$userId'), headers: await _getHeaders());
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('Error fetching live prediction: $e');
    }
    return null;
  }

  // Fetch User Stats
  Future<Map<String, dynamic>?> fetchUserStats(String userId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/stats/$userId'), headers: await _getHeaders());
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('Error fetching user stats: $e');
    }
    return null;
  }

  // Submit screening packet for diagnosis
  Future<Map<String, dynamic>?> evaluateScreening({
    required String userId,
    required PatientQuestionnaire survey,
    required double tdsVoltage,
    required double mqVoltage,
    required double phVoltage,
    double? phValue,
  }) async {
    try {
      final body = {
        'user_id': userId,
        'tds_voltage': tdsVoltage,
        'mq_voltage': mqVoltage,
        'ph_voltage': phVoltage,
        'ph_value': phValue ?? phVoltage,
        ...survey.toJson(),
      };

      final response = await http.post(
        Uri.parse('$baseUrl/api/predict'),
        headers: await _getHeaders(),
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Error evaluating risk screening: $e");
    }
    return null;
  }

  // Fetch historical logs list
  Future<List<dynamic>> fetchHistoryLogs(String userId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/history/$userId'), headers: await _getHeaders());
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Error fetching screening history: $e");
    }
    return [];
  }

  // Helper to sanitize Map for JSON encoding, converting Firestore Timestamps/FieldValues to strings
  Map<String, dynamic> _sanitizeForJson(Map<String, dynamic> map) {
    final sanitized = <String, dynamic>{};
    map.forEach((key, val) {
      if (val == null) {
        sanitized[key] = null;
      } else if (val is Map<String, dynamic>) {
        sanitized[key] = _sanitizeForJson(val);
      } else if (val is List) {
        sanitized[key] = val.map((item) {
          if (item is Map<String, dynamic>) {
            return _sanitizeForJson(item);
          }
          return item.toString();
        }).toList();
      } else if (val.toString().contains('Timestamp') || val.runtimeType.toString() == 'Timestamp') {
        try {
          sanitized[key] = (val as dynamic).toDate().toUtc().toIso8601String();
        } catch (_) {
          sanitized[key] = val.toString();
        }
      } else if (val.toString().contains('FieldValue') || val.runtimeType.toString().contains('FieldValue')) {
        sanitized[key] = DateTime.now().toUtc().toIso8601String();
      } else {
        sanitized[key] = val;
      }
    });
    return sanitized;
  }

  // Download PDF
  Future<String?> downloadPdf(String logId, {Map<String, dynamic>? logData}) async {
    try {
      final headers = await _getHeaders();
      final url = Uri.parse('$baseUrl/api/generate-pdf/$logId');
      final http.Response response;
      
      if (logData != null) {
        headers['Content-Type'] = 'application/json';
        final sanitizedData = _sanitizeForJson(logData);
        response = await http.post(url, headers: headers, body: jsonEncode(sanitizedData));
      } else {
        response = await http.get(url, headers: headers);
      }
      
      if (response.statusCode == 200) {
        if (kIsWeb) {
          downloadFileWeb(response.bodyBytes, 'report_$logId.pdf');
          return 'downloaded';
        } else {
          final directory = await getApplicationDocumentsDirectory();
          final file = File('${directory.path}/report_$logId.pdf');
          await file.writeAsBytes(response.bodyBytes);
          await OpenFilex.open(file.path);
          return file.path;
        }
      }
    } catch (e) {
      print("Error downloading PDF: $e");
    }
    return null;
  }

  // Fetch Raw PDF Bytes from backend
  Future<Uint8List?> fetchPdfBytes(String logId, {Map<String, dynamic>? logData}) async {
    try {
      final headers = await _getHeaders();
      final url = Uri.parse('$baseUrl/api/generate-pdf/$logId');
      final http.Response response;
      
      if (logData != null) {
        headers['Content-Type'] = 'application/json';
        final sanitizedData = _sanitizeForJson(logData);
        response = await http.post(url, headers: headers, body: jsonEncode(sanitizedData));
      } else {
        response = await http.get(url, headers: headers);
      }
      
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (e) {
      print("Error fetching PDF bytes: $e");
    }
    return null;
  }

  // Fetch Profile
  Future<Map<String, dynamic>?> fetchProfile(String userId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/profile/$userId'), headers: await _getHeaders());
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Error fetching profile: $e");
    }
    return null;
  }

  // Update Profile
  Future<bool> updateProfile(String userId, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/profile/$userId'),
        headers: await _getHeaders(),
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return true;
      }
    } catch (e) {
      print("Error updating profile: $e");
    }
    return false;
  }

  // Wake up/warm up the server to handle cold start
  Future<void> pingServer() async {
    try {
      await http.get(Uri.parse(baseUrl)).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }
}
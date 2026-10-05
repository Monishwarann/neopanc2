import 'dart:async';
import 'package:flutter/material.dart';
import '../models/sensor_reading.dart';
import '../models/patient.dart';
import 'api_service.dart';
import 'firestore_service.dart';
import 'network_service.dart';
import 'esp32_connection_service.dart';

enum DeviceState { initializing, connected, offline }

class DateTimeStateProvider with ChangeNotifier {
  DateTime _currentDateTime = DateTime.now();
  Timer? _timer;

  DateTime get currentDateTime => _currentDateTime;

  DateTimeStateProvider() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _currentDateTime = DateTime.now();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class ESP32StateProvider with ChangeNotifier {
  final NetworkService networkService = NetworkService();
  final ESP32ConnectionService esp32Service = ESP32ConnectionService();
  final FirestoreService _firestoreService = FirestoreService();

  SensorReading? _liveSensors;
  DeviceState _deviceState = DeviceState.initializing;
  String? _userId;
  StreamSubscription<SensorReading?>? _cloudSub;

  StreamSubscription<NetworkDetails>? _networkSub;
  StreamSubscription<ESP32Status>? _esp32StatusSub;
  StreamSubscription<SensorReading>? _esp32ReadingSub;

  SensorReading? get liveSensors => _liveSensors;
  DeviceState get deviceState => _deviceState;
  
  NetworkDetails get networkDetails => networkService.currentDetails;
  ESP32Status get esp32Status => esp32Service.status;
  
  ESP32StateProvider() {
    networkService.startMonitoring();
    
    _networkSub = networkService.networkStream.listen((details) {
      if (details.isConnected && details.networkType == 'Wi-Fi') {
        esp32Service.startConnectionLoop(details.ssid, details.gateway);
      } else {
        esp32Service.stopConnectionLoop();
      }
      notifyListeners();
    });

    _esp32StatusSub = esp32Service.statusStream.listen((status) {
      if (status == ESP32Status.connected) {
        _deviceState = DeviceState.connected;
      } else if (status == ESP32Status.searching) {
        _deviceState = DeviceState.initializing;
      } else {
        _deviceState = DeviceState.offline;
      }
      notifyListeners();
    });

    _esp32ReadingSub = esp32Service.readingStream.listen((reading) {
      _liveSensors = reading;
      notifyListeners();
    });
  }

  void updateDependencies(String? userId, String baseUrl) {
    _userId = userId;
    
    if (_userId != null) {
      _startCloudStreaming();
    } else {
      _stopCloudStreaming();
    }
  }

  void _startCloudStreaming() {
    _cloudSub?.cancel();
    _cloudSub = _firestoreService.streamLatestSensorReading(_userId!).listen((reading) {
      // Only override with cloud data if we are NOT connected locally to ESP32!
      if (esp32Service.status == ESP32Status.connected) return;

      if (reading != null) {
        final readingTime = reading.timestamp.toUtc();
        final now = DateTime.now().toUtc();
        final isFresh = now.difference(readingTime).inSeconds < 15;
        
        _liveSensors = reading;
        _deviceState = isFresh ? DeviceState.connected : DeviceState.offline;
        notifyListeners();
      } else {
        _deviceState = DeviceState.offline;
        _liveSensors = null;
        notifyListeners();
      }
    }, onError: (err) {
      print("Error streaming latest sensor reading: $err");
      _deviceState = DeviceState.offline;
      notifyListeners();
    });
  }

  void _stopCloudStreaming() {
    _cloudSub?.cancel();
    _cloudSub = null;
  }

  @override
  void dispose() {
    _networkSub?.cancel();
    _esp32StatusSub?.cancel();
    _esp32ReadingSub?.cancel();
    networkService.stopMonitoring();
    esp32Service.stopConnectionLoop();
    _stopCloudStreaming();
    super.dispose();
  }
}

class AIStateProvider with ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  Map<String, dynamic>? _latestPrediction;
  String? _userId;
  ApiService? _apiService;

  Map<String, dynamic>? get latestPrediction => _latestPrediction;

  void updateDependencies(String? userId, String baseUrl) {
    _userId = userId;
    _apiService = ApiService(baseUrl: baseUrl);
    
    if (_userId != null) {
      _startStreaming();
    } else {
      _stopStreaming();
    }
  }

  Future<Map<String, dynamic>?> evaluateScreening({
    required PatientQuestionnaire survey,
    required double tdsVoltage,
    required double mqVoltage,
    required double phVoltage,
    double? phValue,
  }) async {
    if (_userId == null || _apiService == null) return null;
    return await _apiService!.evaluateScreening(
      userId: _userId!,
      survey: survey,
      tdsVoltage: tdsVoltage,
      mqVoltage: mqVoltage,
      phVoltage: phVoltage,
      phValue: phValue,
    );
  }

  void _startStreaming() {
    _subscription?.cancel();
    _subscription = _firestoreService.streamHistoryLogs(_userId!).listen((logs) {
      if (logs.isNotEmpty) {
        _latestPrediction = logs.first;
      } else {
        _latestPrediction = null;
      }
      notifyListeners();
    }, onError: (err) {
      print("Error streaming AI prediction history: $err");
    });
  }

  void _stopStreaming() {
    _subscription?.cancel();
    _subscription = null;
    _latestPrediction = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopStreaming();
    super.dispose();
  }
}

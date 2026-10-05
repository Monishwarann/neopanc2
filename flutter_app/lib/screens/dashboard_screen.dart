import 'dart:async';
import 'dart:io';
import 'dart:convert' as dart_convert;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../services/pancreasense_api_service.dart';
import '../services/battery_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_primary_button.dart';
import '../widgets/skeleton_loader.dart';
import '../services/central_providers.dart';
import '../services/datetime_service.dart';
import 'history_screen.dart';
import 'main_wrapper.dart';
import 'about_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _userStats;
  Timer? _telemetryTimer;
  Map<String, dynamic>? _fastApiSensorData;

  @override
  void initState() {
    super.initState();
    _fetchStats();
    _fetchTelemetry();
    _telemetryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _fetchTelemetry();
    });
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning,';
    if (hour < 17) return 'Good Afternoon,';
    return 'Good Evening,';
  }

  Future<void> _fetchStats() async {
    final provider = Provider.of<UserStateProvider>(context, listen: false);
    final api = ApiService(baseUrl: provider.baseUrl);
    final userId = provider.userId ?? '1';

    final stats = await api.fetchUserStats(userId);
    if (mounted) {
      setState(() {
        _userStats = stats;
      });
    }
  }

  Future<void> _fetchTelemetry() async {
    final data = await PancreasenseApiService.fetchLatestSensorData();
    if (mounted && data != null) {
      setState(() {
        _fastApiSensorData = data['sensor'];
      });
    }
  }

  void _shareLatestReport(BuildContext context, Map<String, dynamic>? latestPrediction) async {
    final provider = Provider.of<UserStateProvider>(context, listen: false);
    final userId = provider.userId;
    if (userId == null) return;

    if (latestPrediction == null) {
      try {
        await Share.share(
          'Check out NeoPanc - an AI-driven IoT Pancreatic Cancer Risk Screening Application!',
          subject: 'NeoPanc Risk Screening App',
        );
      } catch (e) {
        print("Error sharing app info: $e");
      }
      return;
    }

    final log = latestPrediction;
    final logId = log['id']?.toString() ?? log['log_id']?.toString() ?? 'new';
    final pcriScore = log['pcri_score']?.toString() ?? '0.0';
    final riskLevel = log['risk_level']?.toString() ?? 'Low';
    final url = log['pdfUrl'] ?? log['pdf_download_url'] ?? '';

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preparing report to share...'), duration: Duration(seconds: 1)),
    );

    final shareText = 'My Pancreatic Cancer Risk Assessment Report.\nRisk Level: $riskLevel Risk (Score: $pcriScore%)\n${url.isNotEmpty ? "View Report: $url" : ""}';

    if (kIsWeb) {
      try {
        await Share.share(
          shareText,
          subject: 'Pancreatic Cancer Risk Assessment Report',
        );
      } catch (e) {
        print("Web share failed: $e");
        if (url.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: url));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Report URL copied to clipboard!'), backgroundColor: Colors.green),
            );
          }
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Sharing failed: cloud URL not ready.'), backgroundColor: Colors.redAccent),
            );
          }
        }
      }
    } else {
      try {
        final api = ApiService(baseUrl: provider.baseUrl);
        final bytes = await api.fetchPdfBytes(logId, logData: log);
        if (bytes == null) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to prepare PDF report bytes.'), backgroundColor: Colors.redAccent),
            );
          }
          return;
        }

        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/report_$logId.pdf');
        await file.writeAsBytes(bytes);

        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/pdf')],
          text: shareText,
          subject: 'Pancreatic Cancer Risk Assessment Report',
        );
      } catch (e) {
        print("Error native sharing PDF: $e");
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error sharing report: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserStateProvider>(context);
    final esp32Provider = Provider.of<ESP32StateProvider>(context);
    final aiProvider = Provider.of<AIStateProvider>(context);
    final dateTimeProvider = Provider.of<DateTimeStateProvider>(context);
    
    final theme = Theme.of(context);
    
    final _liveSensors = esp32Provider.liveSensors;
    final _deviceState = esp32Provider.deviceState;
    final _latestPrediction = aiProvider.latestPrediction;
    
    // Formatting Date and Time
    final now = dateTimeProvider.currentDateTime;
    final timeString = DateTimeService.formatTimeWithSeconds(now);
    final dateString = DateTimeService.formatDate(now);
    
    // Sensor Telemetry Extracted Data
    final tdsRaw = _fastApiSensorData?['tds_raw']?.toString() ?? '--';
    final tdsVolt = _fastApiSensorData?['tds_voltage'] != null
        ? (_fastApiSensorData!['tds_voltage'] as num).toStringAsFixed(3)
        : (_liveSensors != null ? _liveSensors.tdsVoltage.toStringAsFixed(3) : '--');

    final mqRaw = _fastApiSensorData?['mq_raw']?.toString() ?? '--';
    final mqVolt = _fastApiSensorData?['mq_voltage'] != null
        ? (_fastApiSensorData!['mq_voltage'] as num).toStringAsFixed(3)
        : (_liveSensors != null ? _liveSensors.mqVoltage.toStringAsFixed(3) : '--');

    final phRaw = _fastApiSensorData?['ph_raw']?.toString() ?? '--';
    final phVolt = _fastApiSensorData?['ph_voltage'] != null
        ? (_fastApiSensorData!['ph_voltage'] as num).toStringAsFixed(3)
        : (_liveSensors != null ? _liveSensors.phVoltage.toStringAsFixed(3) : '--');
    
    final phValueStr = _liveSensors != null ? (_liveSensors.phValue ?? _liveSensors.phVoltage).toStringAsFixed(2) : null;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchStats,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Premium Hero Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ClipOval(
                                child: Image.asset(
                                  'assets/images/6.jpeg',
                                  width: 36,
                                  height: 36,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _getGreeting(), 
                                  style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 15, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            userProvider.profileData?['username'] ?? userProvider.username ?? "User", 
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28, color: theme.colorScheme.onSurface, letterSpacing: -0.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.access_time_rounded, size: 14, color: theme.primaryColor),
                                  const SizedBox(width: 4),
                                  Text(timeString, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.calendar_today_rounded, size: 14, color: theme.primaryColor),
                                  const SizedBox(width: 4),
                                  Text(dateString, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    PremiumAvatarButton(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        try {
                          MainWrapper.switchTab(context, 3);
                        } catch (e, stack) {
                          debugPrint("Profile navigation failed: $e\n$stack");
                        }
                      },
                      child: Stack(
                        alignment: Alignment.topRight,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: theme.primaryColor.withOpacity(0.3), width: 2),
                              boxShadow: [BoxShadow(color: theme.primaryColor.withOpacity(0.2), blurRadius: 12)],
                            ),
                            child: ClipOval(
                              child: (userProvider.profileData?['profileImageUrl'] != null && userProvider.profileData!['profileImageUrl'].toString().isNotEmpty)
                                  ? Image.network(
                                      userProvider.profileData!['profileImageUrl'],
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => Container(
                                        width: 50,
                                        height: 50,
                                        color: theme.colorScheme.surface,
                                        child: Icon(Icons.person, color: theme.primaryColor, size: 28),
                                      ),
                                    )
                                  : Container(
                                      width: 50,
                                      height: 50,
                                      color: theme.colorScheme.surface,
                                      child: Icon(Icons.person, color: theme.primaryColor, size: 28),
                                    ),
                            ),
                          ),
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                              border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 20),
              
              // AI Health Summary
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.primaryColor.withOpacity(0.15), theme.colorScheme.secondary.withOpacity(0.15)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.primaryColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.psychology_rounded, color: theme.primaryColor),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AI Health Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: theme.colorScheme.onSurface)),
                          const SizedBox(height: 4),
                          Text(
                            _latestPrediction != null 
                                ? 'Your recent biomarker analysis indicates a ${_latestPrediction!['risk_level'].toString().toLowerCase()} risk level. Maintain your current routine and monitor your telemetry data.'
                                : 'Connect your ESP32 device to generate a personalized AI health summary based on your saliva biomarkers.',
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.7), height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Quick Actions Grid
              Text('Quick Actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildQuickAction(theme, Icons.add_rounded, 'New Test', () {
                    MainWrapper.switchTab(context, 1);
                  }),
                  _buildQuickAction(theme, Icons.history_rounded, 'History', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => HistoryScreen()));
                  }),
                  _buildQuickAction(theme, Icons.share_rounded, 'Share', () {
                     _shareLatestReport(context, _latestPrediction);
                  }),
                  _buildQuickAction(theme, Icons.info_outline_rounded, 'About', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()));
                  }),
                ],
              ),
              const SizedBox(height: 24),

              // Today's Health Tip
              GlassCard(
                padding: const EdgeInsets.all(16),
                borderRadius: 20,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), shape: BoxShape.circle),
                      child: const Icon(Icons.lightbulb_outline_rounded, color: Colors.orange, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Today's Tip", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: theme.colorScheme.onSurface)),
                          const SizedBox(height: 4),
                          Text(
                            "Drink at least 8 glasses of water today to keep your saliva consistency optimal for accurate sensor readings.",
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.7), height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // AI Risk Prediction Card Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'AI Risk Prediction', 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildStatusIndicator('ESP32', _deviceState == DeviceState.connected ? 'Online' : 'Offline', _deviceState),
                ],
              ),
              const SizedBox(height: 14),
              
              _latestPrediction == null && _deviceState == DeviceState.initializing
                  ? const SkeletonLoader(width: double.infinity, height: 170, borderRadius: 24)
                  : GlassCard(
                      padding: const EdgeInsets.all(20),
                      borderRadius: 24,
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Current Risk Level', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 13)),
                                    const SizedBox(height: 6),
                                    if (_latestPrediction != null)
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: _getRiskColor(_latestPrediction!['risk_level']).withOpacity(0.2),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.warning_rounded,
                                              color: _getRiskColor(_latestPrediction!['risk_level']),
                                              size: 18,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              '${_latestPrediction!['risk_level']} Risk', 
                                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      )
                                    else
                                      Row(
                                        children: [
                                          Icon(Icons.hourglass_empty, color: theme.colorScheme.onSurface.withOpacity(0.5), size: 18),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text('Waiting for Device...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.7)), overflow: TextOverflow.ellipsis),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('Risk Score', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Text(
                                      _latestPrediction != null ? '${_latestPrediction!['pcri_score']}%' : '--',
                                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28, color: theme.primaryColor),
                                    ),
                                    if (_latestPrediction != null && _latestPrediction!['ai_confidence'] != null)
                                      Builder(
                                        builder: (context) {
                                          num confidenceVal = _latestPrediction!['ai_confidence'] as num;
                                          if (confidenceVal > 100.0) {
                                            confidenceVal = confidenceVal / 100.0;
                                          }
                                          final confidence = confidenceVal.clamp(0.0, 100.0);
                                          return Text('Confidence: ${confidence.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold));
                                        }
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          AnimatedPrimaryButton(
                            text: 'Predict Now',
                            icon: Icons.analytics_outlined,
                            onPressed: _liveSensors != null ? () => Navigator.pushNamed(context, '/prediction') : null,
                          ),
                        ],
                      ),
                    ),
              
              const SizedBox(height: 28),

              // Live Sensors Section (3 SENSORS ONLY: TDS, MQ, pH)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Live Telemetry', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface)),
                ],
              ),
              const SizedBox(height: 14),
              
              if (_liveSensors == null && _fastApiSensorData == null && _deviceState == DeviceState.initializing)
                const SkeletonLoader(width: double.infinity, height: 220, borderRadius: 24)
              else
                GlassCard(
                  padding: const EdgeInsets.all(18),
                  borderRadius: 24,
                  child: Column(
                    children: [
                      // 1. TDS Sensor (GPIO 32)
                      _buildResponsiveSensorRow(
                        name: 'TDS Sensor',
                        gpio: 'GPIO 32',
                        raw: tdsRaw,
                        voltage: tdsVolt,
                        color: const Color(0xFF38BDF8),
                        icon: Icons.water_drop,
                      ),
                      Divider(color: theme.colorScheme.onSurface.withOpacity(0.08), height: 20),
                      
                      // 2. MQ Gas Sensor (GPIO 33)
                      _buildResponsiveSensorRow(
                        name: 'MQ Gas Sensor',
                        gpio: 'GPIO 33',
                        raw: mqRaw,
                        voltage: mqVolt,
                        color: const Color(0xFFF59E0B),
                        icon: Icons.air,
                      ),
                      Divider(color: theme.colorScheme.onSurface.withOpacity(0.08), height: 20),
                      
                      // 3. pH Sensor (GPIO 34)
                      _buildResponsiveSensorRow(
                        name: 'pH Sensor',
                        gpio: 'GPIO 34',
                        raw: phRaw,
                        voltage: phVolt,
                        phValue: phValueStr,
                        color: const Color(0xFFA855F7),
                        icon: Icons.science,
                      ),
                    ],
                  ),
                ),
              
              const SizedBox(height: 28),

              // Device Overview Section
              Text('Device Overview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: GlassCard(
                      padding: const EdgeInsets.all(14),
                      borderRadius: 20,
                      child: Row(
                        children: [
                          Icon(Icons.wifi_rounded, color: _deviceState == DeviceState.connected ? Colors.green : Colors.grey, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Wi-Fi', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 11)),
                                Text(_deviceState == DeviceState.connected ? 'Strong' : 'Offline', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface), overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassCard(
                      padding: const EdgeInsets.all(14),
                      borderRadius: 20,
                      child: StreamBuilder<int?>(
                        stream: BatteryService().batteryLevelStream,
                        builder: (context, snapshot) {
                          String batteryText = 'Loading...';
                          if (snapshot.hasError) {
                            batteryText = 'Unavailable';
                          } else if (snapshot.connectionState == ConnectionState.active || snapshot.connectionState == ConnectionState.done || snapshot.hasData) {
                            if (snapshot.data != null) {
                              batteryText = '${snapshot.data}%';
                            } else {
                              batteryText = 'Unavailable';
                            }
                          }

                          return Row(
                            children: [
                              const Icon(Icons.battery_charging_full_rounded, color: Colors.green, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Battery', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 11)),
                                    Text(batteryText, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface), overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    ),
  );
}

  Color _getRiskColor(String? risk) {
    if (risk == 'High') return Colors.red;
    if (risk == 'Moderate') return Colors.orange;
    return Colors.green;
  }

  Widget _buildResponsiveSensorRow({
    required String name,
    required String gpio,
    required String raw,
    required String voltage,
    String? phValue,
    required Color color,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left Side: Icon + Name + GPIO tag + Raw ADC (Expanded to eliminate flex overflow)
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              gpio,
                              style: TextStyle(
                                color: color,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Raw ADC: $raw',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Right Side: Voltage & pH value (Flexible to prevent right overflow)
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  voltage == '--' ? '-- V' : '$voltage V',
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (phValue != null && phValue != '--') ...[
                  const SizedBox(height: 2),
                  Text(
                    '$phValue pH',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(String prefix, String status, DeviceState state) {
    Color dotColor = state == DeviceState.connected ? Colors.green : (state == DeviceState.initializing ? Colors.orange : Colors.red);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: dotColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dotColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          const SizedBox(width: 6),
          Text(
            '$prefix $status',
            style: TextStyle(color: dotColor, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(ThemeData theme, IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.colorScheme.surface, theme.colorScheme.surface.withOpacity(0.8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Icon(icon, color: theme.primaryColor, size: 24),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label, 
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface.withOpacity(0.9)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PremiumAvatarButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const PremiumAvatarButton({
    super.key,
    required this.child,
    required this.onTap,
  });

  @override
  State<PremiumAvatarButton> createState() => _PremiumAvatarButtonState();
}

class _PremiumAvatarButtonState extends State<PremiumAvatarButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Material(
          color: Colors.transparent,
          child: InkResponse(
            onTap: widget.onTap,
            radius: 30,
            highlightColor: Colors.transparent,
            splashColor: Theme.of(context).primaryColor.withOpacity(0.3),
            child: Semantics(
              label: 'User Profile Avatar',
              button: true,
              hint: 'Double tap to open user profile settings',
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

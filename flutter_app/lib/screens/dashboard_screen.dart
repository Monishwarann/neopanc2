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

  @override
  void initState() {
    super.initState();
    _fetchStats();
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

  String _formatRelativeTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '--';
    try {
      final date = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inSeconds < 60) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
      if (diff.inHours < 24 && now.day == date.day) return 'Today at ${date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour)}:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';
      if (diff.inDays < 2 && now.day != date.day) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays} days ago';
      if (diff.inDays < 14) return 'Last week';
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return '--';
    }
  }

  String _formatMonthYear(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '--';
    try {
      final date = DateTime.parse(isoString).toLocal();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[date.month - 1]} ${date.year}';
    } catch (e) {
      return '--';
    }
  }

  String _calculateDaysUsing(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '--';
    try {
      final date = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);
      return '${diff.inDays}';
    } catch (e) {
      return '--';
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
    
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchStats,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24.0),
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
                              Text(
                                _getGreeting(), 
                                style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            userProvider.profileData?['username'] ?? userProvider.username ?? "User", 
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 32, color: theme.colorScheme.onSurface, letterSpacing: -0.5),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.access_time_rounded, size: 14, color: theme.primaryColor),
                              const SizedBox(width: 4),
                              Text(timeString, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 12),
                              Icon(Icons.calendar_today_rounded, size: 14, color: theme.primaryColor),
                              const SizedBox(width: 4),
                              Text(dateString, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    PremiumAvatarButton(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        try {
                          MainWrapper.switchTab(context, 3);
                        } catch (e, stack) {
                          debugPrint("Profile navigation failed: $e\n$stack");
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Cannot navigate to profile screen: $e'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
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
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => Container(
                                        width: 56,
                                        height: 56,
                                        color: theme.colorScheme.surface,
                                        child: Icon(Icons.person, color: theme.primaryColor, size: 32),
                                      ),
                                    )
                                  : (userProvider.profileData?['profileImageBase64'] != null && userProvider.profileData!['profileImageBase64'].toString().isNotEmpty
                                      ? Image.memory(
                                          dart_convert.base64Decode(userProvider.profileData!['profileImageBase64']),
                                          width: 56,
                                          height: 56,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          width: 56,
                                          height: 56,
                                          color: theme.colorScheme.surface,
                                          child: Icon(Icons.person, color: theme.primaryColor, size: 32),
                                        )),
                            ),
                          ),
                          Container(
                            width: 14,
                            height: 14,
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
              const SizedBox(height: 24),
              
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
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AI Health Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface)),
                          const SizedBox(height: 4),
                          Text(
                            _latestPrediction != null 
                                ? 'Your recent biomarker analysis indicates a ${_latestPrediction!['risk_level'].toString().toLowerCase()} risk level. Maintain your current routine and monitor your telemetry data.'
                                : 'Connect your ESP32 device to generate a personalized AI health summary based on your saliva biomarkers.',
                            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.7), height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Quick Actions Grid
              Text('Quick Actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 16),
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
              const SizedBox(height: 32),

              // Today's Health Tip
              GlassCard(
                padding: const EdgeInsets.all(20),
                borderRadius: 20,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), shape: BoxShape.circle),
                      child: const Icon(Icons.lightbulb_outline_rounded, color: Colors.orange),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Today's Tip", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface)),
                          const SizedBox(height: 4),
                          Text(
                            "Drink at least 8 glasses of water today to keep your saliva consistency optimal for accurate sensor readings.",
                            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.7), height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // AI Risk Prediction Card
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('AI Risk Prediction', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: theme.colorScheme.onSurface)),
                  _buildStatusIndicator('ESP32', _deviceState == DeviceState.connected ? 'Online' : 'Offline', _deviceState),
                ],
              ),
              const SizedBox(height: 16),
              
              _latestPrediction == null && _deviceState == DeviceState.initializing
                  ? const SkeletonLoader(width: double.infinity, height: 180, borderRadius: 24)
                  : GlassCard(
                      padding: const EdgeInsets.all(24),
                      borderRadius: 24,
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Current Risk Level', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 14)),
                                  const SizedBox(height: 8),
                                  if (_latestPrediction != null)
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: _getRiskColor(_latestPrediction!['risk_level']).withOpacity(0.2),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.warning_rounded,
                                            color: _getRiskColor(_latestPrediction!['risk_level']),
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          '${_latestPrediction!['risk_level']} Risk', 
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: theme.colorScheme.onSurface),
                                        ),
                                      ],
                                    )
                                  else
                                    Row(
                                      children: [
                                        Icon(Icons.hourglass_empty, color: theme.colorScheme.onSurface.withOpacity(0.5), size: 20),
                                        const SizedBox(width: 8),
                                        Text('Waiting for Device...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface.withOpacity(0.7))),
                                      ],
                                    ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('Risk Score', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 14)),
                                  const SizedBox(height: 4),
                                  Text(
                                    _latestPrediction != null ? '${_latestPrediction!['pcri_score']}%' : '--',
                                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 32, color: theme.primaryColor),
                                  ),
                                  if (_latestPrediction != null && _latestPrediction!['ai_confidence'] != null)
                                    Builder(
                                      builder: (context) {
                                        num confidenceVal = _latestPrediction!['ai_confidence'] as num;
                                        if (confidenceVal > 100.0) {
                                          confidenceVal = confidenceVal / 100.0;
                                        }
                                        final confidence = confidenceVal.clamp(0.0, 100.0);
                                        return Text('Confidence: ${confidence.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold));
                                      }
                                    ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          AnimatedPrimaryButton(
                            text: 'Predict Now',
                            icon: Icons.analytics_outlined,
                            onPressed: _liveSensors != null ? () => Navigator.pushNamed(context, '/prediction') : null,
                          ),
                        ],
                      ),
                    ),
              
              const SizedBox(height: 32),



              // Live Sensors Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Live Telemetry', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: theme.colorScheme.onSurface)),
                ],
              ),
              const SizedBox(height: 16),
              
              if (_liveSensors == null && _deviceState == DeviceState.initializing)
                const SkeletonLoader(width: double.infinity, height: 280, borderRadius: 24)
              else
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  borderRadius: 24,
                  child: Column(
                    children: [
                      _buildSensorRow('TDS Sensor', _liveSensors?.salivaEc.toStringAsFixed(2) ?? '--', 'V', Colors.blue),
                      Divider(color: theme.colorScheme.onSurface.withOpacity(0.05), height: 24),
                      _buildSensorRow('MQ3 (Alcohol)', _liveSensors?.mq3Ppm.toStringAsFixed(1) ?? '--', 'PPM', Colors.pink),
                      Divider(color: theme.colorScheme.onSurface.withOpacity(0.05), height: 24),
                      _buildSensorRow('Saliva pH', _liveSensors?.salivaPh.toStringAsFixed(2) ?? '--', 'pH', Colors.teal),
                      Divider(color: theme.colorScheme.onSurface.withOpacity(0.05), height: 24),
                      _buildSensorRow('Saliva EC', _liveSensors?.salivaEc.toStringAsFixed(2) ?? '--', 'mS/cm', Colors.purple),
                    ],
                  ),
                ),
              
              const SizedBox(height: 32),
              // Device Overview
              Text('Device Overview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GlassCard(
                      padding: const EdgeInsets.all(16),
                      borderRadius: 20,
                      child: Row(
                        children: [
                          Icon(Icons.wifi_rounded, color: _deviceState == DeviceState.connected ? Colors.green : Colors.grey),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Wi-Fi', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 12)),
                                Text(_deviceState == DeviceState.connected ? 'Strong' : 'Offline', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GlassCard(
                      padding: const EdgeInsets.all(16),
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
                              Icon(Icons.battery_charging_full_rounded, color: Colors.green),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Battery', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 12)),
                                    Text(batteryText, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
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
              const SizedBox(height: 40),
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

  Widget _buildSensorRow(String name, String value, String unit, Color color) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.sensors, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Text(name, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.8), fontSize: 16, fontWeight: FontWeight.w500)),
          ],
        ),
        Row(
          children: [
            Text(value, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            Text(unit, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusIndicator(String prefix, String status, DeviceState state) {
    Color dotColor = state == DeviceState.connected ? Colors.green : (state == DeviceState.initializing ? Colors.orange : Colors.red);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          const SizedBox(width: 8),
          Text(
            '$prefix $status',
            style: TextStyle(color: dotColor, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(ThemeData theme, IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.colorScheme.surface, theme.colorScheme.surface.withOpacity(0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 5)),
              ],
            ),
            child: Icon(icon, color: theme.primaryColor, size: 28),
          ),
          const SizedBox(height: 10),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface.withOpacity(0.9))),
        ],
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
            radius: 32,
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

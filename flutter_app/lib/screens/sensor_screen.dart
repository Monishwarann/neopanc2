import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:app_settings/app_settings.dart';
import '../services/network_service.dart';
import '../services/esp32_connection_service.dart';
import '../main.dart';
import '../services/central_providers.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_primary_button.dart';

class SensorScreen extends StatefulWidget {
  const SensorScreen({super.key});

  @override
  State<SensorScreen> createState() => _SensorScreenState();
}

class _SensorScreenState extends State<SensorScreen> with TickerProviderStateMixin {
  List<FlSpot> mq135Data = [];
  List<FlSpot> mq3Data = [];
  int _counter = 0;
  DeviceState _deviceState = DeviceState.initializing;
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  List<String> _logs = ["System Initialized", "Waiting for ESP32 connection..."];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final esp32 = Provider.of<ESP32StateProvider>(context, listen: false);
      esp32.addListener(_onEsp32Update);
      _onEsp32Update(); // trigger initial sync
    });
  }

  @override
  void dispose() {
    final esp32 = Provider.of<ESP32StateProvider>(context, listen: false);
    esp32.removeListener(_onEsp32Update);
    _pulseController.dispose();
    super.dispose();
  }

  void _addLog(String message) {
    if (_logs.length > 5) _logs.removeAt(0);
    final time = "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}";
    _logs.add("[$time] $message");
  }

  void _onEsp32Update() {
    if (!mounted) return;
    final esp32 = Provider.of<ESP32StateProvider>(context, listen: false);
    
    final reading = esp32.liveSensors;
    final isFresh = esp32.deviceState == DeviceState.connected;

    setState(() {
      if (_deviceState != DeviceState.connected && isFresh) {
        _addLog("Connected to ESP32 stream");
      } else if (_deviceState == DeviceState.connected && !isFresh) {
        _addLog("Lost connection to ESP32 stream");
      }
      
      _deviceState = esp32.deviceState == DeviceState.connected ? DeviceState.connected : DeviceState.offline;
      
      if (isFresh && reading != null) {
        if (mq135Data.length > 20) {
          mq135Data.removeAt(0);
          mq3Data.removeAt(0);
        }
        mq135Data.add(FlSpot(_counter.toDouble(), reading.tdsVoltage));
        mq3Data.add(FlSpot(_counter.toDouble(), reading.mqVoltage));
        _counter++;
      }
    });
  }

  void _restartDevice() {
    setState(() {
      _addLog("Sending restart command...");
      _deviceState = DeviceState.initializing;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _addLog("ESP32 rebooting..."));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esp32 = Provider.of<ESP32StateProvider>(context);
    final netDetails = esp32.networkDetails;
    final esp32Status = esp32.esp32Status;
    final esp32Service = esp32.esp32Service;

    final isOnline = _deviceState == DeviceState.connected;
    final statusColor = isOnline ? Colors.green : (esp32Status == ESP32Status.searching ? Colors.orange : Colors.redAccent);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipOval(
              child: Image.asset(
                'assets/images/6.jpeg',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            const Text('IoT Dashboard'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Row(
              children: [
                ScaleTransition(
                  scale: isOnline ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                  child: Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle, boxShadow: [BoxShadow(color: statusColor.withOpacity(0.5), blurRadius: 8)]),
                  ),
                ),
                const SizedBox(width: 8),
                Text(isOnline ? 'LIVE' : (esp32Status == ESP32Status.searching ? 'SEARCHING' : (esp32Status == ESP32Status.connecting ? 'CONNECTING' : 'OFFLINE')), style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Device Info & Status
            Row(
              children: [
                Expanded(
                  child: GlassCard(
                    padding: const EdgeInsets.all(20),
                    borderRadius: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.router_rounded, color: theme.primaryColor),
                            const SizedBox(width: 8),
                            Text('ESP32 Node', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface)),
                          ],
                        ),
                        Divider(color: theme.colorScheme.onSurface.withOpacity(0.1), height: 24),
                        _buildInfoRow('Status', isOnline ? 'Connected' : (esp32Status == ESP32Status.searching ? 'Searching...' : 'Disconnected'), theme),
                        const SizedBox(height: 8),
                        _buildInfoRow('Firmware', esp32Service.firmwareVersion, theme),
                        const SizedBox(height: 8),
                        _buildInfoRow('Latency', isOnline ? '${esp32Service.latency} ms' : '--', theme),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      if (kIsWeb) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Wi-Fi settings cannot be opened from a web browser. Please configure Wi-Fi in your system settings.'),
                            backgroundColor: Colors.orangeAccent,
                          ),
                        );
                        return;
                      }
                      try {
                        await AppSettings.openAppSettings(type: AppSettingsType.wifi);
                      } catch (e) {
                        debugPrint("Error opening settings: $e");
                        try {
                          await AppSettings.openAppSettings();
                        } catch (_) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Cannot open settings page: $e')),
                          );
                        }
                      }
                    },
                    onLongPress: () {
                      _showNetworkDiagnosticSheet(context, netDetails, esp32);
                    },
                    child: GlassCard(
                      padding: const EdgeInsets.all(20),
                      borderRadius: 24,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.network_check_rounded, color: Colors.blue),
                              const SizedBox(width: 8),
                              Text('Network', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface)),
                            ],
                          ),
                          Divider(color: theme.colorScheme.onSurface.withOpacity(0.1), height: 24),
                          _buildInfoRow('Status', netDetails.isConnected ? netDetails.networkType : 'Offline', theme),
                          const SizedBox(height: 8),
                          _buildInfoRow('SSID', netDetails.isConnected ? netDetails.ssid : 'Not Connected', theme),
                          const SizedBox(height: 8),
                          _buildInfoRow('Quality', netDetails.isConnected ? '${netDetails.signalQuality} (${netDetails.rssi} dBm)' : '--', theme),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Animated Sensor Cards
            if (isOnline && mq135Data.isNotEmpty) ...[
              Text('Live Sensor Values', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _buildAnimatedSensorCard('TDS Sensor', '${mq135Data.last.y.toStringAsFixed(2)} V', Colors.blue, theme),
                    const SizedBox(width: 16),
                    _buildAnimatedSensorCard('MQ3', '${mq3Data.last.y.toStringAsFixed(1)} PPM', Colors.pink, theme),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Live Chart
            GlassCard(
              padding: const EdgeInsets.all(20.0),
              borderRadius: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.show_chart_rounded, color: theme.primaryColor),
                          const SizedBox(width: 8),
                          Text('Real-Time Telemetry', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface)),
                        ],
                      ),
                      if (isOnline)
                        Row(
                          children: [
                            const SizedBox(
                              width: 12, height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text('Auto-refreshing', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 12)),
                          ],
                        )
                    ],
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 250,
                    child: _deviceState == DeviceState.initializing && mq135Data.isEmpty
                        ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
                        : LineChart(
                            LineChartData(
                              gridData: FlGridData(
                                show: true, 
                                drawVerticalLine: false, 
                                getDrawingHorizontalLine: (val) => FlLine(color: theme.colorScheme.onSurface.withOpacity(0.1), strokeWidth: 1),
                              ),
                              titlesData: FlTitlesData(
                                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 10)))),
                                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              borderData: FlBorderData(show: false),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: mq135Data.isEmpty ? [const FlSpot(0, 0)] : mq135Data,
                                  isCurved: true,
                                  color: Colors.blue,
                                  barWidth: 3,
                                  isStrokeCapRound: true,
                                  dotData: FlDotData(show: false),
                                  belowBarData: BarAreaData(show: true, color: Colors.blue.withOpacity(0.1)),
                                ),
                                LineChartBarData(
                                  spots: mq3Data.isEmpty ? [const FlSpot(0, 0)] : mq3Data,
                                  isCurved: true,
                                  color: Colors.pink,
                                  barWidth: 3,
                                  isStrokeCapRound: true,
                                  dotData: FlDotData(show: false),
                                  belowBarData: BarAreaData(show: true, color: Colors.pink.withOpacity(0.1)),
                                ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLegendItem('TDS Sensor', Colors.blue),
                      const SizedBox(width: 16),
                      _buildLegendItem('MQ3 (Alcohol)', Colors.pink),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Connection Logs
            GlassCard(
              padding: const EdgeInsets.all(20),
              borderRadius: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.terminal_rounded, color: theme.colorScheme.onSurface.withOpacity(0.7)),
                          const SizedBox(width: 8),
                          Text('System Logs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface)),
                        ],
                      ),
                    ],
                  ),
                  Divider(color: theme.colorScheme.onSurface.withOpacity(0.1), height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    height: 120,
                    child: ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: Text(
                            _logs[index],
                            style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.8)),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            OutlinedButton.icon(
              onPressed: _restartDevice,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Restart ESP32 Device'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                foregroundColor: Colors.orange,
                side: BorderSide(color: Colors.orange.withOpacity(0.3)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 12)),
        Text(value, style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }

  Widget _buildStatusRow(String text, bool active) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.circle, color: active ? Colors.greenAccent : Colors.redAccent, size: 12),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(color: active ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8))),
      ],
    );
  }

  Widget _buildAnimatedSensorCard(String label, String value, Color color, ThemeData theme) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(value),
      tween: Tween(begin: 0.8, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 140,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.3), width: 1.5),
              boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.sensors, color: color, size: 20),
                    const SizedBox(width: 8),
                    Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.7))),
                  ],
                ),
                const SizedBox(height: 12),
                Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: theme.colorScheme.onSurface)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showNetworkDiagnosticSheet(BuildContext context, NetworkDetails details, ESP32StateProvider esp32) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Network Diagnostics',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: theme.colorScheme.onSurface),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white10, height: 24),
              _buildDiagRow('SSID', details.ssid, theme),
              _buildDiagRow('BSSID', details.bssid, theme),
              _buildDiagRow('Local IP', details.ip, theme),
              _buildDiagRow('Gateway IP', details.gateway, theme),
              _buildDiagRow('Network Type', details.networkType, theme),
              _buildDiagRow('Internet Access', details.hasInternet ? 'Active' : 'Offline', theme),
              _buildDiagRow('Signal RSSI', '${details.rssi} dBm', theme),
              _buildDiagRow('Connection Duration', details.durationString, theme),
              _buildDiagRow('Auto Reconnect', 'Enabled', theme),
              _buildDiagRow('ESP32 Status', esp32.esp32Status.name.toUpperCase(), theme),
              if (esp32.esp32Status == ESP32Status.connected)
                _buildDiagRow('ESP32 Latency', '${esp32.esp32Service.latency} ms', theme),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDiagRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 14)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface)),
        ],
      ),
    );
  }
}

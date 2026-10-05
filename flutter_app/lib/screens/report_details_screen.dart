import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../main.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';
import '../services/datetime_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_primary_button.dart';

class ReportDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> log;
  const ReportDetailsScreen({super.key, required this.log});

  @override
  State<ReportDetailsScreen> createState() => _ReportDetailsScreenState();
}

class _ReportDetailsScreenState extends State<ReportDetailsScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  late TextEditingController _notesController;
  bool _isSavingNotes = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: widget.log['doctor_notes'] ?? '');
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveDoctorNotes() async {
    setState(() => _isSavingNotes = true);
    final provider = Provider.of<UserStateProvider>(context, listen: false);
    final userId = provider.userId ?? '1';
    final logId = widget.log['id'] ?? widget.log['log_id'] ?? 'new';

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('predictionHistory')
          .doc(logId)
          .update({
        'doctor_notes': _notesController.text,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Doctor notes saved successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      print("Error saving doctor notes: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save notes: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingNotes = false);
    }
  }

  void _downloadPdf() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.1;
    });

    final provider = Provider.of<UserStateProvider>(context, listen: false);
    final api = ApiService(baseUrl: provider.baseUrl);
    final logId = widget.log['id']?.toString() ?? widget.log['log_id']?.toString() ?? 'new';

    // Simulate download progress
    for (int i = 2; i <= 9; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        setState(() {
          _downloadProgress = i / 10.0;
        });
      }
    }

    final file = await api.downloadPdf(logId, logData: widget.log);

    if (mounted) {
      setState(() {
        _isDownloading = false;
        _downloadProgress = 1.0;
      });

      if (file != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report downloaded successfully.'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to download PDF report.'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _shareReport() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preparing report to share...'), duration: Duration(seconds: 1)),
    );
    final provider = Provider.of<UserStateProvider>(context, listen: false);
    final api = ApiService(baseUrl: provider.baseUrl);
    final logId = widget.log['id']?.toString() ?? widget.log['log_id']?.toString() ?? 'new';
    
    final bytes = await api.fetchPdfBytes(logId, logData: widget.log);
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to prepare sharing file.'), backgroundColor: Colors.redAccent),
        );
      }
      return;
    }
    
    // Trigger share sheet (web uses link sharing, mobile uses files)
    final url = widget.log['pdfUrl'] ?? widget.log['pdf_download_url'] ?? '';
    if (kIsWeb) {
      if (url.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copied cloud report URL to clipboard: $url'), duration: const Duration(seconds: 4)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sharing not supported on this platform without cloud copy.'), backgroundColor: Colors.redAccent),
        );
      }
    } else {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/report_$logId.pdf');
      await file.writeAsBytes(bytes);
      // Fallback share info
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report saved to temporary directory: ${file.path}')),
      );
    }
  }

  void _deleteReport() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete Report?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'This will permanently delete the report Firestore log and the cloud PDF document. This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white30)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final provider = Provider.of<UserStateProvider>(context, listen: false);
      final userId = provider.userId ?? '1';
      final logId = widget.log['id'] ?? widget.log['log_id'] ?? 'new';

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deleting report from cloud storage...')),
      );

      await _firebaseService.deletePredictionLog(userId, logId);
      await _firebaseService.deleteMedicalReport(userId, logId);

      if (mounted) {
        Navigator.pop(context); // Close details page
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report deleted successfully.'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final riskLevel = widget.log['risk_level'] ?? 'Low';
    
    Color riskColor = Colors.green;
    IconData riskIcon = Icons.check_circle_rounded;
    if (riskLevel == 'Moderate') {
      riskColor = Colors.orange;
      riskIcon = Icons.warning_rounded;
    } else if (riskLevel == 'High') {
      riskColor = Colors.redAccent;
      riskIcon = Icons.error_rounded;
    }

    final timestamp = DateTimeService.parseToLocal(widget.log['timestamp'] ?? widget.log['createdAt']);
    final dateStr = DateTimeService.formatDate(timestamp);
    final timeStr = DateTimeService.formatTimeWithSeconds(timestamp);

    final sensors = widget.log['sensors'] ?? {};
    final survey = widget.log['survey'] ?? {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medical Report Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: _deleteReport,
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            GlassCard(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'REPORT #${widget.log['id'] ?? 'N/A'}',
                          style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.log['patient_name'] ?? 'Patient Name',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Generated: $dateStr • $timeStr',
                          style: const TextStyle(color: Colors.white30, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: riskColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: riskColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(riskIcon, color: riskColor, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          riskLevel.toUpperCase(),
                          style: TextStyle(color: riskColor, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Diagnostic Results Gauge Row
            Row(
              children: [
                Expanded(
                  child: GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('PCRI Score', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '${widget.log['pcri_score'] ?? 0.0}',
                              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white),
                            ),
                            const Text(' / 100', style: TextStyle(fontSize: 14, color: Colors.white30)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('AI Confidence', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 8),
                        Text(
                          '${widget.log['ai_confidence'] ?? 0.0}%',
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Patient Information Grid
            const Text('Patient Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 12),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.2,
                children: [
                  _buildGridItem('Age', '${widget.log['age'] ?? survey['age'] ?? 'N/A'} yrs'),
                  _buildGridItem('Gender', '${widget.log['gender'] ?? survey['gender'] ?? 'N/A'}'),
                  _buildGridItem('Blood Group', '${widget.log['bloodGroup'] ?? survey['bloodGroup'] ?? 'N/A'}'),
                  _buildGridItem('BMI', '${widget.log['bmi'] ?? survey['bmi'] ?? 'N/A'}'),
                  _buildGridItem('Height', '${widget.log['height'] ?? survey['height'] ?? 'N/A'} cm'),
                  _buildGridItem('Weight', '${widget.log['weight'] ?? survey['weight'] ?? 'N/A'} kg'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ESP32 Sensor Readings
            const Text('ESP32 Multi-Sensor Metrics', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 12),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildMetricRow('TDS Sensor (GPIO 32)', 'Raw: ${widget.log['tds_raw'] ?? sensors['tds_raw'] ?? '--'}  |  ${widget.log['tds_voltage'] ?? sensors['tds_voltage'] ?? '--'} V'),
                  const Divider(color: Colors.white10),
                  _buildMetricRow('MQ Gas Sensor (GPIO 33)', 'Raw: ${widget.log['mq_raw'] ?? sensors['mq_raw'] ?? '--'}  |  ${widget.log['mq_voltage'] ?? sensors['mq_voltage'] ?? '--'} V'),
                  const Divider(color: Colors.white10),
                  _buildMetricRow('pH Sensor (GPIO 34)', 'Raw: ${widget.log['ph_raw'] ?? sensors['ph_raw'] ?? '--'}  |  ${widget.log['ph_voltage'] ?? sensors['ph_voltage'] ?? '--'} V'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ESP32 Hardware Info
            const Text('Hardware Integrity Logs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 12),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildMetricRow('Device ID', widget.log['esp32_device_id'] ?? 'ESP32_EMULATOR'),
                  const Divider(color: Colors.white10),
                  _buildMetricRow('Firmware Version', widget.log['firmware_version'] ?? '1.0.2-stable'),
                  const Divider(color: Colors.white10),
                  _buildMetricRow('Status', widget.log['report_status'] ?? 'Completed'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Recommendation Summary
            const Text('Clinical & AI Recommendations', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 12),
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Text(
                widget.log['ai_recommendation'] ?? widget.log['recommendations'] ?? 'No recommendations logged.',
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
              ),
            ),
            const SizedBox(height: 24),

            // Interactive Doctor Notes
            const Text('Doctor Notes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 12),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _notesController,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Enter clinical observations or follow-up notes here...',
                      hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isSavingNotes ? null : _saveDoctorNotes,
                        icon: _isSavingNotes 
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.save_outlined, size: 16, color: Colors.white),
                        label: const Text('Save Notes', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      )
                    ],
                  )
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Downloads & Actions Bar
            if (_isDownloading) ...[
              LinearProgressIndicator(value: _downloadProgress, color: theme.primaryColor, backgroundColor: Colors.white10),
              const SizedBox(height: 8),
              Center(child: Text('Downloading PDF (${(_downloadProgress * 100).toInt()}%)...', style: const TextStyle(color: Colors.white54, fontSize: 12))),
              const SizedBox(height: 24),
            ],

            Row(
              children: [
                Expanded(
                  child: AnimatedPrimaryButton(
                    text: 'Download PDF',
                    icon: Icons.download,
                    onPressed: _isDownloading ? null : _downloadPdf,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AnimatedPrimaryButton(
                    text: 'Share Report',
                    icon: Icons.share,
                    onPressed: _shareReport,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildGridItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: const TextStyle(color: Colors.white30, fontSize: 11), overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label, 
              style: const TextStyle(color: Colors.white54, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value, 
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../models/patient.dart';
import '../services/central_providers.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_primary_button.dart';
import '../widgets/custom_text_field.dart';
import '../services/firestore_service.dart';
import '../services/datetime_service.dart';

class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key});

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  late AnimationController _scanAnimationController;

  @override
  void initState() {
    super.initState();
    _scanAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Warm up backend api on screen mount to handle cold-start spun down services
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final userProvider = Provider.of<UserStateProvider>(context, listen: false);
        ApiService(baseUrl: userProvider.baseUrl).pingServer();
      } catch (e) {
        print("Backend warm up error: $e");
      }
    });
  }

  @override
  void dispose() {
    _scanAnimationController.dispose();
    super.dispose();
  }

  bool _smoking = false;
  bool _alcohol = false;
  bool _diabetes = false;
  bool _familyHistory = false;
  bool _weightLoss = false;
  bool _abdominalPain = false;
  bool _appetiteChanges = false;
  bool _jaundice = false;

  bool _isLoading = false;
  int _processingStep = 0;
  Map<String, dynamic>? _predictionResult;
  final FirebaseService _firebaseService = FirebaseService();

  void _runDiagnosticScan() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _processingStep = 1;
      _predictionResult = null;
    });

    try {
      final userProvider = Provider.of<UserStateProvider>(context, listen: false);
      final esp32Provider = Provider.of<ESP32StateProvider>(context, listen: false);
      final aiProvider = Provider.of<AIStateProvider>(context, listen: false);

      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      setState(() => _processingStep = 2);

      final latestReading = esp32Provider.liveSensors;
      
      final tdsVoltage = latestReading?.tdsVoltage ?? 0.0;
      final mqVoltage = latestReading?.mqVoltage ?? 0.0;
      final phVoltage = latestReading?.phVoltage ?? 0.0;
      final phValue = latestReading?.phValue ?? phVoltage;

      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      setState(() => _processingStep = 3);

      final profile = userProvider.profileData ?? {};
      final age = profile['age'] is num ? (profile['age'] as num).toInt() : int.tryParse(profile['age']?.toString() ?? '45') ?? 45;
      final bmi = profile['bmi'] is num ? (profile['bmi'] as num).toDouble() : double.tryParse(profile['bmi']?.toString() ?? '23.5') ?? 23.5;
      final height = profile['height'] is num ? (profile['height'] as num).toDouble() : double.tryParse(profile['height']?.toString() ?? '170.0') ?? 170.0;
      final weight = profile['weight'] is num ? (profile['weight'] as num).toDouble() : double.tryParse(profile['weight']?.toString() ?? '70.0') ?? 70.0;
      final gender = profile['gender']?.toString() ?? 'Male';
      final bloodGroup = profile['bloodGroup']?.toString() ?? 'O+';

      final survey = PatientQuestionnaire(
        age: age,
        gender: gender,
        bloodGroup: bloodGroup,
        height: height,
        weight: weight,
        bmi: bmi,
        smokingHistory: _smoking ? 1 : 0,
        alcoholConsumption: _alcohol ? 1 : 0,
        diabetes: _diabetes ? 1 : 0,
        familyHistory: _familyHistory ? 1 : 0,
        weightLoss: _weightLoss ? 1 : 0,
        abdominalPain: _abdominalPain ? 1 : 0,
        appetiteChanges: _appetiteChanges ? 1 : 0,
        jaundice: _jaundice ? 1 : 0,
      );

      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      setState(() => _processingStep = 4);

      var res = await aiProvider.evaluateScreening(
        survey: survey,
        tdsVoltage: tdsVoltage,
        mqVoltage: mqVoltage,
        phVoltage: phVoltage,
        phValue: phValue,
      );

      // Secure local fallback and automatic cloud report generation
      if (res != null) {
        final finalRes = Map<String, dynamic>.from(res);
        
        // Pre-create Firestore document to obtain reportId
        String reportId = 'local_log_' + DateTime.now().millisecondsSinceEpoch.toString();
        DocumentReference? docRef;
        try {
          docRef = FirebaseFirestore.instance
              .collection('users')
              .doc(userProvider.userId ?? '1')
              .collection('predictionHistory')
              .doc();
          reportId = docRef.id;
        } catch (e) {
          print("Warning: Failed to pre-create Firestore doc ref: $e");
        }

        final profile = userProvider.profileData ?? {};
        final age = profile['age'] is num ? (profile['age'] as num).toInt() : int.tryParse(profile['age']?.toString() ?? '45') ?? 45;
        final bmi = profile['bmi'] is num ? (profile['bmi'] as num).toDouble() : double.tryParse(profile['bmi']?.toString() ?? '23.5') ?? 23.5;
        final patientName = profile['username']?.toString() ?? userProvider.username ?? 'Patient';

        final logData = {
          'id': reportId,
          'reportId': reportId,
          'userId': userProvider.userId ?? '1',
          'patient_name': patientName,
          'age': age,
          'gender': profile['gender']?.toString() ?? 'Male',
          'bloodGroup': profile['bloodGroup']?.toString() ?? 'O+',
          'height': profile['height'] is num ? (profile['height'] as num).toDouble() : 170.0,
          'weight': profile['weight'] is num ? (profile['weight'] as num).toDouble() : 70.0,
          'bmi': bmi,
          'prediction_score': finalRes['pcri_score'] ?? 0.0,
          'pcri_score': finalRes['pcri_score'] ?? 0.0,
          'risk_level': finalRes['risk_level'] ?? 'Low',
          'ai_confidence': finalRes['ai_confidence'] ?? 0.0,
          'timestamp': FieldValue.serverTimestamp(),
          'predictionTimestamp': DateTime.now().toUtc().toIso8601String(),
          'deviceTimestamp': DateTime.now().toIso8601String(),
          'esp32_device_id': esp32Provider.deviceState == DeviceState.connected ? 'ESP32_DEV_NEOPANC' : 'ESP32_EMULATOR',
          'firmware_version': '1.0.2-stable',
          'tds_voltage': tdsVoltage,
          'mq_voltage': mqVoltage,
          'ph_voltage': phVoltage,
          'ph_value': phValue,
          'ai_recommendation': finalRes['recommendations'] ?? '',
          'clinical_recommendation': finalRes['recommendations'] ?? '',
          'pdf_storage_path': 'users/${userProvider.userId}/reports/$reportId.pdf',
          'pdf_file_name': 'report_$reportId.pdf',
          'report_status': 'Completed',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'serverTimestamp': FieldValue.serverTimestamp(),
          'lastViewed': FieldValue.serverTimestamp(),
          'lastModified': FieldValue.serverTimestamp(),
          'timezone': DateTime.now().timeZoneName,
          'deviceTimeZoneOffset': DateTime.now().timeZoneOffset.toString(),
        };

        logData['components'] = finalRes['components'] ?? {};
        logData['sensors'] = {
          'tds_raw': latestReading?.tdsRaw ?? 0,
          'tds_voltage': tdsVoltage,
          'mq_raw': latestReading?.mqRaw ?? 0,
          'mq_voltage': mqVoltage,
          'ph_raw': latestReading?.phRaw ?? 0,
          'ph_voltage': phVoltage,
          'ph_value': phValue,
        };
        logData['survey'] = {
          'age': age,
          'bmi': bmi,
          'gender': profile['gender']?.toString() ?? 'Male',
          'bloodGroup': profile['bloodGroup']?.toString() ?? 'O+',
          'height': profile['height'] is num ? (profile['height'] as num).toDouble() : 170.0,
          'weight': profile['weight'] is num ? (profile['weight'] as num).toDouble() : 70.0,
          'smoking_history': _smoking ? 1 : 0,
          'alcohol_consumption': _alcohol ? 1 : 0,
          'diabetes': _diabetes ? 1 : 0,
          'family_history': _familyHistory ? 1 : 0,
          'weight_loss': _weightLoss ? 1 : 0,
          'abdominal_pain': _abdominalPain ? 1 : 0,
          'appetite_changes': _appetiteChanges ? 1 : 0,
          'jaundice': _jaundice ? 1 : 0,
        };

        // Write the prediction to Firestore immediately (fast operation)
        if (docRef != null) {
          try {
            await docRef.set(logData);
          } catch (e) {
            print("Error writing prediction to Firestore: $e");
          }
        }
        
        // Update result reference immediately so UI finishes scanning
        finalRes['log_id'] = reportId;
        finalRes['timestamp'] = logData['predictionTimestamp'];
        finalRes['pdfUrl'] = ''; // initially empty, updated in background
        res = finalRes;

        // Generate & upload PDF report in the background asynchronously (non-blocking)
        _runBackgroundPdfUpload(userProvider.baseUrl, userProvider.userId ?? '1', reportId, logData, docRef);
      }

      if (mounted) {
        if (res != null) {
          setState(() => _processingStep = 5);
          await Future.delayed(const Duration(milliseconds: 600));
          if (!mounted) return;
          setState(() => _processingStep = 6);
          await Future.delayed(const Duration(milliseconds: 800));
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _predictionResult = res;
          });
        } else {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to calculate risk screening score.'), backgroundColor: Colors.redAccent),
          );
        }
      }
    } catch (e, stack) {
      print("Error in diagnostic scan: $e\n$stack");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error running diagnostic scan: ${e.toString()}'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _exportPdf() async {
    if (_predictionResult == null) return;
    final logId = _predictionResult!['log_id']?.toString() ?? _predictionResult!['id']?.toString();
    if (logId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot export report: log ID missing.'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    
    final provider = Provider.of<UserStateProvider>(context, listen: false);
    final userId = provider.userId;
    if (userId == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating & Uploading PDF Report to cloud...'), duration: Duration(seconds: 2)),
    );
    
    final api = ApiService(baseUrl: provider.baseUrl);
    
    // Construct self-contained logData payload
    final profile = provider.profileData ?? {};
    final age = profile['age'] is num ? (profile['age'] as num).toInt() : int.tryParse(profile['age']?.toString() ?? '45') ?? 45;
    final bmi = profile['bmi'] is num ? (profile['bmi'] as num).toDouble() : double.tryParse(profile['bmi']?.toString() ?? '23.5') ?? 23.5;
    final latestReading = Provider.of<ESP32StateProvider>(context, listen: false).liveSensors;
    
    final logData = {
      'user_id': userId,
      'pcri_score': _predictionResult!['pcri_score'],
      'risk_level': _predictionResult!['risk_level'],
      'ai_confidence': _predictionResult!['ai_confidence'],
      'recommendations': _predictionResult!['recommendations'],
      'components': _predictionResult!['components'],
      'timestamp': _predictionResult!['timestamp'] ?? DateTime.now().toUtc().toIso8601String(),
      'timezone': DateTime.now().timeZoneName,
      'deviceTimeZoneOffset': DateTime.now().timeZoneOffset.toString(),
      'sensors': {
        'tds_raw': latestReading?.tdsRaw ?? 0,
        'tds_voltage': latestReading?.tdsVoltage ?? 0.0,
        'mq_raw': latestReading?.mqRaw ?? 0,
        'mq_voltage': latestReading?.mqVoltage ?? 0.0,
        'ph_raw': latestReading?.phRaw ?? 0,
        'ph_voltage': latestReading?.phVoltage ?? 0.0,
        'ph_value': latestReading?.phValue ?? (latestReading?.phVoltage ?? 0.0),
      },
      'survey': {
        'age': age,
        'bmi': bmi,
        'gender': profile['gender']?.toString() ?? 'Male',
        'bloodGroup': profile['bloodGroup']?.toString() ?? 'O+',
        'height': profile['height'] is num ? (profile['height'] as num).toDouble() : 170.0,
        'weight': profile['weight'] is num ? (profile['weight'] as num).toDouble() : 70.0,
        'smoking_history': _smoking ? 1 : 0,
        'alcohol_consumption': _alcohol ? 1 : 0,
        'diabetes': _diabetes ? 1 : 0,
        'family_history': _familyHistory ? 1 : 0,
        'weight_loss': _weightLoss ? 1 : 0,
        'abdominal_pain': _abdominalPain ? 1 : 0,
        'appetite_changes': _appetiteChanges ? 1 : 0,
        'jaundice': _jaundice ? 1 : 0,
      }
    };

    final bytes = await api.fetchPdfBytes(logId, logData: logData);
    
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to generate PDF from server.'), backgroundColor: Colors.redAccent),
        );
      }
      return;
    }

    final downloadUrl = await _firebaseService.uploadMedicalReport(userId, logId, bytes);
    if (downloadUrl != null) {
      // Save PDF URL inside Firestore prediction log
      try {
        await FirebaseFirestore.instance.collection('screening_logs').doc(logId).update({
          'pdfUrl': downloadUrl,
        });
      } catch (e) {
        print("Error updating PDF URL in Firestore: $e");
      }
    } else {
      print("Warning: Firebase Storage upload failed, downloading locally only.");
    }

    // Open/download file locally for immediate viewing
    if (kIsWeb) {
      await api.downloadPdf(logId, logData: logData);
    } else {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/report_$logId.pdf');
      await file.writeAsBytes(bytes);
      await OpenFilex.open(file.path);
    }
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PDF Generated & Downloaded Successfully!')),
    );
  }

  void _shareReport() async {
    if (_predictionResult == null) return;
    final logId = _predictionResult!['log_id']?.toString() ?? _predictionResult!['id']?.toString();
    if (logId == null) return;

    final provider = Provider.of<UserStateProvider>(context, listen: false);
    final userId = provider.userId;
    if (userId == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preparing report to share...'), duration: Duration(seconds: 1)),
      );
    }

    final pdfUrl = _predictionResult!['pdfUrl']?.toString() ?? '';
    final pcriScore = _predictionResult!['pcri_score']?.toString() ?? '0.0';
    final riskLevel = _predictionResult!['risk_level']?.toString() ?? 'Low';
    
    final shareText = 'My Pancreatic Cancer Risk Assessment Report.\nRisk Level: $riskLevel Risk (Score: $pcriScore%)\n${pdfUrl.isNotEmpty ? "View Report: $pdfUrl" : ""}';

    if (kIsWeb) {
      try {
        await Share.share(
          shareText,
          subject: 'Pancreatic Cancer Risk Assessment Report',
        );
      } catch (e) {
        print("Web native share failed: $e");
        // Fallback for browsers that don't support Web Share API
        if (pdfUrl.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: pdfUrl));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Report URL copied to clipboard!'), backgroundColor: Colors.green),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Report sharing failed: cloud URL not ready.'), backgroundColor: Colors.redAccent),
            );
          }
        }
      }
    } else {
      // Android / Native platforms: download and share XFile
      try {
        final api = ApiService(baseUrl: provider.baseUrl);
        final profile = provider.profileData ?? {};
        final age = profile['age'] is num ? (profile['age'] as num).toInt() : int.tryParse(profile['age']?.toString() ?? '45') ?? 45;
        final bmi = profile['bmi'] is num ? (profile['bmi'] as num).toDouble() : double.tryParse(profile['bmi']?.toString() ?? '23.5') ?? 23.5;
        final latestReading = Provider.of<ESP32StateProvider>(context, listen: false).liveSensors;
        
        final logData = {
          'user_id': userId,
          'pcri_score': _predictionResult!['pcri_score'],
          'risk_level': _predictionResult!['risk_level'],
          'ai_confidence': _predictionResult!['ai_confidence'],
          'recommendations': _predictionResult!['recommendations'],
          'components': _predictionResult!['components'],
          'timestamp': _predictionResult!['timestamp'] ?? DateTime.now().toUtc().toIso8601String(),
          'timezone': DateTime.now().timeZoneName,
          'deviceTimeZoneOffset': DateTime.now().timeZoneOffset.toString(),
          'sensors': {
            'tds_raw': latestReading?.tdsRaw ?? 0,
            'tds_voltage': latestReading?.tdsVoltage ?? 0.0,
            'mq_raw': latestReading?.mqRaw ?? 0,
            'mq_voltage': latestReading?.mqVoltage ?? 0.0,
            'ph_raw': latestReading?.phRaw ?? 0,
            'ph_voltage': latestReading?.phVoltage ?? 0.0,
            'ph_value': latestReading?.phValue ?? (latestReading?.phVoltage ?? 0.0),
          },
          'survey': {
            'age': age,
            'bmi': bmi,
            'gender': profile['gender']?.toString() ?? 'Male',
            'bloodGroup': profile['bloodGroup']?.toString() ?? 'O+',
            'height': profile['height'] is num ? (profile['height'] as num).toDouble() : 170.0,
            'weight': profile['weight'] is num ? (profile['weight'] as num).toDouble() : 70.0,
            'smoking_history': _smoking ? 1 : 0,
            'alcohol_consumption': _alcohol ? 1 : 0,
            'diabetes': _diabetes ? 1 : 0,
            'family_history': _familyHistory ? 1 : 0,
            'weight_loss': _weightLoss ? 1 : 0,
            'abdominal_pain': _abdominalPain ? 1 : 0,
            'appetite_changes': _appetiteChanges ? 1 : 0,
            'jaundice': _jaundice ? 1 : 0,
          }
        };

        final bytes = await api.fetchPdfBytes(logId, logData: logData);
        if (bytes != null) {
          final directory = await getTemporaryDirectory();
          final file = File('${directory.path}/report_$logId.pdf');
          await file.writeAsBytes(bytes);

        final patientName = profile['username']?.toString() ?? provider.username ?? 'Patient';

        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/pdf')],
          text: shareText,
          subject: '$patientName Risk Assessment Report',
        );
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to generate PDF for sharing.'), backgroundColor: Colors.redAccent),
            );
          }
        }
      } catch (e) {
        print("Error native sharing PDF: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error sharing report: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  void _runBackgroundPdfUpload(
    String baseUrl,
    String userId,
    String reportId,
    Map<String, dynamic> logData,
    DocumentReference? docRef,
  ) async {
    try {
      final api = ApiService(baseUrl: baseUrl);
      final bytes = await api.fetchPdfBytes(reportId, logData: logData);
      if (bytes != null) {
        final downloadUrl = await _firebaseService.uploadMedicalReport(userId, reportId, bytes);
        if (downloadUrl != null) {
          logData['pdf_download_url'] = downloadUrl;
          logData['pdfUrl'] = downloadUrl;
          
          if (docRef != null) {
            await docRef.update({
              'pdf_download_url': downloadUrl,
              'pdfUrl': downloadUrl,
            });
          }
          
          // Also update local state if user is still on this screen
          if (mounted && _predictionResult != null && 
              (_predictionResult!['log_id'] == reportId || _predictionResult!['id'] == reportId)) {
            setState(() {
              _predictionResult!['pdfUrl'] = downloadUrl;
            });
          }
        }
      }
    } catch (e) {
      print("Automatic background PDF generation/upload failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
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
            const Text('AI Diagnostics'),
          ],
        ),
        centerTitle: true,
        actions: _predictionResult != null ? [
          IconButton(icon: const Icon(Icons.share_rounded), onPressed: _shareReport),
          IconButton(icon: const Icon(Icons.picture_as_pdf_rounded), onPressed: _exportPdf),
        ] : null,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: _isLoading
            ? _buildScanningAnimation()
            : _predictionResult != null
                ? _buildResultView()
                : _buildFormView(),
      ),
    );
  }

  Widget _buildScanningAnimation() {
    final theme = Theme.of(context);
    final steps = [
      'Collecting Sensor Data...',
      'Validating Saliva Biomarkers...',
      'Connecting to AI Model...',
      'Running XGBoost Prediction...',
      'Calculating Confidence Score...',
      'Generating Medical Report...',
    ];
    return Center(
      key: const ValueKey('loading'),
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CircularProgressIndicator(
                      color: theme.primaryColor.withOpacity(0.2),
                      strokeWidth: 8,
                      value: 1,
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _scanAnimationController,
                    builder: (context, child) {
                      return SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          color: theme.primaryColor,
                          strokeWidth: 8,
                          value: _scanAnimationController.value,
                        ),
                      );
                    },
                  ),
                  Icon(Icons.psychology_rounded, size: 50, color: theme.primaryColor),
                ],
              ),
            ),
            const SizedBox(height: 48),
            Text(
              'AI Processing Timeline',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 24),
            GlassCard(
              padding: const EdgeInsets.all(24),
              borderRadius: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(steps.length, (index) {
                  final stepNumber = index + 1;
                  final isCompleted = _processingStep > stepNumber;
                  final isCurrent = _processingStep == stepNumber;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCompleted ? Colors.green : (isCurrent ? theme.primaryColor : Colors.transparent),
                            border: Border.all(
                              color: isCompleted ? Colors.green : (isCurrent ? theme.primaryColor : theme.colorScheme.onSurface.withOpacity(0.2)),
                              width: 2,
                            ),
                          ),
                          child: isCompleted 
                              ? const Icon(Icons.check, size: 16, color: Colors.white) 
                              : (isCurrent ? const Center(
                                  child: SizedBox(
                                    width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  ),
                                ) : null),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            steps[index],
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                              color: isCompleted || isCurrent 
                                  ? theme.colorScheme.onSurface 
                                  : theme.colorScheme.onSurface.withOpacity(0.4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultView() {
    final theme = Theme.of(context);
    final score = _predictionResult!['pcri_score'] as num;
    final riskLevel = _predictionResult!['risk_level'] as String;
    num confidenceVal = _predictionResult!['ai_confidence'] as num;
    if (confidenceVal > 100.0) {
      confidenceVal = confidenceVal / 100.0;
    }
    final confidence = confidenceVal.clamp(0.0, 100.0);
    final recommendation = _predictionResult!['recommendations'] as String;

    Color riskColor = Colors.green;
    if (riskLevel == 'Moderate') riskColor = Colors.orange;
    if (riskLevel == 'High') riskColor = Colors.redAccent;

    return SingleChildScrollView(
      key: const ValueKey('result'),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassCard(
            padding: const EdgeInsets.all(32),
            borderRadius: 32,
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 180,
                      height: 180,
                      child: CircularProgressIndicator(
                        value: score / 100,
                        strokeWidth: 16,
                        backgroundColor: riskColor.withOpacity(0.1),
                        color: riskColor,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$score', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
                        Text('PCRI Score', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: riskColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: riskColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_rounded, color: riskColor, size: 24),
                      const SizedBox(width: 8),
                      Text('$riskLevel Risk', style: TextStyle(color: riskColor, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'AI Confidence: ${confidence.toStringAsFixed(1)}%',
                  style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 14),
                ),
                const SizedBox(height: 16),
                Text(
                  'Prediction Date: ${DateTimeService.formatDate(_predictionResult!['timestamp'] ?? _predictionResult!['predictionTimestamp'] ?? DateTime.now())}',
                  style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.85), fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Prediction Time: ${DateTimeService.formatTimeWithSeconds(_predictionResult!['timestamp'] ?? _predictionResult!['predictionTimestamp'] ?? DateTime.now())}',
                  style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.85), fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Recommendations
          GlassCard(
            padding: const EdgeInsets.all(24),
            borderRadius: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.medical_services_rounded, color: theme.primaryColor),
                    Expanded(
                      child: Text(
                        'Clinical Recommendations', 
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Divider(color: theme.colorScheme.onSurface.withOpacity(0.1), height: 32),
                Text(
                  recommendation,
                  style: TextStyle(fontSize: 15, color: theme.colorScheme.onSurface.withOpacity(0.8), height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Medical Disclaimer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.orange, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'This prediction is generated by an AI model and should not replace professional medical advice. Please consult with a healthcare provider for clinical diagnosis.',
                    style: TextStyle(color: Colors.orange.shade200, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exportPdf,
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text('Export PDF'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: AnimatedPrimaryButton(
                  text: 'New Scan',
                  icon: Icons.refresh_rounded,
                  onPressed: () => setState(() => _predictionResult = null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildFormView() {
    final theme = Theme.of(context);
    final esp32Provider = Provider.of<ESP32StateProvider>(context);
    final isConnected = esp32Provider.deviceState == DeviceState.connected;
    
    return SingleChildScrollView(
      key: const ValueKey('form'),
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlassCard(
              padding: const EdgeInsets.all(20),
              borderRadius: 20,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isConnected ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isConnected ? Icons.bluetooth_connected_rounded : Icons.bluetooth_disabled_rounded,
                      color: isConnected ? Colors.green : Colors.redAccent,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ESP32 Sensor Array', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface)),
                        Text(isConnected ? 'Connected & Streaming' : 'Disconnected - Using cached data', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Patient Vitals', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: theme.colorScheme.onSurface)),
                TextButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/profile'),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Edit Profile'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(16),
              borderRadius: 20,
              child: Builder(
                builder: (context) {
                  final provider = Provider.of<UserStateProvider>(context);
                  final profile = provider.profileData ?? {};
                  final age = profile['age']?.toString() ?? 'N/A';
                  final bmi = profile['bmi']?.toString() ?? 'N/A';
                  final height = profile['height']?.toString() ?? 'N/A';
                  final weight = profile['weight']?.toString() ?? 'N/A';
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _buildVitalInfo(theme, Icons.cake, 'Age', age)),
                          Expanded(child: _buildVitalInfo(theme, Icons.calculate, 'BMI', bmi)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _buildVitalInfo(theme, Icons.height, 'Height', '$height cm')),
                          Expanded(child: _buildVitalInfo(theme, Icons.monitor_weight, 'Weight', '$weight kg')),
                        ],
                      ),
                    ],
                  );
                }
              ),
            ),
            const SizedBox(height: 24),
            Text('Risk Factors', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(8),
              borderRadius: 20,
              child: Column(
                children: [
                  _buildCheckbox('Smoking History', _smoking, (val) => setState(() => _smoking = val!)),
                  _buildCheckbox('Alcohol Consumption', _alcohol, (val) => setState(() => _alcohol = val!)),
                  _buildCheckbox('Diabetes', _diabetes, (val) => setState(() => _diabetes = val!)),
                  _buildCheckbox('Family History', _familyHistory, (val) => setState(() => _familyHistory = val!)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Symptoms', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(8),
              borderRadius: 20,
              child: Column(
                children: [
                  _buildCheckbox('Unexplained Weight Loss', _weightLoss, (val) => setState(() => _weightLoss = val!)),
                  _buildCheckbox('Abdominal Pain', _abdominalPain, (val) => setState(() => _abdominalPain = val!)),
                  _buildCheckbox('Appetite Changes', _appetiteChanges, (val) => setState(() => _appetiteChanges = val!)),
                  _buildCheckbox('Jaundice', _jaundice, (val) => setState(() => _jaundice = val!)),
                ],
              ),
            ),
            const SizedBox(height: 40),
            AnimatedPrimaryButton(
              text: 'Run AI Diagnostics',
              icon: Icons.psychology_rounded,
              onPressed: _runDiagnosticScan,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildVitalInfo(ThemeData theme, IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.primaryColor),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.6))),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
          ],
        ),
      ],
    );
  }

  Widget _buildCheckbox(String title, bool value, void Function(bool?) onChanged) {
    return Material(
      color: Colors.transparent,
      child: CheckboxListTile(
        title: Text(title, style: const TextStyle(fontSize: 15)),
        value: value,
        onChanged: onChanged,
        activeColor: Theme.of(context).primaryColor,
        checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      ),
    );
  }
}

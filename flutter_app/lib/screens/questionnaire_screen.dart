import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/patient.dart';
import '../services/api_service.dart';

class QuestionnaireScreen extends StatefulWidget {
  const QuestionnaireScreen({super.key});

  @override
  State<QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ageController = TextEditingController(text: '45');
  final _bmiController = TextEditingController(text: '23.5');

  bool _smoking = false;
  bool _alcohol = false;
  bool _diabetes = false;
  bool _familyHistory = false;
  bool _weightLoss = false;
  bool _abdominalPain = false;
  bool _appetiteChanges = false;
  bool _jaundice = false;

  bool _isLoading = false;

  void _runDiagnosticScan() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final provider = Provider.of<UserStateProvider>(context, listen: false);
    final api = ApiService(baseUrl: provider.baseUrl);

    // 1. Fetch latest baseline telemetry
    final latestReading = await api.fetchLatestSensorReading(provider.userId ?? '1');
    
    final tdsVoltage = latestReading?.tdsVoltage ?? 0.0;
    final mqVoltage = latestReading?.mqVoltage ?? 0.0;
    final phVoltage = latestReading?.phVoltage ?? 0.0;
    final phValue = latestReading?.phValue ?? phVoltage;

    final profile = provider.profileData ?? {};
    final gender = profile['gender']?.toString() ?? 'Male';
    final bloodGroup = profile['bloodGroup']?.toString() ?? 'O+';
    final height = profile['height'] is num ? (profile['height'] as num).toDouble() : double.tryParse(profile['height']?.toString() ?? '170.0') ?? 170.0;
    final weight = profile['weight'] is num ? (profile['weight'] as num).toDouble() : double.tryParse(profile['weight']?.toString() ?? '70.0') ?? 70.0;

    // 2. Prepare questionnaire
    final survey = PatientQuestionnaire(
      age: int.parse(_ageController.text),
      gender: gender,
      bloodGroup: bloodGroup,
      height: height,
      weight: weight,
      bmi: double.parse(_bmiController.text),
      smokingHistory: _smoking ? 1 : 0,
      alcoholConsumption: _alcohol ? 1 : 0,
      diabetes: _diabetes ? 1 : 0,
      familyHistory: _familyHistory ? 1 : 0,
      weightLoss: _weightLoss ? 1 : 0,
      abdominalPain: _abdominalPain ? 1 : 0,
      appetiteChanges: _appetiteChanges ? 1 : 0,
      jaundice: _jaundice ? 1 : 0,
    );

    // 3. Evaluate PCRI
    final res = await api.evaluateScreening(
      userId: provider.userId ?? '1',
      survey: survey,
      tdsVoltage: tdsVoltage,
      mqVoltage: mqVoltage,
      phVoltage: phVoltage,
      phValue: phValue,
    );

    setState(() => _isLoading = false);

    if (res != null) {
      if (mounted) {
        _showResultDialog(res);
      }
    } else {
      _showError("Failed to calculate risk screening score.");
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _showResultDialog(Map<String, dynamic> data) {
    final score = data['pcri_score'] as num;
    final riskLevel = data['risk_level'] as String;
    final confidence = data['ai_confidence'] as num;
    final recommendation = data['recommendations'] as String;

    Color riskColor = Colors.greenAccent;
    if (riskLevel == 'Moderate') riskColor = Colors.amberAccent;
    if (riskLevel == 'High') riskColor = Colors.redAccent;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Diagnostic Screening Summary', textAlign: TextAlign.center),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              // Gauge Mimic Dial
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: riskColor, width: 4),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$score',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
                    ),
                    const Text('PCRI SCORE', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              
              // Risk Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: riskColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: riskColor),
                ),
                child: Text(
                  '$riskLevel Risk Profile',
                  style: TextStyle(color: riskColor, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              Text('AI Confidence Match: $confidence%', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 20),

              // Recommendations
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Screening Advice:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              const SizedBox(height: 6),
              Text(
                recommendation,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Back to dashboard
            },
            child: const Text('Back to Dashboard'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Risk Survey Panel')),
      body: _isLoading
          ? const Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Calibrating Sensors & Running AI Prediction...', style: TextStyle(color: Colors.grey)),
              ],
            ))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  const Text(
                    'Input Clinical Criteria',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _ageController,
                          decoration: const InputDecoration(labelText: 'Patient Age', border: OutlineInputBorder()),
                          keyboardType: TextInputType.number,
                          validator: (v) => v!.isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _bmiController,
                          decoration: const InputDecoration(labelText: 'Patient BMI', border: OutlineInputBorder()),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (v) => v!.isEmpty ? 'Required' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  const Text(
                    'Check Active Physiological Flags',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),

                  _buildCheckItem('Active Smoking History', _smoking, (val) => setState(() => _smoking = val!)),
                  _buildCheckItem('Alcohol Intake (> 3 units/day)', _alcohol, (val) => setState(() => _alcohol = val!)),
                  _buildCheckItem('Type-2 Diabetes Diagnosis', _diabetes, (val) => setState(() => _diabetes = val!)),
                  _buildCheckItem('Family History of Pancreatic Cancer', _familyHistory, (val) => setState(() => _familyHistory = val!)),
                  _buildCheckItem('Unexplained/Sudden Weight Loss', _weightLoss, (val) => setState(() => _weightLoss = val!)),
                  _buildCheckItem('Persistent Abdominal/Back Pain', _abdominalPain, (val) => setState(() => _abdominalPain = val!)),
                  _buildCheckItem('Sudden Loss of Appetite', _appetiteChanges, (val) => setState(() => _appetiteChanges = val!)),
                  _buildCheckItem('Jaundice Indicators (Eyes/Skin Yellowing)', _jaundice, (val) => setState(() => _jaundice = val!)),
                  
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _runDiagnosticScan,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Execute Risk Analysis Scan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildCheckItem(String title, bool value, ValueChanged<bool?> onChanged) {
    return Material(
      color: Colors.transparent,
      child: CheckboxListTile(
        title: Text(title, style: const TextStyle(fontSize: 14)),
        value: value,
        onChanged: onChanged,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: const Color(0xFF3B82F6),
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/sensor_reading.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // --- USER PROFILE ---
  
  // Stream User Profile (Real-Time updates)
  Stream<DocumentSnapshot<Map<String, dynamic>>> streamUserProfile(String userId) {
    return _db.collection('users').doc(userId).snapshots();
  }

  // Update Profile Data
  Future<bool> updateUserProfile(String userId, Map<String, dynamic> data) async {
    try {
      final updateData = Map<String, dynamic>.from(data);
      updateData['updatedAt'] = FieldValue.serverTimestamp();
      await _db.collection('users').doc(userId).set(updateData, SetOptions(merge: true));
      return true;
    } catch (e) {
      print('Error updating user profile in Firestore: $e');
      return false;
    }
  }

  // --- SENSOR READINGS ---

  // Stream Latest Sensor Reading
  Stream<SensorReading?> streamLatestSensorReading(String userId) {
    return _db
        .collection('sensor_readings')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        return SensorReading.fromJson({
          'tds_raw': data['tds_raw'],
          'tds_voltage': data['tds_voltage'],
          'mq_raw': data['mq_raw'],
          'mq_voltage': data['mq_voltage'],
          'ph_raw': data['ph_raw'],
          'ph_voltage': data['ph_voltage'],
          'timestamp': data['timestamp'] != null 
              ? (data['timestamp'] as Timestamp).toDate().toUtc().toIso8601String() 
              : DateTime.now().toUtc().toIso8601String(),
        });
      }
      return null;
    });
  }

  // --- PREDICTION LOGS / HISTORY ---

  // Stream Prediction History Logs (Real-time updates)
  Stream<List<Map<String, dynamic>>> streamHistoryLogs(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('predictionHistory')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        if (data['timestamp'] is Timestamp) {
          data['timestamp'] = (data['timestamp'] as Timestamp).toDate().toUtc().toIso8601String();
        }
        if (data['createdAt'] is Timestamp) {
          data['createdAt'] = (data['createdAt'] as Timestamp).toDate().toUtc().toIso8601String();
        }
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  // Save new Screening/Prediction Log
  Future<String?> savePredictionLog(String userId, Map<String, dynamic> logData) async {
    try {
      final data = Map<String, dynamic>.from(logData);
      data['userId'] = userId;
      data['timestamp'] = FieldValue.serverTimestamp(); // backward compatibility
      
      // Auto-managed Firestore & Local timestamps
      final now = DateTime.now();
      data['createdAt'] = FieldValue.serverTimestamp();
      data['updatedAt'] = FieldValue.serverTimestamp();
      data['serverTimestamp'] = FieldValue.serverTimestamp();
      data['lastViewed'] = FieldValue.serverTimestamp();
      data['lastModified'] = FieldValue.serverTimestamp();
      data['predictionTimestamp'] = now.toUtc().toIso8601String();
      data['deviceTimestamp'] = now.toIso8601String();
      data['timezone'] = now.timeZoneName;
      data['deviceTimeZoneOffset'] = now.timeZoneOffset.toString();
      
      final docRef = await _db
          .collection('users')
          .doc(userId)
          .collection('predictionHistory')
          .add(data);
      return docRef.id;
    } catch (e) {
      print('Error saving prediction log to Firestore: $e');
      return null;
    }
  }

  // Delete prediction log
  Future<bool> deletePredictionLog(String userId, String logId) async {
    try {
      await _db
          .collection('users')
          .doc(userId)
          .collection('predictionHistory')
          .doc(logId)
          .delete();
      return true;
    } catch (e) {
      print('Error deleting prediction log: $e');
      return false;
    }
  }

  // --- NOTIFICATIONS ---
  Stream<List<Map<String, dynamic>>> streamNotifications(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  // --- ACTIVITY LOGS ---
  Future<void> logActivity(String userId, String action, String details) async {
    try {
      await _db
          .collection('users')
          .doc(userId)
          .collection('activityLog')
          .add({
        'action': action,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error logging activity: $e');
    }
  }
}

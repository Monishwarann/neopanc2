import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../services/firebase_service.dart';
import '../services/api_service.dart';
import '../services/datetime_service.dart';
import '../main.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_primary_button.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/skeleton_loader.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery, 
      imageQuality: 50,
      maxWidth: 400,
      maxHeight: 400,
    );
    if (image != null) {
      final bytes = await image.readAsBytes();
      
      if (!mounted) return;
      final provider = Provider.of<UserStateProvider>(context, listen: false);
      if (provider.userId != null) {
        final downloadUrl = await _firebaseService.uploadProfilePicture(provider.userId!, bytes);
        
        if (downloadUrl != null) {
          final success = await _firebaseService.updateUserProfile(provider.userId!, {
            'profileImageUrl': downloadUrl,
            'profileImageBase64': '', // Clear base64 to save Firestore space
          });
          if (success && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile image updated')));
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to upload profile image')));
          }
        }
      }
    }
  }

  void _showEditDialog(Map<String, dynamic> currentData) {
    final nameCtrl = TextEditingController(text: currentData['username'] ?? '');
    final ageCtrl = TextEditingController(text: currentData['age']?.toString() ?? '');
    final genderCtrl = TextEditingController(text: currentData['gender'] ?? '');
    final bloodCtrl = TextEditingController(text: currentData['bloodGroup'] ?? '');
    final phoneCtrl = TextEditingController(text: currentData['phone'] ?? '');
    final addressCtrl = TextEditingController(text: currentData['address'] ?? '');
    final heightCtrl = TextEditingController(text: currentData['height']?.toString() ?? '');
    final weightCtrl = TextEditingController(text: currentData['weight']?.toString() ?? '');
    final bmiCtrl = TextEditingController(text: currentData['bmi']?.toString() ?? '');

    // Auto-calculate BMI when height and weight change
    void calculateBmi() {
      if (heightCtrl.text.isNotEmpty && weightCtrl.text.isNotEmpty) {
        final h = double.tryParse(heightCtrl.text);
        final w = double.tryParse(weightCtrl.text);
        if (h != null && w != null && h > 0) {
          final hMeters = h / 100;
          final bmi = w / (hMeters * hMeters);
          bmiCtrl.text = bmi.toStringAsFixed(1);
        }
      }
    }
    heightCtrl.addListener(calculateBmi);
    weightCtrl.addListener(calculateBmi);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B0F19), // Darker, premium background
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Edit Profile', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                const SizedBox(height: 24),
                CustomTextField(controller: nameCtrl, label: 'Full Name', icon: Icons.person),
                const SizedBox(height: 16),
                CustomTextField(controller: ageCtrl, label: 'Age', icon: Icons.cake, keyboardType: TextInputType.number),
                const SizedBox(height: 16),
                CustomTextField(controller: genderCtrl, label: 'Gender', icon: Icons.wc),
                const SizedBox(height: 16),
                CustomTextField(controller: bloodCtrl, label: 'Blood Group', icon: Icons.bloodtype),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: CustomTextField(controller: heightCtrl, label: 'Height (cm)', icon: Icons.height, keyboardType: TextInputType.number)),
                    const SizedBox(width: 16),
                    Expanded(child: CustomTextField(controller: weightCtrl, label: 'Weight (kg)', icon: Icons.monitor_weight, keyboardType: TextInputType.number)),
                  ],
                ),
                const SizedBox(height: 16),
                CustomTextField(controller: bmiCtrl, label: 'BMI (Auto-calculated)', icon: Icons.calculate, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                const SizedBox(height: 16),
                CustomTextField(controller: phoneCtrl, label: 'Phone Number', icon: Icons.phone, keyboardType: TextInputType.phone),
                const SizedBox(height: 16),
                CustomTextField(controller: addressCtrl, label: 'Address', icon: Icons.location_on),
                const SizedBox(height: 32),
                AnimatedPrimaryButton(
                  text: 'Save Changes',
                  icon: Icons.save,
                  onPressed: () async {
                    final provider = Provider.of<UserStateProvider>(context, listen: false);
                    if (provider.userId != null) {
                      final success = await _firebaseService.updateUserProfile(provider.userId!, {
                        'username': nameCtrl.text,
                        'age': ageCtrl.text.isNotEmpty ? int.tryParse(ageCtrl.text) ?? ageCtrl.text : null,
                        'gender': genderCtrl.text,
                        'bloodGroup': bloodCtrl.text,
                        'phone': phoneCtrl.text,
                        'address': addressCtrl.text,
                        'height': heightCtrl.text.isNotEmpty ? double.tryParse(heightCtrl.text) ?? heightCtrl.text : null,
                        'weight': weightCtrl.text.isNotEmpty ? double.tryParse(weightCtrl.text) ?? weightCtrl.text : null,
                        'bmi': bmiCtrl.text.isNotEmpty ? double.tryParse(bmiCtrl.text) ?? bmiCtrl.text : null,
                        'updatedAt': FieldValue.serverTimestamp(),
                      });
                      if (success) {
                        provider.setUser(provider.userId!, nameCtrl.text, provider.email ?? '');
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update profile')));
                        }
                      }
                    }
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _updateActiveTime();
  }

  void _updateActiveTime() async {
    final provider = Provider.of<UserStateProvider>(context, listen: false);
    if (provider.userId != null) {
      await _firebaseService.updateUserProfile(provider.userId!, {
        'lastActiveTime': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<UserStateProvider>(context);
    final theme = Theme.of(context);
    final data = provider.profileData;
    
    // We treat it as loading if data is completely null (maybe not fetched yet)
    // Though UserStateProvider might just not have data if it doesn't exist
    final isLoading = data == null;

    final name = data?['username'] ?? 'Not Available';
    final age = data?['age']?.toString() ?? 'Not Available';
    final gender = data?['gender'] ?? 'Not Available';
    final bloodGroup = data?['bloodGroup'] ?? 'Not Available';
    final height = data?['height']?.toString() ?? 'Not Available';
    final weight = data?['weight']?.toString() ?? 'Not Available';
    final bmi = data?['bmi']?.toString() ?? 'Not Available';
    final phone = data?['phone'] ?? 'Not Available';
    final address = data?['address'] ?? 'Not Available';
    final profileImageUrl = data?['profileImageUrl'];
    final profileImageBase64 = data?['profileImageBase64'];
    
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
            const Text('User Profile', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ],
        ),
        actions: [
          if (data != null)
            IconButton(
              icon: Icon(Icons.edit, color: theme.primaryColor),
              onPressed: () => _showEditDialog(data),
              tooltip: 'Edit Profile',
            ),
        ],
      ),
      body: isLoading
          ? _buildSkeletonLoading(theme)
          : _buildProfileView(theme, provider.email ?? '', name, age, gender, bloodGroup, height, weight, bmi, phone, address, profileImageUrl, profileImageBase64, data),
    );
  }

  Widget _buildErrorView(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.redAccent.withOpacity(0.8)),
          const SizedBox(height: 16),
          const Text('Unable to load profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('There was an issue fetching your real-time data.', style: TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () {
              setState(() {});
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoading(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
      child: Column(
        children: [
          SkeletonLoader(width: 120, height: 120, borderRadius: 60),
          const SizedBox(height: 20),
          SkeletonLoader(width: 150, height: 28),
          const SizedBox(height: 8),
          SkeletonLoader(width: 200, height: 16),
          const SizedBox(height: 40),
          GlassCard(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: List.generate(6, (index) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                child: Row(
                  children: [
                    SkeletonLoader(width: 42, height: 42, borderRadius: 12),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonLoader(width: 80, height: 12),
                        const SizedBox(height: 8),
                        SkeletonLoader(width: 150, height: 16),
                      ],
                    ),
                  ],
                ),
              )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileView(
      ThemeData theme, String email, String name, String age, String gender, 
      String bloodGroup, String height, String weight, String bmi, String phone, String address, 
      String? profileImageUrl, String? profileImageBase64, Map<String, dynamic> data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.primaryColor.withOpacity(0.3), width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: theme.primaryColor.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: GestureDetector(
                  onTap: _pickImage,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: CircleAvatar(
                      key: ValueKey(profileImageUrl ?? profileImageBase64),
                      radius: 56,
                      backgroundColor: theme.colorScheme.surface,
                      backgroundImage: _getProfileImage(profileImageUrl, profileImageBase64),
                      child: ((profileImageUrl == null || profileImageUrl.isEmpty) && 
                              (profileImageBase64 == null || profileImageBase64.isEmpty))
                          ? Icon(Icons.person, size: 60, color: theme.primaryColor)
                          : null,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.primaryColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.scaffoldBackgroundColor, width: 3),
                    ),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(name, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: theme.colorScheme.onSurface)),
          const SizedBox(height: 4),
          Text(email, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 14)),
          const SizedBox(height: 40),
          
          GlassCard(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildProfileItem(Icons.badge, 'Name', name),
                Divider(color: theme.colorScheme.onSurface.withOpacity(0.1), height: 1),
                _buildProfileItem(Icons.cake, 'Age', age),
                Divider(color: theme.colorScheme.onSurface.withOpacity(0.1), height: 1),
                _buildProfileItem(Icons.person_outline, 'Gender', gender),
                Divider(color: theme.colorScheme.onSurface.withOpacity(0.1), height: 1),
                _buildProfileItem(Icons.bloodtype, 'Blood Group', bloodGroup),
                Divider(color: theme.colorScheme.onSurface.withOpacity(0.1), height: 1),
                _buildProfileItem(Icons.height, 'Height (cm)', height),
                Divider(color: theme.colorScheme.onSurface.withOpacity(0.1), height: 1),
                _buildProfileItem(Icons.monitor_weight, 'Weight (kg)', weight),
                Divider(color: theme.colorScheme.onSurface.withOpacity(0.1), height: 1),
                _buildProfileItem(Icons.calculate, 'BMI', bmi),
                Divider(color: theme.colorScheme.onSurface.withOpacity(0.1), height: 1),
                _buildProfileItem(Icons.phone, 'Phone', phone),
                Divider(color: theme.colorScheme.onSurface.withOpacity(0.1), height: 1),
                _buildProfileItem(Icons.location_on, 'Address', address),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          Row(
            children: [
              Text('Account Lifecycle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface)),
            ],
          ),
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Builder(
                  builder: (context) {
                    final creationTime = _firebaseService.currentUser?.metadata.creationTime;
                    final createdStr = creationTime != null 
                        ? '${DateTimeService.formatDate(creationTime)} • ${DateTimeService.formatTime(creationTime)}'
                        : 'Not Available';
                    return _buildProfileItem(Icons.how_to_reg, 'Account Created', createdStr);
                  }
                ),
                Divider(color: theme.colorScheme.onSurface.withOpacity(0.1), height: 1),
                Builder(
                  builder: (context) {
                    final signInTime = _firebaseService.currentUser?.metadata.lastSignInTime;
                    final loginStr = signInTime != null 
                        ? '${DateTimeService.formatDate(signInTime)} • ${DateTimeService.formatTime(signInTime)}'
                        : 'Not Available';
                    return _buildProfileItem(Icons.login, 'Last Login Time', loginStr);
                  }
                ),
                Divider(color: theme.colorScheme.onSurface.withOpacity(0.1), height: 1),
                Builder(
                  builder: (context) {
                    final updatedTime = data['updatedAt'];
                    final updatedStr = updatedTime != null 
                        ? '${DateTimeService.formatDate(updatedTime)} • ${DateTimeService.formatTime(updatedTime)}'
                        : 'No updates recorded';
                    return _buildProfileItem(Icons.update, 'Last Profile Update', updatedStr);
                  }
                ),
                Divider(color: theme.colorScheme.onSurface.withOpacity(0.1), height: 1),
                Builder(
                  builder: (context) {
                    final pwdTime = data['lastPasswordChange'] ?? _firebaseService.currentUser?.metadata.creationTime;
                    final pwdStr = pwdTime != null 
                        ? '${DateTimeService.formatDate(pwdTime)} • ${DateTimeService.formatTime(pwdTime)}'
                        : 'Not Available';
                    return _buildProfileItem(Icons.lock_reset, 'Last Password Change', pwdStr);
                  }
                ),
                Divider(color: theme.colorScheme.onSurface.withOpacity(0.1), height: 1),
                Builder(
                  builder: (context) {
                    final activeTime = data['lastActiveTime'];
                    final activeStr = activeTime != null 
                        ? DateTimeService.formatRelativeTime(activeTime)
                        : 'Just Now';
                    return _buildProfileItem(Icons.bolt, 'Last Active Time', activeStr);
                  }
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 48),
          AnimatedPrimaryButton(
            text: 'Logout',
            icon: Icons.logout,
            onPressed: () async {
              final provider = Provider.of<UserStateProvider>(context, listen: false);
              await _firebaseService.logout();
              if (context.mounted) {
                provider.clearUser();
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  ImageProvider? _getProfileImage(String? url, String? base64Str) {
    if (url != null && url.isNotEmpty) {
      return NetworkImage(url);
    }
    if (base64Str != null && base64Str.isNotEmpty) {
      try {
        return MemoryImage(base64Decode(base64Str.trim()));
      } catch (e) {
        debugPrint("Error decoding profile image base64: $e");
      }
    }
    return null;
  }

  Widget _buildProfileItem(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: theme.primaryColor, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
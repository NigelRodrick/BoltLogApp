import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/user_service.dart';
import '../models/user_model.dart';
import 'auth_entry_screen.dart';
import 'driver_completion_screen.dart';
import 'main_navigation.dart';
import 'transporter_navigation.dart';
import 'notifications_screen.dart';
import 'payment_methods_screen.dart';
import 'support_screen.dart';
import 'driver_account_edit_screen.dart';
import '../widgets/storage_image.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final UserService _userService = UserService();
  bool _isSwitching = false; // Prevent multiple switch attempts

  Future<void> _handleLogout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthEntryScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _handleSwitchToDriver(UserModel user) async {
    // Check if driver profile is complete
    final hasTruckType = user.truckType != null && user.truckType!.isNotEmpty;
    final hasRatePer10Km = user.ratePer10Km != null && user.ratePer10Km! > 0;
    final hasCarBook = user.carBookImageUrl != null && user.carBookImageUrl!.isNotEmpty;
    final hasTruckSide = user.truckSideImageUrl != null && user.truckSideImageUrl!.isNotEmpty;
    final hasLicense = user.driverLicenseImageUrl != null && user.driverLicenseImageUrl!.isNotEmpty;
    final hasSelfie = user.selfieImageUrl != null && user.selfieImageUrl!.isNotEmpty;

    if (!hasTruckType || !hasRatePer10Km || !hasCarBook || !hasTruckSide || !hasLicense || !hasSelfie) {
      // Navigate to driver completion screen
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DriverCompletionScreen(currentUser: user),
          ),
        );
      }
      return;
    }

    // If profile is complete, switch directly
    await _handleRoleSwitch(user, true);
  }

  Future<void> _handleRoleSwitch(UserModel user, bool switchToDriver) async {
    // Prevent multiple simultaneous switch attempts
    if (_isSwitching) return;
    
    setState(() {
      _isSwitching = true;
    });

    if (switchToDriver) {
      // Switching to Driver - MUST check if driver profile is complete
      final hasTruckType = user.truckType != null && user.truckType!.isNotEmpty;
      final hasRatePer10Km = user.ratePer10Km != null && user.ratePer10Km! > 0;
      final hasCarBook = user.carBookImageUrl != null && user.carBookImageUrl!.isNotEmpty;
      final hasTruckSide = user.truckSideImageUrl != null && user.truckSideImageUrl!.isNotEmpty;
      final hasLicense = user.driverLicenseImageUrl != null && user.driverLicenseImageUrl!.isNotEmpty;
      final hasSelfie = user.selfieImageUrl != null && user.selfieImageUrl!.isNotEmpty;

      if (!hasTruckType || !hasRatePer10Km || !hasCarBook || !hasTruckSide || !hasLicense || !hasSelfie) {
        // Requirements not met - show message and navigate to completion screen
        if (mounted) {
          setState(() {
            _isSwitching = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please complete your driver profile first. Required: Vehicle Type, Rate per 10 km, Car Book, Truck Side View, Driver License, and Selfie.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
          
          // Navigate to driver completion screen
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DriverCompletionScreen(currentUser: user),
            ),
          );
          
          // If user completed the profile, the screen will navigate automatically
          // If they cancelled, we just return (switch stays off)
          return;
        }
        return;
      }
    }

    // Switch role only if:
    // - Switching to Sender (no requirements needed)
    // - Switching to Driver AND all requirements are met (checked above)
    try {
      await _userService.updateDriverProfile(
        uid: user.uid,
        role: switchToDriver ? 'Driver' : 'Passenger',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Switched to ${switchToDriver ? 'Driver' : 'Sender'} profile'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

        // Navigate to appropriate screen based on new role
        if (switchToDriver) {
          // Switched to Driver - go to Driver Dashboard
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const TransporterNavigation()),
            (route) => false,
          );
        } else {
          // Switched to Sender - go to Sender Dashboard
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainNavigation()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSwitching = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error switching profile: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    return StreamBuilder<UserModel?>(
      stream: firebaseUser != null
          ? _userService.streamUser(firebaseUser.uid)
          : null,
      builder: (context, snapshot) {
        final _user = snapshot.data;
        
        return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Profile',
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E40AF), // Blue-700
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Color(0xFF1E40AF)), // Blue-700
            onPressed: () {
              // For drivers, navigate to driver account edit screen
              if (_user?.role.trim().toLowerCase() == 'driver') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DriverAccountEditScreen(user: _user!),
                  ),
                );
              } else {
                // For regular users, show edit dialog or navigate to edit screen
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Profile editing coming soon'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Profile header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.1), // Blue-600
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    // Profile picture: for drivers, use truck side view; otherwise fall back to selfie / Google photo / initial
                    (_user?.role.trim().toLowerCase() == 'driver' &&
                            _user?.truckSideImageUrl != null &&
                            _user!.truckSideImageUrl!.isNotEmpty)
                        ? StorageAvatar(
                            pathOrUrl: _user!.truckSideImageUrl,
                            radius: 50,
                            backgroundColor: const Color(0xFF2563EB),
                            child: null,
                          )
                        : (_user?.role.trim().toLowerCase() == 'driver' &&
                                _user?.selfieImageUrl != null &&
                                _user!.selfieImageUrl!.isNotEmpty)
                            ? StorageAvatar(
                                pathOrUrl: _user!.selfieImageUrl,
                                radius: 50,
                                backgroundColor: const Color(0xFF2563EB),
                                child: Text(
                                  (_user.displayName ?? firebaseUser?.displayName ?? 'U')
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: GoogleFonts.inter(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            : CircleAvatar(
                                radius: 50,
                                backgroundColor: const Color(0xFF2563EB), // Blue-600
                                child: firebaseUser?.photoURL != null
                                    ? ClipOval(
                                        child: Image.network(
                                          firebaseUser!.photoURL!,
                                          width: 100,
                                          height: 100,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : Text(
                                        (_user?.displayName ?? firebaseUser?.displayName ?? 'U')
                                            .substring(0, 1)
                                            .toUpperCase(),
                                        style: GoogleFonts.inter(
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                    const SizedBox(height: 16),
                    Text(
                      _user?.displayName ?? firebaseUser?.displayName ?? 'User',
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E40AF), // Blue-700
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _user?.email ?? firebaseUser?.email ?? '',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB), // Blue-600
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        (_user?.role?.trim().toLowerCase() ?? '') == 'driver' ? 'Transporter' : ((_user?.role?.trim().toLowerCase() ?? '') == 'passenger' ? 'Sender' : _user?.role ?? 'Sender'),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Profile details
              _buildProfileItem(
                Icons.phone,
                'Phone',
                _user?.phoneNumber ?? firebaseUser?.phoneNumber ?? 'Not set',
                _user,
              ),
              _buildProfileItem(
                Icons.email,
                'Email',
                _user?.email ?? firebaseUser?.email ?? 'Not set',
                _user,
              ),
              _buildProfileItem(
                Icons.calendar_today,
                'Member Since',
                _user != null
                    ? '${_user!.createdAt.day}/${_user!.createdAt.month}/${_user!.createdAt.year}'
                    : 'N/A',
                _user,
              ),
              const SizedBox(height: 24),
              // Settings section
              Text(
                'Settings',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E40AF), // Blue-700
                ),
              ),
              const SizedBox(height: 12),
              _buildSettingsItem(
                Icons.notifications_outlined,
                'Notifications',
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  );
                },
              ),
              _buildSettingsItem(
                Icons.payment,
                'Payment Methods',
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PaymentMethodsScreen(),
                    ),
                  );
                },
              ),
              _buildSettingsItem(
                Icons.help_outline,
                'Help & Support',
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SupportScreen(),
                    ),
                  );
                },
              ),
              _buildSettingsItem(
                Icons.info_outline,
                'About',
                () {
                  _showAboutDialog(context);
                },
              ),
              const SizedBox(height: 24),
              // Logout button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: _handleLogout,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Logout',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.red,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Delete account
              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: () => _showDeleteAccountDialog(context),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                  child: Text(
                    'Delete Account',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.red,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Developed by Fidinsky Tech Solutions',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
      },
    );
  }

  Widget _buildProfileItem(IconData icon, String label, String value, UserModel? user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2563EB), size: 24), // Blue-600
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF1E40AF), // Blue-700
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsItem(IconData icon, String title, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF2563EB)), // Blue-600
        title: Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF1E40AF), // Blue-700
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Boltlog',
      applicationVersion: '2.4.0',
      applicationIcon: const Icon(
        Icons.local_shipping,
        size: 48,
        color: Color(0xFF2563EB),
      ),
      applicationLegalese: '© 2024 Boltlog. All rights reserved.',
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            'Boltlog is a goods transportation marketplace app where users can request transport for goods and transporters can accept delivery requests.',
            style: GoogleFonts.inter(),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete Account',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete your account? This action cannot be undone.',
          style: GoogleFonts.inter(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.inter()),
          ),
          TextButton(
            onPressed: () {
              _deleteAccount(ctx);
            },
            child: Text(
              'Delete',
              style: GoogleFonts.inter(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No user is currently logged in.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final uid = user.uid;

      // Delete Firestore user document
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();

      // Delete Firebase Auth user
      await user.delete();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthEntryScreen()),
          (route) => false,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your account has been deleted.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Failed to delete account. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete account: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}


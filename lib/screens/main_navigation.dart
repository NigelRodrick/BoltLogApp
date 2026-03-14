import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'ride_history_screen.dart';
import 'profile_screen.dart';
import '../services/notification_service.dart';
import '../services/ride_service.dart';
import 'request_detail_screen.dart';

class MainNavigation extends StatefulWidget {
  final bool showWelcomeMessage;
  
  const MainNavigation({super.key, this.showWelcomeMessage = false});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const RideHistoryScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handlePendingNotification());
    if (widget.showWelcomeMessage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account created successfully! Welcome to Boltlog!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });
    }
  }

  Future<void> _handlePendingNotification() async {
    final rideId = NotificationService.getPendingRideId();
    if (rideId != null && rideId.isNotEmpty && mounted) {
      try {
        final ride = await RideService().getRideById(rideId);
        if (ride != null && mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => RequestDetailScreen(ride: ride),
            ),
          );
        }
      } catch (_) {}
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final notificationService = NotificationService();
        final token = await notificationService.getToken();
        if (token != null) await notificationService.saveTokenToUser(uid, token);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: const Color(0xFF2563EB), // Blue-600
        unselectedItemColor: Colors.grey.shade600,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}



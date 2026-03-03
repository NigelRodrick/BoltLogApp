import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'permissions_screen.dart';
import 'splash_screen.dart';

/// Decides whether to show permissions screen (first launch) or splash.
class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  // Default true = show permissions immediately on first launch (right after install)
  bool _showPermissions = true;

  static const _permissionsKey = 'permissions_requested_v1';

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final requested = prefs.getBool(_permissionsKey) ?? false;
    if (!mounted) return;
    setState(() => _showPermissions = !requested);
  }

  @override
  Widget build(BuildContext context) {
    if (_showPermissions) {
      return PermissionsScreen(child: const SplashScreen());
    }
    return const SplashScreen();
  }
}

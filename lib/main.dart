import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/app_initializer.dart';
import 'services/notification_service.dart';
import 'services/connectivity_service.dart';
import 'services/theme_service.dart';

// Background message handler
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling a background message: ${message.messageId}');
  debugPrint('Message data: ${message.data}');
  
  // Initialize Firebase if not already initialized
  await Firebase.initializeApp();
  
  // Save notification to Firestore so it can be read in the app
  try {
    final data = message.data;
    final userId = data['userId'] as String?;
    
    if (userId != null) {
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': userId,
        'type': data['type'] ?? 'general',
        'title': message.notification?.title ?? data['title'] ?? 'Notification',
        'message': message.notification?.body ?? data['message'] ?? '',
        'rideId': data['rideId'],
        'data': data,
        'isRead': false,
        'createdAt': DateTime.now().toIso8601String(),
      });
      debugPrint('Background notification saved to Firestore');
    }
  } catch (e) {
    debugPrint('Error saving background notification: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Enable Flutter error handling for Crashlytics
  FlutterError.onError = (errorDetails) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
  };
  
  // Pass all uncaught asynchronous errors to Crashlytics
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    // Enable Firestore offline persistence
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      debugPrint('Firestore offline persistence enabled');
    } catch (e) {
      debugPrint('Firestore persistence error: $e');
    }
    
    // Set up background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    
    // Initialize Notification Service
    try {
      final notificationService = NotificationService();
      await notificationService.initialize();
      debugPrint('Push notifications service initialized');
    } catch (e) {
      debugPrint('Push notifications initialization error: $e');
      // Continue anyway - notifications are optional
    }
    
    // Initialize Connectivity Service
    try {
      ConnectivityService();
      debugPrint('Connectivity service initialized');
    } catch (e) {
      debugPrint('Connectivity service initialization error: $e');
    }
  } catch (e) {
    // If Firebase initialization fails, log the error
    debugPrint('Firebase initialization error: $e');
    FirebaseCrashlytics.instance.recordError(e, null, fatal: false);
    // Continue anyway - the app will show errors when trying to use Firebase
  }
  
  // Load saved theme mode before starting the app
  await ThemeService.init();

  runApp(const BoltlogApp());
}

class BoltlogApp extends StatelessWidget {
  const BoltlogApp({super.key});

  @override
  Widget build(BuildContext context) {
    final lightTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2563EB), // Blue-600
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: Colors.white,
      useMaterial3: true,
      textTheme: GoogleFonts.interTextTheme(),
    );

    final darkTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2563EB), // Blue-600
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      textTheme: GoogleFonts.interTextTheme(),
    );

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Boltlog',
          debugShowCheckedModeBanner: false,
          // Set default locale to English only
          locale: const Locale('en', 'US'),
          supportedLocales: const [
            Locale('en', 'US'), // English
          ],
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: mode,
          home: const AppInitializer(),
        );
      },
    );
  }
}

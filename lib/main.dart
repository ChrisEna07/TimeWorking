import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'config/app_config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/local_db_service.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  
  try {
    // 1. Core initializations
    await initializeDateFormatting('es', null);
    await GetStorage.init();
    
    // 2. Initialize Notifications & Background Service
    final notifService = NotificationService();
    await notifService.init();
    await notifService.scheduleWorkReminders();
    await AppBackgroundService.initialize();

    // 3. Forced delay for logo visibility (Optional, set to 3s for better UX)
    await Future.delayed(const Duration(seconds: 3));

  } catch (e) {
    debugPrint("Initialization error: $e");
  } finally {
    // Always remove splash even if error occurs
    FlutterNativeSplash.remove();
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final db = LocalDbService();
    return MaterialApp(
      title: 'TimeWorking',
      debugShowCheckedModeBanner: false,
      theme: AppConfig.theme,
      home: db.isAuthenticated ? const HomeScreen() : const LoginScreen(),
    );
  }
}

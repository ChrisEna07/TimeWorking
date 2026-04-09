import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:get_storage/get_storage.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'config/app_config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/supabase_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  
  // Initialize Notifications
  final notifService = NotificationService();
  await notifService.init();
  await notifService.scheduleWorkReminders();

  await initializeDateFormatting('es', null);
  await GetStorage.init();
  
  // Wait 5 seconds to show the logo
  await Future.delayed(const Duration(seconds: 5));
  FlutterNativeSplash.remove();
  
  // Initialize Supabase
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  runApp(const TimeWorkingApp());
}

class TimeWorkingApp extends StatelessWidget {
  const TimeWorkingApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Check if user is already logged in
    final bool isLogged = SupabaseService().isAuthenticated;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TimeWorking by ChrizDev',
      theme: AppConfig.theme,
      home: isLogged ? const HomeScreen() : const LoginScreen(),
    );
  }
}

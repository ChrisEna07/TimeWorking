import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:get_storage/get_storage.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'config/app_config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize date formatting for Spanish (Colombia)
  await initializeDateFormatting('es', null);
  
  // Initialize GetStorage
  await GetStorage.init();
  
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

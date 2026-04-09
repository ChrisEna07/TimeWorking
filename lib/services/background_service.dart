import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppBackgroundService {
  static const String notificationChannelId = 'work_timer_channel';
  static const int notificationId = 888;

  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId,
      'Contador de Jornada',
      description: 'Muestra el tiempo transcurrido de la jornada actual',
      importance: Importance.low, // low so it doesn't make sound every update
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'Jornada Activa',
        initialNotificationContent: 'Iniciando cronómetro...',
        foregroundServiceNotificationId: notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    // Update timer every second
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          final prefs = await SharedPreferences.getInstance();
          final startTimeStr = prefs.getString('active_start_time');
          final breakDuration = prefs.getInt('active_break_duration') ?? 0;
          final isOnBreak = prefs.getBool('is_on_break') ?? false;

          if (startTimeStr != null) {
            final startTime = DateTime.parse(startTimeStr);
            final now = DateTime.now();
            final diff = now.difference(startTime);
            final netDiff = diff - Duration(minutes: breakDuration);

            if (isOnBreak) {
              flutterLocalNotificationsPlugin.show(
                notificationId,
                'Jornada en Pausa (Almuerzo)',
                'El tiempo no se sumará al pago.',
                const NotificationDetails(
                  android: AndroidNotificationDetails(
                    notificationChannelId,
                    'Contador de Jornada',
                    icon: '@mipmap/ic_launcher',
                    ongoing: true,
                    importance: Importance.low,
                    priority: Priority.low,
                    onlyAlertOnce: true,
                  ),
                ),
              );
            } else {
              final h = netDiff.inHours;
              final m = (netDiff.inMinutes % 60).toString().padLeft(2, '0');
              final s = (netDiff.inSeconds % 60).toString().padLeft(2, '0');
              final timeStr = "${h.toString().padLeft(2, '0')}:$m:$s";

              flutterLocalNotificationsPlugin.show(
                notificationId,
                'Jornada en Curso',
                'Tiempo transcurrido: $timeStr',
                const NotificationDetails(
                  android: AndroidNotificationDetails(
                    notificationChannelId,
                    'Contador de Jornada',
                    icon: '@mipmap/ic_launcher',
                    ongoing: true,
                    importance: Importance.low,
                    priority: Priority.low,
                    onlyAlertOnce: true,
                  ),
                ),
              );
            }
          }
        }
      }

      // Update data for the UI if needed
      service.invoke('update', {
        "current_date": DateTime.now().toIso8601String(),
      });
    });
  }
}

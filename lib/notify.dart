import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Real Android system notifications for AQUA order events.
///
/// The app generates notifications for three audiences (customer, rider,
/// admin); AppState decides which ones are relevant to the signed-in role and
/// calls [push] here. A single notification channel keeps them grouped in the
/// system settings.
class PhoneNotify {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static int _id = 1;

  static const String _channelId = 'aqua_orders';
  static const String _channelName = 'AQUA order updates';

  static Future<void> init() async {
    if (_ready) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings: settings);
      final android =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        await android.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Order status, delivery assignments and station alerts.',
          importance: Importance.high,
        ));
        // Android 13+ requires a runtime permission prompt.
        await android.requestNotificationsPermission();
      }
      _ready = true;
    } catch (_) {
      // Notifications are a nice-to-have; never let them break the app.
    }
  }

  /// Fires a heads-up / status-bar notification. No-op until [init] ran and
  /// on platforms without support (e.g. web).
  static Future<void> push(String title, String body) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _id++ & 0x7FFFFFFF,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Order status, delivery assignments and station alerts.',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(''),
          ),
        ),
      );
    } catch (_) {}
  }
}

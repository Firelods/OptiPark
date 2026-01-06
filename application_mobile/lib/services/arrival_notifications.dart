import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Called once at app start
Future<void> initArrivalNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');

  const settings = InitializationSettings(android: android);

  await notificationsPlugin.initialize(
    settings,
    onDidReceiveNotificationResponse: (response) {
      final reservationId = response.payload;
      if (reservationId != null && arrivalNotificationCallback != null) {
        arrivalNotificationCallback!(reservationId);
      }
    },
  );
}

// This will be set from HomePage
Function(String reservationId)? arrivalNotificationCallback;

Future<void> showArrivalNotification(String reservationId) async {
  const androidDetails = AndroidNotificationDetails(
    'arrival_channel',
    'Arrival Notifications',
    importance: Importance.max,
    priority: Priority.high,
  );

  const details = NotificationDetails(android: androidDetails);

  await notificationsPlugin.show(
    0,
    'You arrived at your parking',
    'Tap to confirm arrival',
    details,
    payload: reservationId,
  );
}

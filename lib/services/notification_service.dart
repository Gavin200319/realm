import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Handles Firebase Cloud Messaging setup and local notification display.
/// 
/// Setup required (one-time, outside the app):
/// 1. Create a Firebase project at console.firebase.google.com
/// 2. Add an Android app with package name: com.realitymerge
/// 3. Download google-services.json into android/app/
/// 4. Add the FCM token saving below to your Supabase profiles table
///    by running this SQL:
///    ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS fcm_token text;
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _androidChannel = AndroidNotificationChannel(
    'reality_merge_drops',
    'Nearby Drops',
    description: 'Alerts when you are near a locked drop',
    importance: Importance.high,
  );

  Future<void> initialize() async {
    // Request permission
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return; // User declined — don't force
    }

    // Set up local notifications channel (Android 8+)
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    // Save FCM token to Supabase so server can target this device
    final token = await _messaging.getToken();
    if (token != null) await _saveFcmToken(token);

    // Refresh token when it rotates
    _messaging.onTokenRefresh.listen(_saveFcmToken);

    // Handle foreground messages (show as local notification)
    FirebaseMessaging.onMessage.listen(_showLocalNotification);

    // Handle background message taps (app was in background)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      // TODO: navigate to the relevant drop when tapped
      // For now just re-opens the app to the feed
    });
  }

  Future<void> _saveFcmToken(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': token}).eq('id', user.id);
    } catch (_) {
      // Non-fatal — token save failure shouldn't crash the app
    }
  }

  void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }
}

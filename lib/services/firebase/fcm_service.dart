import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/navigation/root_navigator.dart';

/// Background isolate handler. Must be a top-level / static function annotated
/// with `@pragma('vm:entry-point')`. The system tray notification is shown
/// automatically by the OS from the message's `notification` block, so there is
/// nothing to render here — we only log.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('FCM background message: ${message.messageId}');
}

/// Firebase Cloud Messaging integration (spec §8/§12).
///
/// Client responsibilities (delivery is triggered server-side by Cloud
/// Functions — see `functions/index.js`):
///   • request notification permission,
///   • register the device token (done at login via [saveTokenToFirestore] /
///     `AuthRepository`),
///   • show a foreground in-app banner when a push arrives while the app is
///     open (the OS shows the tray notification when it's backgrounded), and
///   • deep-link to the right booking when the user taps a notification —
///     foreground, background, or cold start — using the `route` in the
///     message data payload.
class FcmService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('FCM permission: ${settings.authorizationStatus}');

    // Foreground messages → show an in-app banner; the OS does NOT show a tray
    // notification while the app is open.
    FirebaseMessaging.onMessage.listen(_showForegroundBanner);

    // Tap on a tray notification while the app is backgrounded.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

    // App opened from a terminated state by tapping a notification.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      // Defer until the first frame so the router/navigator exists.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _handleTap(initial));
    }
  }

  /// Shows a foreground SnackBar with a "View" action that opens the booking.
  void _showForegroundBanner(RemoteMessage message) {
    final n = message.notification;
    final title = n?.title ?? message.data['title']?.toString() ?? '';
    final body = n?.body ?? message.data['body']?.toString() ?? '';
    debugPrint('FCM foreground: $title');
    final messenger = rootScaffoldMessengerKey.currentState;
    if (messenger == null) return;
    final route = message.data['route']?.toString();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 5),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (body.isNotEmpty) Text(body),
          ],
        ),
        action: (route != null && route.isNotEmpty)
            ? SnackBarAction(
                label: 'View', onPressed: () => _navigate(route))
            : null,
      ));
  }

  /// Opens the booking referenced by a tapped notification.
  void _handleTap(RemoteMessage message) {
    final route = message.data['route']?.toString();
    if (route != null && route.isNotEmpty) _navigate(route);
  }

  /// Navigates to [route] using the root navigator (works regardless of which
  /// screen is currently shown).
  void _navigate(String route) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) {
      // Router not ready yet (cold start) — retry on the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = rootNavigatorKey.currentContext;
        if (c != null) c.push(route);
      });
      return;
    }
    ctx.push(route);
  }

  Future<String?> getToken() async {
    try {
      // getToken() can hang indefinitely (NOT throw) on emulators without Play
      // Services, on devices where FCM registration stalls, or on restricted
      // networks. Bound it so a push-token fetch can never freeze a caller —
      // most importantly the sign-in flow that registers the token on login.
      return await _messaging.getToken().timeout(const Duration(seconds: 10));
    } on TimeoutException {
      debugPrint('FcmService.getToken timed out (non-fatal).');
      return null;
    } catch (e) {
      debugPrint('FcmService.getToken error: $e');
      return null;
    }
  }

  Future<void> saveTokenToFirestore(String userId) async {
    final token = await getToken();
    if (token == null) return;
    await _db.collection(AppConstants.usersCollection).doc(userId).update({
      'fcmToken': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteToken(String userId) async {
    await _messaging.deleteToken();
    await _db.collection(AppConstants.usersCollection).doc(userId).update({
      'fcmToken': FieldValue.delete(),
    });
  }

  Future<void> subscribeToTopic(String topic) => _messaging.subscribeToTopic(topic);
  Future<void> unsubscribeFromTopic(String topic) => _messaging.unsubscribeFromTopic(topic);

  /// Helper to build a notification payload stored in Firestore; the actual
  /// device push is triggered by the `notifications`-onCreate Cloud Function.
  static Map<String, dynamic> buildPayload({
    required String userId,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? data,
  }) =>
      {
        'userId': userId,
        'title': title,
        'body': body,
        'type': type,
        'data': data ?? {},
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

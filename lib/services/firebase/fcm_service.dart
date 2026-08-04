import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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

/// Firebase Cloud Messaging integration.
///
/// Client responsibilities (delivery is triggered server-side by the Cloud
/// Functions in `functions/index.js` — `onNotificationCreated` + the dedicated
/// interest/chat/profile/announcement triggers):
///   • request notification permission (incl. Android 13+ runtime permission),
///   • register the device token at login AND on every token refresh,
///   • subscribe the signed-in user to their announcement topic,
///   • show a foreground in-app banner when a push arrives while the app is
///     open (the OS shows the tray notification when it's backgrounded), and
///   • deep-link DIRECTLY to the target screen when a notification is tapped —
///     foreground, background, or cold start — using the `route` in the
///     message data payload. Never lands on Home first: a tap that arrives
///     before auth/router are ready is stashed and replayed once they are.
class FcmService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// A deep link whose navigation could not run yet (cold start: router not
  /// mounted / auth still resolving). Replayed once the app is ready.
  static String? _pendingRoute;
  static Timer? _pendingRouteTimer;

  /// Renders REAL heads-up notifications for pushes that arrive while the app
  /// is in the FOREGROUND — the OS only draws tray notifications itself when
  /// the app is backgrounded/killed.
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// The app's single high-importance Android channel. The id MUST stay in
  /// sync with:
  ///  • android/app/src/main/AndroidManifest.xml
  ///    (com.google.firebase.messaging.default_notification_channel_id), and
  ///  • functions/index.js (channelId on every FCM android payload).
  /// Creating it here at startup is what makes it safe for the server to name
  /// it — a channelId pointing at a non-existent channel silently falls back
  /// to the low-importance "Miscellaneous" channel.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'Notifications',
    description:
        'Interests, messages, reports, payments and announcements.',
    importance: Importance.high,
  );

  /// True once the local-notifications plugin initialized and the channel
  /// exists; until then foreground pushes fall back to the SnackBar banner.
  static bool _localNotificationsReady = false;

  Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('FCM permission: ${settings.authorizationStatus}');

    // Local-notifications plugin + the high-importance channel — must exist
    // BEFORE any push can arrive, both for foreground heads-up rendering and
    // so the server-side channelId targets a real channel.
    await _initLocalNotifications();

    // Foreground messages → REAL heads-up notification (SnackBar fallback);
    // the OS does NOT show a tray notification while the app is open.
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // Tap on a tray notification while the app is backgrounded.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

    // Token rotation — keep users/{uid}.fcmToken current without waiting for
    // the next login. (Invalid/expired tokens are additionally cleaned up
    // server-side when a send fails.)
    _messaging.onTokenRefresh.listen((token) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || token.isEmpty) return;
      try {
        await _db.collection(AppConstants.usersCollection).doc(uid).update({
          'fcmToken': token,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        debugPrint('FCM token refreshed for $uid');
      } catch (e) {
        debugPrint('FCM token refresh save failed: $e');
      }
    });

    // Existing signed-in session (no fresh login event): make sure the device
    // is on its announcement topic and its token is registered.
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null) {
      unawaited(saveTokenToFirestore(currentUid).catchError((e) {
        debugPrint('FCM startup token registration failed (non-fatal): $e');
      }));
      // A crash / force-kill while a chat was open leaves a stale
      // activeThreadId presence marker that would suppress that thread's
      // pushes forever — clear it at every app start.
      unawaited(_db
          .collection(AppConstants.usersCollection)
          .doc(currentUid)
          .update({'activeThreadId': FieldValue.delete()}).catchError((e) {
        debugPrint('FCM presence cleanup failed (non-fatal): $e');
      }));
    }

    // App opened from a terminated state by tapping a notification.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      // Defer until the first frame so the router/navigator exists; _navigate
      // additionally waits for auth before pushing, so the auth redirect can
      // never swallow the deep link.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _handleTap(initial));
    }
  }

  /// Initializes flutter_local_notifications, creates the high-importance
  /// channel, wires local-notification taps into the SAME deep-link handler as
  /// push taps, and replays a launch-by-local-notification (the app was killed
  /// after a foreground notification was shown, then the user tapped it).
  /// Best-effort: on any failure the foreground path falls back to SnackBars.
  Future<void> _initLocalNotifications() async {
    try {
      await _localNotifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (response) {
          final route = response.payload;
          if (route != null && route.isNotEmpty) _navigate(route);
        },
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
      _localNotificationsReady = true;

      // Cold start from tapping a still-visible foreground notification after
      // the app was killed: replay its route through the stash-and-retry
      // navigation (same contract as getInitialMessage).
      final launch =
          await _localNotifications.getNotificationAppLaunchDetails();
      final launchRoute = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true &&
          launchRoute != null &&
          launchRoute.isNotEmpty) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _navigate(launchRoute));
      }
    } catch (e) {
      debugPrint(
          'Local notifications init failed (SnackBar fallback active): $e');
    }
  }

  /// Foreground push → heads-up local notification on the high-importance
  /// channel, carrying the deep-link route as its payload. Falls back to the
  /// SnackBar banner when the plugin is unavailable.
  void _onForegroundMessage(RemoteMessage message) {
    if (!_localNotificationsReady) {
      _showForegroundBanner(message);
      return;
    }
    final n = message.notification;
    final title = n?.title ?? message.data['title']?.toString() ?? '';
    final body = n?.body ?? message.data['body']?.toString() ?? '';
    final route = message.data['route']?.toString() ?? '';
    debugPrint('FCM foreground: $title');
    if (title.isEmpty && body.isEmpty) return;
    // Stable id per collapse key (e.g. one per chat thread) so a burst of
    // messages REPLACES its notification instead of stacking dozens;
    // uncollapsed events get a unique id each.
    final collapse = message.collapseKey;
    final id = (collapse != null && collapse.isNotEmpty)
        ? collapse.hashCode
        : DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);
    _localNotifications
        .show(
          id,
          title.isEmpty ? null : title,
          body.isEmpty ? null : body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentSound: true,
            ),
          ),
          payload: route,
        )
        .catchError((Object e) {
      debugPrint('Foreground notification failed, showing banner: $e');
      _showForegroundBanner(message);
    });
  }

  /// Shows a foreground banner with a "View" action that deep-links directly.
  /// FALLBACK path only — used when the local-notifications plugin could not
  /// initialize (so foreground pushes are still visible somewhere).
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
        behavior: SnackBarBehavior.floating,
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

  /// Opens the screen referenced by a tapped notification.
  void _handleTap(RemoteMessage message) {
    final route = message.data['route']?.toString();
    if (route != null && route.isNotEmpty) _navigate(route);
  }

  /// The router's current location, or null when unavailable.
  String? _currentLocation() {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return null;
    try {
      return GoRouter.of(ctx).routerDelegate.currentConfiguration.uri.path;
    } catch (_) {
      return null;
    }
  }

  /// True once the router is mounted, a signed-in user exists AND the app has
  /// LEFT the splash/auth flow. Pushing earlier is futile: the splash/login
  /// screens finish with context.go('/home'), which REPLACES the stack and
  /// would silently wipe the deep-linked screen.
  bool get _readyForDeepLink {
    if (rootNavigatorKey.currentContext == null) return false;
    if (FirebaseAuth.instance.currentUser == null) return false;
    final loc = _currentLocation();
    if (loc == null || loc == '/' || loc.startsWith('/login')) return false;
    return true;
  }

  /// Navigates to [route] using the root navigator (works regardless of which
  /// screen is currently shown). On a cold start the router may not be mounted
  /// yet and auth may still be resolving — in that case the route is stashed
  /// and retried every 300ms for up to 20s, then dropped. The LAST tapped
  /// notification wins.
  void _navigate(String route) {
    if (_readyForDeepLink) {
      _pendingRouteTimer?.cancel();
      _pendingRoute = null;
      rootNavigatorKey.currentContext!.push(route);
      return;
    }
    _pendingRoute = route;
    _pendingRouteTimer?.cancel();
    var attempts = 0;
    _pendingRouteTimer =
        Timer.periodic(const Duration(milliseconds: 300), (timer) {
      attempts++;
      final pending = _pendingRoute;
      if (pending == null || attempts > 66) {
        timer.cancel();
        return;
      }
      if (!_readyForDeepLink) return;
      timer.cancel();
      _pendingRoute = null;
      // One extra frame so the post-login redirect ('/'→'/home') settles first
      // and the pushed screen stacks ON TOP of Home instead of racing it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = rootNavigatorKey.currentContext;
        if (c != null) c.push(pending);
      });
    });
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
    // Role-based announcement topic — lets the announcements Cloud Function
    // broadcast with ONE topic send instead of a per-user fan-out.
    unawaited(_subscribeAnnouncementTopic(userId));
  }

  Future<void> _subscribeAnnouncementTopic(String userId) async {
    try {
      final user = await _db
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .get()
          .timeout(const Duration(seconds: 8));
      final role = (user.data()?['role'] ?? 'user').toString();
      await subscribeToTopic(role == 'astrologer' ? 'employees' : 'users');
    } catch (e) {
      debugPrint('FCM topic subscribe failed (non-fatal): $e');
    }
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

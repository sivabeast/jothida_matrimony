import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('FCM background message: ${message.messageId}');
}

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

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('FCM foreground: ${message.notification?.title}');
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
  }

  Future<void> deleteToken(String userId) async {
    await _messaging.deleteToken();
    await _db.collection(AppConstants.usersCollection).doc(userId).update({
      'fcmToken': FieldValue.delete(),
    });
  }

  Future<void> subscribeToTopic(String topic) => _messaging.subscribeToTopic(topic);
  Future<void> unsubscribeFromTopic(String topic) => _messaging.unsubscribeFromTopic(topic);

  /// Helper to build notification payload stored in Firestore;
  /// actual push is triggered by Cloud Functions (serverside).
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

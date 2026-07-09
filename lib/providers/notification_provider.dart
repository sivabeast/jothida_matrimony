import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification_model.dart';
import 'locale_provider.dart';
import 'service_providers.dart';
import 'auth_provider.dart';

final notificationsProvider = StreamProvider.autoDispose<List<NotificationModel>>((ref) {
  final userId = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
  if (userId == null) return Stream.value([]);
  return ref.watch(firestoreServiceProvider).watchNotifications(userId);
});

final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  final notifs = ref.watch(notificationsProvider).valueOrNull ?? [];
  return notifs.where((n) => !n.isRead).length;
});

/// The event kinds the app generates in-app notifications for.
enum AppNotificationEvent {
  interestReceived,
  interestAccepted,
  interestRejected,
  profileApproved,
  reportReady,
  appointmentConfirmed,
  adminProfileUpdate,
}

class NotificationNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<void> markRead(String notificationId) =>
      ref.read(firestoreServiceProvider).markNotificationRead(notificationId);

  /// Marks EVERY unread notification of the signed-in user read — called the
  /// moment the Notifications page opens, so nothing stays unread and the
  /// badge count drops to zero.
  Future<void> markAllRead() async {
    final uid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
    if (uid == null) return;
    try {
      await ref.read(firestoreServiceProvider).markAllNotificationsRead(uid);
    } catch (e) {
      debugPrint('[Notifications] markAllRead failed: $e');
    }
  }

  /// Creates an in-app notification for [toUid] about [event] — best-effort
  /// (a notification hiccup must never fail the action that triggered it).
  ///
  /// The text is written in the RECEIVER's preferred app language when their
  /// `users/{uid}.preferred_language` is readable; otherwise it falls back to
  /// the sender's current app language.
  Future<void> notify({
    required String toUid,
    required AppNotificationEvent event,
    String name = '',
    String route = '',
  }) async {
    if (toUid.isEmpty) return;
    try {
      String? lang;
      try {
        lang = (await ref.read(authRepositoryProvider).getUserModel(toUid))
            ?.preferredLanguage;
      } catch (_) {/* fall through to the sender's locale */}
      lang ??= ref.read(localeProvider)?.languageCode ?? 'en';

      final t = _template(event, lang == 'ta', name);
      await ref.read(firestoreServiceProvider).createNotification(
            userId: toUid,
            title: t.title,
            body: t.body,
            type: _typeKey(event),
            data: route.isEmpty ? null : {'route': route},
          );
    } catch (e) {
      debugPrint('[Notifications] notify(${event.name}) failed: $e');
    }
  }

  /// Stored `type` strings — kept aligned with the NotificationsTab visuals.
  static String _typeKey(AppNotificationEvent e) => switch (e) {
        AppNotificationEvent.interestReceived => 'interest_received',
        AppNotificationEvent.interestAccepted => 'interest_accepted',
        AppNotificationEvent.interestRejected => 'interest_rejected',
        AppNotificationEvent.profileApproved => 'profile_approval',
        AppNotificationEvent.reportReady => 'porutham_ready',
        AppNotificationEvent.appointmentConfirmed => 'appointment',
        AppNotificationEvent.adminProfileUpdate => 'admin_update',
      };

  static ({String title, String body}) _template(
      AppNotificationEvent e, bool ta, String name) {
    final who = name.trim().isEmpty ? (ta ? 'ஒரு உறுப்பினர்' : 'A member') : name.trim();
    switch (e) {
      case AppNotificationEvent.interestReceived:
        return ta
            ? (
                title: 'புதிய விருப்பம் 💌',
                body: '$who உங்கள் Profile-இல் விருப்பம் தெரிவித்துள்ளார். '
                    'இப்போது பார்க்கலாம்!'
              )
            : (
                title: 'New Interest Received 💌',
                body: '$who has shown interest in your profile. Take a look!'
              );
      case AppNotificationEvent.interestAccepted:
        return ta
            ? (
                title: 'விருப்பம் ஏற்கப்பட்டது 🎉',
                body: '$who உங்கள் விருப்பத்தை ஏற்றுக்கொண்டார். '
                    'இப்போது நீங்கள் இணைக்கப்பட்டுள்ளீர்கள்!'
              )
            : (
                title: 'Interest Accepted 🎉',
                body: '$who accepted your interest. You are now connected!'
              );
      case AppNotificationEvent.interestRejected:
        return ta
            ? (
                title: 'விருப்ப நிலை',
                body: '$who உங்கள் விருப்பத்தை நிராகரித்துள்ளார்.'
              )
            : (
                title: 'Interest Update',
                body: '$who has declined your interest.'
              );
      case AppNotificationEvent.profileApproved:
        return ta
            ? (
                title: 'Profile அங்கீகரிக்கப்பட்டது ✅',
                body: 'உங்கள் Profile இப்போது நேரலையில் உள்ளது — '
                    'பொருத்தமான Matches உங்களை பார்க்க முடியும்.'
              )
            : (
                title: 'Profile Approved ✅',
                body: 'Your profile is now live — matching members can see you.'
              );
      case AppNotificationEvent.reportReady:
        return ta
            ? (
                title: 'ஜாதக அறிக்கை தயார் 📄',
                body: 'உங்கள் ஜாதக பொருத்த அறிக்கை தயாராக உள்ளது. '
                    'Reports பக்கத்தில் பார்க்கவும்.'
              )
            : (
                title: 'Horoscope Report Ready 📄',
                body: 'Your horoscope compatibility report is ready. '
                    'Open the Reports tab to view it.'
              );
      case AppNotificationEvent.appointmentConfirmed:
        return ta
            ? (
                title: 'Appointment உறுதி 📅',
                body: 'உங்கள் ஜோதிடர் appointment உறுதி செய்யப்பட்டது. '
                    'My Appointments-இல் விவரங்களைப் பார்க்கவும்.'
              )
            : (
                title: 'Appointment Confirmed 📅',
                body: 'Your astrologer appointment is confirmed. '
                    'See My Appointments for the details.'
              );
      case AppNotificationEvent.adminProfileUpdate:
        return ta
            ? (
                title: 'Profile புதுப்பிப்பு',
                body: 'உங்கள் Profile நிர்வாகியால் புதுப்பிக்கப்பட்டது. '
                    'மாற்றங்களைச் சரிபார்க்கவும்.'
              )
            : (
                title: 'Profile Updated by Admin',
                body: 'Your profile was updated by the admin. '
                    'Please review the changes.'
              );
    }
  }
}

final notificationNotifierProvider =
    NotifierProvider<NotificationNotifier, void>(() => NotificationNotifier());

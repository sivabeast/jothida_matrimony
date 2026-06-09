import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification_model.dart';
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

class NotificationNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<void> markRead(String notificationId) =>
      ref.read(firestoreServiceProvider).markNotificationRead(notificationId);
}

final notificationNotifierProvider =
    NotifierProvider<NotificationNotifier, void>(() => NotificationNotifier());

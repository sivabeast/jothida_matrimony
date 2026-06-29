import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/dev_config.dart';
import '../models/astrologer_request_model.dart';
import 'astrologer_session_provider.dart';
import 'auth_provider.dart';
import 'service_providers.dart';

/// The signed-in user's in-person astrology APPOINTMENTS (newest first) — powers
/// the status card at the top of the Astrology page and the booking-history
/// screen. Realtime: reflects admin status changes (Pending → Confirmed →
/// Completed / Cancelled) the instant they happen.
final myAppointmentsProvider =
    StreamProvider.autoDispose<List<AstrologerRequestModel>>((ref) {
  if (kBypassAuth) {
    final all = ref.watch(demoAstrologerRequestsProvider);
    final list = all.where((r) => r.hasAppointment).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Stream.value(list);
  }
  final uid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref
      .read(astrologerServiceProvider)
      .watchRequestsByUser(uid)
      .map((list) => list.where((r) => r.hasAppointment).toList());
});

/// EVERY in-person appointment addressed to the internal astrology service —
/// powers the admin Appointment Management page. Realtime, newest first.
final allAppointmentsProvider =
    StreamProvider.autoDispose<List<AstrologerRequestModel>>((ref) {
  if (kBypassAuth) {
    final all = ref.watch(demoAstrologerRequestsProvider);
    final list = all.where((r) => r.hasAppointment).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Stream.value(list);
  }
  return ref.read(astrologerServiceProvider).watchInternalAppointments();
});

/// Admin actions on an appointment: change status (which, for a cancellation,
/// frees the slot for everyone else) and delete. State is an [AsyncValue] so the
/// UI can show inline progress; methods rethrow so screens can SnackBar errors.
class AppointmentController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> setStatus(
      AstrologerRequestModel r, AstrologerRequestStatus status) async {
    state = const AsyncLoading();
    try {
      if (kBypassAuth) {
        ref
            .read(demoAstrologerRequestsProvider.notifier)
            .setStatus(r.id, status);
      } else {
        await ref.read(astrologerServiceProvider).setAppointmentStatus(r, status);
      }
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> delete(AstrologerRequestModel r) async {
    state = const AsyncLoading();
    try {
      if (!kBypassAuth) {
        await ref.read(astrologerServiceProvider).deleteAppointment(r);
      }
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final appointmentControllerProvider =
    NotifierProvider<AppointmentController, AsyncValue<void>>(
        AppointmentController.new);

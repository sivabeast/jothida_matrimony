import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/dev_config.dart';
import '../models/consultation_model.dart';
import 'astrologer_session_provider.dart';
import 'auth_provider.dart';
import 'profile_provider.dart';
import 'service_providers.dart';

/// The signed-in user's consultation bookings, newest first.
final myConsultationsProvider =
    StreamProvider.autoDispose<List<ConsultationBooking>>((ref) {
  final uid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.read(consultationServiceProvider).watchForUser(uid).map((list) {
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  });
});

/// Consultations addressed to the signed-in astrologer, newest first.
final astrologerConsultationsProvider =
    StreamProvider.autoDispose<List<ConsultationBooking>>((ref) {
  final account = ref.watch(myAstrologerAccountProvider);
  if (account == null) return Stream.value(const []);
  return ref
      .read(consultationServiceProvider)
      .watchForAstrologer(account.id)
      .map((list) {
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  });
});

/// `dateKey → taken slot keys` for an astrologer, powering the user's calendar
/// and slot picker (public availability index, no other-user data exposed).
final astrologerBookedSlotsProvider = StreamProvider.autoDispose
    .family<Map<String, Set<String>>, String>((ref, astrologerId) {
  return ref.read(consultationServiceProvider).watchBookedSlots(astrologerId);
});

/// Astrologer earnings, derived live from their consultations. NO commission —
/// every rupee belongs to the astrologer.
class ConsultationEarnings {
  final int total;
  final int pending; // paid but not yet completed
  final int completed; // completed consultations
  final int monthly; // completed this calendar month

  const ConsultationEarnings({
    this.total = 0,
    this.pending = 0,
    this.completed = 0,
    this.monthly = 0,
  });
}

final consultationEarningsProvider =
    Provider.autoDispose<ConsultationEarnings>((ref) {
  final list = ref.watch(astrologerConsultationsProvider).valueOrNull ??
      const <ConsultationBooking>[];
  final now = DateTime.now();
  var pending = 0, completed = 0, monthly = 0;
  for (final c in list) {
    if (c.isPendingEarning) pending += c.amount;
    if (c.isCompletedEarning) {
      completed += c.amount;
      final dt = c.completedAt ?? c.createdAt;
      if (dt.year == now.year && dt.month == now.month) monthly += c.amount;
    }
  }
  return ConsultationEarnings(
    total: pending + completed,
    pending: pending,
    completed: completed,
    monthly: monthly,
  );
});

/// Booking + lifecycle actions for the consultation system. Methods rethrow so a
/// screen's try/catch can surface a SnackBar.
class ConsultationController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Creates a booking request (status pending). For Direct Visit pass
  /// [visitDate] + [slotStartMinutes]. Returns the new booking id; throws
  /// [ConsultationSlotTakenException] if the slot was just taken.
  Future<String> book({
    required String astrologerId,
    required String astrologerName,
    required ConsultationMode mode,
    required int amount,
    String note = '',
    DateTime? visitDate,
    int? slotStartMinutes,
  }) async {
    state = const AsyncLoading();
    try {
      final me = ref.read(myProfileProvider).valueOrNull;
      final user = ref.read(currentUserProvider).valueOrNull;
      final uid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid ??
          user?.uid ??
          '';
      final booking = ConsultationBooking(
        id: 'new',
        astrologerId: astrologerId,
        astrologerName: astrologerName,
        userId: uid,
        userName: me?.fullName ?? user?.displayName ?? 'User',
        userPhotoUrl: me?.profilePhotoUrl ?? '',
        mode: mode,
        status: ConsultationStatus.pending,
        amount: amount,
        note: note.trim(),
        visitDate: visitDate == null
            ? null
            : DateTime(visitDate.year, visitDate.month, visitDate.day),
        slotStartMinutes: slotStartMinutes,
        createdAt: DateTime.now(),
      );
      final id = await ref.read(consultationServiceProvider).createBooking(booking);
      state = const AsyncData(null);
      return id;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Books an In-App consultation and collects payment UPFRONT ("Book & Pay").
  /// Payment is simulated in test mode (otherwise this is where the Razorpay
  /// checkout would run before the booking is written). The booking lands at
  /// `paid`, awaiting the astrologer's acceptance. Returns the new booking id.
  Future<String> bookAndPay({
    required String astrologerId,
    required String astrologerName,
    required int amount,
    String note = '',
  }) async {
    state = const AsyncLoading();
    try {
      final me = ref.read(myProfileProvider).valueOrNull;
      final user = ref.read(currentUserProvider).valueOrNull;
      final uid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid ??
          user?.uid ??
          '';
      final booking = ConsultationBooking(
        id: 'new',
        astrologerId: astrologerId,
        astrologerName: astrologerName,
        userId: uid,
        userName: me?.fullName ?? user?.displayName ?? 'User',
        userPhotoUrl: me?.profilePhotoUrl ?? '',
        mode: ConsultationMode.inApp,
        status: ConsultationStatus.paid,
        amount: amount,
        note: note.trim(),
        createdAt: DateTime.now(),
      );
      final paymentId = kPaymentTestMode
          ? 'test_${DateTime.now().millisecondsSinceEpoch}'
          : 'razorpay_${DateTime.now().millisecondsSinceEpoch}';
      final id = await ref
          .read(consultationServiceProvider)
          .bookAndPay(booking, paymentId: paymentId);
      state = const AsyncData(null);
      return id;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> respond(ConsultationBooking b, bool accept) =>
      _guard(() => ref.read(consultationServiceProvider).respond(b, accept));

  /// User pays for an accepted In-App consultation. In subscription/test mode
  /// payment is simulated; otherwise this is where the Razorpay checkout would
  /// be launched before [ConsultationService.markPaid] is called on success.
  Future<void> pay(ConsultationBooking b) => _guard(() async {
        final paymentId = kPaymentTestMode
            ? 'test_${DateTime.now().millisecondsSinceEpoch}'
            : 'razorpay_${DateTime.now().millisecondsSinceEpoch}';
        await ref
            .read(consultationServiceProvider)
            .markPaid(b, paymentId: paymentId);
      });

  Future<void> startAnalysis(ConsultationBooking b) => _guard(
      () => ref.read(consultationServiceProvider).startAnalysis(b.id));

  /// Uploads any newly-picked report files (Cloudinary, reusing the astrologer
  /// upload), then submits the report. Status → reportSubmitted.
  Future<void> submitReport(
    ConsultationBooking b, {
    required String text,
    List<File> newImages = const [],
    List<File> newPdfs = const [],
    List<String> existingImages = const [],
    List<String> existingPdfs = const [],
  }) =>
      _guard(() async {
        final svc = ref.read(astrologerServiceProvider);
        final images = [...existingImages];
        for (final f in newImages) {
          images.add(await svc.uploadAnalysisFile(
              requestId: b.id, file: f, fileType: 'image'));
        }
        final pdfs = [...existingPdfs];
        for (final f in newPdfs) {
          pdfs.add(await svc.uploadAnalysisFile(
              requestId: b.id, file: f, fileType: 'pdf'));
        }
        await ref.read(consultationServiceProvider).submitReport(
              b,
              text: text.trim(),
              images: images,
              pdfs: pdfs,
            );
      });

  Future<void> complete(ConsultationBooking b) =>
      _guard(() => ref.read(consultationServiceProvider).complete(b));

  Future<void> cancel(ConsultationBooking b) =>
      _guard(() => ref.read(consultationServiceProvider).cancel(b));

  /// Admin: refund a paid booking the astrologer rejected.
  Future<void> refund(ConsultationBooking b) =>
      _guard(() => ref.read(consultationServiceProvider).refund(b));

  /// Admin: settle (pay out) an astrologer's delivered bookings — 100%, no
  /// commission. Only settleable bookings in [bookings] are paid out.
  Future<void> settle({
    required String astrologerId,
    required String astrologerName,
    required List<ConsultationBooking> bookings,
  }) =>
      _guard(() => ref.read(consultationServiceProvider).settleAstrologer(
            astrologerId: astrologerId,
            astrologerName: astrologerName,
            bookings: bookings,
          ));

  Future<void> _guard(Future<void> Function() action) async {
    state = const AsyncLoading();
    try {
      await action();
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final consultationControllerProvider =
    NotifierProvider<ConsultationController, AsyncValue<void>>(
        ConsultationController.new);

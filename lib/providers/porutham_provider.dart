import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../models/porutham_model.dart';
import '../core/constants/app_constants.dart';
import 'service_providers.dart';
import 'auth_provider.dart';

final myPoruthamsProvider = StreamProvider.autoDispose<List<PoruthamsModel>>((ref) {
  final userId = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
  if (userId == null) return Stream.value([]);
  return ref.watch(poruthamsRepositoryProvider).watchUserPoruthams(userId);
});

// Admin / Astrologer: pending poruthams
final pendingPoruthamsProvider = FutureProvider.autoDispose<List<PoruthamsModel>>((ref) =>
    ref.read(poruthamsRepositoryProvider).getPendingPoruthams());

class PoruthamsNotifier extends Notifier<AsyncValue<String?>> {
  @override
  AsyncValue<String?> build() => const AsyncData(null);

  Future<void> requestWithPayment({
    required String userId,
    required String brideProfileId,
    required String groomProfileId,
    required String brideName,
    required String groomName,
    required String userPhone,
    required String userEmail,
    required String userName,
  }) async {
    final razorpay = ref.read(razorpayServiceProvider);
    razorpay.init(
      onSuccess: (PaymentSuccessResponse res) async {
        state = const AsyncLoading();
        state = await AsyncValue.guard(() async {
          final model = PoruthamsModel(
            id: '',
            requestedByUserId: userId,
            brideProfileId: brideProfileId,
            groomProfileId: groomProfileId,
            brideName: brideName,
            groomName: groomName,
            status: 'requested',
            amountPaid: AppConstants.poruthamsRequestPrice,
            razorpayPaymentId: res.paymentId,
            requestedAt: DateTime.now(),
          );
          return await ref.read(poruthamsRepositoryProvider).createRequest(model);
        });
      },
      onFailure: (PaymentFailureResponse res) {
        state = AsyncError(res.message ?? 'Payment failed', StackTrace.current);
      },
    );
    razorpay.openPoruthamsCheckout(
      userId: userId,
      brideProfileId: brideProfileId,
      groomProfileId: groomProfileId,
      userPhone: userPhone,
      userEmail: userEmail,
      userName: userName,
    );
  }

  Future<void> requestFree({
    required String userId,
    required String brideProfileId,
    required String groomProfileId,
    required String brideName,
    required String groomName,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final model = PoruthamsModel(
        id: '',
        requestedByUserId: userId,
        brideProfileId: brideProfileId,
        groomProfileId: groomProfileId,
        brideName: brideName,
        groomName: groomName,
        status: 'requested',
        amountPaid: 0,
        requestedAt: DateTime.now(),
        isFreeRequest: true,
      );
      return await ref.read(poruthamsRepositoryProvider).createRequest(model);
    });
  }

  Future<void> submitResult(
      String poruthamsId, PoruthamsResult result, String astrologerId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(poruthamsRepositoryProvider).submitResult(poruthamsId, result, astrologerId);
      return poruthamsId;
    });
  }
}

final poruthamsNotifierProvider =
    NotifierProvider<PoruthamsNotifier, AsyncValue<String?>>(() => PoruthamsNotifier());

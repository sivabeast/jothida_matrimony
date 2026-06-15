import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/interest_model.dart';
import 'service_providers.dart';
import 'auth_provider.dart';

final sentInterestsProvider = StreamProvider.autoDispose<List<InterestModel>>((ref) {
  final userId = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
  if (userId == null) return Stream.value([]);
  return ref.watch(interestRepositoryProvider).watchSentInterests(userId);
});

final receivedInterestsProvider = StreamProvider.autoDispose<List<InterestModel>>((ref) {
  final userId = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
  if (userId == null) return Stream.value([]);
  return ref.watch(interestRepositoryProvider).watchReceivedInterests(userId);
});

class InterestNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> sendInterest({
    required String senderId,
    required String receiverId,
    required String senderProfileId,
    required String receiverProfileId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final interest = InterestModel(
        id: '${senderProfileId}_$receiverProfileId',
        senderId: senderId,
        receiverId: receiverId,
        senderProfileId: senderProfileId,
        receiverProfileId: receiverProfileId,
        status: 'pending',
        sentAt: DateTime.now(),
      );
      await ref.read(interestRepositoryProvider).sendInterest(interest);
    });
  }

  Future<void> acceptInterest(String interestId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(interestRepositoryProvider).acceptInterest(interestId),
    );
  }

  Future<void> rejectInterest(String interestId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(interestRepositoryProvider).rejectInterest(interestId),
    );
  }

  /// Ensures the contact-unlock connection exists for an accepted interest —
  /// backfills matches accepted before connections were created.
  Future<void> ensureConnection(InterestModel interest) =>
      ref.read(interestRepositoryProvider).ensureConnection(interest);
}

final interestNotifierProvider =
    NotifierProvider<InterestNotifier, AsyncValue<void>>(() => InterestNotifier());

/// True when there is an ACCEPTED interest between the signed-in user and the
/// profile [profileId], in EITHER direction (I accepted theirs, or they
/// accepted mine). Drives profile / compatibility / contact unlock on the
/// Match Details screen — the source of truth is the Firestore `interests`
/// status, NOT the in-memory demo store.
final isInterestAcceptedProvider =
    Provider.autoDispose.family<bool, String>((ref, profileId) {
  final sent =
      ref.watch(sentInterestsProvider).valueOrNull ?? const <InterestModel>[];
  final received =
      ref.watch(receivedInterestsProvider).valueOrNull ?? const <InterestModel>[];
  return sent.any((i) => i.receiverProfileId == profileId && i.isAccepted) ||
      received.any((i) => i.senderProfileId == profileId && i.isAccepted);
});

/// True if the signed-in user has already sent an interest to [profileId]
/// (any status). Prevents asking them to send a duplicate.
final hasSentInterestToProfileProvider =
    Provider.autoDispose.family<bool, String>((ref, profileId) {
  final sent =
      ref.watch(sentInterestsProvider).valueOrNull ?? const <InterestModel>[];
  return sent.any((i) => i.receiverProfileId == profileId);
});

/// The relationship state between the signed-in user and a target profile,
/// derived from the live Firestore `interests` streams (NOT in-memory flags).
/// Drives the Matches / Profile action button so it never shows "Send Interest"
/// for a relationship that already exists.
enum InterestUiStatus {
  /// No interest in either direction → may send one.
  none,

  /// I sent an interest that is still pending.
  sent,

  /// Accepted in EITHER direction → it's a mutual match.
  accepted,

  /// An interest in either direction was rejected.
  rejected,

  /// They sent ME an interest that is still pending (awaiting my response).
  receivedPending,
}

/// Resolves the [InterestUiStatus] between the signed-in user and the profile
/// [profileId]. Acceptance (either direction) wins, then a sent interest, then
/// a received-pending one. Used to render the correct, non-duplicating button.
final interestStatusForProfileProvider =
    Provider.autoDispose.family<InterestUiStatus, String>((ref, profileId) {
  final sent =
      ref.watch(sentInterestsProvider).valueOrNull ?? const <InterestModel>[];
  final received =
      ref.watch(receivedInterestsProvider).valueOrNull ?? const <InterestModel>[];

  // Accepted in either direction → matched (highest priority).
  final acceptedEither =
      sent.any((i) => i.receiverProfileId == profileId && i.isAccepted) ||
          received.any((i) => i.senderProfileId == profileId && i.isAccepted);
  if (acceptedEither) return InterestUiStatus.accepted;

  // An interest I sent to them.
  for (final i in sent) {
    if (i.receiverProfileId == profileId) {
      return i.isRejected ? InterestUiStatus.rejected : InterestUiStatus.sent;
    }
  }
  // An interest they sent to me.
  for (final i in received) {
    if (i.senderProfileId == profileId) {
      return i.isRejected
          ? InterestUiStatus.rejected
          : InterestUiStatus.receivedPending;
    }
  }
  return InterestUiStatus.none;
});

/// The pending interest the target [profileId] sent to the signed-in user, if
/// any. Lets the Matches card accept it in place (turning the pair into a
/// match) without leaving the screen.
final pendingReceivedInterestFromProfileProvider =
    Provider.autoDispose.family<InterestModel?, String>((ref, profileId) {
  final received =
      ref.watch(receivedInterestsProvider).valueOrNull ?? const <InterestModel>[];
  for (final i in received) {
    if (i.senderProfileId == profileId && i.isPending) return i;
  }
  return null;
});

/// The ACCEPTED interest (if any) between the signed-in user and [profileId],
/// in either direction. Used to backfill the contact-unlock connection when
/// the user opens contact for an accepted match.
final acceptedInterestForProfileProvider =
    Provider.autoDispose.family<InterestModel?, String>((ref, profileId) {
  final sent =
      ref.watch(sentInterestsProvider).valueOrNull ?? const <InterestModel>[];
  final received =
      ref.watch(receivedInterestsProvider).valueOrNull ?? const <InterestModel>[];
  for (final i in sent) {
    if (i.receiverProfileId == profileId && i.isAccepted) return i;
  }
  for (final i in received) {
    if (i.senderProfileId == profileId && i.isAccepted) return i;
  }
  return null;
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/interest_model.dart';
import 'auth_provider.dart';
import 'chat_provider.dart';
import 'profile_provider.dart';
import 'service_providers.dart';

/// The one-time opening line dropped into a freshly-created accepted-interest
/// chat so the conversation immediately appears in both users' Chats list.
const String kInterestAcceptedChatGreeting =
    "🎉 You're now connected! You can chat with each other here.";

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

/// Set of PROFILE ids the signed-in user has already sent an interest to (any
/// status). Used to hide already-actioned profiles from the Matches feed when
/// "Hide Interested Profiles" is on.
final sentInterestProfileIdsProvider = Provider.autoDispose<Set<String>>((ref) {
  final sent =
      ref.watch(sentInterestsProvider).valueOrNull ?? const <InterestModel>[];
  return sent.map((i) => i.receiverProfileId).toSet();
});

/// How many interests the signed-in user has sent TODAY. Drives the Free-plan
/// daily-interest limit (2/day).
final interestsSentTodayProvider = Provider.autoDispose<int>((ref) {
  final sent =
      ref.watch(sentInterestsProvider).valueOrNull ?? const <InterestModel>[];
  final now = DateTime.now();
  bool isToday(DateTime d) =>
      d.year == now.year && d.month == now.month && d.day == now.day;
  return sent.where((i) => isToday(i.sentAt)).length;
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
    state = await AsyncValue.guard(() async {
      await ref.read(interestRepositoryProvider).acceptInterest(interestId);
      // A user↔user chat is created automatically ONLY after an interest is
      // accepted (spec §5). Best-effort — never block/fail the accept.
      await _ensureAcceptedChat(interestId);
    });
  }

  /// Creates (idempotently) the chat thread between the two now-matched users
  /// and posts a one-time greeting so the conversation shows up in the Chats
  /// tab for both. Resolves the OTHER user's name/photo from their profile.
  Future<void> _ensureAcceptedChat(String interestId) async {
    try {
      final myUid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
      if (myUid == null) return;
      final all = <InterestModel>[
        ...(ref.read(receivedInterestsProvider).valueOrNull ?? const []),
        ...(ref.read(sentInterestsProvider).valueOrNull ?? const []),
      ];
      InterestModel? interest;
      for (final i in all) {
        if (i.id == interestId) {
          interest = i;
          break;
        }
      }
      if (interest == null) return;
      final otherUid =
          interest.senderId == myUid ? interest.receiverId : interest.senderId;
      if (otherUid.isEmpty || otherUid == myUid) return;

      final other = await ref.read(profileByUserIdProvider(otherUid).future);
      final otherName = other?.fullName.trim();
      final photoUrl = other?.profilePhotoUrl ?? '';
      final String otherPhoto = photoUrl.isNotEmpty
          ? photoUrl
          : (other != null && other.photos.isNotEmpty ? other.photos.first : '');

      final chat = ref.read(chatControllerProvider);
      final threadId = await chat.openChatWith(
        otherUid: otherUid,
        otherName: (otherName == null || otherName.isEmpty) ? 'Member' : otherName,
        otherPhoto: otherPhoto,
      );
      // Seed the opening greeting so the thread is non-empty and surfaces in the
      // Chats list for both users. Accepting an interest is a one-time
      // pending→accepted transition, so this won't double-post in practice.
      await chat.sendMessage(threadId, kInterestAcceptedChatGreeting);
    } catch (_) {
      // Intentionally ignored — chat creation must never fail the accept.
    }
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

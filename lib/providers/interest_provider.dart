import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/interest_model.dart';
import 'auth_provider.dart';
import 'chat_provider.dart';
import 'locale_provider.dart';
import 'profile_provider.dart';
import 'service_providers.dart';

/// The automatic FIRST message sent ON BEHALF OF the user who accepts an
/// interest, the moment they accept it — a normal chat message from them
/// (never a system notification), in the accepter's app language. Sent only
/// once: skipped when the thread already has any message.
const String kInterestAcceptedFirstMessageEn =
    'Hi! I have accepted your interest. We are now connected. '
    'Feel free to start the conversation.';
const String kInterestAcceptedFirstMessageTa =
    'வணக்கம்! உங்கள் விருப்பத்தை நான் ஏற்றுக்கொண்டேன். '
    'இப்போது நாம் இணைக்கப்பட்டுள்ளோம். தயங்காமல் உரையாடலைத் தொடங்கலாம்.';

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
      // A Married profile has left the matchmaking pool — it can no longer
      // send new interests (mirrors being hidden from the Matches feed).
      if (ref.read(myProfileProvider).valueOrNull?.isMarried ?? false) {
        throw Exception(
            'Your profile is marked as Married — new interests are disabled.');
      }
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
      // Married profiles can no longer form new matches.
      if (ref.read(myProfileProvider).valueOrNull?.isMarried ?? false) {
        throw Exception(
            'Your profile is marked as Married — new interests are disabled.');
      }
      await ref.read(interestRepositoryProvider).acceptInterest(interestId);
      // A user↔user chat is created automatically ONLY after an interest is
      // accepted (spec §5). Best-effort — never block/fail the accept.
      await _ensureAcceptedChat(interestId);
    });
  }

  /// Creates (idempotently) the chat thread between the two now-matched users
  /// the moment the interest is accepted — WITHOUT waiting for anyone to send
  /// a first message — and posts a one-time greeting so the conversation shows
  /// a "latest status" line for both. Resolves the OTHER user's name/photo from
  /// their profile.
  ///
  /// Reads the interest STRAIGHT from Firestore (not from provider caches,
  /// which may not be loaded on the screen the accept happened from — that was
  /// why the chat sometimes only appeared after the first manual message), and
  /// each step degrades independently: a profile-lookup failure still creates
  /// the thread with a fallback name, and a greeting failure still leaves the
  /// created thread visible in both Chats lists.
  Future<void> _ensureAcceptedChat(String interestId) async {
    try {
      final myUid = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid;
      if (myUid == null) return;

      // 1) Resolve the interest — Firestore first, provider caches as backup.
      InterestModel? interest;
      try {
        interest =
            await ref.read(interestRepositoryProvider).getInterestById(interestId);
      } catch (_) {/* fall through to caches */}
      if (interest == null) {
        final all = <InterestModel>[
          ...(ref.read(receivedInterestsProvider).valueOrNull ?? const []),
          ...(ref.read(sentInterestsProvider).valueOrNull ?? const []),
        ];
        for (final i in all) {
          if (i.id == interestId) {
            interest = i;
            break;
          }
        }
      }
      if (interest == null) {
        debugPrint('[InterestNotifier] accepted-chat: interest $interestId '
            'not found — no thread created');
        return;
      }
      final otherUid =
          interest.senderId == myUid ? interest.receiverId : interest.senderId;
      if (otherUid.isEmpty || otherUid == myUid) return;

      // 2) Resolve the other member's display name/photo (best-effort).
      String otherName = 'Member';
      String otherPhoto = '';
      try {
        final other = await ref.read(profileByUserIdProvider(otherUid).future);
        final name = other?.fullName.trim() ?? '';
        if (name.isNotEmpty) otherName = name;
        final photoUrl = other?.profilePhotoUrl ?? '';
        otherPhoto = photoUrl.isNotEmpty
            ? photoUrl
            : (other != null && other.photos.isNotEmpty
                ? other.photos.first
                : '');
      } catch (e) {
        debugPrint('[InterestNotifier] accepted-chat: profile lookup for '
            '$otherUid failed ($e) — using fallback name');
      }

      // 3) Create the thread NOW (this alone makes the conversation appear in
      // both users' Chats pages — the list does not require any message).
      final chat = ref.read(chatControllerProvider);
      final threadId = await chat.openChatWith(
        otherUid: otherUid,
        otherName: otherName,
        otherPhoto: otherPhoto,
      );

      // 4) Auto-send the FIRST message on behalf of the accepting user (a
      // normal message from them, in their app language) — ONLY when the
      // thread has no message yet, so it can never post twice. Accepting an
      // interest is a one-time pending→accepted transition; if this send
      // fails, the thread still exists.
      try {
        final thread = await ref.read(chatThreadProvider(threadId).future);
        if ((thread?.lastMessage ?? '').trim().isNotEmpty) {
          debugPrint('[InterestNotifier] accepted-chat: thread $threadId '
              'already has messages — first message skipped');
        } else {
          final isTamil =
              ref.read(localeProvider)?.languageCode == 'ta';
          await chat.sendMessage(
              threadId,
              isTamil
                  ? kInterestAcceptedFirstMessageTa
                  : kInterestAcceptedFirstMessageEn);
        }
      } catch (e) {
        debugPrint(
            '[InterestNotifier] accepted-chat: first message failed ($e) — '
            'thread $threadId still created');
      }
    } catch (e) {
      // Never fail the accept because of a chat hiccup — but leave a trace.
      debugPrint('[InterestNotifier] accepted-chat creation failed: $e');
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

/// The set of OTHER users' UIDs the signed-in user has a mutually-accepted
/// interest with (either direction). This is the single source of truth for
/// chat access control (spec §5/§8): only these users may appear in the Chats
/// list and exchange messages — pending / rejected / cancelled interests are
/// excluded.
final acceptedChatUserIdsProvider = Provider.autoDispose<Set<String>>((ref) {
  final sent =
      ref.watch(sentInterestsProvider).valueOrNull ?? const <InterestModel>[];
  final received =
      ref.watch(receivedInterestsProvider).valueOrNull ?? const <InterestModel>[];
  final ids = <String>{};
  for (final i in sent) {
    if (i.isAccepted) ids.add(i.receiverId);
  }
  for (final i in received) {
    if (i.isAccepted) ids.add(i.senderId);
  }
  return ids;
});

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

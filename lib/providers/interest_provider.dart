import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/interest_model.dart';
import 'auth_provider.dart';
import 'block_provider.dart';
import 'chat_provider.dart';
import 'locale_provider.dart';
import 'notification_provider.dart';
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
      // Approval workflow: an unapproved (pending/rejected) profile is not
      // visible to anyone, so its interests would show as broken "Member"
      // cards on the receiver side. Interests unlock at approval.
      final myStatus = ref.read(myProfileProvider).valueOrNull?.status;
      if (myStatus != null && myStatus != 'approved') {
        throw Exception(myStatus == 'pending'
            ? 'Your profile is awaiting approval — you can send interests '
                'as soon as it is approved.'
            : 'Your profile is not approved for matchmaking.');
      }
      // Blocked in either direction (spec §6) → interest is refused.
      if (ref.read(blockedUidsProvider).contains(receiverId)) {
        throw Exception(
            'You cannot send an interest to a user you have blocked.');
      }

      // DUPLICATE PREVENTION — an interest may exist in at most ONE direction
      // per pair. Check BOTH deterministic doc ids straight from Firestore
      // (the live streams may not be loaded on every surface):
      //  • forward  ({me}_{them})  → I already sent one; never send twice.
      //  • reverse  ({them}_{me})  → THEY already sent one; the only valid
      //    responses are Accept / Reject, never a counter-interest.
      // The security rules enforce the same invariant server-side, so a race
      // between two devices cannot slip through either.
      final repo = ref.read(interestRepositoryProvider);
      final forwardId = '${senderProfileId}_$receiverProfileId';
      final reverseId = '${receiverProfileId}_$senderProfileId';
      final existingForward = await repo.getInterestById(forwardId);
      if (existingForward != null) {
        if (existingForward.isAccepted) return; // already matched — no-op
        throw Exception('You have already sent an interest to this profile.');
      }
      final existingReverse = await repo.getInterestById(reverseId);
      if (existingReverse != null) {
        if (existingReverse.isAccepted) return; // already matched — no-op
        throw Exception(existingReverse.isPending
            ? 'This member has already shown interest in you — '
                'accept or decline their interest instead.'
            : 'An interest already exists between you and this profile.');
      }

      final interest = InterestModel(
        id: forwardId,
        senderId: senderId,
        receiverId: receiverId,
        senderProfileId: senderProfileId,
        receiverProfileId: receiverProfileId,
        status: 'pending',
        sentAt: DateTime.now(),
      );
      await repo.sendInterest(interest);
      // In-app "Interest Received" notification for the receiver. The
      // DETERMINISTIC id means a re-send after withdraw can never stack a
      // second notification, and the `interests`-onDelete Cloud Function can
      // remove it when the interest is withdrawn. The `notifications`-onCreate
      // Cloud Function delivers the FCM push.
      await ref.read(notificationNotifierProvider.notifier).notify(
            toUid: receiverId,
            event: AppNotificationEvent.interestReceived,
            name: ref.read(myProfileProvider).valueOrNull?.fullName ?? '',
            route: '/interests?tab=received&highlight=$senderId',
            id: 'interest_received_$forwardId',
            targetScreen: 'interests',
            targetId: forwardId,
          );
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
      // In-app "Interest Accepted" notification for the sender (best-effort).
      await _notifyInterestOutcome(
          interestId, AppNotificationEvent.interestAccepted);
      // …and a "New Match" for BOTH sides — accepting an interest is exactly
      // when a match comes into existence (spec §10).
      await _notifyNewMatch(interestId);
    });
  }

  /// "New Match" for both members of a freshly accepted interest.
  ///
  /// Each side is told the OTHER's name and deep-links to that profile, so a
  /// tap opens the person they just matched with. Deterministic ids
  /// (`new_match_<interestId>_<uid>`) mean a retry can never double-notify.
  /// Best-effort throughout — never fails the accept.
  Future<void> _notifyNewMatch(String interestId) async {
    try {
      final interest =
          await ref.read(interestRepositoryProvider).getInterestById(interestId);
      if (interest == null) return;
      final notifier = ref.read(notificationNotifierProvider.notifier);
      final myName = ref.read(myProfileProvider).valueOrNull?.fullName ?? '';
      // The interest document carries ids only, so the sender's display name
      // comes from their profile. An unreadable profile just falls back to the
      // generic "a member" wording inside notify().
      String senderName = '';
      try {
        senderName = (await ref
                    .read(profileRepositoryProvider)
                    .getProfileByUserId(interest.senderId))
                ?.fullName ??
            '';
      } catch (_) {/* generic wording is fine */}

      // → the sender, about me (the receiver).
      await notifier.notify(
        toUid: interest.senderId,
        event: AppNotificationEvent.newMatch,
        name: myName,
        route: '/profile-user/${interest.receiverId}',
        id: 'new_match_${interestId}_${interest.senderId}',
        targetScreen: 'profile',
        targetId: interest.receiverId,
      );
      // → me, about the sender.
      await notifier.notify(
        toUid: interest.receiverId,
        event: AppNotificationEvent.newMatch,
        name: senderName,
        route: '/profile-user/${interest.senderId}',
        id: 'new_match_${interestId}_${interest.receiverId}',
        targetScreen: 'profile',
        targetId: interest.senderId,
      );
    } catch (e) {
      debugPrint('[InterestNotifier] new-match notification failed: $e');
    }
  }

  /// Notifies the ORIGINAL SENDER of [interestId] that their interest was
  /// accepted / rejected. Best-effort — never fails the action.
  ///
  /// The route deep-links straight to the tab the interest now lives in, with
  /// the counterpart (me, the responder) highlighted; deterministic ids keep
  /// one notification per interest outcome.
  Future<void> _notifyInterestOutcome(
      String interestId, AppNotificationEvent event) async {
    try {
      final interest =
          await ref.read(interestRepositoryProvider).getInterestById(interestId);
      if (interest == null) return;
      final accepted = event == AppNotificationEvent.interestAccepted;
      await ref.read(notificationNotifierProvider.notifier).notify(
            toUid: interest.senderId,
            event: event,
            name: ref.read(myProfileProvider).valueOrNull?.fullName ?? '',
            route: accepted
                ? '/interests?tab=accepted&highlight=${interest.receiverId}'
                : '/interests?tab=rejected&highlight=${interest.receiverId}',
            id: '${accepted ? 'interest_accepted' : 'interest_rejected'}'
                '_$interestId',
            targetScreen: 'interests',
            targetId: interestId,
          );
    } catch (e) {
      debugPrint('[InterestNotifier] outcome notification failed: $e');
    }
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
          // Deterministic id: the interest-accepted Cloud Function posts the
          // same greeting doc, so client + server can never double-greet.
          await chat.sendMessage(
              threadId,
              isTamil
                  ? kInterestAcceptedFirstMessageTa
                  : kInterestAcceptedFirstMessageEn,
              messageId: 'greeting_$threadId');
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
    state = await AsyncValue.guard(() async {
      await ref.read(interestRepositoryProvider).rejectInterest(interestId);
      // In-app "Interest Update" notification for the sender (best-effort).
      await _notifyInterestOutcome(
          interestId, AppNotificationEvent.interestRejected);
    });
  }

  /// Ensures the contact-unlock connection exists for an accepted interest —
  /// backfills matches accepted before connections were created.
  Future<void> ensureConnection(InterestModel interest) =>
      ref.read(interestRepositoryProvider).ensureConnection(interest);

  /// Withdraws (unsends) a pending interest the signed-in user sent. Deletes
  /// the interest document so it disappears from both users immediately.
  Future<void> withdrawInterest(String interestId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(interestRepositoryProvider).withdrawInterest(interestId);
    });
  }
}

final interestNotifierProvider =
    NotifierProvider<InterestNotifier, AsyncValue<void>>(() => InterestNotifier());

/// Human-readable message from a failed interest action, for SnackBars. The
/// notifier wraps actions in AsyncValue.guard (they never throw), so call
/// sites read the state afterwards; this strips the 'Exception: ' prefix from
/// the deliberate, already-friendly messages thrown above and returns
/// [fallback] for raw platform errors.
String interestErrorText(Object? error, String fallback) {
  final s = (error ?? '').toString();
  if (s.startsWith('Exception: ')) return s.substring('Exception: '.length);
  return fallback;
}

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

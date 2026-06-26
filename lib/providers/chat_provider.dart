import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/dev_config.dart';
import '../models/chat_model.dart';
import 'auth_provider.dart';
import 'demo_data_provider.dart';
import 'profile_provider.dart';
import 'service_providers.dart';

/// Generic fallback for the auto booking-accepted message — used when the
/// booking has no two named profiles (e.g. a non-matching request or a legacy
/// booking). See [buildBookingAcceptedMessage].
const String kBookingAcceptedMessage =
    '✅ உங்கள் Booking ஏற்றுக்கொள்ளப்பட்டது. '
    'உங்கள் Match Analysis தற்போது தொடங்கப்பட்டுள்ளது.';

/// Builds the automatic system message sent FROM the astrologer the moment they
/// accept a match-analysis booking (status → "In Progress"). When BOTH profile
/// names are known it names the two profiles being analysed (dynamically — never
/// hardcoded); otherwise it falls back to [kBookingAcceptedMessage]. The
/// astrologer never types this — see [ChatController.sendBookingAcceptedMessage].
String buildBookingAcceptedMessage({String? groomName, String? brideName}) {
  final groom = groomName?.trim() ?? '';
  final bride = brideName?.trim() ?? '';
  if (groom.isEmpty || bride.isEmpty) return kBookingAcceptedMessage;
  return '✅ உங்கள் Booking ஏற்றுக்கொள்ளப்பட்டுள்ளது.\n\n'
      '👤 Match Analysis Profiles:\n'
      '❤️ $groom  ×  ❤️ $bride\n\n'
      'இந்த இரண்டு Profile-களுக்கான Match Analysis தற்போது தொடங்கப்பட்டுள்ளது.';
}

/// The TWO quick-message options shown to the USER inside an astrologer chat.
/// Tapping one sends it instantly as a normal message (no dialog). The
/// astrologer never sees these.
const String kQuickAskReportEta =
    '📄 என் Match Analysis Report எப்போது கிடைக்கும்?';
const String kQuickAskBookingStatus = '📅 என் Booking Status என்ன?';

/// Uid of the signed-in person (demo id when auth is bypassed).
final myUidProvider = Provider<String?>((ref) {
  if (kBypassAuth) return kDemoUserId;
  return ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
});

// ── Demo in-memory chat store ───────────────────────────────────────────────
class DemoChatState {
  final Map<String, ChatThread> threads;
  final Map<String, List<ChatMessage>> messages;
  const DemoChatState({this.threads = const {}, this.messages = const {}});

  DemoChatState copyWith({
    Map<String, ChatThread>? threads,
    Map<String, List<ChatMessage>>? messages,
  }) =>
      DemoChatState(
        threads: threads ?? this.threads,
        messages: messages ?? this.messages,
      );
}

class DemoChatNotifier extends Notifier<DemoChatState> {
  @override
  DemoChatState build() => const DemoChatState();

  String openThread({
    required String myUid,
    required String myName,
    required String myPhoto,
    required String otherUid,
    required String otherName,
    required String otherPhoto,
  }) {
    final id = ChatThread.threadIdFor(myUid, otherUid);
    if (!state.threads.containsKey(id)) {
      state = state.copyWith(threads: {
        ...state.threads,
        id: ChatThread(
          id: id,
          participantIds: [myUid, otherUid],
          participantNames: {myUid: myName, otherUid: otherName},
          participantPhotos: {myUid: myPhoto, otherUid: otherPhoto},
          lastMessageAt: DateTime.now(),
        ),
      });
    }
    return id;
  }

  void sendMessage(
    String threadId,
    String senderId,
    String text, {
    ChatMessageType type = ChatMessageType.text,
    String attachmentUrl = '',
    String fileName = '',
    String fileType = '',
  }) {
    final now = DateTime.now();
    final msg = ChatMessage(
      id: 'm${now.microsecondsSinceEpoch}',
      senderId: senderId,
      text: text,
      sentAt: now,
      type: type,
      attachmentUrl: attachmentUrl,
      fileName: fileName,
      fileType: fileType,
    );
    final thread = state.threads[threadId];
    state = state.copyWith(
      messages: {
        ...state.messages,
        threadId: [msg, ...(state.messages[threadId] ?? const [])],
      },
      threads: {
        ...state.threads,
        if (thread != null)
          threadId: ChatThread(
            id: thread.id,
            participantIds: thread.participantIds,
            participantNames: thread.participantNames,
            participantPhotos: thread.participantPhotos,
            lastMessage:
                chatPreviewFor(type: type, text: text, fileName: fileName),
            lastSenderId: senderId,
            lastMessageAt: now,
            unread: thread.unread,
          ),
      },
    );
  }
}

final demoChatProvider =
    NotifierProvider<DemoChatNotifier, DemoChatState>(DemoChatNotifier.new);

// ── Streams used by the UI ──────────────────────────────────────────────────
final myChatThreadsProvider =
    StreamProvider.autoDispose<List<ChatThread>>((ref) {
  final uid = ref.watch(myUidProvider);
  if (uid == null) return Stream.value(const []);
  if (kBypassAuth) {
    final threads = ref.watch(demoChatProvider).threads.values.toList()
      ..sort((a, b) => (b.lastMessageAt ?? DateTime(0))
          .compareTo(a.lastMessageAt ?? DateTime(0)));
    return Stream.value(threads);
  }
  return ref.read(chatServiceProvider).watchThreads(uid);
});

/// Total unread messages for the signed-in person across all their threads —
/// drives the red badge on the dashboard Chat icon. Empty (message-less)
/// threads are ignored so a pre-created booking thread never shows a phantom
/// badge. Realtime: recomputed whenever [myChatThreadsProvider] emits, so the
/// badge appears the instant a new message arrives and clears as soon as the
/// thread is opened and marked read.
final myUnreadChatCountProvider = Provider.autoDispose<int>((ref) {
  final uid = ref.watch(myUidProvider);
  if (uid == null) return 0;
  final threads = ref.watch(myChatThreadsProvider).valueOrNull ?? const [];
  var total = 0;
  for (final t in threads) {
    if (t.lastMessage.trim().isEmpty) continue;
    total += t.unreadFor(uid);
  }
  return total;
});

final chatThreadProvider =
    StreamProvider.autoDispose.family<ChatThread?, String>((ref, threadId) {
  if (kBypassAuth) {
    return Stream.value(ref.watch(demoChatProvider).threads[threadId]);
  }
  return ref.read(chatServiceProvider).watchThread(threadId);
});

/// Messages newest-first (UI renders the list reversed).
final chatMessagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, String>((ref, threadId) {
  if (kBypassAuth) {
    return Stream.value(
        ref.watch(demoChatProvider).messages[threadId] ?? const []);
  }
  return ref.read(chatServiceProvider).watchMessages(threadId);
});

/// Imperative chat actions shared by screens.
class ChatController {
  final Ref _ref;
  ChatController(this._ref);

  /// Opens (creating if needed) a thread with [otherUid] and returns its id.
  Future<String> openChatWith({
    required String otherUid,
    required String otherName,
    required String otherPhoto,
  }) async {
    final myUid = _ref.read(myUidProvider);
    if (myUid == null) throw StateError('Not signed in');
    final myProfile = _ref.read(myProfileProvider).valueOrNull;
    final myName = myProfile?.fullName ??
        _ref.read(currentUserProvider).valueOrNull?.displayName ??
        'Me';
    final myPhoto = myProfile?.profilePhotoUrl ?? '';

    if (kBypassAuth) {
      return _ref.read(demoChatProvider.notifier).openThread(
            myUid: myUid,
            myName: myName,
            myPhoto: myPhoto,
            otherUid: otherUid,
            otherName: otherName,
            otherPhoto: otherPhoto,
          );
    }
    return _ref.read(chatServiceProvider).getOrCreateThread(
          myUid: myUid,
          myName: myName,
          myPhoto: myPhoto,
          otherUid: otherUid,
          otherName: otherName,
          otherPhoto: otherPhoto,
        );
  }

  Future<void> sendMessage(String threadId, String text) async {
    final myUid = _ref.read(myUidProvider);
    if (myUid == null || text.trim().isEmpty) return;
    if (kBypassAuth) {
      _ref
          .read(demoChatProvider.notifier)
          .sendMessage(threadId, myUid, text.trim());
      return;
    }
    await _ref.read(chatServiceProvider).sendMessage(
        threadId: threadId, senderId: myUid, text: text.trim());
  }

  /// Uploads [file] (image / pdf / document) to the thread's storage folder and
  /// sends it as an attachment message. The Cloudinary URL is real even in demo
  /// mode, so the attachment opens/previews identically. Rethrows so the screen
  /// can surface a retry SnackBar on failure (graceful handling).
  Future<void> sendAttachment(
    String threadId,
    File file,
    ChatMessageType type, {
    String fileName = '',
  }) async {
    final myUid = _ref.read(myUidProvider);
    if (myUid == null) throw StateError('Not signed in');
    final name = fileName.trim().isEmpty
        ? file.path.split(RegExp(r'[\\/]')).last
        : fileName.trim();
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final url = await _ref.read(storageServiceProvider).uploadChatAttachment(
          threadId: threadId,
          file: file,
          isImage: type == ChatMessageType.image,
        );
    final preview = chatPreviewFor(type: type, text: '', fileName: name);

    if (kBypassAuth) {
      _ref.read(demoChatProvider.notifier).sendMessage(
            threadId,
            myUid,
            preview,
            type: type,
            attachmentUrl: url,
            fileName: name,
            fileType: ext,
          );
      return;
    }
    await _ref.read(chatServiceProvider).sendMessage(
          threadId: threadId,
          senderId: myUid,
          text: preview,
          type: type,
          attachmentUrl: url,
          fileName: name,
          fileType: ext,
        );
  }

  /// Automatically sends the booking-accepted system message FROM the signed-in
  /// astrologer into the thread with [userUid] (creating the thread if needed),
  /// the instant a match-analysis request is accepted.
  ///
  /// Best-effort: a chat hiccup (e.g. rules not yet deployed) must NEVER block
  /// the accept action, so failures are swallowed. With the relaxed `chats`
  /// create rule the astrologer can create the thread here; the user can also
  /// open it later from their booking card either way.
  Future<void> sendBookingAcceptedMessage({
    required String userUid,
    required String userName,
    required String userPhoto,
    String? groomName,
    String? brideName,
  }) async {
    try {
      final threadId = await openChatWith(
        otherUid: userUid,
        otherName: userName.trim().isEmpty ? 'User' : userName.trim(),
        otherPhoto: userPhoto,
      );
      await sendMessage(
          threadId,
          buildBookingAcceptedMessage(
              groomName: groomName, brideName: brideName));
    } catch (_) {
      // Intentionally ignored — accept must succeed regardless.
    }
  }

  Future<void> markRead(String threadId) async {
    final myUid = _ref.read(myUidProvider);
    if (myUid == null || kBypassAuth) return;
    await _ref.read(chatServiceProvider).markThreadRead(threadId, myUid);
  }
}

final chatControllerProvider = Provider<ChatController>(ChatController.new);

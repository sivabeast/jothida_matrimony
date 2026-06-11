import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/dev_config.dart';
import '../models/chat_model.dart';
import 'auth_provider.dart';
import 'demo_data_provider.dart';
import 'profile_provider.dart';
import 'service_providers.dart';

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

  void sendMessage(String threadId, String senderId, String text) {
    final now = DateTime.now();
    final msg = ChatMessage(
      id: 'm${now.microsecondsSinceEpoch}',
      senderId: senderId,
      text: text,
      sentAt: now,
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
            lastMessage: text,
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

  Future<void> markRead(String threadId) async {
    final myUid = _ref.read(myUidProvider);
    if (myUid == null || kBypassAuth) return;
    await _ref.read(chatServiceProvider).markThreadRead(threadId, myUid);
  }
}

final chatControllerProvider = Provider<ChatController>(ChatController.new);

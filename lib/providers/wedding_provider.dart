import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/wedding_model.dart';
import '../services/firebase/wedding_service.dart';
import 'auth_provider.dart';
import 'profile_provider.dart';
import 'service_providers.dart';

/// Marriage Fixed + Wedding Workspace state.
///
/// A workspace participant is either a COUPLE member (bride/groom — keyed by
/// uid) or an invited FAMILY member (keyed by their lowercased gmail, the
/// access key the Firestore rules check).

final weddingServiceProvider =
    Provider<WeddingService>((ref) => WeddingService());

/// True while the Login screen's "Family Member Login" flow is verifying the
/// invitation. The router redirect holds the user on /login during this
/// window instead of racing them into the matrimony onboarding.
final familyLoginInProgressProvider = StateProvider<bool>((ref) => false);

// ── Entry mode (role-based entry) ─────────────────────────────────────────────

/// Which entry card the user chose on the login screen. ONE Gmail can hold
/// BOTH roles — the selected card (not the account) decides which interface
/// opens:
///   • 'matrimony' → the matrimony experience (Home, matches, …);
///   • 'family'    → the Wedding Workspace they were invited to (by gmail).
/// Persisted so the next app open restores the same interface.
class WeddingEntryMode {
  static const matrimony = 'matrimony';
  static const family = 'family';
  static const _prefsKey = 'wedding_entry_mode';

  static Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey);
  }

  static Future<void> save(String? mode) async {
    final prefs = await SharedPreferences.getInstance();
    if (mode == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, mode);
    }
  }
}

/// In-memory mirror of the persisted entry mode. Set by the login flow /
/// splash and by the "Switch to Matrimony" workspace action. When 'family',
/// the workspace resolves the wedding by the login GMAIL (invited member)
/// even for an account that is also a matrimony user.
final entryModeProvider = StateProvider<String?>((ref) => null);

// ── Resolution ────────────────────────────────────────────────────────────────

/// The signed-in MATRIMONY user's wedding (as bride or groom), if any.
final myCoupleWeddingProvider =
    StreamProvider.autoDispose<WeddingModel?>((ref) {
  final uid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(weddingServiceProvider).watchWeddingForCouple(uid);
});

/// The wedding the signed-in user belongs to, resolved by entry role:
/// a FAMILY entry (dedicated 'family' account OR a dual-role Gmail that chose
/// the Family Member card) is matched by their invited gmail, everyone else
/// as a couple member. Drives the Wedding Workspace screen.
final activeWeddingProvider = StreamProvider.autoDispose<WeddingModel?>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(null);
  final service = ref.watch(weddingServiceProvider);
  final familyEntry = user.isFamily ||
      ref.watch(entryModeProvider) == WeddingEntryMode.family;
  if (familyEntry) {
    final email = user.email?.toLowerCase() ?? '';
    if (email.isEmpty) return Stream.value(null);
    return service.watchWeddingByMemberEmail(email);
  }
  return service.watchWeddingForCouple(user.uid);
});

/// The wedding (if any) between the signed-in user and [otherUid] — powers
/// the Marriage Fixed button state on the accepted-interest card.
final weddingWithUserProvider = StreamProvider.autoDispose
    .family<WeddingModel?, String>((ref, otherUid) {
  final uid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
  if (uid == null || otherUid.isEmpty) return Stream.value(null);
  return ref.watch(weddingServiceProvider).watchWeddingByPair(uid, otherUid);
});

// ── Workspace sub-collections ─────────────────────────────────────────────────

final weddingChecklistProvider = StreamProvider.autoDispose
    .family<List<WeddingChecklistItem>, String>((ref, weddingId) =>
        ref.watch(weddingServiceProvider).watchChecklist(weddingId));

final weddingDocumentsProvider = StreamProvider.autoDispose
    .family<List<WeddingDocument>, String>((ref, weddingId) =>
        ref.watch(weddingServiceProvider).watchDocuments(weddingId));

final weddingContactsProvider = StreamProvider.autoDispose
    .family<List<WeddingContact>, String>((ref, weddingId) =>
        ref.watch(weddingServiceProvider).watchContacts(weddingId));

final weddingGuestsProvider = StreamProvider.autoDispose
    .family<List<WeddingGuest>, String>((ref, weddingId) =>
        ref.watch(weddingServiceProvider).watchGuests(weddingId));

final weddingGalleryProvider = StreamProvider.autoDispose
    .family<List<WeddingPhoto>, String>((ref, weddingId) =>
        ref.watch(weddingServiceProvider).watchGallery(weddingId));

final weddingVendorsProvider = StreamProvider.autoDispose
    .family<List<WeddingVendor>, String>((ref, weddingId) =>
        ref.watch(weddingServiceProvider).watchVendors(weddingId));

final weddingChatProvider = StreamProvider.autoDispose
    .family<List<WeddingChatMessage>, String>((ref, weddingId) =>
        ref.watch(weddingServiceProvider).watchChat(weddingId));

// ── Who am I inside the workspace? ────────────────────────────────────────────

class WeddingIdentity {
  final String key; // uid (couple) or email (family)
  final String name;
  final bool isCouple;
  const WeddingIdentity(
      {required this.key, required this.name, required this.isCouple});
}

/// Resolves the signed-in user's participant identity for [wedding]:
/// couple members are keyed by uid, family members by their invited gmail.
final weddingIdentityProvider = Provider.autoDispose
    .family<WeddingIdentity?, WeddingModel>((ref, wedding) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return null;
  if (wedding.coupleIds.contains(user.uid)) {
    return WeddingIdentity(
      key: user.uid,
      name: wedding.nameOf(user.uid),
      isCouple: true,
    );
  }
  final email = user.email?.toLowerCase() ?? '';
  for (final m in wedding.members) {
    if (m.email == email) {
      return WeddingIdentity(key: email, name: m.name, isCouple: false);
    }
  }
  if (email.isNotEmpty && wedding.memberEmails.contains(email)) {
    return WeddingIdentity(
        key: email, name: user.displayName ?? 'Family Member', isCouple: false);
  }
  return null;
});

// ── Actions ───────────────────────────────────────────────────────────────────

class WeddingController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  WeddingService get _service => ref.read(weddingServiceProvider);

  String get _myUid =>
      ref.read(firebaseAuthStreamProvider).valueOrNull?.uid ?? '';

  Future<T?> _guarded<T>(Future<T> Function() action) async {
    state = const AsyncLoading();
    T? result;
    state = await AsyncValue.guard(() async {
      result = await action();
    });
    return state.hasError ? null : result;
  }

  /// "Marriage Fixed" — records the signed-in user's confirmation with
  /// [otherUid]. Sides (bride/groom) are derived from the two profiles'
  /// genders. Returns the resulting wedding (fixed once BOTH confirm).
  Future<WeddingModel?> confirmMarriageFixed(String otherUid) {
    return _guarded(() async {
      final myUid = _myUid;
      if (myUid.isEmpty) throw Exception('Not signed in');
      final myProfile = ref.read(myProfileProvider).valueOrNull;
      final otherProfile =
          await ref.read(profileByUserIdProvider(otherUid).future);
      final myName = myProfile?.fullName.trim().isNotEmpty == true
          ? myProfile!.fullName.trim()
          : (ref.read(currentUserProvider).valueOrNull?.displayName ?? 'Me');
      final otherName = otherProfile?.fullName.trim().isNotEmpty == true
          ? otherProfile!.fullName.trim()
          : 'Partner';
      final mySide =
          (myProfile?.gender.toLowerCase() == 'male') ? 'groom' : 'bride';
      final otherSide = mySide == 'groom' ? 'bride' : 'groom';
      return _service.confirmMarriageFixed(
        myUid: myUid,
        otherUid: otherUid,
        myName: myName,
        otherName: otherName,
        mySide: mySide,
        otherSide: otherSide,
      );
    });
  }

  Future<void> setWeddingDate(String weddingId, DateTime date) async {
    await _guarded(() => _service.setWeddingDate(weddingId, date));
  }

  // ── Family invitations ────────────────────────────────────────────────────

  Future<bool> inviteMember(String weddingId, WeddingMember member) async {
    final ok = await _guarded(() async {
      await _service.inviteMember(weddingId, member);
      return true;
    });
    return ok == true;
  }

  Future<void> removeMember(String weddingId, String email) async {
    await _guarded(() => _service.removeMember(weddingId, email));
  }

  // ── Checklist ─────────────────────────────────────────────────────────────

  Future<void> addChecklistItem(
    String weddingId, {
    required String title,
    String notes = '',
    String scope = 'shared',
    required WeddingIdentity me,
    String assignedToKey = '',
    String assignedToName = '',
  }) async {
    await _guarded(() => _service.addChecklistItem(
          weddingId,
          WeddingChecklistItem(
            id: '',
            title: title,
            notes: notes,
            scope: scope,
            createdByKey: me.key,
            createdByName: me.name,
            assignedToKey: assignedToKey,
            assignedToName: assignedToName,
            assignmentStatus: assignedToKey.isEmpty ? 'none' : 'pending',
            createdAt: DateTime.now(),
          ),
        ));
  }

  Future<void> updateChecklistItem(String weddingId, String itemId,
      {required String title, required String notes}) async {
    await _guarded(() => _service
        .updateChecklistItem(weddingId, itemId, {'title': title, 'notes': notes}));
  }

  Future<void> deleteChecklistItem(String weddingId, String itemId) async {
    await _guarded(() => _service.deleteChecklistItem(weddingId, itemId));
  }

  Future<void> setChecklistStatus(
      String weddingId, String itemId, bool completed) async {
    await _guarded(
        () => _service.setChecklistStatus(weddingId, itemId, completed));
  }

  Future<void> assignChecklistItem(String weddingId, String itemId,
      {required WeddingParticipant assignee}) async {
    await _guarded(() => _service.assignChecklistItem(weddingId, itemId,
        assignedToKey: assignee.key, assignedToName: assignee.name));
  }

  Future<void> respondToAssignment(String weddingId, String itemId,
      {required bool accept, String reason = ''}) async {
    await _guarded(() => _service.respondToAssignment(weddingId, itemId,
        accept: accept, reason: reason));
  }

  // ── Documents ─────────────────────────────────────────────────────────────

  Future<void> uploadDocument(
    String weddingId, {
    required File file,
    required bool isImage,
    required String title,
    required String category,
    String scope = 'shared',
    required WeddingIdentity me,
  }) async {
    await _guarded(() async {
      final url = await ref.read(storageServiceProvider).uploadWeddingDocument(
          weddingId: weddingId, file: file, isImage: isImage);
      await _service.addDocument(
        weddingId,
        WeddingDocument(
          id: '',
          title: title,
          category: category,
          scope: scope,
          url: url,
          isImage: isImage,
          uploadedByName: me.name,
          uploadedAt: DateTime.now(),
        ),
      );
    });
  }

  Future<void> deleteDocument(String weddingId, String docId) async {
    await _guarded(() => _service.deleteDocument(weddingId, docId));
  }

  // ── Contacts ──────────────────────────────────────────────────────────────

  Future<void> saveContact(
    String weddingId, {
    String? contactId,
    required String side,
    required String name,
    required String relationship,
    required String mobile,
    required String gmail,
    required WeddingIdentity me,
  }) async {
    await _guarded(() {
      if (contactId != null) {
        return _service.updateContact(weddingId, contactId, {
          'side': side,
          'name': name,
          'relationship': relationship,
          'mobile': mobile,
          'gmail': gmail,
        });
      }
      return _service.addContact(
        weddingId,
        WeddingContact(
          id: '',
          side: side,
          name: name,
          relationship: relationship,
          mobile: mobile,
          gmail: gmail,
          addedByName: me.name,
          createdAt: DateTime.now(),
        ),
      );
    });
  }

  Future<void> deleteContact(String weddingId, String contactId) async {
    await _guarded(() => _service.deleteContact(weddingId, contactId));
  }

  // ── Guests ────────────────────────────────────────────────────────────────

  Future<void> saveGuest(
    String weddingId, {
    String? guestId,
    required String side,
    required String name,
    String phone = '',
    String notes = '',
    required WeddingIdentity me,
  }) async {
    await _guarded(() {
      if (guestId != null) {
        return _service.updateGuest(weddingId, guestId,
            {'side': side, 'name': name, 'phone': phone, 'notes': notes});
      }
      return _service.addGuest(
        weddingId,
        WeddingGuest(
          id: '',
          side: side,
          name: name,
          phone: phone,
          notes: notes,
          addedByName: me.name,
          createdAt: DateTime.now(),
        ),
      );
    });
  }

  Future<void> deleteGuest(String weddingId, String guestId) async {
    await _guarded(() => _service.deleteGuest(weddingId, guestId));
  }

  // ── Shared photo gallery ──────────────────────────────────────────────────

  Future<void> uploadPhoto(
    String weddingId, {
    required File file,
    required String album,
    String scope = 'shared',
    String caption = '',
    required WeddingIdentity me,
  }) async {
    await _guarded(() async {
      final url = await ref.read(storageServiceProvider).uploadWeddingDocument(
          weddingId: weddingId, file: file, isImage: true);
      await _service.addPhoto(
        weddingId,
        WeddingPhoto(
          id: '',
          album: album,
          scope: scope,
          url: url,
          caption: caption,
          uploadedByName: me.name,
          uploadedAt: DateTime.now(),
        ),
      );
    });
  }

  Future<void> deletePhoto(String weddingId, String photoId) async {
    await _guarded(() => _service.deletePhoto(weddingId, photoId));
  }

  // ── Vendors (couple-only management) ──────────────────────────────────────

  Future<void> saveVendor(
    String weddingId, {
    String? vendorId,
    required String category,
    required String name,
    String contactPerson = '',
    String mobile = '',
    String altMobile = '',
    String address = '',
    String notes = '',
    required List<String> visibleTo,
    required WeddingIdentity me,
  }) async {
    await _guarded(() {
      if (vendorId != null) {
        return _service.updateVendor(weddingId, vendorId, {
          'category': category,
          'name': name,
          'contactPerson': contactPerson,
          'mobile': mobile,
          'altMobile': altMobile,
          'address': address,
          'notes': notes,
          'visibleTo': visibleTo,
        });
      }
      return _service.addVendor(
        weddingId,
        WeddingVendor(
          id: '',
          category: category,
          name: name,
          contactPerson: contactPerson,
          mobile: mobile,
          altMobile: altMobile,
          address: address,
          notes: notes,
          visibleTo: visibleTo,
          createdByName: me.name,
          createdAt: DateTime.now(),
        ),
      );
    });
  }

  Future<void> deleteVendor(String weddingId, String vendorId) async {
    await _guarded(() => _service.deleteVendor(weddingId, vendorId));
  }

  // ── Family Group Chat ─────────────────────────────────────────────────────

  Future<void> sendChatText(
      String weddingId, String text, WeddingIdentity me) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _guarded(() => _service.sendChatMessage(
          weddingId,
          WeddingChatMessage(
            id: '',
            senderKey: me.key,
            senderName: me.name,
            type: 'text',
            text: trimmed,
            sentAt: DateTime.now(),
          ),
        ));
  }

  Future<void> sendChatAttachment(
    String weddingId, {
    required File file,
    required bool isImage,
    required String fileName,
    required WeddingIdentity me,
  }) async {
    await _guarded(() async {
      final url = await ref.read(storageServiceProvider).uploadWeddingDocument(
          weddingId: weddingId, file: file, isImage: isImage);
      await _service.sendChatMessage(
        weddingId,
        WeddingChatMessage(
          id: '',
          senderKey: me.key,
          senderName: me.name,
          type: isImage ? 'image' : 'file',
          url: url,
          fileName: fileName,
          sentAt: DateTime.now(),
        ),
      );
    });
  }

  // ── Postpone & Cancel ─────────────────────────────────────────────────────

  Future<void> postponeWedding(String weddingId, DateTime? newDate) async {
    await _guarded(() => _service.postponeWedding(weddingId, newDate));
  }

  Future<void> resumeWedding(String weddingId, DateTime newDate) async {
    await _guarded(() => _service.resumeWedding(weddingId, newDate));
  }

  /// PERMANENT: removes the Wedding Workspace and every piece of its data.
  /// Returns true on success so the UI can navigate away.
  Future<bool> cancelWedding(String weddingId) async {
    final ok = await _guarded(() async {
      await _service.cancelWedding(weddingId);
      return true;
    });
    return ok == true;
  }

  // ── Automatic Married status ──────────────────────────────────────────────

  /// When the wedding date has passed, marks the SIGNED-IN couple member's
  /// profile as Married (leaves matchmaking, interests disabled) exactly once.
  /// Family members and unaffected users are ignored. Safe to call on every
  /// app open — it no-ops unless there is real work to do.
  Future<void> runMarriedSweepIfDue(WeddingModel wedding) async {
    try {
      final myUid = _myUid;
      if (myUid.isEmpty || !wedding.coupleIds.contains(myUid)) return;
      if (!wedding.isFixed || !wedding.weddingDatePassed) return;
      if (wedding.marriedProcessed[myUid] == true) return;

      final profile = ref.read(myProfileProvider).valueOrNull;
      if (profile == null) return;
      if (!profile.isMarried) {
        await ref.read(firestoreServiceProvider).markProfileMarried(profile.id);
        ref.invalidate(myProfileProvider);
      }
      await _service.markMarriedProcessed(wedding.id, myUid);
      debugPrint('[WeddingController] auto-Married sweep done for $myUid '
          '(wedding ${wedding.id})');
    } catch (e) {
      // Best-effort — retried on the next app open.
      debugPrint('[WeddingController] married sweep failed (non-fatal): $e');
    }
  }
}

final weddingControllerProvider =
    NotifierProvider<WeddingController, AsyncValue<void>>(
        WeddingController.new);

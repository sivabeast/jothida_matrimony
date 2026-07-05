import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
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

final weddingGalleryCategoriesProvider = StreamProvider.autoDispose
    .family<List<WeddingGalleryCategory>, String>((ref, weddingId) =>
        ref.watch(weddingServiceProvider).watchGalleryCategories(weddingId));

/// (weddingId, participantKey) → category-key → last-seen time.
final weddingGallerySeenProvider = StreamProvider.autoDispose
    .family<Map<String, DateTime>, (String, String)>((ref, args) => ref
        .watch(weddingServiceProvider)
        .watchGallerySeen(args.$1, args.$2));

final weddingExpensesProvider = StreamProvider.autoDispose
    .family<List<WeddingExpense>, String>((ref, weddingId) =>
        ref.watch(weddingServiceProvider).watchExpenses(weddingId));

final weddingEventsProvider = StreamProvider.autoDispose
    .family<List<WeddingEvent>, String>((ref, weddingId) =>
        ref.watch(weddingServiceProvider).watchEvents(weddingId));

final weddingNotesProvider = StreamProvider.autoDispose
    .family<List<WeddingNote>, String>((ref, weddingId) =>
        ref.watch(weddingServiceProvider).watchNotes(weddingId));

final weddingDecisionsProvider = StreamProvider.autoDispose
    .family<List<WeddingDecision>, String>((ref, weddingId) =>
        ref.watch(weddingServiceProvider).watchDecisions(weddingId));

final weddingActivityProvider = StreamProvider.autoDispose
    .family<List<WeddingActivity>, String>((ref, weddingId) =>
        ref.watch(weddingServiceProvider).watchActivity(weddingId));

final weddingScheduleProvider = StreamProvider.autoDispose
    .family<List<WeddingScheduleItem>, String>((ref, weddingId) =>
        ref.watch(weddingServiceProvider).watchSchedule(weddingId));

// ── Who am I inside the workspace? ────────────────────────────────────────────

class WeddingIdentity {
  final String key; // uid (couple) or email (family)
  final String name;
  final bool isCouple; // Bride / Groom = Super Admin
  final String side; // 'bride' | 'groom'
  final Set<String> permissions; // family-member permissions (couple: all)

  const WeddingIdentity({
    required this.key,
    required this.name,
    required this.isCouple,
    required this.side,
    this.permissions = const {},
  });

  /// The Bride and Groom are Super Admins — they override every permission
  /// and manage the entire workspace.
  bool get isSuperAdmin => isCouple;

  bool can(String permission) =>
      isSuperAdmin || permissions.contains(permission);

  /// The two workspaces this participant may see: their own side + Shared.
  /// The opposite side's workspace is never visible.
  List<String> get visibleScopes => [side, 'shared'];

  String get sideLabel => side == 'groom' ? 'Groom Side' : 'Bride Side';
}

/// Resolves the signed-in user's participant identity for [wedding]:
/// couple members are keyed by uid, family members by their invited gmail.
/// Also resolves the participant's SIDE (bride/groom) and granted
/// permissions — the basis of all workspace role-based access control.
final weddingIdentityProvider = Provider.autoDispose
    .family<WeddingIdentity?, WeddingModel>((ref, wedding) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return null;
  if (wedding.coupleIds.contains(user.uid)) {
    return WeddingIdentity(
      key: user.uid,
      name: wedding.nameOf(user.uid),
      isCouple: true,
      side: wedding.sideOf(user.uid),
      permissions: WeddingPermissions.all.toSet(),
    );
  }
  final email = user.email?.toLowerCase() ?? '';
  Set<String> permsFor(String email) => (wedding
              .memberPermissions[weddingFieldKey(email)] ??
          WeddingPermissions.defaults)
      .toSet();
  for (final m in wedding.members) {
    if (m.email == email) {
      return WeddingIdentity(
        key: email,
        name: m.name,
        isCouple: false,
        side: m.side,
        permissions: permsFor(email),
      );
    }
  }
  if (email.isNotEmpty && wedding.memberEmails.contains(email)) {
    return WeddingIdentity(
      key: email,
      name: user.displayName ?? 'Family Member',
      isCouple: false,
      side: 'bride',
      permissions: permsFor(email),
    );
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

  /// Task Name is the ONLY mandatory field — every optional field may stay
  /// empty without blocking creation. No Assign To → General Task.
  Future<void> addChecklistItem(
    String weddingId, {
    required String title,
    String description = '',
    String notes = '',
    String category = '',
    String priority = '',
    DateTime? dueDate,
    List<String> attachments = const [],
    String scope = 'shared',
    required WeddingIdentity me,
    String assignedToKey = '',
    String assignedToName = '',
  }) async {
    await _guarded(() async {
      await _service.addChecklistItem(
        weddingId,
        WeddingChecklistItem(
          id: '',
          title: title,
          description: description,
          notes: notes,
          category: category,
          priority: priority,
          dueDate: dueDate,
          attachments: attachments,
          scope: scope,
          createdByKey: me.key,
          createdByName: me.name,
          assignedToKey: assignedToKey,
          assignedToName: assignedToName,
          assignmentStatus: assignedToKey.isEmpty ? 'none' : 'pending',
          createdAt: DateTime.now(),
        ),
      );
      await _service.logActivity(weddingId,
          type: 'task',
          text: assignedToName.isEmpty
              ? '${me.name} created task "$title"'
              : '${me.name} created task "$title" and assigned it to '
                  '$assignedToName',
          actorName: me.name,
          scope: scope);
    });
  }

  Future<void> updateChecklistItem(
      String weddingId, String itemId, Map<String, dynamic> data) async {
    await _guarded(() => _service.updateChecklistItem(weddingId, itemId, data));
  }

  Future<void> deleteChecklistItem(String weddingId, String itemId) async {
    await _guarded(() => _service.deleteChecklistItem(weddingId, itemId));
  }

  Future<void> setChecklistStatus(String weddingId, WeddingChecklistItem item,
      bool completed, WeddingIdentity me) async {
    await _guarded(() async {
      await _service.setChecklistStatus(weddingId, item.id, completed,
          completedByName: me.name);
      await _service.logActivity(weddingId,
          type: 'task',
          text: completed
              ? '${me.name} completed task "${item.title}"'
              : '${me.name} reopened task "${item.title}"',
          actorName: me.name,
          scope: item.scope);
    });
  }

  /// Moves a side-private task into the Shared workspace.
  Future<void> moveTaskToShared(
      String weddingId, WeddingChecklistItem item, WeddingIdentity me) async {
    await _guarded(() async {
      await _service.updateChecklistItem(weddingId, item.id, {'scope': 'shared'});
      await _service.logActivity(weddingId,
          type: 'task',
          text: '${me.name} moved task "${item.title}" to Shared',
          actorName: me.name);
    });
  }

  /// Uploads a task attachment and returns its URL (null on failure).
  Future<String?> uploadTaskAttachment(String weddingId, File file,
      {required bool isImage}) {
    return _guarded(() => ref.read(storageServiceProvider)
        .uploadWeddingDocument(weddingId: weddingId, file: file, isImage: isImage));
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

  /// New contacts are PRIVATE to their side ([scope] defaults to [side]);
  /// "Move to Shared" later flips the scope to 'shared'.
  Future<void> saveContact(
    String weddingId, {
    String? contactId,
    required String side,
    String? scope,
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
          'scope': scope ?? side,
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
          scope: scope ?? side,
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

  // ── Gallery v2 ────────────────────────────────────────────────────────────

  Future<void> uploadPhoto(
    String weddingId, {
    required File file,
    required String album,
    String scope = 'shared',
    String caption = '',
    String vendorId = '',
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
          vendorId: vendorId,
          uploadedByKey: me.key,
          uploadedByName: me.name,
          uploadedAt: DateTime.now(),
        ),
      );
      await _service.logActivity(weddingId,
          type: 'gallery',
          text: '${me.name} uploaded a photo to "$album"',
          actorName: me.name,
          scope: scope);
    });
  }

  Future<void> deletePhoto(String weddingId, String photoId) async {
    await _guarded(() => _service.deletePhoto(weddingId, photoId));
  }

  Future<void> renamePhoto(
      String weddingId, String photoId, String caption) async {
    await _guarded(
        () => _service.updatePhoto(weddingId, photoId, {'caption': caption}));
  }

  /// Replaces the photo file, keeping votes / comments / selection intact.
  Future<void> replacePhoto(
      String weddingId, String photoId, File file) async {
    await _guarded(() async {
      final url = await ref.read(storageServiceProvider).uploadWeddingDocument(
          weddingId: weddingId, file: file, isImage: true);
      await _service.updatePhoto(weddingId, photoId, {'url': url});
    });
  }

  Future<void> addGalleryCategory(
      String weddingId, String name, WeddingIdentity me) async {
    await _guarded(() async {
      await _service.addGalleryCategory(
        weddingId,
        WeddingGalleryCategory(
            id: '', name: name, createdByName: me.name, createdAt: DateTime.now()),
      );
      await _service.logActivity(weddingId,
          type: 'gallery',
          text: '${me.name} created gallery category "$name"',
          actorName: me.name);
    });
  }

  Future<void> votePhoto(String weddingId, WeddingPhoto photo,
      {required WeddingIdentity me, String? vote}) async {
    await _guarded(() async {
      await _service.votePhoto(weddingId, photo.id,
          participantKey: me.key, vote: vote);
      if (vote != null) {
        await _service.logActivity(weddingId,
            type: 'approval',
            text:
                '${me.name} ${vote == 'approve' ? 'approved' : 'rejected'} a '
                'photo in "${photo.album}"',
            actorName: me.name,
            scope: photo.scope);
      }
    });
  }

  Future<void> commentPhoto(String weddingId, String photoId,
      {required WeddingIdentity me, required String text}) async {
    await _guarded(() =>
        _service.commentPhoto(weddingId, photoId, byName: me.name, text: text));
  }

  /// Marks a photo as the ⭐ Selected item of its category — and records the
  /// change in the Decision History when it replaces a previous selection.
  Future<void> selectPhoto(
      String weddingId, WeddingPhoto photo, WeddingIdentity me,
      {String reason = ''}) async {
    await _guarded(() async {
      final previous = await _service.selectPhoto(
        weddingId,
        photoId: photo.id,
        album: photo.album,
        scope: photo.scope,
        selectedByName: me.name,
      );
      final label = photo.caption.isNotEmpty ? photo.caption : 'a photo';
      await _service.addDecision(
        weddingId,
        WeddingDecision(
          id: '',
          field: 'Selected ${photo.album}',
          oldValue: previous == null
              ? '—'
              : (previous.caption.isNotEmpty ? previous.caption : 'Previous photo'),
          newValue: photo.caption.isNotEmpty ? photo.caption : 'New photo',
          changedBy: me.name,
          reason: reason,
          changedAt: DateTime.now(),
        ),
      );
      await _service.logActivity(weddingId,
          type: 'selection',
          text: '${me.name} selected $label as ⭐ ${photo.album}',
          actorName: me.name,
          scope: photo.scope);
    });
  }

  Future<void> movePhotosToShared(
      String weddingId, List<WeddingPhoto> photos, WeddingIdentity me) async {
    await _guarded(() async {
      await _service.movePhotosToShared(
          weddingId, photos.map((p) => p.id).toList());
      final albums = photos.map((p) => p.album).toSet().join(', ');
      await _service.logActivity(weddingId,
          type: 'shared',
          text: '${me.name} moved ${photos.length} '
              'photo${photos.length == 1 ? '' : 's'} ($albums) to Shared',
          actorName: me.name);
    });
  }

  /// Best-effort seen-marker → clears the category's "new uploads" badge.
  Future<void> markCategorySeen(
      String weddingId, WeddingIdentity me, String category) async {
    try {
      await _service.markCategorySeen(weddingId, me.key, category);
    } catch (e) {
      debugPrint('[WeddingController] markCategorySeen failed: $e');
    }
  }

  // ── Vendors (couple-only management) ──────────────────────────────────────

  Future<void> saveVendor(
    String weddingId, {
    String? vendorId,
    required String category,
    required String name,
    String contactPerson = '',
    required String mobile,
    String altMobile = '',
    String whatsapp = '',
    String address = '',
    String notes = '',
    num? price,
    num advancePaid = 0,
    num balanceAmount = 0,
    String capacity = '',
    String distance = '',
    double rating = 0,
    List<String> photos = const [],
    required List<String> visibleTo,
    required WeddingIdentity me,
  }) async {
    await _guarded(() async {
      if (vendorId != null) {
        await _service.updateVendor(weddingId, vendorId, {
          'category': category,
          'name': name,
          'contactPerson': contactPerson,
          'mobile': mobile,
          'altMobile': altMobile,
          'whatsapp': whatsapp,
          'address': address,
          'notes': notes,
          'price': price,
          'advancePaid': advancePaid,
          'balanceAmount': balanceAmount,
          'capacity': capacity,
          'distance': distance,
          'rating': rating,
          'photos': photos,
          'visibleTo': visibleTo,
        });
        return;
      }
      await _service.addVendor(
        weddingId,
        WeddingVendor(
          id: '',
          category: category,
          name: name,
          contactPerson: contactPerson,
          mobile: mobile,
          altMobile: altMobile,
          whatsapp: whatsapp,
          address: address,
          notes: notes,
          price: price,
          advancePaid: advancePaid,
          balanceAmount: balanceAmount,
          capacity: capacity,
          distance: distance,
          rating: rating,
          photos: photos,
          visibleTo: visibleTo,
          createdByName: me.name,
          createdAt: DateTime.now(),
        ),
      );
      await _service.logActivity(weddingId,
          type: 'vendor',
          text: '${me.name} added vendor "$name" ($category)',
          actorName: me.name);
    });
  }

  Future<void> deleteVendor(String weddingId, String vendorId) async {
    await _guarded(() => _service.deleteVendor(weddingId, vendorId));
  }

  /// Uploads one image into a vendor's photo list, returns its URL.
  Future<String?> uploadVendorPhoto(String weddingId, File file) {
    return _guarded(() => ref.read(storageServiceProvider)
        .uploadWeddingDocument(weddingId: weddingId, file: file, isImage: true));
  }

  /// ⭐ Select Final Vendor of a category (+ Decision History + activity).
  Future<void> selectFinalVendor(
      String weddingId, WeddingVendor vendor, WeddingIdentity me,
      {String reason = ''}) async {
    await _guarded(() async {
      final previous = await _service.selectVendor(
        weddingId,
        vendorId: vendor.id,
        category: vendor.category,
        selectedByName: me.name,
      );
      await _service.addDecision(
        weddingId,
        WeddingDecision(
          id: '',
          field: vendor.category,
          oldValue: previous?.name ?? '—',
          newValue: vendor.name,
          changedBy: me.name,
          reason: reason,
          changedAt: DateTime.now(),
        ),
      );
      await _service.logActivity(weddingId,
          type: 'vendor',
          text: '${me.name} selected "${vendor.name}" as the final '
              '${vendor.category} vendor',
          actorName: me.name);
    });
  }

  // ── Expense Tracker ───────────────────────────────────────────────────────

  Future<void> setBudget(String weddingId, num budget) async {
    await _guarded(() => _service.setBudget(weddingId, budget));
  }

  Future<void> saveExpense(
    String weddingId, {
    String? expenseId,
    required String title,
    required String category,
    required num amount,
    String paidBy = '',
    String notes = '',
    required DateTime date,
    required WeddingIdentity me,
  }) async {
    await _guarded(() async {
      if (expenseId != null) {
        await _service.updateExpense(weddingId, expenseId, {
          'title': title,
          'category': category,
          'amount': amount,
          'paidBy': paidBy,
          'notes': notes,
          'date': Timestamp.fromDate(date),
        });
        return;
      }
      await _service.addExpense(
        weddingId,
        WeddingExpense(
          id: '',
          title: title,
          category: category,
          amount: amount,
          paidBy: paidBy,
          notes: notes,
          date: date,
          createdByName: me.name,
        ),
      );
      await _service.logActivity(weddingId,
          type: 'expense',
          text: '${me.name} added expense "$title" (₹$amount, $category)',
          actorName: me.name);
    });
  }

  Future<void> deleteExpense(String weddingId, String expenseId) async {
    await _guarded(() => _service.deleteExpense(weddingId, expenseId));
  }

  // ── Calendar events ───────────────────────────────────────────────────────

  Future<void> saveEvent(
    String weddingId, {
    String? eventId,
    required String title,
    required String type,
    required DateTime dateTime,
    String location = '',
    String notes = '',
    List<String> reminders = const [],
    required WeddingIdentity me,
  }) async {
    await _guarded(() async {
      if (eventId != null) {
        await _service.updateEvent(weddingId, eventId, {
          'title': title,
          'type': type,
          'dateTime': Timestamp.fromDate(dateTime),
          'location': location,
          'notes': notes,
          'reminders': reminders,
        });
        return;
      }
      await _service.addEvent(
        weddingId,
        WeddingEvent(
          id: '',
          title: title,
          type: type,
          dateTime: dateTime,
          location: location,
          notes: notes,
          reminders: reminders,
          createdByName: me.name,
        ),
      );
      await _service.logActivity(weddingId,
          type: 'calendar',
          text: '${me.name} added event "$title" '
              '(${dateTime.day}/${dateTime.month}/${dateTime.year})',
          actorName: me.name);
    });
  }

  Future<void> deleteEvent(String weddingId, String eventId) async {
    await _guarded(() => _service.deleteEvent(weddingId, eventId));
  }

  // ── Discussion Notes ──────────────────────────────────────────────────────

  Future<void> saveNote(
    String weddingId, {
    String? noteId,
    required String title,
    required String body,
    required String scope,
    required WeddingIdentity me,
  }) async {
    await _guarded(() async {
      if (noteId != null) {
        await _service.updateNote(weddingId, noteId, {
          'title': title,
          'body': body,
          'updatedAt': Timestamp.now(),
        });
        return;
      }
      final now = DateTime.now();
      await _service.addNote(
        weddingId,
        WeddingNote(
          id: '',
          title: title,
          body: body,
          scope: scope,
          createdByKey: me.key,
          createdByName: me.name,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _service.logActivity(weddingId,
          type: 'note',
          text: '${me.name} added discussion note "$title"',
          actorName: me.name,
          scope: scope);
    });
  }

  Future<void> deleteNote(String weddingId, String noteId) async {
    await _guarded(() => _service.deleteNote(weddingId, noteId));
  }

  Future<void> moveNoteToShared(
      String weddingId, WeddingNote note, WeddingIdentity me) async {
    await _guarded(() async {
      await _service.updateNote(weddingId, note.id, {'scope': 'shared'});
      await _service.logActivity(weddingId,
          type: 'shared',
          text: '${me.name} moved note "${note.title}" to Shared',
          actorName: me.name);
    });
  }

  // ── Contacts: move to shared ──────────────────────────────────────────────

  Future<void> moveContactToShared(
      String weddingId, WeddingContact contact, WeddingIdentity me) async {
    await _guarded(() async {
      await _service.moveContactToShared(weddingId, contact.id);
      await _service.logActivity(weddingId,
          type: 'shared',
          text: '${me.name} moved contact "${contact.name}" to Shared',
          actorName: me.name);
    });
  }

  // ── Wedding Day Schedule ──────────────────────────────────────────────────

  Future<void> saveScheduleItem(
    String weddingId, {
    String? itemId,
    required int minutes,
    required String event,
    String location = '',
    String person = '',
    String notes = '',
  }) async {
    await _guarded(() {
      final data = WeddingScheduleItem(
        id: '',
        minutes: minutes,
        event: event,
        location: location,
        person: person,
        notes: notes,
      );
      if (itemId != null) {
        return _service.updateScheduleItem(
            weddingId, itemId, data.toFirestore());
      }
      return _service.addScheduleItem(weddingId, data);
    });
  }

  Future<void> deleteScheduleItem(String weddingId, String itemId) async {
    await _guarded(() => _service.deleteScheduleItem(weddingId, itemId));
  }

  // ── Family permissions (couple-only) ──────────────────────────────────────

  Future<void> setMemberPermissions(
      String weddingId, String email, List<String> permissions) async {
    await _guarded(
        () => _service.setMemberPermissions(weddingId, email, permissions));
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

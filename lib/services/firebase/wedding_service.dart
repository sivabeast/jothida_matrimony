import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/constants/app_constants.dart';
import '../../models/wedding_model.dart';

/// Firestore access for the Marriage Fixed workflow and the Wedding Workspace
/// (`weddings/{pairId}` + its checklist / documents / contacts / guests
/// subcollections).
class WeddingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _weddings =>
      _db.collection('weddings');

  DocumentReference<Map<String, dynamic>> _doc(String weddingId) =>
      _weddings.doc(weddingId);

  // ── Resolution ────────────────────────────────────────────────────────────

  /// The signed-in matrimony user's wedding (they are one of the couple).
  Stream<WeddingModel?> watchWeddingForCouple(String uid) => _weddings
      .where('coupleIds', arrayContains: uid)
      .limit(1)
      .snapshots()
      .map((s) =>
          s.docs.isEmpty ? null : WeddingModel.fromFirestore(s.docs.first));

  /// One-shot couple lookup — used by app-entry routing to open the Wedding
  /// Workspace directly once Marriage Fixed is confirmed.
  Future<WeddingModel?> getWeddingForCouple(String uid) async {
    final s = await _weddings
        .where('coupleIds', arrayContains: uid)
        .limit(1)
        .get();
    return s.docs.isEmpty ? null : WeddingModel.fromFirestore(s.docs.first);
  }

  /// The wedding an invited FAMILY member belongs to (matched by gmail).
  Stream<WeddingModel?> watchWeddingByMemberEmail(String email) => _weddings
      .where('memberEmails', arrayContains: email.toLowerCase())
      .limit(1)
      .snapshots()
      .map((s) =>
          s.docs.isEmpty ? null : WeddingModel.fromFirestore(s.docs.first));

  /// One-shot invite lookup used by the Family login flow.
  Future<WeddingModel?> getWeddingByMemberEmail(String email) async {
    final s = await _weddings
        .where('memberEmails', arrayContains: email.toLowerCase())
        .limit(1)
        .get();
    return s.docs.isEmpty ? null : WeddingModel.fromFirestore(s.docs.first);
  }

  /// The wedding between the signed-in user and a specific match (live).
  Stream<WeddingModel?> watchWeddingByPair(String uidA, String uidB) =>
      _doc(weddingPairId(uidA, uidB))
          .snapshots()
          .map((d) => d.exists ? WeddingModel.fromFirestore(d) : null);

  // ── Marriage Fixed (propose + mutual confirm) ─────────────────────────────

  /// Records [myUid]'s Marriage Fixed confirmation with [otherUid].
  /// Creates the wedding document on the first tap (status `proposed`); when
  /// the second partner also confirms, the wedding becomes `fixed` and the
  /// Wedding Workspace unlocks. Idempotent per user.
  Future<WeddingModel> confirmMarriageFixed({
    required String myUid,
    required String otherUid,
    required String myName,
    required String otherName,
    required String mySide, // 'bride' | 'groom'
    required String otherSide,
  }) async {
    final id = weddingPairId(myUid, otherUid);
    final ref = _doc(id);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        tx.set(ref, {
          'coupleIds': [myUid, otherUid],
          'coupleNames': {myUid: myName, otherUid: otherName},
          'sides': {myUid: mySide, otherUid: otherSide},
          'initiatedBy': myUid,
          'confirmations': {myUid: true, otherUid: false},
          'status': 'proposed',
          'weddingDate': null,
          'memberEmails': <String>[],
          'members': <Map<String, dynamic>>[],
          'marriedProcessed': {myUid: false, otherUid: false},
          'createdAt': FieldValue.serverTimestamp(),
          'fixedAt': null,
        });
        return;
      }
      final data = snap.data()!;
      final confirmations =
          Map<String, bool>.from(data['confirmations'] ?? const {});
      confirmations[myUid] = true;
      final bothConfirmed = confirmations[otherUid] == true;
      tx.update(ref, {
        'confirmations': confirmations,
        if (bothConfirmed && data['status'] == 'proposed') ...{
          'status': 'fixed',
          'fixedAt': FieldValue.serverTimestamp(),
        },
      });
    });
    final doc = await ref.get();
    debugPrint('[WeddingService] confirmMarriageFixed($id) → '
        'status=${doc.data()?['status']}');
    return WeddingModel.fromFirestore(doc);
  }

  Future<void> setWeddingDate(String weddingId, DateTime date) =>
      _doc(weddingId).update({'weddingDate': Timestamp.fromDate(date)});

  // ── Postpone & Cancel ─────────────────────────────────────────────────────

  /// Postpones the wedding: status becomes 'postponed' and only the wedding
  /// date changes ([newDate] null = date not decided yet). Checklist,
  /// documents, vendors, chat, gallery, guests and contacts all stay active.
  Future<void> postponeWedding(String weddingId, DateTime? newDate) =>
      _doc(weddingId).update({
        'status': 'postponed',
        'weddingDate': newDate != null ? Timestamp.fromDate(newDate) : null,
      });

  /// Un-postpones: back to 'fixed' with the confirmed [newDate].
  Future<void> resumeWedding(String weddingId, DateTime newDate) =>
      _doc(weddingId).update({
        'status': 'fixed',
        'weddingDate': Timestamp.fromDate(newDate),
      });

  /// Cancels the marriage PERMANENTLY: deletes every workspace subcollection
  /// (checklist, documents, contacts, guests, gallery, vendors, chat) and
  /// then the wedding document itself. Irreversible.
  Future<void> cancelWedding(String weddingId) async {
    const sections = [
      'checklist', 'documents', 'contacts', 'guests',
      'gallery', 'vendors', 'chat',
    ];
    for (final section in sections) {
      await _deleteCollection(_doc(weddingId).collection(section));
    }
    await _doc(weddingId).delete();
    debugPrint('[WeddingService] cancelWedding($weddingId) — workspace and '
        'all data deleted.');
  }

  /// Deletes every document of [col] in pages of 200 (batch limit safe).
  Future<void> _deleteCollection(
      CollectionReference<Map<String, dynamic>> col) async {
    while (true) {
      final page = await col.limit(200).get();
      if (page.docs.isEmpty) return;
      final batch = _db.batch();
      for (final d in page.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (page.docs.length < 200) return;
    }
  }

  // ── Family invitations (stored on the wedding doc) ────────────────────────

  /// Invites a family member: adds them to `members` and their gmail to
  /// `memberEmails` (the rules' access key). Rejects duplicate emails.
  Future<void> inviteMember(String weddingId, WeddingMember member) async {
    final ref = _doc(weddingId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Wedding not found');
      final emails =
          List<String>.from(snap.data()!['memberEmails'] ?? const []);
      if (emails.contains(member.email)) {
        throw Exception('${member.email} has already been invited.');
      }
      tx.update(ref, {
        'memberEmails': FieldValue.arrayUnion([member.email]),
        'members': FieldValue.arrayUnion([member.toMap()]),
      });
    });
  }

  /// Removes an invited family member (and with it their workspace access).
  Future<void> removeMember(String weddingId, String email) async {
    final key = email.toLowerCase();
    final ref = _doc(weddingId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data()!;
      final members = (data['members'] as List<dynamic>? ?? const [])
          .map((m) => Map<String, dynamic>.from(m))
          .where((m) => (m['email'] ?? '').toString().toLowerCase() != key)
          .toList();
      final emails = List<String>.from(data['memberEmails'] ?? const [])
        ..remove(key);
      tx.update(ref, {'members': members, 'memberEmails': emails});
    });
  }

  /// Marks an invited member 'joined' on their first family login.
  /// Best-effort — membership itself is granted by `memberEmails`.
  Future<void> markMemberJoined(String weddingId, String email) async {
    final key = email.toLowerCase();
    final ref = _doc(weddingId);
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        final members = (snap.data()!['members'] as List<dynamic>? ?? const [])
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        var changed = false;
        for (final m in members) {
          if ((m['email'] ?? '').toString().toLowerCase() == key &&
              m['status'] != 'joined') {
            m['status'] = 'joined';
            changed = true;
          }
        }
        if (changed) tx.update(ref, {'members': members});
      });
    } catch (e) {
      debugPrint('[WeddingService] markMemberJoined failed (non-fatal): $e');
    }
  }

  /// Flags a signed-in account as a FAMILY user (invited by gmail; no
  /// matrimony profile, locked to the Wedding Workspace). Mirrors the
  /// employee-registry role promotion pattern.
  Future<void> promoteToFamilyRole(String uid) =>
      _db.collection(AppConstants.usersCollection).doc(uid).set({
        'role': 'family',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  // ── Automatic Married status (wedding date passed) ────────────────────────

  /// Stamps that [uid]'s profile has been auto-marked Married; when both
  /// couple members are processed the wedding becomes `completed`.
  Future<void> markMarriedProcessed(String weddingId, String uid) async {
    final ref = _doc(weddingId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data()!;
      final processed =
          Map<String, bool>.from(data['marriedProcessed'] ?? const {});
      processed[uid] = true;
      final coupleIds = List<String>.from(data['coupleIds'] ?? const []);
      final allDone = coupleIds.every((u) => processed[u] == true);
      tx.update(ref, {
        'marriedProcessed': processed,
        if (allDone) 'status': 'completed',
      });
    });
  }

  // ── Checklist ─────────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _checklist(String weddingId) =>
      _doc(weddingId).collection('checklist');

  Stream<List<WeddingChecklistItem>> watchChecklist(String weddingId) =>
      _checklist(weddingId).orderBy('createdAt', descending: false).snapshots().map(
          (s) => s.docs.map(WeddingChecklistItem.fromFirestore).toList());

  Future<void> addChecklistItem(
          String weddingId, WeddingChecklistItem item) =>
      _checklist(weddingId).add(item.toFirestore());

  Future<void> updateChecklistItem(
          String weddingId, String itemId, Map<String, dynamic> data) =>
      _checklist(weddingId).doc(itemId).update(data);

  Future<void> deleteChecklistItem(String weddingId, String itemId) =>
      _checklist(weddingId).doc(itemId).delete();

  Future<void> setChecklistStatus(
          String weddingId, String itemId, bool completed) =>
      _checklist(weddingId).doc(itemId).update({
        'status': completed ? 'completed' : 'pending',
        'completedAt': completed ? FieldValue.serverTimestamp() : null,
      });

  /// Assigns (or re-assigns) an item to a workspace participant. The assignee
  /// then accepts / rejects.
  Future<void> assignChecklistItem(
    String weddingId,
    String itemId, {
    required String assignedToKey,
    required String assignedToName,
  }) =>
      _checklist(weddingId).doc(itemId).update({
        'assignedToKey': assignedToKey,
        'assignedToName': assignedToName,
        'assignmentStatus': 'pending',
        'rejectionReason': '',
      });

  /// The assignee's response. On reject an optional [reason] is stored and
  /// the task goes back to unassigned so it can be given to someone else.
  Future<void> respondToAssignment(
    String weddingId,
    String itemId, {
    required bool accept,
    String reason = '',
  }) =>
      _checklist(weddingId).doc(itemId).update(accept
          ? {'assignmentStatus': 'accepted'}
          : {
              'assignmentStatus': 'rejected',
              'rejectionReason': reason,
            });

  // ── Documents ─────────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _documents(String weddingId) =>
      _doc(weddingId).collection('documents');

  Stream<List<WeddingDocument>> watchDocuments(String weddingId) =>
      _documents(weddingId)
          .orderBy('uploadedAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map(WeddingDocument.fromFirestore).toList());

  Future<void> addDocument(String weddingId, WeddingDocument doc) =>
      _documents(weddingId).add(doc.toFirestore());

  Future<void> deleteDocument(String weddingId, String docId) =>
      _documents(weddingId).doc(docId).delete();

  // ── Family contacts ───────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _contacts(String weddingId) =>
      _doc(weddingId).collection('contacts');

  Stream<List<WeddingContact>> watchContacts(String weddingId) =>
      _contacts(weddingId).orderBy('createdAt', descending: false).snapshots().map(
          (s) => s.docs.map(WeddingContact.fromFirestore).toList());

  Future<void> addContact(String weddingId, WeddingContact contact) =>
      _contacts(weddingId).add(contact.toFirestore());

  Future<void> updateContact(
          String weddingId, String contactId, Map<String, dynamic> data) =>
      _contacts(weddingId).doc(contactId).update(data);

  Future<void> deleteContact(String weddingId, String contactId) =>
      _contacts(weddingId).doc(contactId).delete();

  // ── Guest list ────────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _guests(String weddingId) =>
      _doc(weddingId).collection('guests');

  Stream<List<WeddingGuest>> watchGuests(String weddingId) =>
      _guests(weddingId).orderBy('createdAt', descending: false).snapshots().map(
          (s) => s.docs.map(WeddingGuest.fromFirestore).toList());

  Future<void> addGuest(String weddingId, WeddingGuest guest) =>
      _guests(weddingId).add(guest.toFirestore());

  Future<void> updateGuest(
          String weddingId, String guestId, Map<String, dynamic> data) =>
      _guests(weddingId).doc(guestId).update(data);

  Future<void> deleteGuest(String weddingId, String guestId) =>
      _guests(weddingId).doc(guestId).delete();

  // ── Shared photo gallery ──────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _gallery(String weddingId) =>
      _doc(weddingId).collection('gallery');

  Stream<List<WeddingPhoto>> watchGallery(String weddingId) =>
      _gallery(weddingId)
          .orderBy('uploadedAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map(WeddingPhoto.fromFirestore).toList());

  Future<void> addPhoto(String weddingId, WeddingPhoto photo) =>
      _gallery(weddingId).add(photo.toFirestore());

  Future<void> deletePhoto(String weddingId, String photoId) =>
      _gallery(weddingId).doc(photoId).delete();

  // ── Vendors (couple-managed, per-participant visibility) ──────────────────

  CollectionReference<Map<String, dynamic>> _vendors(String weddingId) =>
      _doc(weddingId).collection('vendors');

  Stream<List<WeddingVendor>> watchVendors(String weddingId) =>
      _vendors(weddingId).orderBy('createdAt', descending: false).snapshots().map(
          (s) => s.docs.map(WeddingVendor.fromFirestore).toList());

  Future<void> addVendor(String weddingId, WeddingVendor vendor) =>
      _vendors(weddingId).add(vendor.toFirestore());

  Future<void> updateVendor(
          String weddingId, String vendorId, Map<String, dynamic> data) =>
      _vendors(weddingId).doc(vendorId).update(data);

  Future<void> deleteVendor(String weddingId, String vendorId) =>
      _vendors(weddingId).doc(vendorId).delete();

  // ── Family Group Chat ─────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _chat(String weddingId) =>
      _doc(weddingId).collection('chat');

  /// Latest 200 messages, oldest → newest (rendered bottom-anchored).
  Stream<List<WeddingChatMessage>> watchChat(String weddingId) =>
      _chat(weddingId)
          .orderBy('sentAt', descending: true)
          .limit(200)
          .snapshots()
          .map((s) => s.docs.reversed
              .map(WeddingChatMessage.fromFirestore)
              .toList());

  Future<void> sendChatMessage(String weddingId, WeddingChatMessage msg) =>
      _chat(weddingId).add(msg.toFirestore());
}

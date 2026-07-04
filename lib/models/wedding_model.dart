import 'package:cloud_firestore/cloud_firestore.dart';

/// Deterministic id of the wedding between two users (sorted uids joined with
/// '_') — the same convention as chat threads / connections, so either side
/// resolves the same document.
String weddingPairId(String a, String b) => a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

/// An invited family member of the wedding (bride side / groom side).
/// Membership is keyed by the invited GMAIL (lowercased) — that is also what
/// the Firestore rules use to grant workspace access.
class WeddingMember {
  final String name;
  final String relationship; // Father / Mother / Brother / Sister / Uncle / …
  final String email; // lowercased gmail — the login + access key
  final String side; // 'bride' | 'groom'
  final String status; // 'invited' | 'joined'
  final String invitedBy; // uid of the couple member who invited

  const WeddingMember({
    required this.name,
    required this.relationship,
    required this.email,
    required this.side,
    this.status = 'invited',
    this.invitedBy = '',
  });

  factory WeddingMember.fromMap(Map<String, dynamic> m) => WeddingMember(
        name: m['name'] ?? '',
        relationship: m['relationship'] ?? '',
        email: (m['email'] ?? '').toString().toLowerCase(),
        side: m['side'] ?? 'bride',
        status: m['status'] ?? 'invited',
        invitedBy: m['invitedBy'] ?? '',
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'relationship': relationship,
        'email': email,
        'side': side,
        'status': status,
        'invitedBy': invitedBy,
      };

  String get sideLabel => side == 'groom' ? 'Groom Side' : 'Bride Side';
}

/// The wedding document (`weddings/{pairId}`) created by the Marriage Fixed
/// workflow and powering the whole Wedding Workspace.
///
/// Lifecycle: one partner proposes "Marriage Fixed" (`proposed`), the other
/// confirms (`fixed`, workspace unlocked). When the wedding date passes and
/// both profiles have been auto-marked Married it becomes `completed`.
class WeddingModel {
  final String id;
  final List<String> coupleIds; // exactly the two matched users' uids
  final Map<String, String> coupleNames; // uid → display name
  final Map<String, String> sides; // uid → 'bride' | 'groom'
  final String initiatedBy;
  final Map<String, bool> confirmations; // uid → confirmed Marriage Fixed
  final String status; // 'proposed' | 'fixed' | 'completed'
  final DateTime? weddingDate;
  final List<String> memberEmails; // invited family gmails (lowercased)
  final List<WeddingMember> members;
  final Map<String, bool> marriedProcessed; // uid → auto-Married sweep done
  final DateTime createdAt;
  final DateTime? fixedAt;

  const WeddingModel({
    required this.id,
    required this.coupleIds,
    required this.coupleNames,
    required this.sides,
    required this.initiatedBy,
    required this.confirmations,
    required this.status,
    this.weddingDate,
    this.memberEmails = const [],
    this.members = const [],
    this.marriedProcessed = const {},
    required this.createdAt,
    this.fixedAt,
  });

  factory WeddingModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WeddingModel(
      id: doc.id,
      coupleIds: List<String>.from(d['coupleIds'] ?? const []),
      coupleNames: Map<String, String>.from(d['coupleNames'] ?? const {}),
      sides: Map<String, String>.from(d['sides'] ?? const {}),
      initiatedBy: d['initiatedBy'] ?? '',
      confirmations: Map<String, bool>.from(d['confirmations'] ?? const {}),
      status: d['status'] ?? 'proposed',
      weddingDate: d['weddingDate'] != null
          ? (d['weddingDate'] as Timestamp).toDate()
          : null,
      memberEmails: List<String>.from(d['memberEmails'] ?? const []),
      members: (d['members'] as List<dynamic>? ?? const [])
          .map((m) => WeddingMember.fromMap(Map<String, dynamic>.from(m)))
          .toList(),
      marriedProcessed:
          Map<String, bool>.from(d['marriedProcessed'] ?? const {}),
      createdAt: d['createdAt'] != null
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      fixedAt:
          d['fixedAt'] != null ? (d['fixedAt'] as Timestamp).toDate() : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'coupleIds': coupleIds,
        'coupleNames': coupleNames,
        'sides': sides,
        'initiatedBy': initiatedBy,
        'confirmations': confirmations,
        'status': status,
        'weddingDate':
            weddingDate != null ? Timestamp.fromDate(weddingDate!) : null,
        'memberEmails': memberEmails,
        'members': members.map((m) => m.toMap()).toList(),
        'marriedProcessed': marriedProcessed,
        'createdAt': Timestamp.fromDate(createdAt),
        'fixedAt': fixedAt != null ? Timestamp.fromDate(fixedAt!) : null,
      };

  bool get isProposed => status == 'proposed';

  /// Workspace unlocked — both parties confirmed Marriage Fixed.
  bool get isFixed => status == 'fixed' || status == 'completed';
  bool get isCompleted => status == 'completed';

  bool confirmedBy(String uid) => confirmations[uid] == true;
  String otherUid(String myUid) =>
      coupleIds.firstWhere((u) => u != myUid, orElse: () => '');
  String nameOf(String uid) => coupleNames[uid] ?? 'Partner';
  String sideOf(String uid) => sides[uid] ?? 'bride';

  /// Days remaining until the wedding (negative = date passed). Whole-day
  /// difference so "tomorrow" is always 1 regardless of the current time.
  int? get daysRemaining {
    final wd = weddingDate;
    if (wd == null) return null;
    final now = DateTime.now();
    return DateTime(wd.year, wd.month, wd.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }

  bool get weddingDatePassed {
    final r = daysRemaining;
    return r != null && r < 0;
  }
}

// ── Workspace sub-collections ────────────────────────────────────────────────

/// A shared wedding checklist item (`weddings/{id}/checklist/{itemId}`).
/// Anyone in the workspace (bride, groom, both families) may create items;
/// an item can optionally be assigned to another member, who accepts or
/// rejects the assignment. Status is strictly Pending / Completed.
class WeddingChecklistItem {
  final String id;
  final String title;
  final String notes;
  final String status; // 'pending' | 'completed'
  final String createdByKey; // uid (couple) or email (family member)
  final String createdByName;
  final String assignedToKey; // '' = unassigned
  final String assignedToName;
  final String assignmentStatus; // 'none' | 'pending' | 'accepted' | 'rejected'
  final String rejectionReason;
  final DateTime createdAt;
  final DateTime? completedAt;

  const WeddingChecklistItem({
    required this.id,
    required this.title,
    this.notes = '',
    this.status = 'pending',
    required this.createdByKey,
    required this.createdByName,
    this.assignedToKey = '',
    this.assignedToName = '',
    this.assignmentStatus = 'none',
    this.rejectionReason = '',
    required this.createdAt,
    this.completedAt,
  });

  factory WeddingChecklistItem.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WeddingChecklistItem(
      id: doc.id,
      title: d['title'] ?? '',
      notes: d['notes'] ?? '',
      status: d['status'] ?? 'pending',
      createdByKey: d['createdByKey'] ?? '',
      createdByName: d['createdByName'] ?? '',
      assignedToKey: d['assignedToKey'] ?? '',
      assignedToName: d['assignedToName'] ?? '',
      assignmentStatus: d['assignmentStatus'] ?? 'none',
      rejectionReason: d['rejectionReason'] ?? '',
      createdAt: d['createdAt'] != null
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      completedAt: d['completedAt'] != null
          ? (d['completedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'title': title,
        'notes': notes,
        'status': status,
        'createdByKey': createdByKey,
        'createdByName': createdByName,
        'assignedToKey': assignedToKey,
        'assignedToName': assignedToName,
        'assignmentStatus': assignmentStatus,
        'rejectionReason': rejectionReason,
        'createdAt': Timestamp.fromDate(createdAt),
        'completedAt':
            completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      };

  bool get isCompleted => status == 'completed';
  bool get isAssigned => assignedToKey.isNotEmpty;
}

/// An uploaded wedding document (`weddings/{id}/documents/{docId}`).
class WeddingDocument {
  final String id;
  final String title;
  final String category; // Invitation Card / Hall Booking Receipt / …
  final String url;
  final bool isImage;
  final String uploadedByName;
  final DateTime uploadedAt;

  const WeddingDocument({
    required this.id,
    required this.title,
    required this.category,
    required this.url,
    required this.isImage,
    required this.uploadedByName,
    required this.uploadedAt,
  });

  factory WeddingDocument.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WeddingDocument(
      id: doc.id,
      title: d['title'] ?? '',
      category: d['category'] ?? 'Other Wedding Documents',
      url: d['url'] ?? '',
      isImage: d['isImage'] ?? true,
      uploadedByName: d['uploadedByName'] ?? '',
      uploadedAt: d['uploadedAt'] != null
          ? (d['uploadedAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'title': title,
        'category': category,
        'url': url,
        'isImage': isImage,
        'uploadedByName': uploadedByName,
        'uploadedAt': Timestamp.fromDate(uploadedAt),
      };
}

/// A family contact (`weddings/{id}/contacts/{contactId}`), kept separately
/// per side (bride / groom).
class WeddingContact {
  final String id;
  final String side; // 'bride' | 'groom'
  final String name;
  final String relationship;
  final String mobile;
  final String gmail;
  final String addedByName;
  final DateTime createdAt;

  const WeddingContact({
    required this.id,
    required this.side,
    required this.name,
    required this.relationship,
    required this.mobile,
    required this.gmail,
    required this.addedByName,
    required this.createdAt,
  });

  factory WeddingContact.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WeddingContact(
      id: doc.id,
      side: d['side'] ?? 'bride',
      name: d['name'] ?? '',
      relationship: d['relationship'] ?? '',
      mobile: d['mobile'] ?? '',
      gmail: d['gmail'] ?? '',
      addedByName: d['addedByName'] ?? '',
      createdAt: d['createdAt'] != null
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'side': side,
        'name': name,
        'relationship': relationship,
        'mobile': mobile,
        'gmail': gmail,
        'addedByName': addedByName,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}

/// A guest-list entry (`weddings/{id}/guests/{guestId}`), per side.
class WeddingGuest {
  final String id;
  final String side; // 'bride' | 'groom'
  final String name;
  final String phone;
  final String notes;
  final String addedByName;
  final DateTime createdAt;

  const WeddingGuest({
    required this.id,
    required this.side,
    required this.name,
    this.phone = '',
    this.notes = '',
    required this.addedByName,
    required this.createdAt,
  });

  factory WeddingGuest.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WeddingGuest(
      id: doc.id,
      side: d['side'] ?? 'bride',
      name: d['name'] ?? '',
      phone: d['phone'] ?? '',
      notes: d['notes'] ?? '',
      addedByName: d['addedByName'] ?? '',
      createdAt: d['createdAt'] != null
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'side': side,
        'name': name,
        'phone': phone,
        'notes': notes,
        'addedByName': addedByName,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}

/// Someone who can participate in the workspace — a couple member (keyed by
/// uid) or an invited family member (keyed by email). Used by the checklist
/// "Assigned To" picker and by created-by labels.
class WeddingParticipant {
  final String key; // uid for couple, email for family
  final String name;
  final String roleLabel; // 'Bride' / 'Groom' / 'Bride Side – Father' / …

  const WeddingParticipant({
    required this.key,
    required this.name,
    required this.roleLabel,
  });
}

/// Every participant of [w]: bride + groom first, then invited members.
List<WeddingParticipant> weddingParticipants(WeddingModel w) {
  final list = <WeddingParticipant>[];
  for (final uid in w.coupleIds) {
    list.add(WeddingParticipant(
      key: uid,
      name: w.nameOf(uid),
      roleLabel: w.sideOf(uid) == 'groom' ? 'Groom' : 'Bride',
    ));
  }
  for (final m in w.members) {
    list.add(WeddingParticipant(
      key: m.email,
      name: m.name,
      roleLabel: '${m.sideLabel} – ${m.relationship}',
    ));
  }
  return list;
}

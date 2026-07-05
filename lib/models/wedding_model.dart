import 'package:cloud_firestore/cloud_firestore.dart';

/// Deterministic id of the wedding between two users (sorted uids joined with
/// '_') — the same convention as chat threads / connections, so either side
/// resolves the same document.
String weddingPairId(String a, String b) => a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

/// Firestore map-field keys must not contain '.', so participant keys (family
/// gmails) and free-text category names are sanitised before being used as
/// map keys (votes, permissions, seen-tracking).
String weddingFieldKey(String raw) => raw.replaceAll('.', ',');

/// Granular family-member permissions, assigned by the couple (Super Admins).
/// The couple always implicitly holds every permission.
class WeddingPermissions {
  static const createTask = 'create_task';
  static const assignTask = 'assign_task';
  static const reassignTask = 'reassign_task';
  static const editTask = 'edit_task';
  static const deleteTask = 'delete_task';
  static const completeTask = 'complete_task';
  static const reopenTask = 'reopen_task';
  static const createGalleryCategory = 'create_gallery_category';
  static const uploadPhotos = 'upload_photos';
  static const deleteOwnPhotos = 'delete_own_photos';
  static const inviteFamilyMembers = 'invite_family_members';
  static const manageFamilyMembers = 'manage_family_members';

  static const all = [
    createTask,
    assignTask,
    reassignTask,
    editTask,
    deleteTask,
    completeTask,
    reopenTask,
    createGalleryCategory,
    uploadPhotos,
    deleteOwnPhotos,
    inviteFamilyMembers,
    manageFamilyMembers,
  ];

  /// What a freshly invited family member can do before the couple has
  /// explicitly configured them.
  static const defaults = [
    createTask,
    completeTask,
    uploadPhotos,
    deleteOwnPhotos,
  ];

  static String label(String p) => switch (p) {
        createTask => 'Create Task',
        assignTask => 'Assign Task',
        reassignTask => 'Reassign Task',
        editTask => 'Edit Task',
        deleteTask => 'Delete Task',
        completeTask => 'Complete Task',
        reopenTask => 'Reopen Task',
        createGalleryCategory => 'Create Gallery Category',
        uploadPhotos => 'Upload Photos',
        deleteOwnPhotos => 'Delete Own Photos',
        inviteFamilyMembers => 'Invite Family Members',
        manageFamilyMembers => 'Manage Family Members',
        _ => p,
      };
}

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
/// confirms (`fixed`, workspace unlocked). When the wedding is delayed the
/// couple may mark it `postponed` (everything stays active — only the date
/// changes). When the wedding date passes and both profiles have been
/// auto-marked Married it becomes `completed`. Cancelling a marriage DELETES
/// the wedding document and all workspace data — there is no cancelled state.
class WeddingModel {
  final String id;
  final List<String> coupleIds; // exactly the two matched users' uids
  final Map<String, String> coupleNames; // uid → display name
  final Map<String, String> sides; // uid → 'bride' | 'groom'
  final String initiatedBy;
  final Map<String, bool> confirmations; // uid → confirmed Marriage Fixed
  final String status; // 'proposed' | 'fixed' | 'postponed' | 'completed'
  final DateTime? weddingDate;
  final List<String> memberEmails; // invited family gmails (lowercased)
  final List<WeddingMember> members;
  final Map<String, bool> marriedProcessed; // uid → auto-Married sweep done
  final num totalBudget; // Expense Tracker budget (couple-managed)
  // sanitised email key → granted permission ids (family members only).
  final Map<String, List<String>> memberPermissions;
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
    this.totalBudget = 0,
    this.memberPermissions = const {},
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
      totalBudget: (d['totalBudget'] ?? 0) as num,
      memberPermissions: (d['memberPermissions'] as Map<String, dynamic>? ??
              const {})
          .map((k, v) => MapEntry(k, List<String>.from(v ?? const []))),
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
        'totalBudget': totalBudget,
        'memberPermissions': memberPermissions,
        'createdAt': Timestamp.fromDate(createdAt),
        'fixedAt': fixedAt != null ? Timestamp.fromDate(fixedAt!) : null,
      };

  bool get isProposed => status == 'proposed';

  /// Workspace unlocked — both parties confirmed Marriage Fixed. A postponed
  /// wedding stays fully unlocked: only the date changed.
  bool get isFixed =>
      status == 'fixed' || status == 'postponed' || status == 'completed';
  bool get isPostponed => status == 'postponed';
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
  static const priorities = ['Low', 'Medium', 'High', 'Urgent'];

  final String id;
  final String title; // the ONLY mandatory field
  final String description;
  final String notes;
  final String category; // free text, optional
  final String templateKey; // '' or the planning-template item key that made it
  final String priority; // '' | Low | Medium | High | Urgent
  final DateTime? dueDate;
  final List<String> attachments; // uploaded file URLs (optional)
  final String scope; // 'shared' | 'bride' | 'groom'
  final String status; // 'pending' | 'completed'
  final String createdByKey; // uid (couple) or email (family member) = OWNER
  final String createdByName;
  final String assignedToKey; // '' = unassigned → General Task
  final String assignedToName;
  final String assignmentStatus; // 'none' | 'pending' | 'accepted' | 'rejected'
  final String rejectionReason;
  final String completedByName;
  final DateTime createdAt;
  final DateTime? completedAt;

  const WeddingChecklistItem({
    required this.id,
    required this.title,
    this.description = '',
    this.notes = '',
    this.category = '',
    this.templateKey = '',
    this.priority = '',
    this.dueDate,
    this.attachments = const [],
    this.scope = 'shared',
    this.status = 'pending',
    required this.createdByKey,
    required this.createdByName,
    this.assignedToKey = '',
    this.assignedToName = '',
    this.assignmentStatus = 'none',
    this.rejectionReason = '',
    this.completedByName = '',
    required this.createdAt,
    this.completedAt,
  });

  factory WeddingChecklistItem.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WeddingChecklistItem(
      id: doc.id,
      title: d['title'] ?? '',
      description: d['description'] ?? '',
      notes: d['notes'] ?? '',
      category: d['category'] ?? '',
      templateKey: d['templateKey'] ?? '',
      priority: d['priority'] ?? '',
      dueDate: d['dueDate'] != null
          ? (d['dueDate'] as Timestamp).toDate()
          : null,
      attachments: List<String>.from(d['attachments'] ?? const []),
      scope: d['scope'] ?? 'shared',
      status: d['status'] ?? 'pending',
      createdByKey: d['createdByKey'] ?? '',
      createdByName: d['createdByName'] ?? '',
      assignedToKey: d['assignedToKey'] ?? '',
      assignedToName: d['assignedToName'] ?? '',
      assignmentStatus: d['assignmentStatus'] ?? 'none',
      rejectionReason: d['rejectionReason'] ?? '',
      completedByName: d['completedByName'] ?? '',
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
        'description': description,
        'notes': notes,
        'category': category,
        'templateKey': templateKey,
        'priority': priority,
        'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
        'attachments': attachments,
        'scope': scope,
        'status': status,
        'createdByKey': createdByKey,
        'createdByName': createdByName,
        'assignedToKey': assignedToKey,
        'assignedToName': assignedToName,
        'assignmentStatus': assignmentStatus,
        'rejectionReason': rejectionReason,
        'completedByName': completedByName,
        'createdAt': Timestamp.fromDate(createdAt),
        'completedAt':
            completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      };

  bool get isCompleted => status == 'completed';
  bool get isAssigned => assignedToKey.isNotEmpty;

  /// Unassigned = General Task: anyone with the Complete Task permission may
  /// complete it. Assigned = only the assignee (or a Super Admin).
  bool get isGeneral => assignedToKey.isEmpty;
}

/// An uploaded wedding document (`weddings/{id}/documents/{docId}`).
class WeddingDocument {
  final String id;
  final String title;
  final String category; // Invitation / Hall Booking / Catering / …
  final String scope; // 'shared' | 'bride' | 'groom'
  final String url;
  final bool isImage;
  final String uploadedByName;
  final DateTime uploadedAt;

  const WeddingDocument({
    required this.id,
    required this.title,
    required this.category,
    this.scope = 'shared',
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
      scope: d['scope'] ?? 'shared',
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
        'scope': scope,
        'url': url,
        'isImage': isImage,
        'uploadedByName': uploadedByName,
        'uploadedAt': Timestamp.fromDate(uploadedAt),
      };
}

/// A photo in the Wedding Gallery (`weddings/{id}/gallery/{photoId}`).
///
/// Photos live in an unlimited, user-extensible set of CATEGORIES (stored in
/// the `album` field for backwards compatibility) and are side-scoped:
/// 'bride' / 'groom' (private to that side) or 'shared' (both sides).
/// Each photo carries ownership (uploader may delete/rename/replace; the
/// couple may delete anything), an approval system (votes + comments) and
/// per-category "⭐ Selected" support.
class WeddingPhoto {
  /// Starter categories — users can add unlimited custom ones.
  static const defaultCategories = [
    'Hall',
    'Jewellery',
    'Sarees',
    'Dress',
    'Decoration',
    'Invitation',
    'Photography',
    'Catering',
    'Car',
    'Return Gifts',
    'Makeup',
    'Others',
  ];

  final String id;
  final String album; // = category name
  final String scope; // 'shared' | 'bride' | 'groom'
  final String url;
  final String caption;
  final String vendorId; // optional link to a vendor
  final String uploadedByKey; // uid / email — the OWNER
  final String uploadedByName;
  final Map<String, String> votes; // sanitised key → 'approve' | 'reject'
  final List<Map<String, dynamic>> comments; // {byName, text, at}
  final bool isSelected; // ⭐ Selected item of its category+scope
  final String selectedBy;
  final DateTime? selectedAt;
  final DateTime uploadedAt;

  const WeddingPhoto({
    required this.id,
    required this.album,
    this.scope = 'shared',
    required this.url,
    this.caption = '',
    this.vendorId = '',
    this.uploadedByKey = '',
    required this.uploadedByName,
    this.votes = const {},
    this.comments = const [],
    this.isSelected = false,
    this.selectedBy = '',
    this.selectedAt,
    required this.uploadedAt,
  });

  factory WeddingPhoto.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WeddingPhoto(
      id: doc.id,
      album: d['album'] ?? 'Others',
      scope: d['scope'] ?? 'shared',
      url: d['url'] ?? '',
      caption: d['caption'] ?? '',
      vendorId: d['vendorId'] ?? '',
      uploadedByKey: d['uploadedByKey'] ?? '',
      uploadedByName: d['uploadedByName'] ?? '',
      votes: Map<String, String>.from(d['votes'] ?? const {}),
      comments: (d['comments'] as List<dynamic>? ?? const [])
          .map((c) => Map<String, dynamic>.from(c))
          .toList(),
      isSelected: d['isSelected'] ?? false,
      selectedBy: d['selectedBy'] ?? '',
      selectedAt: d['selectedAt'] != null
          ? (d['selectedAt'] as Timestamp).toDate()
          : null,
      uploadedAt: d['uploadedAt'] != null
          ? (d['uploadedAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'album': album,
        'scope': scope,
        'url': url,
        'caption': caption,
        'vendorId': vendorId,
        'uploadedByKey': uploadedByKey,
        'uploadedByName': uploadedByName,
        'votes': votes,
        'comments': comments,
        'isSelected': isSelected,
        'selectedBy': selectedBy,
        'selectedAt':
            selectedAt != null ? Timestamp.fromDate(selectedAt!) : null,
        'uploadedAt': Timestamp.fromDate(uploadedAt),
      };

  int get approveCount => votes.values.where((v) => v == 'approve').length;
  int get rejectCount => votes.values.where((v) => v == 'reject').length;
  String? voteOf(String key) => votes[weddingFieldKey(key)];

  /// 'Approved' / 'Rejected' / 'Tie' by most votes; null when no votes yet.
  String? get voteResult {
    if (votes.isEmpty) return null;
    if (approveCount == rejectCount) return 'Tie';
    return approveCount > rejectCount ? 'Approved' : 'Rejected';
  }
}

/// A user-created gallery category (`weddings/{id}/galleryCategories`).
/// The gallery shows the union of [WeddingPhoto.defaultCategories] and these.
class WeddingGalleryCategory {
  final String id;
  final String name;
  final String createdByName;
  final DateTime createdAt;

  const WeddingGalleryCategory({
    required this.id,
    required this.name,
    required this.createdByName,
    required this.createdAt,
  });

  factory WeddingGalleryCategory.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WeddingGalleryCategory(
      id: doc.id,
      name: d['name'] ?? '',
      createdByName: d['createdByName'] ?? '',
      createdAt: d['createdAt'] != null
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'createdByName': createdByName,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}

/// A wedding vendor (`weddings/{id}/vendors/{vendorId}`).
///
/// ONLY the couple (bride / groom) may create, edit or delete vendors.
/// Each vendor carries an explicit visibility list of participant keys
/// (couple uids + family gmails) — only those participants (plus the couple,
/// who always see everything they manage) can see the vendor.
class WeddingVendor {
  static const categories = [
    'Wedding Hall',
    'Photographer',
    'Videographer',
    'Makeup Artist',
    'Decorator',
    'Catering',
    'Flower Decoration',
    'Travel',
    'Invitation Printing',
    'Others',
  ];

  final String id;
  final String category;
  final String name; // mandatory
  final String contactPerson;
  final String mobile; // mandatory (phone number)
  final String altMobile;
  final String whatsapp;
  final String address;
  final String notes;
  final num? price; // total quoted price (comparison)
  final num advancePaid;
  final num balanceAmount;
  final String capacity; // free text, e.g. '500 seats'
  final String distance; // free text, e.g. '4 km'
  final double rating; // 0–5
  final List<String> photos; // vendor gallery (image URLs)
  final bool isSelected; // ⭐ final vendor of its category
  final String selectedBy;
  final DateTime? selectedAt;
  final List<String> visibleTo; // participant keys (uids + emails)
  final String createdByName;
  final DateTime createdAt;

  const WeddingVendor({
    required this.id,
    required this.category,
    required this.name,
    this.contactPerson = '',
    this.mobile = '',
    this.altMobile = '',
    this.whatsapp = '',
    this.address = '',
    this.notes = '',
    this.price,
    this.advancePaid = 0,
    this.balanceAmount = 0,
    this.capacity = '',
    this.distance = '',
    this.rating = 0,
    this.photos = const [],
    this.isSelected = false,
    this.selectedBy = '',
    this.selectedAt,
    this.visibleTo = const [],
    required this.createdByName,
    required this.createdAt,
  });

  factory WeddingVendor.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WeddingVendor(
      id: doc.id,
      category: d['category'] ?? 'Others',
      name: d['name'] ?? '',
      contactPerson: d['contactPerson'] ?? '',
      mobile: d['mobile'] ?? '',
      altMobile: d['altMobile'] ?? '',
      whatsapp: d['whatsapp'] ?? '',
      address: d['address'] ?? '',
      notes: d['notes'] ?? '',
      price: d['price'] as num?,
      advancePaid: (d['advancePaid'] ?? 0) as num,
      balanceAmount: (d['balanceAmount'] ?? 0) as num,
      capacity: d['capacity'] ?? '',
      distance: d['distance'] ?? '',
      rating: ((d['rating'] ?? 0) as num).toDouble(),
      photos: List<String>.from(d['photos'] ?? const []),
      isSelected: d['isSelected'] ?? false,
      selectedBy: d['selectedBy'] ?? '',
      selectedAt: d['selectedAt'] != null
          ? (d['selectedAt'] as Timestamp).toDate()
          : null,
      visibleTo: List<String>.from(d['visibleTo'] ?? const []),
      createdByName: d['createdByName'] ?? '',
      createdAt: d['createdAt'] != null
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
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
        'isSelected': isSelected,
        'selectedBy': selectedBy,
        'selectedAt':
            selectedAt != null ? Timestamp.fromDate(selectedAt!) : null,
        'visibleTo': visibleTo,
        'createdByName': createdByName,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  bool visibleToKey(String key) => visibleTo.contains(key);
}

/// A Family Group Chat message (`weddings/{id}/chat/{messageId}`) — the
/// whole workspace (couple + both families) shares one group thread.
/// Supports text (incl. emoji), images and files.
class WeddingChatMessage {
  final String id;
  final String senderKey; // uid (couple) or email (family)
  final String senderName;
  final String type; // 'text' | 'image' | 'file'
  final String text;
  final String url; // attachment url for image / file
  final String fileName;
  final DateTime sentAt;

  const WeddingChatMessage({
    required this.id,
    required this.senderKey,
    required this.senderName,
    this.type = 'text',
    this.text = '',
    this.url = '',
    this.fileName = '',
    required this.sentAt,
  });

  factory WeddingChatMessage.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WeddingChatMessage(
      id: doc.id,
      senderKey: d['senderKey'] ?? '',
      senderName: d['senderName'] ?? '',
      type: d['type'] ?? 'text',
      text: d['text'] ?? '',
      url: d['url'] ?? '',
      fileName: d['fileName'] ?? '',
      sentAt: d['sentAt'] != null
          ? (d['sentAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'senderKey': senderKey,
        'senderName': senderName,
        'type': type,
        'text': text,
        'url': url,
        'fileName': fileName,
        'sentAt': Timestamp.fromDate(sentAt),
      };
}

/// An Expense Tracker entry (`weddings/{id}/expenses/{expenseId}`).
/// The overall budget lives on the wedding document ([WeddingModel.totalBudget]);
/// expenses are the payment history, summed into Spent / Remaining and a
/// category-wise breakdown.
class WeddingExpense {
  static const categories = [
    'Hall',
    'Jewellery',
    'Dress',
    'Decoration',
    'Invitation',
    'Photography',
    'Catering',
    'Makeup',
    'Travel',
    'Return Gifts',
    'Others',
  ];

  final String id;
  final String title;
  final String category;
  final num amount;
  final String paidBy;
  final String notes;
  final DateTime date;
  final String createdByName;

  const WeddingExpense({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    this.paidBy = '',
    this.notes = '',
    required this.date,
    required this.createdByName,
  });

  factory WeddingExpense.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WeddingExpense(
      id: doc.id,
      title: d['title'] ?? '',
      category: d['category'] ?? 'Others',
      amount: (d['amount'] ?? 0) as num,
      paidBy: d['paidBy'] ?? '',
      notes: d['notes'] ?? '',
      date: d['date'] != null
          ? (d['date'] as Timestamp).toDate()
          : DateTime.now(),
      createdByName: d['createdByName'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
        'title': title,
        'category': category,
        'amount': amount,
        'paidBy': paidBy,
        'notes': notes,
        'date': Timestamp.fromDate(date),
        'createdByName': createdByName,
      };
}

/// A Wedding Calendar event (`weddings/{id}/events/{eventId}`), with
/// reminder offsets surfaced as in-app reminders (dashboard / notifications).
class WeddingEvent {
  static const types = [
    'Wedding',
    'Engagement',
    'Reception',
    'Hall Visit',
    'Jewellery Purchase',
    'Dress Purchase',
    'Invitation Printing',
    'Other Event',
  ];

  /// Reminder option id → offset before the event.
  static const reminderOptions = {
    '1h': Duration(hours: 1),
    '1d': Duration(days: 1),
    '3d': Duration(days: 3),
    '1w': Duration(days: 7),
  };

  static String reminderLabel(String id) => switch (id) {
        '1h' => '1 Hour Before',
        '1d' => '1 Day Before',
        '3d' => '3 Days Before',
        '1w' => '1 Week Before',
        _ => id,
      };

  final String id;
  final String title;
  final String type;
  final DateTime dateTime;
  final String location;
  final String notes;
  final List<String> reminders; // reminder option ids
  final String createdByName;

  const WeddingEvent({
    required this.id,
    required this.title,
    required this.type,
    required this.dateTime,
    this.location = '',
    this.notes = '',
    this.reminders = const [],
    required this.createdByName,
  });

  factory WeddingEvent.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WeddingEvent(
      id: doc.id,
      title: d['title'] ?? '',
      type: d['type'] ?? 'Other Event',
      dateTime: d['dateTime'] != null
          ? (d['dateTime'] as Timestamp).toDate()
          : DateTime.now(),
      location: d['location'] ?? '',
      notes: d['notes'] ?? '',
      reminders: List<String>.from(d['reminders'] ?? const []),
      createdByName: d['createdByName'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
        'title': title,
        'type': type,
        'dateTime': Timestamp.fromDate(dateTime),
        'location': location,
        'notes': notes,
        'reminders': reminders,
        'createdByName': createdByName,
      };

  /// True when any configured reminder window covers [now] (event upcoming
  /// and inside the largest matching offset).
  bool reminderDue(DateTime now) {
    if (dateTime.isBefore(now)) return false;
    for (final r in reminders) {
      final offset = WeddingEvent.reminderOptions[r];
      if (offset != null && dateTime.difference(now) <= offset) return true;
    }
    return false;
  }
}

/// A Discussion Note (`weddings/{id}/notes/{noteId}`) — planning discussions,
/// side-private until moved to Shared.
class WeddingNote {
  final String id;
  final String title;
  final String body;
  final String scope; // 'bride' | 'groom' | 'shared'
  final String createdByKey;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WeddingNote({
    required this.id,
    required this.title,
    this.body = '',
    required this.scope,
    required this.createdByKey,
    required this.createdByName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WeddingNote.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WeddingNote(
      id: doc.id,
      title: d['title'] ?? '',
      body: d['body'] ?? '',
      scope: d['scope'] ?? 'shared',
      createdByKey: d['createdByKey'] ?? '',
      createdByName: d['createdByName'] ?? '',
      createdAt: d['createdAt'] != null
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: d['updatedAt'] != null
          ? (d['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'title': title,
        'body': body,
        'scope': scope,
        'createdByKey': createdByKey,
        'createdByName': createdByName,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };
}

/// A Decision History entry (`weddings/{id}/decisions/{decisionId}`) —
/// "Hall: ABC Mahal → XYZ Mahal, changed by …, because …". Written
/// automatically whenever a ⭐ selection or the wedding date changes.
class WeddingDecision {
  final String id;
  final String field; // e.g. 'Hall', 'Selected Jewellery', 'Wedding Date'
  final String oldValue;
  final String newValue;
  final String changedBy;
  final String reason;
  final DateTime changedAt;

  const WeddingDecision({
    required this.id,
    required this.field,
    required this.oldValue,
    required this.newValue,
    required this.changedBy,
    this.reason = '',
    required this.changedAt,
  });

  factory WeddingDecision.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WeddingDecision(
      id: doc.id,
      field: d['field'] ?? '',
      oldValue: d['oldValue'] ?? '',
      newValue: d['newValue'] ?? '',
      changedBy: d['changedBy'] ?? '',
      reason: d['reason'] ?? '',
      changedAt: d['changedAt'] != null
          ? (d['changedAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'field': field,
        'oldValue': oldValue,
        'newValue': newValue,
        'changedBy': changedBy,
        'reason': reason,
        'changedAt': Timestamp.fromDate(changedAt),
      };
}

/// An Activity Log entry (`weddings/{id}/activity/{activityId}`) — the
/// chronological history of everything that happened in the workspace, and
/// the source feed of the Notifications page.
class WeddingActivity {
  final String id;
  final String type; // 'gallery' | 'task' | 'vendor' | 'expense' | ...
  final String text; // human-readable: "Priya uploaded 3 Hall photos"
  final String actorName;
  final String scope; // visibility of the underlying content
  final DateTime at;

  const WeddingActivity({
    required this.id,
    required this.type,
    required this.text,
    required this.actorName,
    this.scope = 'shared',
    required this.at,
  });

  factory WeddingActivity.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WeddingActivity(
      id: doc.id,
      type: d['type'] ?? 'general',
      text: d['text'] ?? '',
      actorName: d['actorName'] ?? '',
      scope: d['scope'] ?? 'shared',
      at: d['at'] != null ? (d['at'] as Timestamp).toDate() : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'type': type,
        'text': text,
        'actorName': actorName,
        'scope': scope,
        'at': Timestamp.fromDate(at),
      };
}

/// A Wedding Day Schedule row (`weddings/{id}/schedule/{itemId}`) shown on
/// the Dashboard ("06:00 AM Makeup → 07:30 AM Muhurtham → …"). Managed by
/// the couple; ordered by [minutes] (time of day).
class WeddingScheduleItem {
  final String id;
  final int minutes; // minutes since midnight, for ordering
  final String event;
  final String location;
  final String person; // responsible person (optional)
  final String notes;

  const WeddingScheduleItem({
    required this.id,
    required this.minutes,
    required this.event,
    this.location = '',
    this.person = '',
    this.notes = '',
  });

  factory WeddingScheduleItem.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WeddingScheduleItem(
      id: doc.id,
      minutes: (d['minutes'] ?? 0) as int,
      event: d['event'] ?? '',
      location: d['location'] ?? '',
      person: d['person'] ?? '',
      notes: d['notes'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
        'minutes': minutes,
        'event': event,
        'location': location,
        'person': person,
        'notes': notes,
      };

  String get timeLabel {
    final h24 = minutes ~/ 60;
    final m = minutes % 60;
    final h12 = h24 > 12 ? h24 - 12 : (h24 == 0 ? 12 : h24);
    return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} '
        '${h24 >= 12 ? 'PM' : 'AM'}';
  }
}

/// A family contact (`weddings/{id}/contacts/{contactId}`).
///
/// Contacts are PRIVATE to their side ([scope] 'bride' / 'groom') until
/// explicitly moved to Shared ([scope] 'shared'), which makes them visible
/// to both sides. Legacy documents without a scope inherit their side.
class WeddingContact {
  final String id;
  final String side; // 'bride' | 'groom' (which family it belongs to)
  final String scope; // 'bride' | 'groom' | 'shared' (visibility)
  final String name;
  final String relationship;
  final String mobile;
  final String gmail;
  final String addedByName;
  final DateTime createdAt;

  const WeddingContact({
    required this.id,
    required this.side,
    String? scope,
    required this.name,
    required this.relationship,
    required this.mobile,
    required this.gmail,
    required this.addedByName,
    required this.createdAt,
  }) : scope = scope ?? side;

  factory WeddingContact.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final side = d['side'] ?? 'bride';
    return WeddingContact(
      id: doc.id,
      side: side,
      scope: d['scope'] ?? side,
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
        'scope': scope,
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

// ── Custom planning-item learning ─────────────────────────────────────────────

/// A family-contributed custom planning item, stored GLOBALLY (outside any one
/// wedding) in `wedding_plan_custom_items/{id}`. The system learns from these:
/// when the same item is used across enough weddings — or an admin approves it —
/// it is promoted (`status == 'approved'`) and merged into the master template
/// shown to all future weddings.
class WeddingPlanCustomItem {
  /// Auto-promotion threshold: used by this many distinct weddings → approved.
  static const promoteThreshold = 3;

  final String id; // normalised '<categoryKey>__<slug>'
  final String categoryKey;
  final String categoryName;
  final String title;
  final int usageCount; // distinct weddings that added it
  final List<String> weddingIds;
  final String status; // 'pending' | 'approved' | 'rejected'
  final String firstAddedByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WeddingPlanCustomItem({
    required this.id,
    required this.categoryKey,
    required this.categoryName,
    required this.title,
    this.usageCount = 0,
    this.weddingIds = const [],
    this.status = 'pending',
    this.firstAddedByName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory WeddingPlanCustomItem.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WeddingPlanCustomItem(
      id: doc.id,
      categoryKey: d['categoryKey'] ?? '',
      categoryName: d['categoryName'] ?? '',
      title: d['title'] ?? '',
      usageCount: (d['usageCount'] ?? 0) as int,
      weddingIds: List<String>.from(d['weddingIds'] ?? const []),
      status: d['status'] ?? 'pending',
      firstAddedByName: d['firstAddedByName'] ?? '',
      createdAt: d['createdAt'] != null
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: d['updatedAt'] != null
          ? (d['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  /// The stable template key this custom item maps to once selected as a task.
  String get templateKey => 'custom.$id';

  bool get isApproved => status == 'approved';
}

/// Normalises a free-text custom item name into a stable slug for the global
/// learning id — so the same item added by two families collides (and its
/// usage count rises) instead of creating duplicates.
String weddingPlanCustomId(String categoryKey, String title) {
  final slug = title
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'(^-+|-+$)'), '');
  return '${categoryKey}__$slug';
}

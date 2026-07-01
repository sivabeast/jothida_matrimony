import 'package:cloud_firestore/cloud_firestore.dart';

/// A member of the internal astrology team, provisioned by an admin.
///
/// Firestore: `astrology_team/{emailKey}` where `emailKey = email.trim().toLowerCase()`.
///
/// The admin registers only the astrologer's Gmail (+ an optional display
/// name). The account stays *inactive* until the astrologer first signs in with
/// that exact Gmail — which stamps [uid]. [active] is the admin's enable /
/// disable switch and gates BOTH login and auto-assignment eligibility, so
/// toggling it takes effect immediately for the next assignment.
class AstrologerTeamMember {
  /// Document id — the lowercased Gmail ([keyFor]).
  final String id;
  final String email;
  final String displayName;
  final String mobile;
  final String photoUrl;

  /// Admin enable/disable switch (default true). A disabled member can neither
  /// log in nor receive new auto-assigned requests.
  final bool active;

  /// Astrologer-controlled Available / Unavailable switch (default true, set
  /// from their Profile page). When false, the smart auto-assigner skips them
  /// for NEW requests — independent of the admin's [active] flag.
  final bool available;

  /// The astrologer's real Firebase uid. Empty until their first Google
  /// sign-in links the account ("inactive until sign-in").
  final String uid;

  // ── Astrologer-managed profile (spec §5) ────────────────────────────────
  final String about;
  final String experience;
  final String qualification;

  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  /// Round-robin tie-break cursor: when several assignable members share the
  /// lowest pending count, the one assigned least recently wins.
  final DateTime? lastAssignedAt;

  /// Denormalised count of OPEN (assigned, not-yet-completed) requests — the
  /// signal the auto-assigner balances on. Kept on the doc so assignment never
  /// has to read other users' requests.
  final int pendingCount;

  // ── Weekly fixed salary (spec §13, replaces per-report commission) ───────
  /// Admin-defined fixed weekly salary (₹).
  final int weeklySalary;

  /// 'paid' | 'pending'.
  final String salaryStatus;
  final DateTime? lastPaidDate;

  /// When this astrologer last submitted a completed report (admin perf view).
  final DateTime? lastSubmittedAt;

  const AstrologerTeamMember({
    required this.id,
    required this.email,
    this.displayName = '',
    this.mobile = '',
    this.photoUrl = '',
    this.active = true,
    this.available = true,
    this.about = '',
    this.experience = '',
    this.qualification = '',
    this.weeklySalary = 0,
    this.salaryStatus = 'pending',
    this.lastPaidDate,
    this.lastSubmittedAt,
    this.uid = '',
    this.createdAt,
    this.lastLoginAt,
    this.lastAssignedAt,
    this.pendingCount = 0,
  });

  /// True once the astrologer has signed in at least once.
  bool get isLinked => uid.trim().isNotEmpty;

  /// Eligible to receive a newly auto-assigned request: admin-enabled AND the
  /// astrologer has marked themselves Available. Sign-in is NOT required — a
  /// request can be assigned by the stable Gmail before their first login.
  bool get isAssignable => active && available;

  /// A human label for the account state shown on the admin list.
  String get statusLabel {
    if (!active) return 'Disabled';
    if (!available) return 'Unavailable';
    return isLinked ? 'Active' : 'Awaiting sign-in';
  }

  /// Deterministic doc id for an email.
  static String keyFor(String email) => email.trim().toLowerCase();

  static DateTime? _ts(dynamic v) => v is Timestamp ? v.toDate() : null;

  factory AstrologerTeamMember.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    return AstrologerTeamMember(
      id: doc.id,
      email: (d['email'] ?? doc.id).toString(),
      displayName: (d['displayName'] ?? '').toString(),
      mobile: (d['mobile'] ?? '').toString(),
      photoUrl: (d['photoUrl'] ?? '').toString(),
      active: d['active'] != false, // default true
      available: d['available'] != false, // default true
      about: (d['about'] ?? '').toString(),
      experience: (d['experience'] ?? '').toString(),
      qualification: (d['qualification'] ?? '').toString(),
      weeklySalary: (d['weeklySalary'] as num?)?.toInt() ?? 0,
      salaryStatus: (d['salaryStatus'] ?? 'pending').toString(),
      lastPaidDate: _ts(d['lastPaidDate']),
      lastSubmittedAt: _ts(d['lastSubmittedAt']),
      uid: (d['uid'] ?? '').toString(),
      createdAt: _ts(d['createdAt']),
      lastLoginAt: _ts(d['lastLoginAt']),
      lastAssignedAt: _ts(d['lastAssignedAt']),
      pendingCount: (d['pendingCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'email': email,
        'displayName': displayName,
        'mobile': mobile,
        'photoUrl': photoUrl,
        'active': active,
        'available': available,
        'about': about,
        'experience': experience,
        'qualification': qualification,
        'weeklySalary': weeklySalary,
        'salaryStatus': salaryStatus,
        if (lastPaidDate != null) 'lastPaidDate': Timestamp.fromDate(lastPaidDate!),
        if (lastSubmittedAt != null)
          'lastSubmittedAt': Timestamp.fromDate(lastSubmittedAt!),
        'uid': uid,
        'pendingCount': pendingCount,
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
        if (lastLoginAt != null) 'lastLoginAt': Timestamp.fromDate(lastLoginAt!),
        if (lastAssignedAt != null)
          'lastAssignedAt': Timestamp.fromDate(lastAssignedAt!),
      };

  AstrologerTeamMember copyWith({
    String? displayName,
    String? mobile,
    String? photoUrl,
    bool? active,
    bool? available,
    String? about,
    String? experience,
    String? qualification,
    int? weeklySalary,
    String? salaryStatus,
    DateTime? lastPaidDate,
    DateTime? lastSubmittedAt,
    String? uid,
    DateTime? lastLoginAt,
    DateTime? lastAssignedAt,
    int? pendingCount,
  }) =>
      AstrologerTeamMember(
        id: id,
        email: email,
        displayName: displayName ?? this.displayName,
        mobile: mobile ?? this.mobile,
        photoUrl: photoUrl ?? this.photoUrl,
        active: active ?? this.active,
        available: available ?? this.available,
        about: about ?? this.about,
        experience: experience ?? this.experience,
        qualification: qualification ?? this.qualification,
        weeklySalary: weeklySalary ?? this.weeklySalary,
        salaryStatus: salaryStatus ?? this.salaryStatus,
        lastPaidDate: lastPaidDate ?? this.lastPaidDate,
        lastSubmittedAt: lastSubmittedAt ?? this.lastSubmittedAt,
        uid: uid ?? this.uid,
        createdAt: createdAt,
        lastLoginAt: lastLoginAt ?? this.lastLoginAt,
        lastAssignedAt: lastAssignedAt ?? this.lastAssignedAt,
        pendingCount: pendingCount ?? this.pendingCount,
      );
}

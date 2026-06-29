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
  final String photoUrl;

  /// Admin enable/disable switch (default true). A disabled member can neither
  /// log in nor receive new auto-assigned requests.
  final bool active;

  /// The astrologer's real Firebase uid. Empty until their first Google
  /// sign-in links the account ("inactive until sign-in").
  final String uid;

  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  /// Round-robin tie-break cursor: when several assignable members share the
  /// lowest pending count, the one assigned least recently wins.
  final DateTime? lastAssignedAt;

  /// Denormalised count of OPEN (assigned, not-yet-completed) requests — the
  /// signal the auto-assigner balances on. Kept on the doc so assignment never
  /// has to read other users' requests.
  final int pendingCount;

  const AstrologerTeamMember({
    required this.id,
    required this.email,
    this.displayName = '',
    this.photoUrl = '',
    this.active = true,
    this.uid = '',
    this.createdAt,
    this.lastLoginAt,
    this.lastAssignedAt,
    this.pendingCount = 0,
  });

  /// True once the astrologer has signed in at least once.
  bool get isLinked => uid.trim().isNotEmpty;

  /// Eligible to receive a newly auto-assigned request.
  bool get isAssignable => active && isLinked;

  /// A human label for the account state shown on the admin list.
  String get statusLabel {
    if (!active) return 'Disabled';
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
      photoUrl: (d['photoUrl'] ?? '').toString(),
      active: d['active'] != false, // default true
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
        'photoUrl': photoUrl,
        'active': active,
        'uid': uid,
        'pendingCount': pendingCount,
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
        if (lastLoginAt != null) 'lastLoginAt': Timestamp.fromDate(lastLoginAt!),
        if (lastAssignedAt != null)
          'lastAssignedAt': Timestamp.fromDate(lastAssignedAt!),
      };

  AstrologerTeamMember copyWith({
    String? displayName,
    String? photoUrl,
    bool? active,
    String? uid,
    DateTime? lastLoginAt,
    DateTime? lastAssignedAt,
    int? pendingCount,
  }) =>
      AstrologerTeamMember(
        id: id,
        email: email,
        displayName: displayName ?? this.displayName,
        photoUrl: photoUrl ?? this.photoUrl,
        active: active ?? this.active,
        uid: uid ?? this.uid,
        createdAt: createdAt,
        lastLoginAt: lastLoginAt ?? this.lastLoginAt,
        lastAssignedAt: lastAssignedAt ?? this.lastAssignedAt,
        pendingCount: pendingCount ?? this.pendingCount,
      );
}

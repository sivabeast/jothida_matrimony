import 'package:cloud_firestore/cloud_firestore.dart';

/// A member's Aadhaar verification record — stored in the strictly-gated
/// `aadhaar/{userId}` collection (owner + admin only; NEVER on the public
/// profile document, which every signed-in user can read).
///
/// Lifecycle: the user submits number + front/back images (during profile
/// creation or later from Edit Profile) → the admin reviews and marks it
/// verified (which also stamps the profile's public "Verified" badge). Any
/// user edit resets [verified] to false — re-verification required.
class AadhaarDetails {
  final String userId;
  final String number; // 12 digits
  final String frontUrl;
  final String backUrl;
  final bool verified;
  final DateTime? updatedAt;
  final DateTime? verifiedAt;

  const AadhaarDetails({
    required this.userId,
    this.number = '',
    this.frontUrl = '',
    this.backUrl = '',
    this.verified = false,
    this.updatedAt,
    this.verifiedAt,
  });

  bool get hasNumber => number.trim().length == 12;
  bool get hasImages => frontUrl.isNotEmpty && backUrl.isNotEmpty;
  bool get isSubmitted => hasNumber || frontUrl.isNotEmpty || backUrl.isNotEmpty;

  /// Masked display form: "XXXX XXXX 1234".
  String get masked => number.trim().length == 12
      ? 'XXXX XXXX ${number.trim().substring(8)}'
      : number;

  /// True when [value] is a plausible Aadhaar number (12 digits, not starting
  /// with 0/1 per UIDAI rules).
  static bool isValidNumber(String value) =>
      RegExp(r'^[2-9]\d{11}$').hasMatch(value.trim().replaceAll(' ', ''));

  factory AadhaarDetails.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    return AadhaarDetails(
      userId: doc.id,
      number: (d['number'] ?? '').toString(),
      frontUrl: (d['frontUrl'] ?? '').toString(),
      backUrl: (d['backUrl'] ?? '').toString(),
      verified: d['verified'] == true,
      updatedAt: ts(d['updatedAt']),
      verifiedAt: ts(d['verifiedAt']),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'number': number.trim().replaceAll(' ', ''),
        'frontUrl': frontUrl,
        'backUrl': backUrl,
        'verified': verified,
        'updatedAt': FieldValue.serverTimestamp(),
        if (verified) 'verifiedAt': FieldValue.serverTimestamp(),
      };
}

import 'package:cloud_firestore/cloud_firestore.dart';

/// A certificate / qualification document an astrologer uploads for admin
/// verification. Stored inside the astrologer account document under a
/// `certificates` array so the Admin module (Astrologer Verification) can read,
/// download, approve and reject them.
///
/// Firestore map:
/// { id, name, url, fileType, uploadedAt, status }
///
/// [status] is one of: pending · approved · rejected (set by an admin).
class AstrologerCertificate {
  final String id;
  final String name;
  final String url; // public URL of the uploaded file (Cloudinary)
  final String fileType; // pdf | jpg | jpeg | png
  final DateTime uploadedAt;
  final String status; // pending | approved | rejected

  const AstrologerCertificate({
    required this.id,
    required this.name,
    required this.url,
    required this.fileType,
    required this.uploadedAt,
    this.status = 'pending',
  });

  bool get isPdf => fileType.toLowerCase() == 'pdf';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory AstrologerCertificate.fromMap(Map<String, dynamic> m) =>
      AstrologerCertificate(
        id: m['id'] ?? '',
        name: m['name'] ?? 'Certificate',
        url: m['url'] ?? '',
        fileType: (m['fileType'] ?? '').toString().toLowerCase(),
        uploadedAt: m['uploadedAt'] is Timestamp
            ? (m['uploadedAt'] as Timestamp).toDate()
            : DateTime.tryParse('${m['uploadedAt']}') ?? DateTime.now(),
        // Back-compat: older docs used a `verified` bool.
        status: m['status'] ??
            ((m['verified'] == true) ? 'approved' : 'pending'),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'url': url,
        'fileType': fileType,
        // Stored as ISO string so it round-trips inside an array (array
        // elements can't hold server timestamps).
        'uploadedAt': uploadedAt.toIso8601String(),
        'status': status,
      };

  AstrologerCertificate copyWith({
    String? name,
    String? url,
    String? fileType,
    String? status,
  }) =>
      AstrologerCertificate(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        fileType: fileType ?? this.fileType,
        uploadedAt: uploadedAt,
        status: status ?? this.status,
      );
}

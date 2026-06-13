import 'package:cloud_firestore/cloud_firestore.dart';
import 'astrologer_certificate.dart';
import 'astrologer_model.dart';

/// Certificate verification status set by the admin.
enum VerificationStatus { pending, approved, rejected }

extension VerificationStatusX on VerificationStatus {
  String get label {
    switch (this) {
      case VerificationStatus.pending:
        return 'Pending Verification';
      case VerificationStatus.approved:
        return 'Approved';
      case VerificationStatus.rejected:
        return 'Rejected';
    }
  }
}

/// The logged-in astrologer's own account/profile created during onboarding.
///
/// Maps to Firestore `astrologers/{uid}` + `astrologer_certificates` +
/// `astrologer_services`. The profile cannot go live until [status] is
/// `approved` by an admin.
class AstrologerAccount {
  final String id;
  // Basic
  final String fullName;
  final String gender;
  final DateTime? dob;
  final String mobile;
  final String email;
  final String city;
  final String state;
  final String country;
  final String photoUrl;
  // Professional
  final int experienceYears;
  final List<String> expertise;
  final List<String> languages;
  final String about;
  final List<String> consultationModes; // Chat, Audio Call, Video Call, In-Person
  final String qualification; // highest astrology/academic qualification
  // Certification (legacy single-cert fields, kept for backward compatibility).
  final String certName;
  final String certOrg;
  final String certNumber;
  final String certFileName;
  // Uploaded certificate documents (for admin verification).
  final List<AstrologerCertificate> certificates;
  // Consultation
  final double consultationFee; // per session, in INR
  final String availability; // e.g. "Monday – Saturday"
  final String workingHours; // e.g. "10:00 AM – 6:00 PM"
  final String consultationMode; // Online | Offline | Both
  // Set once the astrologer has completed the post-Google profile setup.
  final bool profileCompleted;
  // Status & services
  final VerificationStatus status;
  final List<AstrologerService> services;
  final double rating;
  final int reviewCount;
  // When the astrologer account was first created (registration date). Read
  // from the Firestore `createdAt` server timestamp; may be null for older docs.
  final DateTime? createdAt;

  const AstrologerAccount({
    required this.id,
    required this.fullName,
    required this.gender,
    required this.dob,
    required this.mobile,
    required this.email,
    required this.city,
    required this.state,
    required this.country,
    this.photoUrl = '',
    required this.experienceYears,
    required this.expertise,
    required this.languages,
    required this.about,
    required this.consultationModes,
    this.qualification = '',
    required this.certName,
    required this.certOrg,
    required this.certNumber,
    required this.certFileName,
    this.certificates = const [],
    this.consultationFee = 0,
    this.availability = '',
    this.workingHours = '',
    this.consultationMode = 'Online',
    this.profileCompleted = false,
    this.status = VerificationStatus.pending,
    this.services = const [],
    this.rating = 0,
    this.reviewCount = 0,
    this.createdAt,
  });

  bool get isApproved => status == VerificationStatus.approved;

  AstrologerAccount copyWith({
    String? fullName,
    String? gender,
    DateTime? dob,
    String? mobile,
    String? email,
    String? city,
    String? state,
    String? country,
    String? photoUrl,
    int? experienceYears,
    List<String>? expertise,
    List<String>? languages,
    String? about,
    List<String>? consultationModes,
    String? qualification,
    String? certName,
    String? certOrg,
    String? certNumber,
    String? certFileName,
    List<AstrologerCertificate>? certificates,
    double? consultationFee,
    String? availability,
    String? workingHours,
    String? consultationMode,
    bool? profileCompleted,
    VerificationStatus? status,
    List<AstrologerService>? services,
  }) =>
      AstrologerAccount(
        id: id,
        fullName: fullName ?? this.fullName,
        gender: gender ?? this.gender,
        dob: dob ?? this.dob,
        mobile: mobile ?? this.mobile,
        email: email ?? this.email,
        city: city ?? this.city,
        state: state ?? this.state,
        country: country ?? this.country,
        photoUrl: photoUrl ?? this.photoUrl,
        experienceYears: experienceYears ?? this.experienceYears,
        expertise: expertise ?? this.expertise,
        languages: languages ?? this.languages,
        about: about ?? this.about,
        consultationModes: consultationModes ?? this.consultationModes,
        qualification: qualification ?? this.qualification,
        certName: certName ?? this.certName,
        certOrg: certOrg ?? this.certOrg,
        certNumber: certNumber ?? this.certNumber,
        certFileName: certFileName ?? this.certFileName,
        certificates: certificates ?? this.certificates,
        consultationFee: consultationFee ?? this.consultationFee,
        availability: availability ?? this.availability,
        workingHours: workingHours ?? this.workingHours,
        consultationMode: consultationMode ?? this.consultationMode,
        profileCompleted: profileCompleted ?? this.profileCompleted,
        status: status ?? this.status,
        services: services ?? this.services,
        rating: rating,
        reviewCount: reviewCount,
        createdAt: createdAt,
      );

  factory AstrologerAccount.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final cert = (d['certification'] as Map<String, dynamic>?) ?? const {};
    return AstrologerAccount(
      id: doc.id,
      fullName: d['fullName'] ?? '',
      gender: d['gender'] ?? '',
      dob: d['dob'] != null ? DateTime.tryParse(d['dob']) : null,
      mobile: d['mobile'] ?? '',
      email: d['email'] ?? '',
      city: d['city'] ?? '',
      state: d['state'] ?? '',
      country: d['country'] ?? 'India',
      photoUrl: d['photoUrl'] ?? '',
      experienceYears: (d['experienceYears'] ?? 0) is int
          ? d['experienceYears'] ?? 0
          : int.tryParse('${d['experienceYears']}') ?? 0,
      expertise: List<String>.from(d['expertise'] ?? const []),
      languages: List<String>.from(d['languages'] ?? const []),
      about: d['about'] ?? '',
      consultationModes:
          List<String>.from(d['consultationModes'] ?? const ['Chat']),
      qualification: d['qualification'] ?? '',
      certName: cert['name'] ?? '',
      certOrg: cert['organization'] ?? '',
      certNumber: cert['number'] ?? '',
      certFileName: cert['fileName'] ?? '',
      certificates: ((d['certificates'] as List?) ?? const [])
          .map((c) =>
              AstrologerCertificate.fromMap(Map<String, dynamic>.from(c)))
          .toList(),
      consultationFee: (d['consultationFee'] ?? 0).toDouble(),
      availability: d['availability'] ?? '',
      workingHours: d['workingHours'] ?? '',
      consultationMode: d['consultationMode'] ?? 'Online',
      profileCompleted: d['profileCompleted'] ?? false,
      status: VerificationStatus.values.firstWhere(
        (s) => s.name == (d['status'] ?? 'pending'),
        orElse: () => VerificationStatus.pending,
      ),
      services: ((d['services'] as List?) ?? const [])
          .map((s) => AstrologerService.fromMap(Map<String, dynamic>.from(s)))
          .toList(),
      rating: (d['rating'] ?? 0).toDouble(),
      reviewCount: d['reviewCount'] ?? 0,
      createdAt: d['createdAt'] is Timestamp
          ? (d['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'fullName': fullName,
        'gender': gender,
        'dob': dob?.toIso8601String(),
        'mobile': mobile,
        'email': email,
        'city': city,
        'state': state,
        'country': country,
        'photoUrl': photoUrl,
        'experienceYears': experienceYears,
        'expertise': expertise,
        'languages': languages,
        'about': about,
        'consultationModes': consultationModes,
        'qualification': qualification,
        'certification': {
          'name': certName,
          'organization': certOrg,
          'number': certNumber,
          'fileName': certFileName,
        },
        'certificates': certificates.map((c) => c.toMap()).toList(),
        'consultationFee': consultationFee,
        'availability': availability,
        'workingHours': workingHours,
        'consultationMode': consultationMode,
        'profileCompleted': profileCompleted,
        'status': status.name,
        'services': services.map((s) => s.toMap()).toList(),
        'rating': rating,
        'reviewCount': reviewCount,
      };
}

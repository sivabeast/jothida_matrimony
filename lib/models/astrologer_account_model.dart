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
  // Certification (mandatory)
  final String certName;
  final String certOrg;
  final String certNumber;
  final String certFileName;
  // Status & services
  final VerificationStatus status;
  final List<AstrologerService> services;
  final double rating;
  final int reviewCount;

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
    required this.certName,
    required this.certOrg,
    required this.certNumber,
    required this.certFileName,
    this.status = VerificationStatus.pending,
    this.services = const [],
    this.rating = 0,
    this.reviewCount = 0,
  });

  bool get isApproved => status == VerificationStatus.approved;

  AstrologerAccount copyWith({
    VerificationStatus? status,
    List<AstrologerService>? services,
  }) =>
      AstrologerAccount(
        id: id,
        fullName: fullName,
        gender: gender,
        dob: dob,
        mobile: mobile,
        email: email,
        city: city,
        state: state,
        country: country,
        photoUrl: photoUrl,
        experienceYears: experienceYears,
        expertise: expertise,
        languages: languages,
        about: about,
        consultationModes: consultationModes,
        certName: certName,
        certOrg: certOrg,
        certNumber: certNumber,
        certFileName: certFileName,
        status: status ?? this.status,
        services: services ?? this.services,
        rating: rating,
        reviewCount: reviewCount,
      );

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
        'certification': {
          'name': certName,
          'organization': certOrg,
          'number': certNumber,
          'fileName': certFileName,
        },
        'status': status.name,
        'rating': rating,
        'reviewCount': reviewCount,
      };
}

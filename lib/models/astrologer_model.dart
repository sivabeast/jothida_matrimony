/// A service an astrologer offers, with its price (INR).
class AstrologerService {
  final String name;
  final int price;
  final String description;

  const AstrologerService({
    required this.name,
    required this.price,
    this.description = '',
  });

  factory AstrologerService.fromMap(Map<String, dynamic> m) => AstrologerService(
        name: m['name'] ?? '',
        price: m['price'] ?? 0,
        description: m['description'] ?? '',
      );

  Map<String, dynamic> toMap() =>
      {'name': name, 'price': price, 'description': description};
}

/// A short user review of an astrologer.
class AstrologerReview {
  final String userName;
  final double rating;
  final String comment;

  const AstrologerReview({
    required this.userName,
    required this.rating,
    required this.comment,
  });
}

/// An astrologer registered on the platform.
class Astrologer {
  final String id;
  final String name;
  final String photoUrl;
  final double rating;
  final int reviewCount;
  final int experienceYears;
  final List<String> languages;
  final List<String> specializations;
  final List<String> certifications;
  final List<AstrologerService> services;
  final List<AstrologerReview> reviews;
  final bool isAvailable;
  final bool isRecommended;
  final DateTime lastActive;
  final String about;

  const Astrologer({
    required this.id,
    required this.name,
    required this.photoUrl,
    required this.rating,
    required this.reviewCount,
    required this.experienceYears,
    required this.languages,
    required this.specializations,
    required this.certifications,
    required this.services,
    required this.reviews,
    required this.isAvailable,
    required this.isRecommended,
    required this.lastActive,
    required this.about,
  });

  /// Lowest priced service — handy for "from ₹X" labels.
  int get startingPrice =>
      services.isEmpty ? 0 : services.map((s) => s.price).reduce((a, b) => a < b ? a : b);

  factory Astrologer.fromMap(String id, Map<String, dynamic> m) => Astrologer(
        id: id,
        name: m['name'] ?? '',
        photoUrl: m['photoUrl'] ?? '',
        rating: (m['rating'] ?? 0).toDouble(),
        reviewCount: m['reviewCount'] ?? 0,
        experienceYears: m['experienceYears'] ?? 0,
        languages: List<String>.from(m['languages'] ?? []),
        specializations: List<String>.from(m['specializations'] ?? []),
        certifications: List<String>.from(m['certifications'] ?? []),
        services: (m['services'] as List? ?? [])
            .map((e) => AstrologerService.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
        reviews: const [],
        isAvailable: m['isAvailable'] ?? false,
        isRecommended: m['isRecommended'] ?? false,
        lastActive: DateTime.now(),
        about: m['about'] ?? '',
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'photoUrl': photoUrl,
        'rating': rating,
        'reviewCount': reviewCount,
        'experienceYears': experienceYears,
        'languages': languages,
        'specializations': specializations,
        'certifications': certifications,
        'services': services.map((s) => s.toMap()).toList(),
        'isAvailable': isAvailable,
        'isRecommended': isRecommended,
        'about': about,
      };
}

import '../../models/astrologer_model.dart';

/// 10 sample astrologers for frontend/demo mode.
List<Astrologer> sampleAstrologers() {
  AstrologerService s(String n, int p, [String d = '']) =>
      AstrologerService(name: n, price: p, description: d);

  // Standard service catalogue (prices vary per astrologer).
  List<AstrologerService> services(int base) => [
        s('Marriage Compatibility Analysis', base, 'Full 10-porutham match report'),
        s('Horoscope Matching', (base * 1.6).round(), 'Jathagam-to-jathagam matching'),
        s('Detailed Marriage Consultation', (base * 3).round(), '45-min guided session'),
        s('Career Consultation', (base * 1.4).round(), 'Profession & timing guidance'),
        s('General Astrology Consultation', (base * 1.2).round(), 'Open Q&A session'),
      ];

  const reviews = [
    AstrologerReview(
        userName: 'Ramesh K', rating: 5, comment: 'Very accurate porutham analysis. Highly recommend.'),
    AstrologerReview(
        userName: 'Deepa S', rating: 4.5, comment: 'Patient and clear explanations.'),
    AstrologerReview(
        userName: 'Vikram R', rating: 4, comment: 'Helpful consultation for our family.'),
  ];

  Astrologer a(
    String id,
    String name,
    int photo,
    double rating,
    int reviews1,
    int exp,
    List<String> langs,
    List<String> specs,
    int base, {
    required String location,
    bool available = true,
    bool recommended = false,
    int activeMinsAgo = 5,
  }) =>
      Astrologer(
        id: id,
        name: name,
        photoUrl: 'https://randomuser.me/api/portraits/men/$photo.jpg',
        location: location,
        rating: rating,
        reviewCount: reviews1,
        experienceYears: exp,
        languages: langs,
        specializations: specs,
        certifications: const [
          'Jyotish Visharad',
          'Certified Vedic Astrologer',
        ],
        services: services(base),
        reviews: reviews,
        isAvailable: available,
        isRecommended: recommended,
        lastActive: DateTime.now().subtract(Duration(minutes: activeMinsAgo)),
        about:
            '$name is a trusted Vedic astrologer with $exp years of experience in Tamil marriage matching, porutham analysis and horoscope consultation.',
      );

  return [
    a('astro_1', 'Pandit Sivakumar Sharma', 32, 4.9, 1240, 22,
        ['Tamil', 'English', 'Hindi'], ['Marriage Matching', 'Porutham', 'Jathagam'], 499,
        location: 'Chennai', recommended: true, activeMinsAgo: 2),
    a('astro_2', 'Astro Ravichandran', 45, 4.8, 980, 18,
        ['Tamil', 'Telugu'], ['Horoscope Matching', 'Career'], 399,
        location: 'Coimbatore', recommended: true, activeMinsAgo: 8),
    a('astro_3', 'Guru Venkatraman', 12, 4.7, 760, 15,
        ['Tamil', 'English'], ['Marriage Consultation', 'Dosha Analysis'], 599,
        location: 'Madurai', activeMinsAgo: 20),
    a('astro_4', 'Jothidar Murugan', 22, 4.6, 540, 12,
        ['Tamil'], ['Porutham', 'Muhurtham'], 349, location: 'Trichy', activeMinsAgo: 1),
    a('astro_5', 'Pandit Anand Iyer', 60, 4.5, 430, 10,
        ['Tamil', 'English', 'Malayalam'], ['Jathagam', 'Career'], 449,
        location: 'Chennai', recommended: true, activeMinsAgo: 35),
    a('astro_6', 'Astro Krishnamurthy', 51, 4.4, 390, 20,
        ['Tamil', 'Kannada'], ['Marriage Matching', 'Numerology'], 549,
        location: 'Salem', available: false, activeMinsAgo: 180),
    a('astro_7', 'Guru Balasubramaniam', 8, 4.3, 280, 8,
        ['Tamil', 'English'], ['Horoscope Matching'], 299, location: 'Coimbatore', activeMinsAgo: 12),
    a('astro_8', 'Jothidar Selvaraj', 18, 4.2, 210, 14,
        ['Tamil'], ['Porutham', 'Dosha Analysis'], 399, location: 'Madurai', available: false, activeMinsAgo: 240),
    a('astro_9', 'Pandit Hariharan', 28, 4.1, 160, 6,
        ['Tamil', 'Telugu', 'English'], ['General Astrology', 'Career'], 349,
        location: 'Chennai', activeMinsAgo: 50),
    a('astro_10', 'Astro Natarajan', 36, 4.0, 120, 25,
        ['Tamil', 'English'], ['Marriage Consultation', 'Muhurtham'], 699,
        location: 'Trichy', activeMinsAgo: 4),
  ];
}

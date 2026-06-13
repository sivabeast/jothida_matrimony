import '../../models/astrologer_model.dart';

/// Default services pre-filled for a new astrologer at signup. The astrologer
/// can edit/remove these from their Profile → My Services after onboarding.
///
/// NOTE: the old sample bookings / reviews / weekly-availability generators were
/// removed — the astrologer dashboard now renders only real Firestore data.
List<AstrologerService> defaultAstrologerServices() => const [
      AstrologerService(
          name: 'Marriage Compatibility Analysis',
          price: 499,
          description: '10-porutham match report',
          durationMinutes: 30),
      AstrologerService(
          name: 'Horoscope Matching',
          price: 799,
          description: 'Jathagam matching',
          durationMinutes: 45),
      AstrologerService(
          name: 'Marriage Consultation',
          price: 1499,
          description: '45-min guided session',
          durationMinutes: 45),
    ];

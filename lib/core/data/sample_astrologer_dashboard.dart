import '../../models/astrologer_booking_model.dart';
import '../../models/astrologer_model.dart';

/// Sample dashboard data for the logged-in astrologer (demo mode).

List<AstrologerBooking> sampleBookings() {
  final now = DateTime.now();
  AstrologerBooking b(String id, String name, int photo, String service,
          String mode, Duration when, int amount, BookingStatus st) =>
      AstrologerBooking(
        id: id,
        userName: name,
        userPhotoUrl: 'https://randomuser.me/api/portraits/men/$photo.jpg',
        serviceName: service,
        mode: mode,
        dateTime: now.add(when),
        amount: amount,
        status: st,
      );

  return [
    b('bk1', 'Arjun Kumar', 32, 'Marriage Compatibility Analysis', 'Video Call',
        const Duration(hours: 3), 499, BookingStatus.upcoming),
    b('bk2', 'Karthik Raja', 45, 'Horoscope Matching', 'Audio Call',
        const Duration(days: 1, hours: 2), 799, BookingStatus.upcoming),
    b('bk3', 'Surya Prakash', 60, 'Marriage Consultation', 'In-Person',
        const Duration(days: 2), 1499, BookingStatus.upcoming),
    b('bk4', 'Vignesh Babu', 22, 'Career Consultation', 'Chat',
        const Duration(days: -1), 699, BookingStatus.completed),
    b('bk5', 'Ramesh K', 12, 'Marriage Compatibility Analysis', 'Video Call',
        const Duration(days: -3), 499, BookingStatus.completed),
    b('bk6', 'Manoj S', 8, 'General Astrology Consultation', 'Audio Call',
        const Duration(days: -5), 399, BookingStatus.completed),
    b('bk7', 'Dinesh R', 51, 'Horoscope Matching', 'Chat',
        const Duration(days: -2), 799, BookingStatus.cancelled),
  ];
}

List<AstrologerReview> sampleDashboardReviews() => const [
      AstrologerReview(
          userName: 'Arjun Kumar',
          rating: 5,
          comment: 'Very detailed porutham analysis. Explained everything clearly.'),
      AstrologerReview(
          userName: 'Karthik Raja',
          rating: 4.5,
          comment: 'Helpful and patient. Worth the consultation fee.'),
      AstrologerReview(
          userName: 'Surya Prakash',
          rating: 4,
          comment: 'Good guidance on marriage timing.'),
      AstrologerReview(
          userName: 'Vignesh Babu',
          rating: 5,
          comment: 'Career advice was spot on. Highly recommend.'),
    ];

/// Default services pre-filled for a new astrologer.
List<AstrologerService> defaultAstrologerServices() => const [
      AstrologerService(
          name: 'Marriage Compatibility Analysis',
          price: 499,
          description: '10-porutham match report'),
      AstrologerService(
          name: 'Horoscope Matching', price: 799, description: 'Jathagam matching'),
      AstrologerService(
          name: 'Marriage Consultation',
          price: 1499,
          description: '45-min guided session'),
    ];

/// A single availability slot in the weekly schedule.
class AvailabilitySlot {
  final String start; // e.g. '10:00 AM'
  final String end; // e.g. '01:00 PM'
  final bool enabled;
  const AvailabilitySlot(this.start, this.end, {this.enabled = true});
}

/// Sample weekly availability (day → slots).
Map<String, List<AvailabilitySlot>> sampleWeeklyAvailability() => {
      'Monday': const [
        AvailabilitySlot('10:00 AM', '01:00 PM'),
        AvailabilitySlot('04:00 PM', '08:00 PM'),
      ],
      'Tuesday': const [AvailabilitySlot('11:00 AM', '05:00 PM')],
      'Wednesday': const [
        AvailabilitySlot('10:00 AM', '02:00 PM'),
        AvailabilitySlot('06:00 PM', '09:00 PM', enabled: false),
      ],
      'Thursday': const [AvailabilitySlot('10:00 AM', '01:00 PM')],
      'Friday': const [
        AvailabilitySlot('09:00 AM', '12:00 PM'),
        AvailabilitySlot('04:00 PM', '07:00 PM'),
      ],
      'Saturday': const [AvailabilitySlot('10:00 AM', '06:00 PM')],
      'Sunday': const [],
    };

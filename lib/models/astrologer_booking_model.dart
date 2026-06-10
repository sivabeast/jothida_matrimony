/// Status of a consultation booking.
enum BookingStatus { upcoming, completed, cancelled }

extension BookingStatusX on BookingStatus {
  String get label {
    switch (this) {
      case BookingStatus.upcoming:
        return 'Upcoming';
      case BookingStatus.completed:
        return 'Completed';
      case BookingStatus.cancelled:
        return 'Cancelled';
    }
  }
}

/// A consultation booking between a matrimony user and an astrologer.
///
/// Maps to the Firestore `bookings` collection:
/// { userId, astrologerId, serviceName, dateTime, amount, status, mode, createdAt }.
class AstrologerBooking {
  final String id;
  final String userName;
  final String userPhotoUrl;
  final String serviceName;
  final String mode; // Chat / Audio Call / Video Call / In-Person
  final DateTime dateTime;
  final int amount;
  final BookingStatus status;

  const AstrologerBooking({
    required this.id,
    required this.userName,
    required this.userPhotoUrl,
    required this.serviceName,
    required this.mode,
    required this.dateTime,
    required this.amount,
    required this.status,
  });
}

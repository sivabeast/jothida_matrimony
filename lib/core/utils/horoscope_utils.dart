import '../constants/app_constants.dart';

class HoroscopeUtils {
  /// Calculate Rasi from date of birth (simplified Sun sign based calculation)
  /// For accurate results, use birth time & place with a proper Panchangam
  static String calculateRasi(DateTime dob) {
    final month = dob.month;
    final day = dob.day;

    if ((month == 3 && day >= 21) || (month == 4 && day <= 19)) return AppConstants.rasiList[0]; // Mesham
    if ((month == 4 && day >= 20) || (month == 5 && day <= 20)) return AppConstants.rasiList[1]; // Rishabam
    if ((month == 5 && day >= 21) || (month == 6 && day <= 20)) return AppConstants.rasiList[2]; // Midhunam
    if ((month == 6 && day >= 21) || (month == 7 && day <= 22)) return AppConstants.rasiList[3]; // Kadagam
    if ((month == 7 && day >= 23) || (month == 8 && day <= 22)) return AppConstants.rasiList[4]; // Simmam
    if ((month == 8 && day >= 23) || (month == 9 && day <= 22)) return AppConstants.rasiList[5]; // Kanni
    if ((month == 9 && day >= 23) || (month == 10 && day <= 22)) return AppConstants.rasiList[6]; // Thulam
    if ((month == 10 && day >= 23) || (month == 11 && day <= 21)) return AppConstants.rasiList[7]; // Viruchigam
    if ((month == 11 && day >= 22) || (month == 12 && day <= 21)) return AppConstants.rasiList[8]; // Dhanusu
    if ((month == 12 && day >= 22) || (month == 1 && day <= 19)) return AppConstants.rasiList[9]; // Magaram
    if ((month == 1 && day >= 20) || (month == 2 && day <= 18)) return AppConstants.rasiList[10]; // Kumbam
    return AppConstants.rasiList[11]; // Meenam
  }

  /// Calculate Nakshatra index from day of year (simplified)
  static String calculateNakshatra(DateTime dob) {
    final dayOfYear = dob.difference(DateTime(dob.year, 1, 1)).inDays;
    final index = (dayOfYear * 27 ~/ 365) % 27;
    return AppConstants.nakshatraList[index];
  }

  /// Calculate approximate Lagnam (simplified - needs birth time for accuracy)
  static String calculateLagnam(DateTime dob, String birthTime) {
    // Lagnam changes every 2 hours; this is a simplified estimation
    // For production accuracy, use a proper Jyotish library
    final parts = birthTime.split(':');
    if (parts.length < 2) return AppConstants.lagnamList[0];
    final hour = int.tryParse(parts[0]) ?? 0;
    final lagnamIndex = (hour ~/ 2) % 12;
    return AppConstants.lagnamList[lagnamIndex];
  }

  /// Calculate Dasa Balance based on Nakshatra
  static Map<String, dynamic> calculateDasaBalance(DateTime dob) {
    final nakshatraIndex = AppConstants.nakshatraList.indexOf(calculateNakshatra(dob));
    const dasaYears = [6, 10, 7, 18, 16, 19, 17, 7, 20]; // Sun,Moon,Mars,Rahu,Jup,Sat,Mer,Ketu,Ven
    final dasaOwner = AppConstants.dasaList[nakshatraIndex % 9];
    final dasaYearsLeft = dasaYears[nakshatraIndex % 9];
    final dayOfNakshatra = dob.difference(DateTime(dob.year, 1, 1)).inDays % 13;
    final yearsLeft = dasaYearsLeft - (dayOfNakshatra * dasaYearsLeft ~/ 13);

    return {
      'owner': dasaOwner,
      'yearsBalance': yearsLeft,
      'display': '$dasaOwner தசை - $yearsLeft ஆண்டுகள் மீதம்',
    };
  }

  /// Calculate age from DOB
  static int calculateAge(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  /// Get Yogam based on Nakshatra
  static String calculateYogam(DateTime dob) {
    const yogams = [
      'விஷ்கம்பம்', 'பிரீதி', 'ஆயுஷ்மான்', 'சௌபாக்யம்', 'சோபனம்',
      'அதிகண்ட', 'சுகர்மா', 'திருதி', 'சூல', 'கண்ட', 'விருத்தி',
      'த்ருவம்', 'வியாகாத', 'ஹர்ஷண', 'வஜ்ரம்', 'சித்தி', 'வியதீபாதம்',
      'வரியான்', 'பரிகம்', 'சிவம்', 'சித்தம்', 'சாத்தியம்', 'சுபம்',
      'சுக்லம்', 'பிரம்மம்', 'இந்திரம்', 'வைத்ருதி',
    ];
    final dayOfYear = dob.difference(DateTime(dob.year, 1, 1)).inDays;
    return yogams[dayOfYear % yogams.length];
  }

  /// Get Karanam based on date
  static String calculateKaranam(DateTime dob) {
    const karanams = [
      'பவம்', 'பாலவம்', 'கௌலவம்', 'தைதிலம்', 'கரசம்',
      'வணிஜம்', 'விஷ்டி', 'சகுனி', 'சதுஷ்பாதம்', 'நாகவம்', 'கிம்ஸ்துக்னம்',
    ];
    final dayOfYear = dob.difference(DateTime(dob.year, 1, 1)).inDays;
    return karanams[dayOfYear % karanams.length];
  }

  /// Get moon sign (same as Rasi in Tamil astrology)
  static String getMoonSign(String rasi) => rasi;

  /// Get sun sign in English
  static String getSunSign(DateTime dob) {
    final month = dob.month;
    final day = dob.day;
    if ((month == 3 && day >= 21) || (month == 4 && day <= 19)) return 'Aries';
    if ((month == 4 && day >= 20) || (month == 5 && day <= 20)) return 'Taurus';
    if ((month == 5 && day >= 21) || (month == 6 && day <= 20)) return 'Gemini';
    if ((month == 6 && day >= 21) || (month == 7 && day <= 22)) return 'Cancer';
    if ((month == 7 && day >= 23) || (month == 8 && day <= 22)) return 'Leo';
    if ((month == 8 && day >= 23) || (month == 9 && day <= 22)) return 'Virgo';
    if ((month == 9 && day >= 23) || (month == 10 && day <= 22)) return 'Libra';
    if ((month == 10 && day >= 23) || (month == 11 && day <= 21)) return 'Scorpio';
    if ((month == 11 && day >= 22) || (month == 12 && day <= 21)) return 'Sagittarius';
    if ((month == 12 && day >= 22) || (month == 1 && day <= 19)) return 'Capricorn';
    if ((month == 1 && day >= 20) || (month == 2 && day <= 18)) return 'Aquarius';
    return 'Pisces';
  }

  /// Format birth time for display
  static String formatBirthTime(String time24h) {
    if (time24h.isEmpty) return '';
    final parts = time24h.split(':');
    if (parts.length < 2) return time24h;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts[1];
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$hour12:$minute $period';
  }
}

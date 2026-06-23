/// Kind of recent platform event shown on the admin Dashboard activity feed.
enum AdminActivityType {
  user,
  astrologer,
  subscription,
  deletion,
  verification, // an astrologer was verified/approved
  horoscope, // a horoscope / match-analysis report was completed
}

/// A single recent-activity entry for the admin Dashboard.
class AdminActivity {
  final AdminActivityType type;
  final String title; // who (name / email / plan)
  final String subtitle; // what happened
  final DateTime time;

  const AdminActivity({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.time,
  });
}

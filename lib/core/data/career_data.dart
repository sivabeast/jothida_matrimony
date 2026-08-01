import '../constants/app_constants.dart';

/// HIERARCHICAL Education & Career data (spec §5–§7).
///
/// The app used to offer Education and Occupation as two FLAT dropdowns. Both
/// are now two/three-level dependent pickers:
///
///   Education Level  →  Course / Degree
///   Employment Status → Government / Private  →  Occupation
///                     → Business / Profession →  Occupation
///
/// **Nothing about the stored VALUES changes**: every leaf string below is
/// taken verbatim from the website's `src/constants/profileOptions.js`
/// (`EDUCATION` / `OCCUPATION`), so a profile created on the app and one created
/// on the website still store identical `education` / `occupation` values and
/// the existing matching, filtering and admin screens keep working. The levels
/// and statuses are the grouping layer added on top; they are persisted in the
/// new `educationLevel` / `employmentStatus` fields and can always be recovered
/// from a legacy document with [levelForDegree] / [statusForOccupation].
///
/// Per §9 the LEVEL and STATUS names are localizable (they are ordinary UI
/// vocabulary), while degree names and occupation titles stay in English
/// exactly as the website presents them.
class CareerData {
  CareerData._();

  // ══════════════════════════════════════════════════════════════════════════
  // EDUCATION — Level → Course / Degree
  // ══════════════════════════════════════════════════════════════════════════

  static const String levelBelow10 = 'Below 10th';
  static const String level10 = '10th';
  static const String level12 = '12th';
  static const String levelDiploma = 'Diploma';
  static const String levelIti = 'ITI';
  static const String levelUg = 'UG';
  static const String levelPg = 'PG';
  static const String levelDoctorate = 'Doctorate';

  /// The education levels, in the order the picker lists them (§5).
  static const List<String> educationLevels = [
    levelBelow10,
    level10,
    level12,
    levelDiploma,
    levelIti,
    levelUg,
    levelPg,
    levelDoctorate,
  ];

  /// Whether [level] asks the member to pick a Course / Degree afterwards.
  ///
  /// A level with a single possible qualification (10th → SSLC, 12th → HSC,
  /// ITI → ITI) doesn't: picking the level already says everything, so the
  /// value is filled in automatically by [defaultCourseFor].
  static bool levelHasCourses(String? level) => coursesFor(level).length > 1;

  /// The value to store in `education` for a level that has exactly one
  /// qualification, or null when the member must choose.
  static String? defaultCourseFor(String? level) {
    final courses = coursesFor(level);
    return courses.length == 1 ? courses.first : null;
  }

  /// Level → the courses/degrees it contains. Every value is a string from the
  /// website's `EDUCATION` list; the union of all eight buckets is exactly that
  /// list (enforced by `test/career_data_test.dart`).
  static const Map<String, List<String>> coursesByLevel = {
    levelBelow10: ['No Formal Education', 'Below SSLC'],
    level10: ['SSLC'],
    level12: ['HSC'],
    levelIti: ['ITI'],
    levelDiploma: [
      'Diploma',
      'Polytechnic',
      'D.Pharm',
      'DMLT',
      'GNM',
      'ANM',
      'D.El.Ed',
      'TTC',
      'Certificate Course',
      'Vocational Training',
    ],
    levelUg: [
      // Arts / Science / Commerce
      'B.A', 'B.Sc', 'B.Com', 'B.Sc Computer Science', 'B.Sc IT',
      'B.Sc Nursing', 'B.Sc Agriculture', 'B.Sc Fashion Design', 'BFA', 'BSW',
      'BJMC', 'B.Lib.Sc', 'BMS', 'B.Des',
      // Management / Computer applications
      'BBA', 'BCA', 'BHM',
      // Engineering / Architecture
      'B.E', 'B.Tech', 'B.Arch', 'B.Plan',
      // Medical / Allied health
      'MBBS', 'BDS', 'BAMS', 'BHMS', 'BUMS', 'BSMS', 'BNYS', 'B.V.Sc',
      'B.Pharm', 'BPT',
      // Education
      'B.Ed', 'B.El.Ed',
      // Law (incl. integrated)
      'LLB', 'BA LLB', 'BBA LLB', 'B.Com LLB',
    ],
    levelPg: [
      'M.A', 'M.Sc', 'M.Com', 'M.Sc Computer Science', 'M.Sc IT',
      'M.Sc Nursing', 'M.Sc Agriculture', 'MFA', 'MSW', 'M.Lib.Sc',
      'MBA', 'PG Diploma', 'MCA', 'M.E', 'M.Tech', 'M.Arch', 'M.Des',
      'MD', 'MS', 'MDS', 'M.Pharm', 'MPT', 'M.Ed', 'LLM', 'Integrated M.Sc',
      // Professional qualifications taken after graduation
      'CA', 'CMA', 'CS', 'CFA',
    ],
    levelDoctorate: [
      'M.Phil', 'Ph.D', 'DM', 'M.Ch', 'D.Litt', 'Post Doctorate', 'Pharm.D',
    ],
  };

  /// Courses for [level] (empty when the level has none / is unknown).
  static List<String> coursesFor(String? level) =>
      coursesByLevel[level] ?? const [];

  /// The level that owns [degree], or null when it is a custom ("Others")
  /// value. Lets a legacy profile — which only ever stored the flat
  /// `education` string — still render the "Level → Course" hierarchy (§13).
  static String? levelForDegree(String? degree) {
    final d = (degree ?? '').trim().toLowerCase();
    if (d.isEmpty) return null;
    for (final entry in coursesByLevel.entries) {
      for (final course in entry.value) {
        if (course.toLowerCase() == d) return entry.key;
      }
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // OCCUPATION — Employment Status → Sector → Occupation
  // ══════════════════════════════════════════════════════════════════════════

  static const String statusEmployed = 'Employed';
  static const String statusSelfEmployed = 'Self Employed';
  static const String statusStudent = 'Student';
  static const String statusJobSeeker = 'Job Seeker';
  static const String statusHomemaker = 'Homemaker';
  static const String statusRetired = 'Retired';

  /// Employment statuses, in picker order (§6).
  static const List<String> employmentStatuses = [
    statusEmployed,
    statusSelfEmployed,
    statusStudent,
    statusJobSeeker,
    statusHomemaker,
    statusRetired,
  ];

  static const String sectorGovernment = 'Government';
  static const String sectorPrivate = 'Private';
  static const String sectorBusiness = 'Business';
  static const String sectorProfession = 'Profession';

  /// The second level under [statusEmployed].
  static const List<String> employedSectors = [sectorGovernment, sectorPrivate];

  /// The second level under [statusSelfEmployed] (§6 — "Business / Profession
  /// only").
  static const List<String> selfEmployedSectors = [
    sectorBusiness,
    sectorProfession,
  ];

  /// Sectors offered for [status]; empty for the statuses that stop at level 1.
  static List<String> sectorsFor(String? status) {
    switch (status) {
      case statusEmployed:
        return employedSectors;
      case statusSelfEmployed:
        return selfEmployedSectors;
      default:
        return const [];
    }
  }

  /// Whether [status] continues into Sector → Occupation. Student, Job Seeker,
  /// Homemaker and Retired deliberately show NO occupation field (§6).
  static bool statusHasOccupation(String? status) =>
      status == statusEmployed || status == statusSelfEmployed;

  /// Salaried roles that exist in public service (government departments, PSUs,
  /// defence, police, government schools/colleges/hospitals).
  static const List<String> governmentOccupations = [
    'Administrative Officer', 'Advocate', 'Agriculturist',
    'Air Force Personnel', 'Army Personnel', 'Assistant Professor', 'Auditor',
    'Ayurvedic Doctor', 'Bank Employee', 'Bank Officer', 'Chemical Engineer',
    'Civil Engineer', 'Civil Servant (IAS / IPS / IFS)', 'Clerk',
    'Data Entry Operator', 'Dentist', 'Doctor', 'Driver', 'Electrical Engineer',
    'Electronics Engineer', 'Fire & Rescue Officer', 'Government Employee',
    'Horticulturist', 'Judge', 'Lab Technician', 'Lecturer', 'Legal Advisor',
    'Librarian', 'Marine Engineer', 'Mechanical Engineer', 'Medical Officer',
    'Navy Personnel', 'Nurse', 'Nutritionist', 'Optometrist', 'Pharmacist',
    'Physiotherapist', 'Police Officer', 'Postal Employee', 'Professor',
    'Psychologist', 'Radiologist', 'Railway Employee', 'Research Scholar',
    'School Principal', 'Scientist', 'Site Engineer', 'Social Worker',
    'Surgeon', 'Teacher', 'Technician', 'Veterinary Doctor',
  ];

  /// Salaried roles in private companies. Everything the occupation catalogue
  /// offers except the strictly-government postings and the owner-run roles.
  static const List<String> privateOccupations = [
    'Accountant', 'Actor', 'Administrative Officer', 'Advocate',
    'Aeronautical Engineer', 'Animator', 'Architect', 'Artist',
    'Assistant Professor', 'Auditor', 'Automobile Engineer', 'Ayurvedic Doctor',
    'Bank Employee', 'Bank Officer', 'Beautician', 'Business Analyst',
    'Carpenter', 'Chartered Accountant', 'Chef', 'Chemical Engineer',
    'Civil Engineer', 'Clerk', 'Cloud Architect', 'Company Secretary',
    'Consultant', 'Content Creator', 'Cost Accountant', 'Cybersecurity Analyst',
    'Dancer', 'Data Analyst', 'Data Entry Operator', 'Data Scientist',
    'Database Administrator', 'Delivery Executive', 'Dentist',
    'DevOps Engineer', 'Doctor', 'Driver', 'Editor', 'Electrical Engineer',
    'Electrician', 'Electronics Engineer', 'Event Manager', 'Fashion Designer',
    'Film Director', 'Financial Analyst', 'Flight Attendant', 'Goldsmith',
    'Graphic Designer', 'Hotel Manager', 'HR Manager', 'Insurance Agent',
    'Interior Designer', 'Investment Banker', 'IT Consultant',
    'IT Support Engineer', 'Journalist', 'Lab Technician', 'Lawyer', 'Lecturer',
    'Legal Advisor', 'Librarian', 'Logistics Manager', 'Marine Engineer',
    'Marketing Executive', 'Mechanic', 'Mechanical Engineer', 'Medical Officer',
    'Mobile App Developer', 'Musician', 'Network Engineer', 'News Anchor',
    'Nurse', 'Nutritionist', 'Optometrist', 'Pharmacist', 'Photographer',
    'Physiotherapist', 'Pilot', 'Plumber', 'Product Manager', 'Professor',
    'Project Manager', 'Psychologist', 'QA / Test Engineer', 'Radiologist',
    'Receptionist', 'Research Scholar', 'Sales Executive', 'School Principal',
    'Scientist', 'Ship Captain', 'Singer', 'Site Engineer', 'Social Worker',
    'Software Developer', 'Software Engineer', 'Stock Broker',
    'System Administrator', 'Tailor', 'Tax Consultant', 'Teacher', 'Technician',
    'Travel Agent', 'Tutor', 'UI / UX Designer', 'Veterinary Doctor',
    'Video Editor', 'Web Developer', 'Welder', 'Writer',
  ];

  /// Self-employed → **Business**: owner-run trades and enterprises.
  static const List<String> businessOccupations = [
    'Agriculturist', 'Business Owner', 'Civil Contractor', 'Contractor',
    'Dairy Farmer', 'Entrepreneur', 'Farmer', 'Fisherman', 'Horticulturist',
    'Hotel Manager', 'Insurance Agent', 'Poultry Farmer', 'Real Estate Agent',
    'Self Employed', 'Shop Owner', 'Startup Founder', 'Trader', 'Travel Agent',
  ];

  /// Self-employed → **Profession**: independent practitioners and freelancers.
  static const List<String> professionOccupations = [
    'Advocate', 'Architect', 'Artist', 'Ayurvedic Doctor', 'Beautician',
    'Carpenter', 'Chartered Accountant', 'Chef', 'Company Secretary',
    'Consultant', 'Content Creator', 'Cost Accountant', 'Dancer', 'Dentist',
    'Doctor', 'Driver', 'Electrician', 'Event Manager', 'Fashion Designer',
    'Film Director', 'Freelancer', 'Goldsmith', 'Graphic Designer',
    'Interior Designer', 'Lawyer', 'Legal Advisor', 'Mechanic', 'Musician',
    'Nutritionist', 'Photographer', 'Physiotherapist', 'Plumber', 'Psychologist',
    'Singer', 'Software Developer', 'Stock Broker', 'Surgeon', 'Tailor',
    'Tax Consultant', 'Technician', 'Tutor', 'UI / UX Designer',
    'Veterinary Doctor', 'Video Editor', 'Web Developer', 'Welder', 'Writer',
  ];

  /// Occupations available for a status + sector pair. Returns an empty list
  /// for the statuses that have no occupation step.
  static List<String> occupationsFor({String? status, String? sector}) {
    if (!statusHasOccupation(status)) return const [];
    switch (sector) {
      case sectorGovernment:
        return governmentOccupations;
      case sectorPrivate:
        return privateOccupations;
      case sectorBusiness:
        return businessOccupations;
      case sectorProfession:
        return professionOccupations;
      default:
        return const [];
    }
  }

  /// The canonical value written to the legacy `occupation` field for a status
  /// that has no occupation of its own. Keeps every stored `occupation` a valid
  /// website `OCCUPATION` entry so matching, filters and the website's My
  /// Profile keep working unchanged.
  static const Map<String, String> _occupationForStatus = {
    statusStudent: 'Student',
    statusJobSeeker: 'Not Working',
    statusHomemaker: 'Homemaker',
    statusRetired: 'Retired',
  };

  /// What to store in `occupation` for [status] given the member's [picked]
  /// occupation (only meaningful for Employed / Self Employed).
  static String occupationValueFor(String? status, String? picked) =>
      statusHasOccupation(status)
          ? (picked ?? '')
          : (_occupationForStatus[status ?? ''] ?? '');

  /// Best-effort employment status for a legacy profile that only stored the
  /// flat `occupation` string, so §13's hierarchy renders for old documents
  /// too. [employmentType] is the legacy sector value when present.
  static String? statusForOccupation(String? occupation,
      {String? employmentType}) {
    final o = (occupation ?? '').trim();
    if (o.isEmpty) return null;
    final lower = o.toLowerCase();
    if (lower == 'student') return statusStudent;
    if (lower == 'not working') return statusJobSeeker;
    if (lower == 'homemaker') return statusHomemaker;
    if (lower == 'retired') return statusRetired;
    final type = (employmentType ?? '').trim();
    if (type == sectorBusiness ||
        type == sectorProfession ||
        type == statusSelfEmployed) {
      return statusSelfEmployed;
    }
    if (lower == 'self employed' || lower == 'freelancer') {
      return statusSelfEmployed;
    }
    return statusEmployed;
  }

  /// Best-effort sector for a legacy profile. Prefers the stored
  /// `employmentType`, then infers from which bucket owns [occupation].
  static String? sectorForOccupation(String? occupation,
      {String? employmentType}) {
    final type = (employmentType ?? '').trim();
    if (type == sectorGovernment ||
        type == sectorPrivate ||
        type == sectorBusiness ||
        type == sectorProfession) {
      return type;
    }
    // The legacy `employmentType` list also held 'Self Employed', which maps
    // onto the new Business sector.
    if (type == statusSelfEmployed) return sectorBusiness;

    final o = (occupation ?? '').trim().toLowerCase();
    if (o.isEmpty) return null;
    bool has(List<String> list) =>
        list.any((e) => e.toLowerCase() == o);
    if (has(businessOccupations) && !has(privateOccupations)) {
      return sectorBusiness;
    }
    if (has(professionOccupations) && !has(privateOccupations)) {
      return sectorProfession;
    }
    if (has(privateOccupations)) return sectorPrivate;
    if (has(governmentOccupations)) return sectorGovernment;
    return null;
  }

  /// Every occupation string the hierarchy can produce, de-duplicated — used by
  /// screens (Partner Preference, admin filters) that still need ONE flat list.
  /// Falls back to [AppConstants.occupationList] entries not covered by any
  /// bucket so nothing a legacy profile stored disappears from a filter.
  static List<String> get allOccupations {
    final set = <String>{
      ...governmentOccupations,
      ...privateOccupations,
      ...businessOccupations,
      ...professionOccupations,
      ...AppConstants.occupationList,
    };
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  /// Every degree the hierarchy can produce — the flat list kept for Partner
  /// Preference / admin filters.
  static List<String> get allDegrees {
    final set = <String>{
      for (final courses in coursesByLevel.values) ...courses,
      ...AppConstants.educationList,
    };
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }
}

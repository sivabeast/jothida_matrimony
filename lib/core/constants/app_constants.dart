class AppConstants {
  static const String appName = 'Jothida Matrimony';
  static const String appTagline = 'ஜோதிட மேட்ரிமோனி';
  static const String appVersion = '1.0.0';

  // Firestore Collections
  static const String usersCollection = 'users';
  static const String profilesCollection = 'profiles';
  static const String interestsCollection = 'interests';
  static const String poruthamsCollection = 'poruthams';
  static const String reportsCollection = 'reports';
  static const String notificationsCollection = 'notifications';
  static const String announcementsCollection = 'announcements';
  // Admin-managed Home page banners (image banners + text-builder banners).
  static const String bannersCollection = 'banners';
  static const String transactionsCollection = 'transactions';
  static const String adminCollection = 'admin';
  static const String astrologersCollection = 'astrologers';
  static const String astrologerRequestsCollection = 'astrologer_requests';
  // Internal astrology TEAM registry, provisioned by the admin (Google-only
  // login). One doc per team member, keyed by the lowercased Gmail address:
  //   astrology_team/{emailKey}
  // Kept separate from the legacy `astrologers` collection so new lean
  // team-member docs never collide with old marketplace astrologer documents.
  static const String astrologyTeamCollection = 'astrology_team';
  // Weekly employee-commission payouts ("Mark As Paid" history). One doc per
  // closed payroll cycle per employee.
  static const String payrollPaymentsCollection = 'payroll_payments';
  // Reviews live in a subcollection of each astrologer document:
  //   astrologers/{astrologerId}/reviews/{userId}
  static const String astrologerReviewsSubcollection = 'reviews';
  static const String bookingsCollection = 'bookings';
  // Astrology consultation bookings (In-App + Direct Visit). One booking per
  // direct-visit slot is enforced by a deterministic doc id.
  static const String consultationsCollection = 'consultations';
  // Astrologer payout settlement history. One doc per "Mark as Paid" batch the
  // admin runs (the consultation docs it covers are flagged settled).
  static const String settlementsCollection = 'settlements';
  static const String chatsCollection = 'chats';
  static const String messagesSubcollection = 'messages';
  static const String blocksCollection = 'blocks';
  static const String accountDeletionRequestsCollection = 'account_deletion_requests';
  // Contact details live OUTSIDE the public profile and unlock only after a
  // mutually-accepted interest (recorded in `connections`).
  static const String contactsCollection = 'contacts';
  static const String connectionsCollection = 'connections';
  // Aadhaar verification records — SENSITIVE, gated to owner + admin only.
  static const String aadhaarCollection = 'aadhaar';
  // Immutable audit trail of important admin actions (approve/reject/suspend/
  // delete profile, credentials shared, announcements sent…). Admin-only.
  static const String adminLogsCollection = 'admin_logs';

  // Astrologer specializations
  static const List<String> astrologerSpecializations = [
    'Vedic Astrology',
    'Horoscope Matching (Porutham)',
    'Nadi Astrology',
    'Numerology',
    'Palmistry',
    'Vastu Shastra',
    'KP Astrology',
    'Prashna Astrology',
    'Gemology',
    'Muhurtha (Auspicious Timing)',
  ];

  // Storage Paths
  static const String profilePhotosPath = 'profile_photos';
  static const String horoscopeDocsPath = 'horoscope_docs';
  static const String idProofsPath = 'id_proofs';

  // ── Pricing ─────────────────────────────────────────────────────────────
  // The app is FREE. There is NO membership, subscription or general pricing
  // system — the ONE-TIME fee for a Horoscope Request is the only payment in
  // the entire application. Appointments are free (settled at the office).
  static const int poruthamsPrice = 199;
  // The one-time fee for a Horoscope Compatibility Report request (paid,
  // auto-assigned, delivered to the user's Reports page). Charged via Google
  // Play Billing (product id `horoscope_report`) — Play Console is the source
  // of truth for what is actually charged; this is only the fallback label.
  static const int horoscopeAnalysisFee = 200;

  // Pagination
  static const int profilesPerPage = 20;
  static const int notificationsPerPage = 30;

  // Interest Status
  static const String interestPending = 'pending';
  static const String interestAccepted = 'accepted';
  static const String interestRejected = 'rejected';

  // Profile Status. The app calls 'approved' VERIFIED everywhere a human reads
  // it (see `core/utils/profile_status.dart`); the stored value keeps the
  // legacy name because the Firestore rules, indexes and Cloud Functions all
  // key off it.
  static const String profilePending = 'pending';
  static const String profileApproved = 'approved';
  static const String profileRejected = 'rejected';
  static const String profileBlocked = 'blocked';

  // User Roles
  static const String roleUser = 'user';
  static const String roleAdmin = 'admin';
  // EMPLOYEE role (horoscope-analysis staff). There is no astrologer login,
  // account or dashboard — the value keeps the legacy name for data
  // compatibility only.
  static const String roleAstrologer = 'astrologer';

  // Porutham Status
  static const String poruthamsRequested = 'requested';
  static const String poruthamsCompleted = 'completed';

  // Horoscope Badges
  static const String badgeAutoGenerated = 'auto_generated';
  static const String badgeUserEdited = 'user_edited';
  static const String badgeAstrologerVerified = 'astrologer_verified';

  // Report Levels
  static const int reportWarningThreshold = 3;
  static const int reportHighThreshold = 5;
  static const int reportCriticalThreshold = 10;

  // Tamil Rasi List
  static const List<String> rasiList = [
    'மேஷம்', 'ரிஷபம்', 'மிதுனம்', 'கடகம்',
    'சிம்மம்', 'கன்னி', 'துலாம்', 'விருச்சிகம்',
    'தனுசு', 'மகரம்', 'கும்பம்', 'மீனம்',
  ];

  // English Rasi List
  static const List<String> rasiEnList = [
    'Mesham (Aries)', 'Rishabam (Taurus)', 'Midhunam (Gemini)', 'Kadagam (Cancer)',
    'Simmam (Leo)', 'Kanni (Virgo)', 'Thulam (Libra)', 'Viruchigam (Scorpio)',
    'Dhanusu (Sagittarius)', 'Magaram (Capricorn)', 'Kumbam (Aquarius)', 'Meenam (Pisces)',
  ];

  // Nakshatra List
  static const List<String> nakshatraList = [
    'அஸ்வினி', 'பரணி', 'கார்த்திகை', 'ரோகிணி', 'மிருகசீரிஷம்',
    'திருவாதிரை', 'புனர்பூசம்', 'பூசம்', 'ஆயில்யம்', 'மகம்',
    'பூரம்', 'உத்திரம்', 'அஸ்தம்', 'சித்திரை', 'சுவாதி',
    'விசாகம்', 'அனுஷம்', 'கேட்டை', 'மூலம்', 'பூராடம்',
    'உத்திராடம்', 'திருவோணம்', 'அவிட்டம்', 'சதயம்',
    'பூரட்டாதி', 'உத்திரட்டாதி', 'ரேவதி',
  ];

  // English Nakshatra List — transliterations aligned index-for-index with
  // [nakshatraList] so a stored Tamil star name can be shown in English.
  static const List<String> nakshatraEnList = [
    'Aswini', 'Bharani', 'Karthigai', 'Rohini', 'Mrigashira',
    'Thiruvathirai', 'Punarpoosam', 'Poosam', 'Ayilyam', 'Magam',
    'Pooram', 'Uthiram', 'Hastham', 'Chithirai', 'Swathi',
    'Visakam', 'Anusham', 'Kettai', 'Moolam', 'Pooradam',
    'Uthiradam', 'Thiruvonam', 'Avittam', 'Sathayam',
    'Poorattathi', 'Uthirattathi', 'Revathi',
  ];

  // Lagnam List
  static const List<String> lagnamList = [
    'மேஷம்', 'ரிஷபம்', 'மிதுனம்', 'கடகம்',
    'சிம்மம்', 'கன்னி', 'துலாம்', 'விருச்சிகம்',
    'தனுசு', 'மகரம்', 'கும்பம்', 'மீனம்',
  ];

  // Dasa List
  static const List<String> dasaList = [
    'சூரியன்', 'சந்திரன்', 'செவ்வாய்', 'ராகு',
    'குரு', 'சனி', 'புதன்', 'கேது', 'சுக்கிரன்',
  ];

  // Religion List
  static const List<String> religionList = [
    'Hindu', 'Muslim', 'Christian', 'Sikh', 'Buddhist', 'Jain', 'Other',
  ];

  // Caste List (Hindu)
  static const List<String> castList = [
    'Brahmin', 'Kshatriya', 'Vaisya', 'Nadar', 'Thevar', 'Gounder',
    'Mudaliar', 'Chettiar', 'Pillai', 'Yadav', 'Naicker', 'Vellalar',
    'Paraiyar', 'Pallar', 'Kallar', 'Agamudayar', 'Maravar', 'Servai',
    'Any Caste', 'Other',
  ];

  // ── Marital status ────────────────────────────────────────────────────────
  /// The ONE marital-status list. Every surface reads this and nothing else:
  /// profile creation (member AND admin — they are the same wizard), profile
  /// edit, admin edit, partner preferences, filters and search.
  ///
  /// There used to be a second `maritalStatusOptions` list holding
  /// `Widow` / `Widower`, which is why the same dropdown offered different
  /// values depending on which screen you opened. It is gone: adding or
  /// removing an option here changes it everywhere at once.
  ///
  /// `Widowed` is deliberately the only bereavement option and is rendered in
  /// Tamil as the gender-neutral "துணையை இழந்தவர்" — the app never offers the
  /// gendered "விதவை" / "விதவர்".
  static const List<String> maritalStatusList = [
    'Never Married',
    'Married',
    'Divorced',
    'Widowed',
  ];

  /// Values written by older builds → the canonical option they map onto.
  /// Kept so an existing profile still selects the right dropdown entry (and
  /// still displays correctly) after the list was unified.
  static const Map<String, String> legacyMaritalStatusAliases = {
    'Widow': 'Widowed',
    'Widower': 'Widowed',
    'Unmarried': 'Never Married',
    'Awaiting Divorce': 'Divorced',
    'Separated': 'Divorced',
  };

  /// Maps a STORED marital status onto the canonical option, so a dropdown
  /// seeded from an old profile lands on a real entry instead of showing blank
  /// (or appending a stale one-off option). Unknown / empty values return null.
  static String? normalizeMaritalStatus(String? stored) {
    final v = (stored ?? '').trim();
    if (v.isEmpty) return null;
    if (maritalStatusList.contains(v)) return v;
    return legacyMaritalStatusAliases[v];
  }

  /// Marital statuses that imply the user may have children → show the
  /// children count / living-status fields. Includes the legacy spellings so
  /// the check works on a raw stored value too.
  static const List<String> maritalStatusesWithChildren = [
    'Divorced', 'Widowed',
    'Widow', 'Widower', 'Awaiting Divorce', 'Separated',
  ];

  /// Gender options. Hardcoded `['Male', 'Female']` literals were scattered
  /// across the member and admin forms; they all read this now.
  static const List<String> genderList = ['Male', 'Female'];

  // Physical status (Step 3)
  static const List<String> physicalStatusList = [
    'Normal', 'Physically Challenged',
  ];

  // Children living status (Step 4)
  static const List<String> childrenLivingStatusList = [
    'Living with me', 'Not living with me', 'No children',
  ];

  // Employment type (Step 7)
  static const List<String> employmentTypeList = [
    'Private', 'Government', 'Business', 'Self Employed',
  ];

  // Citizenship (Step 8)
  static const List<String> citizenshipList = [
    'Indian', 'NRI', 'Foreign National',
  ];

  // Lifestyle & habits
  static const List<String> eatingHabitList = [
    'Vegetarian', 'Non-Vegetarian', 'Eggetarian', 'Vegan', 'Jain',
  ];
  static const List<String> smokingHabitList = [
    'No', 'Occasionally', 'Yes',
  ];
  static const List<String> drinkingHabitList = [
    'No', 'Occasionally', 'Yes',
  ];

  // Languages known (reuses the mother-tongue catalogue).
  static const List<String> languagesKnownList = motherTongueList;

  // Education List — consolidated from UNESCO ISCED, UGC, AICTE and NSQF
  // (schooling, ITI/Diploma/Polytechnic, UG, PG, professional, doctorate &
  // research across every stream). Sorted + deduplicated, mirrored VERBATIM
  // from the website (src/constants/profileOptions.js) so both platforms store
  // identical values. The single "Other → please specify" entry is added by the
  // UI, never stored in this shared list.
  static const List<String> educationList = [
    'ANM', 'B.A', 'B.Arch', 'B.Com', 'B.Com LLB', 'B.Des', 'B.E', 'B.Ed',
    'B.El.Ed', 'B.Lib.Sc', 'B.Pharm', 'B.Plan', 'B.Sc', 'B.Sc Agriculture',
    'B.Sc Computer Science', 'B.Sc Fashion Design', 'B.Sc IT', 'B.Sc Nursing',
    'B.Tech', 'B.V.Sc', 'BA LLB', 'BAMS', 'BBA', 'BBA LLB', 'BCA', 'BDS',
    'Below SSLC', 'BFA', 'BHM', 'BHMS', 'BJMC', 'BMS', 'BNYS', 'BPT', 'BSMS',
    'BSW', 'BUMS', 'CA', 'Certificate Course', 'CFA', 'CMA', 'CS', 'D.El.Ed',
    'D.Litt', 'D.Pharm', 'Diploma', 'DM', 'DMLT', 'GNM', 'HSC',
    'Integrated M.Sc', 'ITI', 'LLB', 'LLM', 'M.A', 'M.Arch', 'M.Ch', 'M.Com',
    'M.Des', 'M.E', 'M.Ed', 'M.Lib.Sc', 'M.Pharm', 'M.Phil', 'M.Sc',
    'M.Sc Agriculture', 'M.Sc Computer Science', 'M.Sc IT', 'M.Sc Nursing',
    'M.Tech', 'MBA', 'MBBS', 'MCA', 'MD', 'MDS', 'MFA', 'MPT', 'MS', 'MSW',
    'No Formal Education', 'PG Diploma', 'Ph.D', 'Pharm.D', 'Polytechnic',
    'Post Doctorate', 'SSLC', 'TTC', 'Vocational Training',
  ];

  // Occupation List — consolidated from NCO (India), ISCO-08 and ANZSCO across
  // government, private, self-employed, business, IT, healthcare, engineering,
  // education, agriculture, skilled trades, defence, police, legal, finance,
  // arts, media, hospitality, transport and construction. Sorted +
  // deduplicated, mirrored VERBATIM from the website. 'Student' and
  // 'Not Working' are load-bearing (drive the career-form branching).
  static const List<String> occupationList = [
    'Accountant', 'Actor', 'Administrative Officer', 'Advocate',
    'Aeronautical Engineer', 'Agriculturist', 'Air Force Personnel', 'Animator',
    'Architect', 'Army Personnel', 'Artist', 'Assistant Professor', 'Auditor',
    'Automobile Engineer', 'Ayurvedic Doctor', 'Bank Employee', 'Bank Officer',
    'Beautician', 'Business Analyst', 'Business Owner', 'Carpenter',
    'Chartered Accountant', 'Chef', 'Chemical Engineer', 'Civil Contractor',
    'Civil Engineer', 'Civil Servant (IAS / IPS / IFS)', 'Clerk',
    'Cloud Architect', 'Company Secretary', 'Consultant', 'Content Creator',
    'Contractor', 'Cost Accountant', 'Cybersecurity Analyst', 'Dairy Farmer',
    'Dancer', 'Data Analyst', 'Data Entry Operator', 'Data Scientist',
    'Database Administrator', 'Delivery Executive', 'Dentist', 'DevOps Engineer',
    'Doctor', 'Driver', 'Editor', 'Electrical Engineer', 'Electrician',
    'Electronics Engineer', 'Entrepreneur', 'Event Manager', 'Farmer',
    'Fashion Designer', 'Film Director', 'Financial Analyst',
    'Fire & Rescue Officer', 'Fisherman', 'Flight Attendant', 'Freelancer',
    'Goldsmith', 'Government Employee', 'Graphic Designer', 'Homemaker',
    'Horticulturist', 'Hotel Manager', 'HR Manager', 'Insurance Agent',
    'Interior Designer', 'Investment Banker', 'IT Consultant',
    'IT Support Engineer', 'Journalist', 'Judge', 'Lab Technician', 'Lawyer',
    'Lecturer', 'Legal Advisor', 'Librarian', 'Logistics Manager',
    'Marine Engineer', 'Marketing Executive', 'Mechanic', 'Mechanical Engineer',
    'Medical Officer', 'Mobile App Developer', 'Musician', 'Navy Personnel',
    'Network Engineer', 'News Anchor', 'Not Working', 'Nurse', 'Nutritionist',
    'Optometrist', 'Pharmacist', 'Photographer', 'Physiotherapist', 'Pilot',
    'Plumber', 'Police Officer', 'Postal Employee', 'Poultry Farmer',
    'Product Manager', 'Professor', 'Project Manager', 'Psychologist',
    'QA / Test Engineer', 'Radiologist', 'Railway Employee', 'Real Estate Agent',
    'Receptionist', 'Research Scholar', 'Retired', 'Sales Executive',
    'School Principal', 'Scientist', 'Self Employed', 'Ship Captain',
    'Shop Owner', 'Singer', 'Site Engineer', 'Social Worker',
    'Software Developer', 'Software Engineer', 'Startup Founder', 'Stock Broker',
    'Student', 'Surgeon', 'System Administrator', 'Tailor', 'Tax Consultant',
    'Teacher', 'Technician', 'Trader', 'Travel Agent', 'Tutor',
    'UI / UX Designer', 'Veterinary Doctor', 'Video Editor', 'Web Developer',
    'Welder', 'Writer',
  ];

  // Income List
  static const List<String> incomeList = [
    'Below ₹1 Lakh', '₹1-2 Lakhs', '₹2-3 Lakhs', '₹3-5 Lakhs',
    '₹5-7 Lakhs', '₹7-10 Lakhs', '₹10-15 Lakhs', '₹15-20 Lakhs',
    '₹20-30 Lakhs', '₹30-50 Lakhs', 'Above ₹50 Lakhs',
  ];

  // Mother Tongue
  static const List<String> motherTongueList = [
    'Tamil', 'Telugu', 'Kannada', 'Malayalam', 'Hindi', 'Marathi',
    'Bengali', 'Gujarati', 'Punjabi', 'Urdu', 'Other',
  ];

  // Report Reasons (profile) — spec §5
  static const List<String> reportReasons = [
    'Fake Profile',
    'Spam',
    'Harassment',
    'Inappropriate Behaviour',
    'Abusive Language',
    'Wrong Information',
    'Scam',
    'Other',
  ];

  // Report Reasons (chat) — spec §7
  static const List<String> chatReportReasons = [
    'Harassment',
    'Abusive Language',
    'Spam',
    'Inappropriate Content',
    'Scam / Fraud',
    'Other',
  ];

  // Porutham Types
  static const List<String> poruthamsTypes = [
    'Dina Porutham', 'Gana Porutham', 'Mahendra Porutham',
    'Rajju Porutham', 'Yoni Porutham', 'Rasi Porutham',
  ];

  // Profile Created By
  static const List<String> profileCreatedByList = [
    'Myself', 'Son', 'Daughter', 'Brother', 'Sister', 'Relative',
  ];

  // Height Range
  static const List<String> heightList = [
    "4'6\"", "4'7\"", "4'8\"", "4'9\"", "4'10\"", "4'11\"",
    "5'0\"", "5'1\"", "5'2\"", "5'3\"", "5'4\"", "5'5\"",
    "5'6\"", "5'7\"", "5'8\"", "5'9\"", "5'10\"", "5'11\"",
    "6'0\"", "6'1\"", "6'2\"", "6'3\"", "6'4\"", "6'5\"",
  ];

  // Country List (common)
  static const List<String> countryList = [
    'India', 'USA', 'UK', 'Canada', 'Australia', 'UAE', 'Singapore',
    'Malaysia', 'Germany', 'France', 'Other',
  ];

  // Indian States
  static const List<String> indianStates = [
    'Tamil Nadu', 'Andhra Pradesh', 'Karnataka', 'Kerala', 'Telangana',
    'Maharashtra', 'Gujarat', 'Rajasthan', 'Uttar Pradesh', 'Madhya Pradesh',
    'West Bengal', 'Bihar', 'Odisha', 'Punjab', 'Haryana', 'Delhi',
    'Himachal Pradesh', 'Uttarakhand', 'Goa', 'Chhattisgarh', 'Jharkhand',
    'Assam', 'Other',
  ];

  // ── Shorthand aliases used by screens ─────────────────────────────────────
  static const List<String> religions = religionList;
  static const List<String> castes = castList;
  static const List<String> maritalStatuses = maritalStatusList;
  static const List<String> educations = educationList;
  static const List<String> occupations = occupationList;
  static const List<String> incomeRanges = incomeList;
}

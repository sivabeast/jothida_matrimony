import 'master_option.dart';

/// Bilingual Education master data: **Level → Degree(s)** (§3, §4, §7).
///
/// Two rules drive the whole file:
///
///  * **Schooling levels carry no degree.** Below 10th / 10th / 12th describe a
///    qualification completely on their own, so the wizard hides
///    "படிப்பு / பட்டம்" for them entirely (§3). Everything from ITI upwards
///    asks for it.
///  * **A member may hold several degrees** (B.Sc *and* MBA *and* M.Phil), so
///    degrees are stored as a list, not a single string (§4).
///
/// Canonical English names are what reach Firestore, unchanged from the
/// flat-list era, so matching, filters, the admin screens and the website keep
/// reading the same values. The Tamil names are display-only and — because a
/// degree abbreviation is what people actually say out loud — render as
/// "இளங்கலை அறிவியல் (B.Sc)".
class EducationCatalog {
  EducationCatalog._();

  // ── Level ids ─────────────────────────────────────────────────────────────
  static const String levelBelow10 = 'Below 10th';
  static const String level10 = '10th';
  static const String level12 = '12th';
  static const String levelIti = 'ITI';
  static const String levelDiploma = 'Diploma';
  static const String levelUg = 'UG';
  static const String levelPg = 'PG';
  static const String levelMPhil = 'M.Phil';
  static const String levelPhd = 'Ph.D';
  static const String levelProfessional = 'Professional Qualification';

  /// Legacy level value: everything doctoral used to sit under one "Doctorate"
  /// bucket. Old profiles still store it, so it must keep resolving (§13).
  static const String levelDoctorateLegacy = 'Doctorate';

  /// The levels, in picker order.
  static const List<MasterOption> levels = [
    MasterOption(
        id: 'edu_below10',
        en: levelBelow10,
        ta: '10ஆம் வகுப்புக்குக் கீழ்',
        aliases: ['below 10', 'below sslc', 'school']),
    MasterOption(
        id: 'edu_10th', en: level10, ta: '10ஆம் வகுப்பு', aliases: ['sslc', 'matric']),
    MasterOption(
        id: 'edu_12th', en: level12, ta: '12ஆம் வகுப்பு', aliases: ['hsc', 'plus two', '+2']),
    MasterOption(
        id: 'edu_iti', en: levelIti, ta: 'தொழிற்பயிற்சி', aliases: ['industrial training']),
    MasterOption(
        id: 'edu_diploma', en: levelDiploma, ta: 'பட்டயப் படிப்பு', aliases: ['polytechnic']),
    MasterOption(
        id: 'edu_ug',
        en: levelUg,
        ta: 'இளங்கலை',
        aliases: ['under graduate', 'undergraduate', 'bachelor', 'degree']),
    MasterOption(
        id: 'edu_pg',
        en: levelPg,
        ta: 'முதுகலை',
        aliases: ['post graduate', 'postgraduate', 'master']),
    MasterOption(
        id: 'edu_mphil', en: levelMPhil, ta: 'எம்.ஃபில்', aliases: ['mphil', 'philosophy']),
    MasterOption(
        id: 'edu_phd', en: levelPhd, ta: 'முனைவர் பட்டம்', aliases: ['phd', 'doctorate', 'doctoral']),
    MasterOption(
        id: 'edu_professional',
        en: levelProfessional,
        ta: 'தொழில்முறைத் தகுதி',
        aliases: ['ca', 'cs', 'cma', 'cfa', 'professional']),
  ];

  /// Levels that describe schooling only — the wizard shows NO degree field for
  /// them (§3).
  static const Set<String> schoolingLevels = {levelBelow10, level10, level12};

  /// Whether [level] should show the "படிப்பு / பட்டம்" picker (§3).
  static bool levelHasDegrees(String? level) {
    final l = canonicalLevel(level);
    if (l == null || l.isEmpty) return false;
    return !schoolingLevels.contains(l);
  }

  /// Maps a stored level onto one this catalogue knows, so a profile written
  /// before the Doctorate split still resolves.
  static String? canonicalLevel(String? level) {
    final l = (level ?? '').trim();
    if (l.isEmpty) return null;
    if (l == levelDoctorateLegacy) return levelPhd;
    final hit = levels.byValue(l);
    return hit?.en ?? l;
  }

  // ── Degrees, grouped by the level that owns them ──────────────────────────

  static const List<MasterOption> _below10 = [
    MasterOption(id: 'deg_no_formal', en: 'No Formal Education', ta: 'முறையான கல்வி இல்லை'),
    MasterOption(id: 'deg_below_sslc', en: 'Below SSLC', ta: 'எஸ்எஸ்எல்சிக்குக் கீழ்'),
  ];

  static const List<MasterOption> _iti = [
    MasterOption(id: 'deg_iti', en: 'ITI', ta: 'தொழிற்பயிற்சி'),
    MasterOption(id: 'deg_iti_fitter', en: 'ITI Fitter', ta: 'ஐடிஐ ஃபிட்டர்'),
    MasterOption(id: 'deg_iti_electrician', en: 'ITI Electrician', ta: 'ஐடிஐ மின் தொழில்நுட்பம்'),
    MasterOption(id: 'deg_iti_welder', en: 'ITI Welder', ta: 'ஐடிஐ பற்றவைப்பு'),
    MasterOption(id: 'deg_iti_mechanic', en: 'ITI Mechanic', ta: 'ஐடிஐ இயந்திரவியல்'),
    MasterOption(id: 'deg_iti_turner', en: 'ITI Turner', ta: 'ஐடிஐ டர்னர்'),
    MasterOption(id: 'deg_iti_copa', en: 'ITI COPA', ta: 'ஐடிஐ கணினி இயக்குநர்'),
  ];

  static const List<MasterOption> _diploma = [
    MasterOption(id: 'deg_diploma', en: 'Diploma', ta: 'பட்டயப் படிப்பு'),
    MasterOption(id: 'deg_polytechnic', en: 'Polytechnic', ta: 'பாலிடெக்னிக்'),
    MasterOption(id: 'deg_dpharm', en: 'D.Pharm', ta: 'மருந்தியல் பட்டயம்', aliases: ['pharmacy']),
    MasterOption(id: 'deg_dmlt', en: 'DMLT', ta: 'மருத்துவ ஆய்வகத் தொழில்நுட்பம்'),
    MasterOption(id: 'deg_gnm', en: 'GNM', ta: 'பொது செவிலியம் மற்றும் மகப்பேறு', aliases: ['nursing']),
    MasterOption(id: 'deg_anm', en: 'ANM', ta: 'துணை செவிலியர்', aliases: ['nursing']),
    MasterOption(id: 'deg_deled', en: 'D.El.Ed', ta: 'தொடக்கக் கல்வி பட்டயம்', aliases: ['teacher']),
    MasterOption(id: 'deg_ttc', en: 'TTC', ta: 'ஆசிரியர் பயிற்சி', aliases: ['teacher training']),
    MasterOption(id: 'deg_certificate', en: 'Certificate Course', ta: 'சான்றிதழ் படிப்பு'),
    MasterOption(id: 'deg_vocational', en: 'Vocational Training', ta: 'தொழிற்கல்வி பயிற்சி'),
  ];

  static const List<MasterOption> _ug = [
    MasterOption(id: 'deg_ba', en: 'B.A', ta: 'இளங்கலை கலை', aliases: ['arts']),
    MasterOption(id: 'deg_bsc', en: 'B.Sc', ta: 'இளங்கலை அறிவியல்', aliases: ['science']),
    MasterOption(id: 'deg_bcom', en: 'B.Com', ta: 'இளங்கலை வணிகவியல்', aliases: ['commerce']),
    MasterOption(
        id: 'deg_bsc_cs',
        en: 'B.Sc Computer Science',
        ta: 'இளங்கலை கணினி அறிவியல்',
        aliases: ['bsc cs', 'computer']),
    MasterOption(id: 'deg_bsc_it', en: 'B.Sc IT', ta: 'இளங்கலை தகவல் தொழில்நுட்பம்'),
    MasterOption(id: 'deg_bsc_nursing', en: 'B.Sc Nursing', ta: 'இளங்கலை செவிலியம்'),
    MasterOption(id: 'deg_bsc_agri', en: 'B.Sc Agriculture', ta: 'இளங்கலை வேளாண்மை'),
    MasterOption(
        id: 'deg_bsc_fashion', en: 'B.Sc Fashion Design', ta: 'இளங்கலை ஆடை வடிவமைப்பு'),
    MasterOption(id: 'deg_bfa', en: 'BFA', ta: 'இளங்கலை நுண்கலை'),
    MasterOption(id: 'deg_bsw', en: 'BSW', ta: 'இளங்கலை சமூகப் பணி'),
    MasterOption(id: 'deg_bjmc', en: 'BJMC', ta: 'இளங்கலை பத்திரிகையியல்'),
    MasterOption(id: 'deg_blibsc', en: 'B.Lib.Sc', ta: 'இளங்கலை நூலகவியல்'),
    MasterOption(id: 'deg_bms', en: 'BMS', ta: 'இளங்கலை மேலாண்மை அறிவியல்'),
    MasterOption(id: 'deg_bdes', en: 'B.Des', ta: 'இளங்கலை வடிவமைப்பு'),
    MasterOption(id: 'deg_bba', en: 'BBA', ta: 'இளங்கலை வணிக நிர்வாகம்'),
    MasterOption(id: 'deg_bca', en: 'BCA', ta: 'இளங்கலை கணினி பயன்பாடுகள்'),
    MasterOption(id: 'deg_bhm', en: 'BHM', ta: 'இளங்கலை விடுதி மேலாண்மை'),
    MasterOption(id: 'deg_be', en: 'B.E', ta: 'இளங்கலை பொறியியல்', aliases: ['engineering']),
    MasterOption(id: 'deg_btech', en: 'B.Tech', ta: 'இளங்கலை தொழில்நுட்பம்', aliases: ['engineering']),
    MasterOption(id: 'deg_barch', en: 'B.Arch', ta: 'இளங்கலை கட்டிடக்கலை'),
    MasterOption(id: 'deg_bplan', en: 'B.Plan', ta: 'இளங்கலை நகரத் திட்டமிடல்'),
    MasterOption(id: 'deg_mbbs', en: 'MBBS', ta: 'மருத்துவப் பட்டம்', aliases: ['doctor']),
    MasterOption(id: 'deg_bds', en: 'BDS', ta: 'பல் மருத்துவம்', aliases: ['dental']),
    MasterOption(id: 'deg_bams', en: 'BAMS', ta: 'ஆயுர்வேத மருத்துவம்'),
    MasterOption(id: 'deg_bhms', en: 'BHMS', ta: 'ஹோமியோபதி மருத்துவம்'),
    MasterOption(id: 'deg_bums', en: 'BUMS', ta: 'யுனானி மருத்துவம்'),
    MasterOption(id: 'deg_bsms', en: 'BSMS', ta: 'சித்த மருத்துவம்'),
    MasterOption(id: 'deg_bnys', en: 'BNYS', ta: 'இயற்கை மருத்துவம்'),
    MasterOption(id: 'deg_bvsc', en: 'B.V.Sc', ta: 'கால்நடை மருத்துவம்'),
    MasterOption(id: 'deg_bpharm', en: 'B.Pharm', ta: 'இளங்கலை மருந்தியல்'),
    MasterOption(id: 'deg_bpt', en: 'BPT', ta: 'இளங்கலை இயன்முறை மருத்துவம்'),
    MasterOption(id: 'deg_bed', en: 'B.Ed', ta: 'இளங்கலை கல்வியியல்', aliases: ['teacher']),
    MasterOption(id: 'deg_beled', en: 'B.El.Ed', ta: 'இளங்கலை தொடக்கக் கல்வி'),
    MasterOption(id: 'deg_llb', en: 'LLB', ta: 'சட்டப் பட்டம்', aliases: ['law']),
    MasterOption(id: 'deg_ba_llb', en: 'BA LLB', ta: 'கலை மற்றும் சட்டப் பட்டம்', aliases: ['law']),
    MasterOption(
        id: 'deg_bba_llb', en: 'BBA LLB', ta: 'வணிக நிர்வாகம் மற்றும் சட்டம்', aliases: ['law']),
    MasterOption(
        id: 'deg_bcom_llb', en: 'B.Com LLB', ta: 'வணிகவியல் மற்றும் சட்டம்', aliases: ['law']),
  ];

  static const List<MasterOption> _pg = [
    MasterOption(id: 'deg_ma', en: 'M.A', ta: 'முதுகலை கலை'),
    MasterOption(id: 'deg_msc', en: 'M.Sc', ta: 'முதுகலை அறிவியல்'),
    MasterOption(id: 'deg_mcom', en: 'M.Com', ta: 'முதுகலை வணிகவியல்'),
    MasterOption(id: 'deg_msc_cs', en: 'M.Sc Computer Science', ta: 'முதுகலை கணினி அறிவியல்'),
    MasterOption(id: 'deg_msc_it', en: 'M.Sc IT', ta: 'முதுகலை தகவல் தொழில்நுட்பம்'),
    MasterOption(id: 'deg_msc_nursing', en: 'M.Sc Nursing', ta: 'முதுகலை செவிலியம்'),
    MasterOption(id: 'deg_msc_agri', en: 'M.Sc Agriculture', ta: 'முதுகலை வேளாண்மை'),
    MasterOption(id: 'deg_mfa', en: 'MFA', ta: 'முதுகலை நுண்கலை'),
    MasterOption(id: 'deg_msw', en: 'MSW', ta: 'முதுகலை சமூகப் பணி'),
    MasterOption(id: 'deg_mlibsc', en: 'M.Lib.Sc', ta: 'முதுகலை நூலகவியல்'),
    MasterOption(
        id: 'deg_mba', en: 'MBA', ta: 'வணிக நிர்வாகவியல் முதுகலை', aliases: ['management']),
    MasterOption(id: 'deg_pg_diploma', en: 'PG Diploma', ta: 'முதுகலை பட்டயம்'),
    MasterOption(id: 'deg_mca', en: 'MCA', ta: 'முதுகலை கணினி பயன்பாடுகள்', aliases: ['computer']),
    MasterOption(id: 'deg_me', en: 'M.E', ta: 'முதுகலை பொறியியல்', aliases: ['engineering']),
    MasterOption(id: 'deg_mtech', en: 'M.Tech', ta: 'முதுகலை தொழில்நுட்பம்', aliases: ['engineering']),
    MasterOption(id: 'deg_march', en: 'M.Arch', ta: 'முதுகலை கட்டிடக்கலை'),
    MasterOption(id: 'deg_mdes', en: 'M.Des', ta: 'முதுகலை வடிவமைப்பு'),
    MasterOption(id: 'deg_md', en: 'MD', ta: 'மருத்துவ முதுகலை'),
    MasterOption(id: 'deg_ms', en: 'MS', ta: 'அறுவை மருத்துவ முதுகலை'),
    MasterOption(id: 'deg_mds', en: 'MDS', ta: 'பல் மருத்துவ முதுகலை'),
    MasterOption(id: 'deg_mpharm', en: 'M.Pharm', ta: 'முதுகலை மருந்தியல்'),
    MasterOption(id: 'deg_mpt', en: 'MPT', ta: 'முதுகலை இயன்முறை மருத்துவம்'),
    MasterOption(id: 'deg_med', en: 'M.Ed', ta: 'முதுகலை கல்வியியல்'),
    MasterOption(id: 'deg_llm', en: 'LLM', ta: 'முதுகலை சட்டம்', aliases: ['law']),
    MasterOption(id: 'deg_int_msc', en: 'Integrated M.Sc', ta: 'ஒருங்கிணைந்த முதுகலை அறிவியல்'),
  ];

  static const List<MasterOption> _mphil = [
    MasterOption(id: 'deg_mphil', en: 'M.Phil', ta: 'எம்.ஃபில்'),
  ];

  static const List<MasterOption> _phd = [
    MasterOption(id: 'deg_phd', en: 'Ph.D', ta: 'முனைவர் பட்டம்', aliases: ['phd', 'doctorate']),
    MasterOption(id: 'deg_dm', en: 'DM', ta: 'மருத்துவ முனைவர்'),
    MasterOption(id: 'deg_mch', en: 'M.Ch', ta: 'அறுவை மருத்துவ முனைவர்'),
    MasterOption(id: 'deg_dlitt', en: 'D.Litt', ta: 'இலக்கிய முனைவர்'),
    MasterOption(id: 'deg_post_doc', en: 'Post Doctorate', ta: 'முனைவருக்குப் பிந்தைய ஆய்வு'),
    MasterOption(id: 'deg_pharmd', en: 'Pharm.D', ta: 'மருந்தியல் முனைவர்'),
  ];

  /// Professional bodies — deliberately their own level (§3), because a CA or
  /// CS is not a university degree and members do not think of it as "PG".
  static const List<MasterOption> _professional = [
    MasterOption(id: 'deg_ca', en: 'CA', ta: 'பட்டயக் கணக்கர்', aliases: ['chartered accountant']),
    MasterOption(id: 'deg_cma', en: 'CMA', ta: 'செலவுக் கணக்கியல்', aliases: ['cost accountant']),
    MasterOption(id: 'deg_cs', en: 'CS', ta: 'நிறுவனச் செயலர்', aliases: ['company secretary']),
    MasterOption(id: 'deg_cfa', en: 'CFA', ta: 'பட்டய நிதி ஆய்வாளர்'),
    MasterOption(id: 'deg_acca', en: 'ACCA', ta: 'சான்றளிக்கப்பட்ட கணக்கர்'),
    MasterOption(id: 'deg_actuary', en: 'Actuarial Science', ta: 'ஆயுள் கணிப்பியல்'),
  ];

  /// Level → its degrees.
  static const Map<String, List<MasterOption>> degreesByLevel = {
    levelBelow10: _below10,
    level10: [MasterOption(id: 'deg_sslc', en: 'SSLC', ta: 'எஸ்எஸ்எல்சி')],
    level12: [MasterOption(id: 'deg_hsc', en: 'HSC', ta: 'ஹெச்எஸ்சி')],
    levelIti: _iti,
    levelDiploma: _diploma,
    levelUg: _ug,
    levelPg: _pg,
    levelMPhil: _mphil,
    levelPhd: _phd,
    levelProfessional: _professional,
  };

  /// Degrees offered for [level] (empty for schooling levels and unknown ones).
  static List<MasterOption> degreesFor(String? level) {
    final l = canonicalLevel(level);
    if (l == null || !levelHasDegrees(l)) return const [];
    return degreesByLevel[l] ?? const [];
  }

  /// Every degree in the catalogue, de-duplicated by canonical value.
  static List<MasterOption> get allDegrees {
    final seen = <String>{};
    final out = <MasterOption>[];
    for (final list in degreesByLevel.values) {
      for (final d in list) {
        if (seen.add(d.en.toLowerCase())) out.add(d);
      }
    }
    return out;
  }

  /// The level that owns [degree], or null for a custom ("Others") value.
  /// Lets a legacy profile that only stored the flat `education` string still
  /// render the Level → Degree hierarchy.
  static String? levelForDegree(String? degree) {
    final d = (degree ?? '').trim().toLowerCase();
    if (d.isEmpty) return null;
    for (final entry in degreesByLevel.entries) {
      for (final course in entry.value) {
        if (course.en.toLowerCase() == d) return entry.key;
      }
    }
    return null;
  }

  /// For a schooling level the qualification IS the level, so the wizard stores
  /// it without asking (§3).
  static String? implicitDegreeFor(String? level) {
    final l = canonicalLevel(level);
    if (l == null || !schoolingLevels.contains(l)) return null;
    final list = degreesByLevel[l] ?? const [];
    return list.length == 1 ? list.first.en : null;
  }

  /// Tamil-aware display for a stored degree value.
  static String degreeDisplay(String value, {required bool tamil}) =>
      allDegrees.byValue(value)?.display(tamil: tamil, withEnglish: true) ??
      value;

  /// Tamil-aware display for a stored level value.
  static String levelDisplay(String value, {required bool tamil}) =>
      levels.byValue(canonicalLevel(value))?.display(tamil: tamil) ?? value;
}

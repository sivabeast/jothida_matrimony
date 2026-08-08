import 'education_catalog.dart';
import 'master_option.dart';

/// One job title, with everything needed to place, rank and translate it.
class OccupationEntry {
  final MasterOption option;

  /// Employment TYPE ids this title can appear under. A doctor exists in
  /// government service, in a private hospital and in private practice, so
  /// titles deliberately belong to several buckets rather than exactly one.
  final Set<String> types;

  /// Roughly how much education the role normally expects (§6):
  /// 0 = none, 1 = school / ITI / diploma, 2 = a degree, 3 = PG or professional.
  ///
  /// This only ORDERS the list — every title stays searchable and selectable
  /// whatever the member studied, because plenty of people work outside their
  /// qualification and the spec is explicit that we must not restrict.
  final int tier;

  const OccupationEntry(this.option, this.types, this.tier);

  String get en => option.en;
}

/// Bilingual Employment master data: **Status → Type → Occupation** (§5–§7).
///
/// The three fields cascade. Picking வேலை நிலை decides which தொழில் முறை
/// options exist (and whether that field appears at all — a homemaker or a
/// student is not asked for a sector), and தொழில் முறை decides the occupation
/// list. Occupation ORDER then depends on what the member studied (§6).
///
/// Canonical English values are unchanged from the flat-list era so stored
/// profiles, filters and the website keep working; Tamil is display-only and
/// renders as "மென்பொருள் பொறியாளர் (Software Engineer)".
class OccupationCatalog {
  OccupationCatalog._();

  // ══════════════════════════════════════════════════════════════════════════
  // 1. Employment status (§5, field 1)
  // ══════════════════════════════════════════════════════════════════════════

  static const String statusEmployed = 'Employed';
  static const String statusSelfEmployed = 'Self Employed';
  static const String statusBusinessman = 'Businessman';
  static const String statusStudent = 'Student';
  static const String statusJobSeeker = 'Job Seeker';
  static const String statusHomemaker = 'Homemaker';
  static const String statusRetired = 'Retired';
  static const String statusOthers = 'Others';

  static const List<MasterOption> statuses = [
    MasterOption(id: 'emp_employed', en: statusEmployed, ta: 'பணியாளர்', aliases: ['job', 'salaried', 'working']),
    MasterOption(id: 'emp_self', en: statusSelfEmployed, ta: 'சுயதொழில்', aliases: ['self employed', 'own work']),
    MasterOption(id: 'emp_business', en: statusBusinessman, ta: 'வணிகர்', aliases: ['business', 'trader', 'merchant']),
    MasterOption(id: 'emp_student', en: statusStudent, ta: 'மாணவர்', aliases: ['studying']),
    MasterOption(id: 'emp_jobseeker', en: statusJobSeeker, ta: 'வேலை தேடுபவர்', aliases: ['unemployed', 'not working']),
    MasterOption(id: 'emp_homemaker', en: statusHomemaker, ta: 'இல்லத்தரசி', aliases: ['housewife', 'home maker']),
    MasterOption(id: 'emp_retired', en: statusRetired, ta: 'ஓய்வு பெற்றவர்', aliases: ['pensioner']),
    MasterOption(id: 'emp_others', en: statusOthers, ta: 'மற்றவை', aliases: ['other']),
  ];

  // ══════════════════════════════════════════════════════════════════════════
  // 2. Employment type (§5, field 2) — depends on the status
  // ══════════════════════════════════════════════════════════════════════════

  static const String typeGovernment = 'Government';
  static const String typePrivate = 'Private';
  static const String typePublicSector = 'Public Sector';
  static const String typeContract = 'Contract';
  static const String typeProfession = 'Profession';
  static const String typeFreelance = 'Freelance';
  static const String typeOnlineBusiness = 'Online Business';
  static const String typeAgriculture = 'Agriculture';
  static const String typeRetail = 'Retail';
  static const String typeWholesale = 'Wholesale';
  static const String typeManufacturing = 'Manufacturing';
  static const String typeTrading = 'Trading';
  static const String typeServices = 'Services';
  static const String typeImportExport = 'Import & Export';

  /// Legacy type value: 'Business' used to be a sector under Self Employed
  /// before வணிகர் became its own status. Old profiles still store it.
  static const String typeBusinessLegacy = 'Business';

  static const List<MasterOption> _employedTypes = [
    MasterOption(id: 'typ_government', en: typeGovernment, ta: 'அரசு', aliases: ['govt', 'government job']),
    MasterOption(id: 'typ_private', en: typePrivate, ta: 'தனியார்', aliases: ['private job', 'company']),
    MasterOption(id: 'typ_public_sector', en: typePublicSector, ta: 'பொதுத்துறை', aliases: ['psu', 'public']),
    MasterOption(id: 'typ_contract', en: typeContract, ta: 'ஒப்பந்த பணி', aliases: ['contract job', 'temporary']),
  ];

  static const List<MasterOption> _selfEmployedTypes = [
    MasterOption(id: 'typ_profession', en: typeProfession, ta: 'தொழில்முறை', aliases: ['practice', 'consultant']),
    MasterOption(id: 'typ_freelance', en: typeFreelance, ta: 'தன்னார்வப் பணி', aliases: ['freelancer', 'freelancing']),
    MasterOption(id: 'typ_online', en: typeOnlineBusiness, ta: 'இணையவழி வணிகம்', aliases: ['online', 'ecommerce']),
    MasterOption(id: 'typ_agriculture', en: typeAgriculture, ta: 'விவசாயம்', aliases: ['farming', 'agri']),
  ];

  static const List<MasterOption> _businessmanTypes = [
    MasterOption(id: 'typ_retail', en: typeRetail, ta: 'சில்லறை வணிகம்', aliases: ['shop', 'store']),
    MasterOption(id: 'typ_wholesale', en: typeWholesale, ta: 'மொத்த வணிகம்', aliases: ['bulk']),
    MasterOption(id: 'typ_manufacturing', en: typeManufacturing, ta: 'உற்பத்தி', aliases: ['factory', 'industry']),
    MasterOption(id: 'typ_trading', en: typeTrading, ta: 'வர்த்தகம்', aliases: ['trade']),
    MasterOption(id: 'typ_services', en: typeServices, ta: 'சேவைகள்', aliases: ['service']),
    MasterOption(id: 'typ_import_export', en: typeImportExport, ta: 'இறக்குமதி மற்றும் ஏற்றுமதி', aliases: ['import', 'export']),
  ];

  /// Employment types offered for [status]. Empty means the field is HIDDEN —
  /// a student, job seeker, homemaker, retiree or "other" is never asked for a
  /// sector (§5).
  static List<MasterOption> typesFor(String? status) {
    switch ((status ?? '').trim()) {
      case statusEmployed:
        return _employedTypes;
      case statusSelfEmployed:
        return _selfEmployedTypes;
      case statusBusinessman:
        return _businessmanTypes;
      default:
        return const [];
    }
  }

  /// Whether [status] continues into Type → Occupation at all.
  static bool statusHasOccupation(String? status) {
    final s = (status ?? '').trim();
    return s == statusEmployed ||
        s == statusSelfEmployed ||
        s == statusBusinessman;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 3. Occupations (§5, field 3) — tagged with their types and education tier
  // ══════════════════════════════════════════════════════════════════════════

  static const Set<String> _gov = {typeGovernment, typePublicSector};
  static const Set<String> _govPriv = {
    typeGovernment, typePrivate, typePublicSector, typeContract,
  };
  static const Set<String> _priv = {typePrivate, typeContract};
  static const Set<String> _privProf = {typePrivate, typeProfession};
  static const Set<String> _profFree = {typeProfession, typeFreelance};
  static const Set<String> _privProfFree = {
    typePrivate, typeProfession, typeFreelance,
  };
  static const Set<String> _agri = {typeAgriculture};
  static const Set<String> _online = {typeOnlineBusiness, typeFreelance};

  /// Every job title the app knows, once each.
  static const List<OccupationEntry> all = [
    // ── Software / IT ──────────────────────────────────────────────────────
    OccupationEntry(MasterOption(id: 'occ_software_engineer', en: 'Software Engineer', ta: 'மென்பொருள் பொறியாளர்', aliases: ['it', 'developer']), _priv, 2),
    OccupationEntry(MasterOption(id: 'occ_software_developer', en: 'Software Developer', ta: 'மென்பொருள் உருவாக்குநர்', aliases: ['it', 'programmer']), _privProfFree, 2),
    OccupationEntry(MasterOption(id: 'occ_web_developer', en: 'Web Developer', ta: 'இணையதள உருவாக்குநர்'), _privProfFree, 2),
    OccupationEntry(MasterOption(id: 'occ_mobile_dev', en: 'Mobile App Developer', ta: 'செயலி உருவாக்குநர்'), _privProfFree, 2),
    OccupationEntry(MasterOption(id: 'occ_data_scientist', en: 'Data Scientist', ta: 'தரவு அறிவியலாளர்'), _priv, 3),
    OccupationEntry(MasterOption(id: 'occ_data_analyst', en: 'Data Analyst', ta: 'தரவு ஆய்வாளர்'), _priv, 2),
    OccupationEntry(MasterOption(id: 'occ_business_analyst', en: 'Business Analyst', ta: 'வணிக ஆய்வாளர்'), _priv, 2),
    OccupationEntry(MasterOption(id: 'occ_qa_engineer', en: 'QA / Test Engineer', ta: 'தர சோதனைப் பொறியாளர்', aliases: ['testing', 'qa']), _priv, 2),
    OccupationEntry(MasterOption(id: 'occ_devops', en: 'DevOps Engineer', ta: 'டெவ்ஆப்ஸ் பொறியாளர்'), _priv, 2),
    OccupationEntry(MasterOption(id: 'occ_cloud_architect', en: 'Cloud Architect', ta: 'கிளவுட் கட்டமைப்பாளர்'), _priv, 3),
    OccupationEntry(MasterOption(id: 'occ_cybersecurity', en: 'Cybersecurity Analyst', ta: 'இணையப் பாதுகாப்பு ஆய்வாளர்'), _priv, 2),
    OccupationEntry(MasterOption(id: 'occ_network_engineer', en: 'Network Engineer', ta: 'வலையமைப்புப் பொறியாளர்'), _priv, 2),
    OccupationEntry(MasterOption(id: 'occ_dba', en: 'Database Administrator', ta: 'தரவுத்தள நிர்வாகி'), _priv, 2),
    OccupationEntry(MasterOption(id: 'occ_sysadmin', en: 'System Administrator', ta: 'கணினி அமைப்பு நிர்வாகி'), _priv, 2),
    OccupationEntry(MasterOption(id: 'occ_it_support', en: 'IT Support Engineer', ta: 'தகவல் தொழில்நுட்ப உதவிப் பொறியாளர்'), _priv, 1),
    OccupationEntry(MasterOption(id: 'occ_it_consultant', en: 'IT Consultant', ta: 'தகவல் தொழில்நுட்ப ஆலோசகர்'), _privProfFree, 3),
    OccupationEntry(MasterOption(id: 'occ_uiux', en: 'UI / UX Designer', ta: 'இடைமுக வடிவமைப்பாளர்', aliases: ['ui ux', 'designer']), _privProfFree, 2),
    OccupationEntry(MasterOption(id: 'occ_product_manager', en: 'Product Manager', ta: 'தயாரிப்பு மேலாளர்'), _priv, 3),
    OccupationEntry(MasterOption(id: 'occ_project_manager', en: 'Project Manager', ta: 'திட்ட மேலாளர்'), _priv, 2),

    // ── Engineering ────────────────────────────────────────────────────────
    OccupationEntry(MasterOption(id: 'occ_civil_engineer', en: 'Civil Engineer', ta: 'கட்டுமானப் பொறியாளர்'), _govPriv, 2),
    OccupationEntry(MasterOption(id: 'occ_mech_engineer', en: 'Mechanical Engineer', ta: 'இயந்திரப் பொறியாளர்'), _govPriv, 2),
    OccupationEntry(MasterOption(id: 'occ_elec_engineer', en: 'Electrical Engineer', ta: 'மின் பொறியாளர்'), _govPriv, 2),
    OccupationEntry(MasterOption(id: 'occ_electronics_engineer', en: 'Electronics Engineer', ta: 'மின்னணுப் பொறியாளர்'), _govPriv, 2),
    OccupationEntry(MasterOption(id: 'occ_chemical_engineer', en: 'Chemical Engineer', ta: 'வேதியியல் பொறியாளர்'), _govPriv, 2),
    OccupationEntry(MasterOption(id: 'occ_aero_engineer', en: 'Aeronautical Engineer', ta: 'வானூர்திப் பொறியாளர்'), _priv, 2),
    OccupationEntry(MasterOption(id: 'occ_auto_engineer', en: 'Automobile Engineer', ta: 'வாகனப் பொறியாளர்'), _priv, 2),
    OccupationEntry(MasterOption(id: 'occ_marine_engineer', en: 'Marine Engineer', ta: 'கடல்சார் பொறியாளர்'), _govPriv, 2),
    OccupationEntry(MasterOption(id: 'occ_site_engineer', en: 'Site Engineer', ta: 'பணியிடப் பொறியாளர்'), _govPriv, 2),
    OccupationEntry(MasterOption(id: 'occ_architect', en: 'Architect', ta: 'கட்டிடக் கலைஞர்'), _privProf, 2),

    // ── Medical / health ───────────────────────────────────────────────────
    OccupationEntry(MasterOption(id: 'occ_doctor', en: 'Doctor', ta: 'மருத்துவர்'), {typeGovernment, typePrivate, typePublicSector, typeProfession}, 3),
    OccupationEntry(MasterOption(id: 'occ_surgeon', en: 'Surgeon', ta: 'அறுவை சிகிச்சை மருத்துவர்'), {typeGovernment, typePrivate, typeProfession}, 3),
    OccupationEntry(MasterOption(id: 'occ_dentist', en: 'Dentist', ta: 'பல் மருத்துவர்'), {typeGovernment, typePrivate, typeProfession}, 3),
    OccupationEntry(MasterOption(id: 'occ_medical_officer', en: 'Medical Officer', ta: 'மருத்துவ அலுவலர்'), _govPriv, 3),
    OccupationEntry(MasterOption(id: 'occ_ayurvedic_doctor', en: 'Ayurvedic Doctor', ta: 'ஆயுர்வேத மருத்துவர்'), {typeGovernment, typePrivate, typeProfession}, 3),
    OccupationEntry(MasterOption(id: 'occ_veterinary', en: 'Veterinary Doctor', ta: 'கால்நடை மருத்துவர்'), {typeGovernment, typePrivate, typeProfession}, 3),
    OccupationEntry(MasterOption(id: 'occ_radiologist', en: 'Radiologist', ta: 'கதிரியக்க மருத்துவர்'), _govPriv, 3),
    OccupationEntry(MasterOption(id: 'occ_nurse', en: 'Nurse', ta: 'செவிலியர்'), _govPriv, 1),
    OccupationEntry(MasterOption(id: 'occ_pharmacist', en: 'Pharmacist', ta: 'மருந்தாளர்'), _govPriv, 1),
    OccupationEntry(MasterOption(id: 'occ_physiotherapist', en: 'Physiotherapist', ta: 'இயன்முறை மருத்துவர்'), _privProf, 2),
    OccupationEntry(MasterOption(id: 'occ_lab_technician', en: 'Lab Technician', ta: 'ஆய்வக உதவியாளர்'), _govPriv, 1),
    OccupationEntry(MasterOption(id: 'occ_optometrist', en: 'Optometrist', ta: 'கண் பரிசோதகர்'), _privProf, 2),
    OccupationEntry(MasterOption(id: 'occ_nutritionist', en: 'Nutritionist', ta: 'ஊட்டச்சத்து நிபுணர்'), _privProfFree, 2),
    OccupationEntry(MasterOption(id: 'occ_psychologist', en: 'Psychologist', ta: 'உளவியலாளர்'), _privProf, 3),

    // ── Teaching / research ────────────────────────────────────────────────
    OccupationEntry(MasterOption(id: 'occ_teacher', en: 'Teacher', ta: 'ஆசிரியர்'), _govPriv, 2),
    OccupationEntry(MasterOption(id: 'occ_lecturer', en: 'Lecturer', ta: 'விரிவுரையாளர்'), _govPriv, 3),
    OccupationEntry(MasterOption(id: 'occ_asst_professor', en: 'Assistant Professor', ta: 'உதவிப் பேராசிரியர்'), _govPriv, 3),
    OccupationEntry(MasterOption(id: 'occ_professor', en: 'Professor', ta: 'பேராசிரியர்'), _govPriv, 3),
    OccupationEntry(MasterOption(id: 'occ_principal', en: 'School Principal', ta: 'பள்ளித் தலைமையாசிரியர்'), _govPriv, 3),
    OccupationEntry(MasterOption(id: 'occ_scientist', en: 'Scientist', ta: 'அறிவியலாளர்'), _govPriv, 3),
    OccupationEntry(MasterOption(id: 'occ_research_scholar', en: 'Research Scholar', ta: 'ஆய்வு மாணவர்'), _govPriv, 3),
    OccupationEntry(MasterOption(id: 'occ_tutor', en: 'Tutor', ta: 'பயிற்றுநர்'), _privProfFree, 1),
    OccupationEntry(MasterOption(id: 'occ_librarian', en: 'Librarian', ta: 'நூலகர்'), _govPriv, 2),

    // ── Government / defence / civil ───────────────────────────────────────
    OccupationEntry(MasterOption(id: 'occ_civil_servant', en: 'Civil Servant (IAS / IPS / IFS)', ta: 'குடிமைப் பணி அலுவலர்', aliases: ['ias', 'ips', 'ifs', 'collector']), _gov, 3),
    OccupationEntry(MasterOption(id: 'occ_govt_employee', en: 'Government Employee', ta: 'அரசு ஊழியர்'), _gov, 1),
    OccupationEntry(MasterOption(id: 'occ_police', en: 'Police Officer', ta: 'காவல் அலுவலர்'), _gov, 1),
    OccupationEntry(MasterOption(id: 'occ_army', en: 'Army Personnel', ta: 'இராணுவப் பணியாளர்'), _gov, 1),
    OccupationEntry(MasterOption(id: 'occ_navy', en: 'Navy Personnel', ta: 'கடற்படைப் பணியாளர்'), _gov, 1),
    OccupationEntry(MasterOption(id: 'occ_airforce', en: 'Air Force Personnel', ta: 'விமானப்படைப் பணியாளர்'), _gov, 1),
    OccupationEntry(MasterOption(id: 'occ_fire_officer', en: 'Fire & Rescue Officer', ta: 'தீயணைப்பு அலுவலர்'), _gov, 1),
    OccupationEntry(MasterOption(id: 'occ_railway', en: 'Railway Employee', ta: 'இரயில்வே ஊழியர்'), _gov, 1),
    OccupationEntry(MasterOption(id: 'occ_postal', en: 'Postal Employee', ta: 'அஞ்சல் ஊழியர்'), _gov, 1),
    OccupationEntry(MasterOption(id: 'occ_admin_officer', en: 'Administrative Officer', ta: 'நிர்வாக அலுவலர்'), _govPriv, 2),
    OccupationEntry(MasterOption(id: 'occ_judge', en: 'Judge', ta: 'நீதிபதி'), _gov, 3),

    // ── Law / finance ──────────────────────────────────────────────────────
    OccupationEntry(MasterOption(id: 'occ_advocate', en: 'Advocate', ta: 'வழக்கறிஞர்'), {typeGovernment, typePrivate, typeProfession}, 3),
    OccupationEntry(MasterOption(id: 'occ_lawyer', en: 'Lawyer', ta: 'வழக்குரைஞர்'), _privProf, 3),
    OccupationEntry(MasterOption(id: 'occ_legal_advisor', en: 'Legal Advisor', ta: 'சட்ட ஆலோசகர்'), {typeGovernment, typePrivate, typeProfession}, 3),
    OccupationEntry(MasterOption(id: 'occ_ca', en: 'Chartered Accountant', ta: 'பட்டயக் கணக்கர்', aliases: ['ca']), _privProf, 3),
    OccupationEntry(MasterOption(id: 'occ_cost_accountant', en: 'Cost Accountant', ta: 'செலவுக் கணக்கர்'), _privProf, 3),
    OccupationEntry(MasterOption(id: 'occ_company_secretary', en: 'Company Secretary', ta: 'நிறுவனச் செயலர்'), _privProf, 3),
    OccupationEntry(MasterOption(id: 'occ_accountant', en: 'Accountant', ta: 'கணக்காளர்'), _priv, 2),
    OccupationEntry(MasterOption(id: 'occ_auditor', en: 'Auditor', ta: 'தணிக்கையாளர்'), _govPriv, 2),
    OccupationEntry(MasterOption(id: 'occ_bank_employee', en: 'Bank Employee', ta: 'வங்கி ஊழியர்'), _govPriv, 2),
    OccupationEntry(MasterOption(id: 'occ_bank_officer', en: 'Bank Officer', ta: 'வங்கி அலுவலர்'), _govPriv, 2),
    OccupationEntry(MasterOption(id: 'occ_financial_analyst', en: 'Financial Analyst', ta: 'நிதி ஆய்வாளர்'), _priv, 2),
    OccupationEntry(MasterOption(id: 'occ_investment_banker', en: 'Investment Banker', ta: 'முதலீட்டு வங்கியாளர்'), _priv, 3),
    OccupationEntry(MasterOption(id: 'occ_stock_broker', en: 'Stock Broker', ta: 'பங்கு தரகர்'), _privProf, 2),
    OccupationEntry(MasterOption(id: 'occ_tax_consultant', en: 'Tax Consultant', ta: 'வரி ஆலோசகர்'), _profFree, 2),
    OccupationEntry(MasterOption(id: 'occ_insurance_agent', en: 'Insurance Agent', ta: 'காப்பீட்டு முகவர்'), {typePrivate, typeProfession, typeServices}, 1),

    // ── Business / management ──────────────────────────────────────────────
    OccupationEntry(MasterOption(id: 'occ_business_owner', en: 'Business Owner', ta: 'வணிக உரிமையாளர்'), {typeRetail, typeWholesale, typeManufacturing, typeTrading, typeServices, typeImportExport}, 1),
    OccupationEntry(MasterOption(id: 'occ_shop_owner', en: 'Shop Owner', ta: 'கடை உரிமையாளர்'), {typeRetail, typeServices}, 0),
    OccupationEntry(MasterOption(id: 'occ_trader', en: 'Trader', ta: 'வர்த்தகர்'), {typeTrading, typeWholesale, typeImportExport}, 1),
    OccupationEntry(MasterOption(id: 'occ_entrepreneur', en: 'Entrepreneur', ta: 'தொழில்முனைவோர்'), {typeManufacturing, typeServices, typeTrading, typeOnlineBusiness}, 2),
    OccupationEntry(MasterOption(id: 'occ_startup_founder', en: 'Startup Founder', ta: 'ஸ்டார்ட்அப் நிறுவனர்'), {typeServices, typeOnlineBusiness, typeManufacturing}, 2),
    OccupationEntry(MasterOption(id: 'occ_contractor', en: 'Contractor', ta: 'ஒப்பந்ததாரர்'), {typeServices, typeManufacturing, typeContract}, 1),
    OccupationEntry(MasterOption(id: 'occ_civil_contractor', en: 'Civil Contractor', ta: 'கட்டுமான ஒப்பந்ததாரர்'), {typeServices, typeManufacturing}, 1),
    OccupationEntry(MasterOption(id: 'occ_real_estate', en: 'Real Estate Agent', ta: 'அசையா சொத்து முகவர்'), {typeServices, typeTrading, typeProfession}, 1),
    OccupationEntry(MasterOption(id: 'occ_hr_manager', en: 'HR Manager', ta: 'மனிதவள மேலாளர்'), _priv, 2),
    OccupationEntry(MasterOption(id: 'occ_marketing_exec', en: 'Marketing Executive', ta: 'சந்தைப்படுத்தல் அலுவலர்'), _priv, 2),
    OccupationEntry(MasterOption(id: 'occ_sales_exec', en: 'Sales Executive', ta: 'விற்பனை அலுவலர்'), _priv, 1),
    OccupationEntry(MasterOption(id: 'occ_logistics_manager', en: 'Logistics Manager', ta: 'சரக்கு மேலாண்மையாளர்'), {typePrivate, typeServices, typeImportExport}, 2),
    OccupationEntry(MasterOption(id: 'occ_hotel_manager', en: 'Hotel Manager', ta: 'விடுதி மேலாளர்'), {typePrivate, typeServices}, 2),
    OccupationEntry(MasterOption(id: 'occ_event_manager', en: 'Event Manager', ta: 'நிகழ்ச்சி மேலாளர்'), {typePrivate, typeProfession, typeServices}, 1),
    OccupationEntry(MasterOption(id: 'occ_travel_agent', en: 'Travel Agent', ta: 'பயண முகவர்'), {typePrivate, typeServices, typeOnlineBusiness}, 1),
    OccupationEntry(MasterOption(id: 'occ_consultant', en: 'Consultant', ta: 'ஆலோசகர்'), _privProfFree, 3),

    // ── Media / creative ───────────────────────────────────────────────────
    OccupationEntry(MasterOption(id: 'occ_journalist', en: 'Journalist', ta: 'பத்திரிகையாளர்'), _privProfFree, 2),
    OccupationEntry(MasterOption(id: 'occ_news_anchor', en: 'News Anchor', ta: 'செய்தி வாசிப்பாளர்'), _priv, 2),
    OccupationEntry(MasterOption(id: 'occ_editor', en: 'Editor', ta: 'ஆசிரியர் (பதிப்பு)'), _privProfFree, 2),
    OccupationEntry(MasterOption(id: 'occ_writer', en: 'Writer', ta: 'எழுத்தாளர்'), _profFree, 2),
    OccupationEntry(MasterOption(id: 'occ_content_creator', en: 'Content Creator', ta: 'உள்ளடக்க உருவாக்குநர்'), _online, 1),
    OccupationEntry(MasterOption(id: 'occ_graphic_designer', en: 'Graphic Designer', ta: 'வரைகலை வடிவமைப்பாளர்'), _privProfFree, 1),
    OccupationEntry(MasterOption(id: 'occ_photographer', en: 'Photographer', ta: 'ஒளிப்படக் கலைஞர்'), _profFree, 1),
    OccupationEntry(MasterOption(id: 'occ_video_editor', en: 'Video Editor', ta: 'காணொளி தொகுப்பாளர்'), _privProfFree, 1),
    OccupationEntry(MasterOption(id: 'occ_animator', en: 'Animator', ta: 'அசைவூட்டக் கலைஞர்'), _privProfFree, 2),
    OccupationEntry(MasterOption(id: 'occ_film_director', en: 'Film Director', ta: 'திரைப்பட இயக்குநர்'), _profFree, 2),
    OccupationEntry(MasterOption(id: 'occ_actor', en: 'Actor', ta: 'நடிகர்'), _profFree, 1),
    OccupationEntry(MasterOption(id: 'occ_singer', en: 'Singer', ta: 'பாடகர்'), _profFree, 1),
    OccupationEntry(MasterOption(id: 'occ_musician', en: 'Musician', ta: 'இசைக்கலைஞர்'), _profFree, 1),
    OccupationEntry(MasterOption(id: 'occ_dancer', en: 'Dancer', ta: 'நடனக் கலைஞர்'), _profFree, 1),
    OccupationEntry(MasterOption(id: 'occ_artist', en: 'Artist', ta: 'ஓவியர்'), _profFree, 1),
    OccupationEntry(MasterOption(id: 'occ_fashion_designer', en: 'Fashion Designer', ta: 'ஆடை வடிவமைப்பாளர்'), _privProfFree, 2),
    OccupationEntry(MasterOption(id: 'occ_interior_designer', en: 'Interior Designer', ta: 'உள்ளக வடிவமைப்பாளர்'), _privProfFree, 2),

    // ── Skilled trades / services (no degree expected) ─────────────────────
    OccupationEntry(MasterOption(id: 'occ_electrician', en: 'Electrician', ta: 'மின் பணியாளர்'), {typePrivate, typeProfession, typeContract, typeServices}, 0),
    OccupationEntry(MasterOption(id: 'occ_plumber', en: 'Plumber', ta: 'குழாய் பணியாளர்'), {typePrivate, typeProfession, typeContract, typeServices}, 0),
    OccupationEntry(MasterOption(id: 'occ_carpenter', en: 'Carpenter', ta: 'தச்சர்'), {typePrivate, typeProfession, typeContract, typeServices}, 0),
    OccupationEntry(MasterOption(id: 'occ_welder', en: 'Welder', ta: 'பற்றவைப்புத் தொழிலாளி'), {typePrivate, typeContract, typeManufacturing}, 0),
    OccupationEntry(MasterOption(id: 'occ_mechanic', en: 'Mechanic', ta: 'இயந்திர பழுதுநீக்குநர்'), {typePrivate, typeProfession, typeServices}, 0),
    OccupationEntry(MasterOption(id: 'occ_technician', en: 'Technician', ta: 'தொழில்நுட்ப உதவியாளர்'), _govPriv, 1),
    OccupationEntry(MasterOption(id: 'occ_driver', en: 'Driver', ta: 'ஓட்டுநர்'), {typeGovernment, typePrivate, typeContract, typeServices}, 0),
    OccupationEntry(MasterOption(id: 'occ_tailor', en: 'Tailor', ta: 'தையல் கலைஞர்'), {typePrivate, typeProfession, typeRetail}, 0),
    OccupationEntry(MasterOption(id: 'occ_goldsmith', en: 'Goldsmith', ta: 'பொற்கொல்லர்'), {typePrivate, typeProfession, typeRetail}, 0),
    OccupationEntry(MasterOption(id: 'occ_beautician', en: 'Beautician', ta: 'அழகுக் கலைஞர்'), {typePrivate, typeProfession, typeServices}, 0),
    OccupationEntry(MasterOption(id: 'occ_chef', en: 'Chef', ta: 'சமையல் கலைஞர்'), {typePrivate, typeProfession, typeServices}, 1),
    OccupationEntry(MasterOption(id: 'occ_delivery', en: 'Delivery Executive', ta: 'விநியோகப் பணியாளர்'), _priv, 0),
    OccupationEntry(MasterOption(id: 'occ_receptionist', en: 'Receptionist', ta: 'வரவேற்பாளர்'), _priv, 1),
    OccupationEntry(MasterOption(id: 'occ_clerk', en: 'Clerk', ta: 'எழுத்தர்'), _govPriv, 1),
    OccupationEntry(MasterOption(id: 'occ_data_entry', en: 'Data Entry Operator', ta: 'தரவு பதிவாளர்'), _govPriv, 1),
    OccupationEntry(MasterOption(id: 'occ_social_worker', en: 'Social Worker', ta: 'சமூக சேவகர்'), _govPriv, 2),

    // ── Transport / aviation / marine ──────────────────────────────────────
    OccupationEntry(MasterOption(id: 'occ_pilot', en: 'Pilot', ta: 'விமானி'), _priv, 2),
    OccupationEntry(MasterOption(id: 'occ_flight_attendant', en: 'Flight Attendant', ta: 'விமானப் பணிப்பெண்/பணியாளர்'), _priv, 1),
    OccupationEntry(MasterOption(id: 'occ_ship_captain', en: 'Ship Captain', ta: 'கப்பல் தலைவர்'), _priv, 2),

    // ── Agriculture ────────────────────────────────────────────────────────
    OccupationEntry(MasterOption(id: 'occ_farmer', en: 'Farmer', ta: 'விவசாயி'), _agri, 0),
    OccupationEntry(MasterOption(id: 'occ_agriculturist', en: 'Agriculturist', ta: 'வேளாண் நிபுணர்'), {typeAgriculture, typeGovernment}, 2),
    OccupationEntry(MasterOption(id: 'occ_horticulturist', en: 'Horticulturist', ta: 'தோட்டக்கலை நிபுணர்'), {typeAgriculture, typeGovernment}, 2),
    OccupationEntry(MasterOption(id: 'occ_dairy_farmer', en: 'Dairy Farmer', ta: 'பால் பண்ணையாளர்'), _agri, 0),
    OccupationEntry(MasterOption(id: 'occ_poultry_farmer', en: 'Poultry Farmer', ta: 'கோழிப் பண்ணையாளர்'), _agri, 0),
    OccupationEntry(MasterOption(id: 'occ_fisherman', en: 'Fisherman', ta: 'மீனவர்'), _agri, 0),

    // ── Independent / online ───────────────────────────────────────────────
    OccupationEntry(MasterOption(id: 'occ_freelancer', en: 'Freelancer', ta: 'தன்னார்வப் பணியாளர்'), {typeFreelance}, 1),
    OccupationEntry(MasterOption(id: 'occ_online_seller', en: 'Online Seller', ta: 'இணையவழி விற்பனையாளர்'), {typeOnlineBusiness}, 0),
    OccupationEntry(MasterOption(id: 'occ_digital_marketer', en: 'Digital Marketer', ta: 'இணைய சந்தைப்படுத்துநர்'), {typeOnlineBusiness, typeFreelance, typePrivate}, 1),
    OccupationEntry(MasterOption(id: 'occ_self_employed', en: 'Self Employed', ta: 'சுயதொழில் செய்பவர்'), {typeProfession, typeServices}, 0),
  ];

  /// Canonical `occupation` value for a status that has no occupation step, so
  /// every stored value stays a valid catalogue entry.
  static const Map<String, String> _valueForStatus = {
    statusStudent: 'Student',
    statusJobSeeker: 'Not Working',
    statusHomemaker: 'Homemaker',
    statusRetired: 'Retired',
    statusOthers: 'Others',
  };

  /// What to store in `occupation` for [status] given the [picked] title.
  static String occupationValueFor(String? status, String? picked) =>
      statusHasOccupation(status)
          ? (picked ?? '')
          : (_valueForStatus[(status ?? '').trim()] ?? '');

  // ══════════════════════════════════════════════════════════════════════════
  // Education-aware ordering (§6)
  // ══════════════════════════════════════════════════════════════════════════

  /// How far the member studied, on the same 0–3 scale as [OccupationEntry.tier].
  static int educationTier(String? level) {
    switch (EducationCatalog.canonicalLevel(level)) {
      case EducationCatalog.levelBelow10:
      case EducationCatalog.level10:
        return 0;
      case EducationCatalog.level12:
      case EducationCatalog.levelIti:
      case EducationCatalog.levelDiploma:
        return 1;
      case EducationCatalog.levelUg:
        return 2;
      case EducationCatalog.levelPg:
      case EducationCatalog.levelMPhil:
      case EducationCatalog.levelPhd:
      case EducationCatalog.levelProfessional:
        return 3;
      default:
        return -1; // unknown → don't re-order
    }
  }

  /// Occupations for a status + type pair, ordered by how well they fit
  /// [educationLevel] (§6).
  ///
  /// Nothing is filtered out. A 10th-pass member still finds "Software
  /// Engineer" by typing it — it simply is not what the list opens on. When the
  /// education level is unknown the list stays alphabetical.
  static List<MasterOption> occupationsFor({
    String? status,
    String? type,
    String? educationLevel,
  }) {
    if (!statusHasOccupation(status)) return const [];
    final t = (type ?? '').trim();
    if (t.isEmpty) return const [];

    // 'Business' was a Self Employed sector before வணிகர் became its own
    // status; treat a legacy value as the closest current bucket.
    final wanted = t == typeBusinessLegacy ? typeTrading : t;
    final matching = [
      for (final e in all)
        if (e.types.contains(wanted)) e,
    ];

    final memberTier = educationTier(educationLevel);
    matching.sort((a, b) {
      if (memberTier >= 0) {
        final da = (a.tier - memberTier).abs();
        final db = (b.tier - memberTier).abs();
        if (da != db) return da.compareTo(db);
      }
      return a.en.toLowerCase().compareTo(b.en.toLowerCase());
    });
    return [for (final e in matching) e.option];
  }

  /// Every job title, alphabetical — for the flat lists that filters and
  /// Partner Preferences still need.
  static List<MasterOption> get allOccupations {
    final list = [for (final e in all) e.option]
      ..sort((a, b) => a.en.toLowerCase().compareTo(b.en.toLowerCase()));
    return list;
  }

  /// Tamil-aware display for a stored occupation value.
  static String occupationDisplay(String value, {required bool tamil}) =>
      allOccupations.byValue(value)?.display(tamil: tamil, withEnglish: true) ??
      value;

  /// Tamil-aware display for a stored employment status.
  static String statusDisplay(String value, {required bool tamil}) =>
      statuses.byValue(value)?.display(tamil: tamil) ?? value;

  /// Tamil-aware display for a stored employment type.
  static String typeDisplay(String value, {required bool tamil}) {
    for (final list in [_employedTypes, _selfEmployedTypes, _businessmanTypes]) {
      final hit = list.byValue(value);
      if (hit != null) return hit.display(tamil: tamil);
    }
    return value;
  }

  /// Best-effort status for a legacy profile that only stored the flat
  /// `occupation` string.
  static String? statusForOccupation(String? occupation, {String? employmentType}) {
    final o = (occupation ?? '').trim().toLowerCase();
    if (o.isEmpty) return null;
    if (o == 'student') return statusStudent;
    if (o == 'not working') return statusJobSeeker;
    if (o == 'homemaker') return statusHomemaker;
    if (o == 'retired') return statusRetired;

    final type = (employmentType ?? '').trim();
    if (_businessmanTypes.byValue(type) != null) return statusBusinessman;
    if (_selfEmployedTypes.byValue(type) != null) return statusSelfEmployed;
    if (_employedTypes.byValue(type) != null) return statusEmployed;
    if (type == typeBusinessLegacy || type == statusSelfEmployed) {
      return statusSelfEmployed;
    }
    if (o == 'self employed' || o == 'freelancer') return statusSelfEmployed;
    if (o == 'business owner' || o == 'shop owner' || o == 'trader') {
      return statusBusinessman;
    }
    return statusEmployed;
  }

  /// Best-effort employment type for a legacy profile.
  static String? typeForOccupation(String? occupation, {String? employmentType}) {
    final type = (employmentType ?? '').trim();
    for (final list in [_employedTypes, _selfEmployedTypes, _businessmanTypes]) {
      if (list.byValue(type) != null) return list.byValue(type)!.en;
    }
    if (type == typeBusinessLegacy) return typeTrading;
    if (type == statusSelfEmployed) return typeProfession;

    final o = (occupation ?? '').trim().toLowerCase();
    if (o.isEmpty) return null;
    for (final e in all) {
      if (e.en.toLowerCase() == o) {
        // Prefer the most common bucket the title belongs to.
        for (final preferred in [
          typePrivate, typeGovernment, typeProfession, typeTrading,
          typeAgriculture, typeServices, typeFreelance, typeOnlineBusiness,
        ]) {
          if (e.types.contains(preferred)) return preferred;
        }
        return e.types.first;
      }
    }
    return null;
  }
}

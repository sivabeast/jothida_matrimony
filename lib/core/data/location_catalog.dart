import 'master_option.dart';

/// Bilingual Country and State master data (§7, §9).
///
/// Depth is deliberately India-shaped: the platform serves Tamil Nadu, so
/// **districts and cities are only modelled for Tamil Nadu** (all 38 districts
/// and 1055 towns, already shipped in `assets/master_data/location/` and served
/// by `LocationRepository`). Countries and states exist so an NRI member can
/// still say where they live, and every one of them carries a Tamil name plus
/// the spellings people actually type.
///
/// Search aliases matter most here: a member reading விருதுநகர் types
/// "virudhu", and one reading "Tiruchirappalli" types "trichy". Aliases are
/// matched, never displayed.
class LocationCatalog {
  LocationCatalog._();

  static const String defaultCountry = 'India';
  static const String defaultState = 'Tamil Nadu';

  /// Countries, India first (the overwhelming majority), then the destinations
  /// Tamil families actually migrate to, then the rest alphabetically.
  static const List<MasterOption> countries = [
    MasterOption(id: 'ctry_india', en: 'India', ta: 'இந்தியா', aliases: ['bharat', 'hindustan']),
    MasterOption(id: 'ctry_usa', en: 'USA', ta: 'அமெரிக்கா', aliases: ['united states', 'america', 'us']),
    MasterOption(id: 'ctry_uk', en: 'UK', ta: 'இங்கிலாந்து', aliases: ['united kingdom', 'britain', 'england']),
    MasterOption(id: 'ctry_canada', en: 'Canada', ta: 'கனடா'),
    MasterOption(id: 'ctry_australia', en: 'Australia', ta: 'ஆஸ்திரேலியா'),
    MasterOption(id: 'ctry_uae', en: 'UAE', ta: 'ஐக்கிய அரபு அமீரகம்', aliases: ['dubai', 'abu dhabi', 'emirates']),
    MasterOption(id: 'ctry_singapore', en: 'Singapore', ta: 'சிங்கப்பூர்'),
    MasterOption(id: 'ctry_malaysia', en: 'Malaysia', ta: 'மலேசியா'),
    MasterOption(id: 'ctry_srilanka', en: 'Sri Lanka', ta: 'இலங்கை', aliases: ['ceylon', 'eelam']),
    MasterOption(id: 'ctry_qatar', en: 'Qatar', ta: 'கத்தார்'),
    MasterOption(id: 'ctry_saudi', en: 'Saudi Arabia', ta: 'சவூதி அரேபியா'),
    MasterOption(id: 'ctry_kuwait', en: 'Kuwait', ta: 'குவைத்'),
    MasterOption(id: 'ctry_oman', en: 'Oman', ta: 'ஓமான்'),
    MasterOption(id: 'ctry_bahrain', en: 'Bahrain', ta: 'பஹ்ரைன்'),
    MasterOption(id: 'ctry_germany', en: 'Germany', ta: 'ஜெர்மனி'),
    MasterOption(id: 'ctry_france', en: 'France', ta: 'பிரான்ஸ்'),
    MasterOption(id: 'ctry_switzerland', en: 'Switzerland', ta: 'சுவிட்சர்லாந்து'),
    MasterOption(id: 'ctry_netherlands', en: 'Netherlands', ta: 'நெதர்லாந்து', aliases: ['holland']),
    MasterOption(id: 'ctry_ireland', en: 'Ireland', ta: 'அயர்லாந்து'),
    MasterOption(id: 'ctry_newzealand', en: 'New Zealand', ta: 'நியூசிலாந்து'),
    MasterOption(id: 'ctry_southafrica', en: 'South Africa', ta: 'தென்னாப்பிரிக்கா'),
    MasterOption(id: 'ctry_japan', en: 'Japan', ta: 'ஜப்பான்'),
    MasterOption(id: 'ctry_china', en: 'China', ta: 'சீனா'),
    MasterOption(id: 'ctry_hongkong', en: 'Hong Kong', ta: 'ஹாங்காங்'),
    MasterOption(id: 'ctry_other', en: 'Other', ta: 'மற்றவை'),
  ];

  /// All 28 Indian states and 8 union territories, Tamil Nadu first.
  static const List<MasterOption> indianStates = [
    MasterOption(id: 'st_tn', en: 'Tamil Nadu', ta: 'தமிழ்நாடு', aliases: ['tamilnadu', 'tn']),
    MasterOption(id: 'st_kerala', en: 'Kerala', ta: 'கேரளா', aliases: ['keralam']),
    MasterOption(id: 'st_karnataka', en: 'Karnataka', ta: 'கர்நாடகா', aliases: ['bangalore', 'mysore']),
    MasterOption(id: 'st_ap', en: 'Andhra Pradesh', ta: 'ஆந்திரப் பிரதேசம்', aliases: ['ap']),
    MasterOption(id: 'st_telangana', en: 'Telangana', ta: 'தெலங்கானா', aliases: ['hyderabad']),
    MasterOption(id: 'st_puducherry', en: 'Puducherry', ta: 'புதுச்சேரி', aliases: ['pondicherry', 'pondy']),
    MasterOption(id: 'st_maharashtra', en: 'Maharashtra', ta: 'மகாராஷ்டிரா', aliases: ['mumbai', 'pune']),
    MasterOption(id: 'st_gujarat', en: 'Gujarat', ta: 'குஜராத்'),
    MasterOption(id: 'st_rajasthan', en: 'Rajasthan', ta: 'ராஜஸ்தான்'),
    MasterOption(id: 'st_up', en: 'Uttar Pradesh', ta: 'உத்தரப் பிரதேசம்', aliases: ['up']),
    MasterOption(id: 'st_mp', en: 'Madhya Pradesh', ta: 'மத்தியப் பிரதேசம்', aliases: ['mp']),
    MasterOption(id: 'st_wb', en: 'West Bengal', ta: 'மேற்கு வங்காளம்', aliases: ['kolkata', 'bengal']),
    MasterOption(id: 'st_bihar', en: 'Bihar', ta: 'பீகார்'),
    MasterOption(id: 'st_odisha', en: 'Odisha', ta: 'ஒடிசா', aliases: ['orissa']),
    MasterOption(id: 'st_punjab', en: 'Punjab', ta: 'பஞ்சாப்'),
    MasterOption(id: 'st_haryana', en: 'Haryana', ta: 'ஹரியானா'),
    MasterOption(id: 'st_delhi', en: 'Delhi', ta: 'டெல்லி', aliases: ['new delhi', 'ncr']),
    MasterOption(id: 'st_hp', en: 'Himachal Pradesh', ta: 'இமாசலப் பிரதேசம்'),
    MasterOption(id: 'st_uttarakhand', en: 'Uttarakhand', ta: 'உத்தராகண்ட்'),
    MasterOption(id: 'st_goa', en: 'Goa', ta: 'கோவா'),
    MasterOption(id: 'st_chhattisgarh', en: 'Chhattisgarh', ta: 'சத்தீஸ்கர்'),
    MasterOption(id: 'st_jharkhand', en: 'Jharkhand', ta: 'ஜார்க்கண்ட்'),
    MasterOption(id: 'st_assam', en: 'Assam', ta: 'அசாம்'),
    MasterOption(id: 'st_jk', en: 'Jammu and Kashmir', ta: 'ஜம்மு காஷ்மீர்', aliases: ['kashmir', 'jk']),
    MasterOption(id: 'st_ladakh', en: 'Ladakh', ta: 'லடாக்'),
    MasterOption(id: 'st_arunachal', en: 'Arunachal Pradesh', ta: 'அருணாசலப் பிரதேசம்'),
    MasterOption(id: 'st_manipur', en: 'Manipur', ta: 'மணிப்பூர்'),
    MasterOption(id: 'st_meghalaya', en: 'Meghalaya', ta: 'மேகாலயா'),
    MasterOption(id: 'st_mizoram', en: 'Mizoram', ta: 'மிசோரம்'),
    MasterOption(id: 'st_nagaland', en: 'Nagaland', ta: 'நாகாலாந்து'),
    MasterOption(id: 'st_sikkim', en: 'Sikkim', ta: 'சிக்கிம்'),
    MasterOption(id: 'st_tripura', en: 'Tripura', ta: 'திரிபுரா'),
    MasterOption(id: 'st_andaman', en: 'Andaman and Nicobar Islands', ta: 'அந்தமான் நிக்கோபார் தீவுகள்', aliases: ['andaman', 'nicobar']),
    MasterOption(id: 'st_chandigarh', en: 'Chandigarh', ta: 'சண்டிகர்'),
    MasterOption(id: 'st_dnh', en: 'Dadra and Nagar Haveli and Daman and Diu', ta: 'தாத்ரா நகர் ஹவேலி மற்றும் தாமன் தியூ', aliases: ['daman', 'diu', 'dadra']),
    MasterOption(id: 'st_lakshadweep', en: 'Lakshadweep', ta: 'லட்சத்தீவு'),
    MasterOption(id: 'st_other', en: 'Other', ta: 'மற்றவை'),
  ];

  /// Search aliases for the Tamil Nadu districts whose common name differs from
  /// their official one. The district list itself lives in
  /// `assets/master_data/location/districts_{en,ta}.json`; this only teaches
  /// the search box the nicknames people actually type (§9).
  static const Map<String, List<String>> districtAliases = {
    'Tiruchirappalli': ['trichy', 'tiruchi', 'thiruchirapalli'],
    'Thoothukkudi': ['tuticorin', 'thoothukudi'],
    'Tirunelveli': ['nellai', 'thirunelveli'],
    'Kanniyakumari': ['kanyakumari', 'nagercoil', 'kk district'],
    'Virudhunagar': ['virudunagar', 'virudhu nagar', 'viruthunagar'],
    'Villupuram': ['viluppuram'],
    'Thiruvananthapuram': ['trivandrum'],
    'Tiruvannamalai': ['thiruvannamalai', 'tiruvanamalai'],
    'Tiruppur': ['tirupur', 'thirupur'],
    'Tiruvallur': ['thiruvallur'],
    'Tiruvarur': ['thiruvarur'],
    'Sivagangai': ['sivaganga'],
    'Ramanathapuram': ['ramnad'],
    'Nagapattinam': ['nagai'],
    'Kancheepuram': ['kanchipuram', 'kanchi'],
    'Thanjavur': ['tanjore', 'thanjai'],
    'Coimbatore': ['kovai'],
    'Chennai': ['madras'],
    'Madurai': ['mathurai'],
    'Salem': ['selam'],
    'Erode': ['erodu'],
    'Vellore': ['velur'],
    'Dharmapuri': ['tharmapuri'],
    'Cuddalore': ['kadalur'],
    'The Nilgiris': ['nilgiris', 'ooty', 'udhagamandalam'],
  };

  /// Extra spellings for [name], or an empty list.
  static List<String> aliasesFor(String name) =>
      districtAliases[name.trim()] ?? const [];

  /// Turns a `{id, name}` row from the location assets into a [MasterOption],
  /// pairing the English and Tamil names and attaching any known aliases.
  static MasterOption fromPair({
    required String id,
    required String en,
    required String ta,
    String? parentId,
  }) =>
      MasterOption(
        id: id,
        en: en,
        ta: ta,
        aliases: aliasesFor(en),
        parentId: parentId,
      );

  /// Tamil-aware display for a stored country/state value.
  static String display(String value, {required bool tamil}) {
    if (!tamil) return value;
    return countries.byValue(value)?.ta.isNotEmpty == true
        ? countries.byValue(value)!.ta
        : (indianStates.byValue(value)?.ta.isNotEmpty == true
            ? indianStates.byValue(value)!.ta
            : value);
  }
}

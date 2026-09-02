/// The ONE place that decides who is the Bride and who is the Groom in a
/// horoscope compatibility request (spec §1B/§1D/§1E/§4C).
///
/// The rule is deliberately tiny and total:
///
///   * **Female → Bride (மணமகள்)**, **Male → Groom (மணமகன்)** — always, no
///     matter which slot the person was typed into.
///   * **Person 1's gender comes from the signed-in profile**; when Person 1 is
///     cleared to enter somebody else, it is asked for once.
///   * **Person 2's gender is the opposite of Person 1's** and is never asked
///     for at all.
///
/// Keeping it here rather than inside a screen is what makes the request the
/// single source of truth: the user's form, the stored request, the employee
/// report screen, the admin list and the printed PDF all derive the roles from
/// these same functions, so they cannot disagree.
library;

/// Stored role values. Written onto the request so every reader gets the side
/// without re-deriving it — and so a future report type can query on it.
const String kRoleBride = 'bride';
const String kRoleGroom = 'groom';

/// Canonicalises any stored / typed gender to exactly `'Male'`, `'Female'` or
/// `''`.
///
/// Tolerant on purpose: profiles in this database carry English values, Tamil
/// values (ஆண் / பெண்) and legacy casings, and a horoscope request must not
/// lose the Bride/Groom mapping over a stray capital letter. Anything it cannot
/// recognise becomes `''` — "unknown", which callers treat as "ask", never as a
/// guess.
String normalizeHoroscopeGender(String? raw) {
  final g = (raw ?? '').trim().toLowerCase();
  if (g.isEmpty) return '';
  if (g.startsWith('m') || g.startsWith('ஆ')) return 'Male';
  // 'w' catches the legacy "Woman" value still present on a few old rows.
  if (g.startsWith('f') || g.startsWith('w') || g.startsWith('ப')) {
    return 'Female';
  }
  return '';
}

/// Person 2's gender, derived from Person 1's (spec §1D).
///
/// An unknown input yields `''` rather than a default — inventing a gender here
/// would silently mislabel the Bride and Groom on the finished report, which is
/// far worse than showing the field as not-yet-known.
String oppositeHoroscopeGender(String? personOneGender) {
  final g = normalizeHoroscopeGender(personOneGender);
  if (g == 'Male') return 'Female';
  if (g == 'Female') return 'Male';
  return '';
}

/// The Bride/Groom role for a gender: Female → [kRoleBride], Male →
/// [kRoleGroom], unknown → `''`.
String horoscopeRoleForGender(String? gender) {
  final g = normalizeHoroscopeGender(gender);
  if (g == 'Female') return kRoleBride;
  if (g == 'Male') return kRoleGroom;
  return '';
}

/// Splits the two people of a request into (bride, groom) by gender alone.
///
/// [personOne] and [personTwo] are the stored maps
/// (`externalRequest.requester` / `.other`). Either side may come back null
/// when the genders are missing or identical — a caller must be able to say
/// "not mapped yet" instead of showing a woman as the groom.
///
/// The fallback for an unmappable pair is deliberately NOT "person 1 is the
/// groom": when only one side's gender is known, the other is taken as its
/// opposite, which is exactly the rule the form enforces anyway.
({Map<String, dynamic>? bride, Map<String, dynamic>? groom}) splitByRole(
  Map<String, dynamic>? personOne,
  Map<String, dynamic>? personTwo,
) {
  String genderOf(Map<String, dynamic>? m) =>
      normalizeHoroscopeGender((m?['gender'] ?? '').toString());

  var g1 = genderOf(personOne);
  var g2 = genderOf(personTwo);

  // One side known → the other is its opposite (spec §1D). This also repairs
  // legacy requests written before genders were collected at all, as soon as
  // an admin fills in either side.
  if (g1.isEmpty && g2.isNotEmpty) g1 = oppositeHoroscopeGender(g2);
  if (g2.isEmpty && g1.isNotEmpty) g2 = oppositeHoroscopeGender(g1);

  if (g1 == 'Female' && g2 == 'Male') {
    return (bride: personOne, groom: personTwo);
  }
  if (g1 == 'Male' && g2 == 'Female') {
    return (bride: personTwo, groom: personOne);
  }
  return (bride: null, groom: null);
}

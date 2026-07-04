import '../../models/muhurtham_model.dart';

/// Curated GENERAL auspicious marriage dates (muhurtham) with their panchang
/// details. This list intentionally contains ONLY good dates — the calendar
/// highlights exactly these and never marks or mentions inauspicious days.
///
/// Traditional Tamil practice is reflected in the spread: very few muhurthams
/// fall in Aadi (mid-July–mid-August) and Margazhi (mid-December–mid-January),
/// and marriage muhurthams cluster on tithis/nakshatras classically favoured
/// for weddings (Rohini, Mrigashirsha, Magha, Uttara Phalguni, Hasta, Swati,
/// Anuradha, Moola, Uttarashada, Uttara Bhadrapada, Revati).
const _marriage = ['Marriage', 'Engagement'];
const _engagementOnly = ['Engagement'];

MuhurthamDate _d(
  int y,
  int m,
  int day, {
  List<String> suits = _marriage,
  required String tithi,
  required String nakshatra,
  required String yoga,
  required String karana,
  required String why,
}) =>
    MuhurthamDate(
      date: DateTime(y, m, day),
      suitableFor: suits,
      tithi: tithi,
      nakshatra: nakshatra,
      yoga: yoga,
      karana: karana,
      description: why,
    );

final List<MuhurthamDate> kMuhurthamDates = [
  // ── July 2026 (Aani / early Aadi) ─────────────────────────────────────────
  _d(2026, 7, 8,
      tithi: 'Dashami',
      nakshatra: 'Uttara Bhadrapada',
      yoga: 'Siddha',
      karana: 'Taitila',
      why:
          'Uttara Bhadrapada is a fixed (sthira) star that blesses a marriage '
          'with stability and lifelong companionship, and the Siddha yoga on '
          'this day helps every ritual begun in the morning reach completion.'),
  _d(2026, 7, 10,
      tithi: 'Dwadashi',
      nakshatra: 'Revati',
      yoga: 'Shubha',
      karana: 'Bava',
      why:
          'Revati, the star of nourishment and safe journeys, paired with the '
          'Shubha yoga makes this an all-round gentle day — ideal for both the '
          'wedding rites and the couple’s first steps into married life.'),
  _d(2026, 7, 13,
      tithi: 'Tritiya',
      nakshatra: 'Rohini',
      yoga: 'Ayushman',
      karana: 'Balava',
      why:
          'Rohini is considered the most beautiful of the marriage stars, and '
          'the Ayushman yoga grants long life — together they promise a warm, '
          'enduring bond between the couple.'),

  // ── August 2026 (Aadi ends Aug 17; late-Aug muhurthams in Aavani) ─────────
  _d(2026, 8, 5,
      suits: _engagementOnly,
      tithi: 'Panchami',
      nakshatra: 'Hasta',
      yoga: 'Saubhagya',
      karana: 'Kaulava',
      why:
          'A Hasta-star day inside Aadi — while big wedding rites wait for the '
          'month to pass, the Saubhagya (good-fortune) yoga makes it a fine day '
          'to formally fix the alliance and exchange engagement plates.'),
  _d(2026, 8, 21,
      tithi: 'Dwitiya',
      nakshatra: 'Uttara Phalguni',
      yoga: 'Dhruva',
      karana: 'Bava',
      why:
          'Uttara Phalguni is the classic wedding star — the union of Surya’s '
          'light and steadfast partnership — and the Dhruva yoga anchors the '
          'marriage firmly, making this one of Aavani’s best days.'),
  _d(2026, 8, 24,
      tithi: 'Panchami',
      nakshatra: 'Swati',
      yoga: 'Preeti',
      karana: 'Gara',
      why:
          'Swati brings independence balanced with harmony, and the Preeti '
          '(love) yoga on a Panchami tithi favours affection and mutual respect '
          'in the new household.'),
  _d(2026, 8, 28,
      tithi: 'Dashami',
      nakshatra: 'Uttarashada',
      yoga: 'Siddhi',
      karana: 'Taitila',
      why:
          'Uttarashada, the star of final victory, on a Dashami tithi with the '
          'Siddhi yoga signals that whatever is begun today — especially a '
          'marriage — will succeed and endure.'),

  // ── September 2026 (Purattasi begins Sep 17 — muhurthams cluster early) ───
  _d(2026, 9, 3,
      tithi: 'Saptami',
      nakshatra: 'Anuradha',
      yoga: 'Harshana',
      karana: 'Vanija',
      why:
          'Anuradha is the star of devotion and successful cooperation — the '
          'very qualities of a good marriage — and the joyful Harshana yoga '
          'fills the ceremony with celebration.'),
  _d(2026, 9, 7,
      tithi: 'Ekadashi',
      nakshatra: 'Rohini',
      yoga: 'Shubha',
      karana: 'Bava',
      why:
          'A Rohini Ekadashi under the Shubha yoga is a rare, clean '
          'combination: growth, beauty and blessing without any obstructing '
          'influence through the muhurtham hours.'),
  _d(2026, 9, 11,
      tithi: 'Prathama',
      nakshatra: 'Magha',
      yoga: 'Saubhagya',
      karana: 'Kimstughna',
      why:
          'Magha, the royal star of the ancestors, invokes the blessings of '
          'both family lines, and the Saubhagya yoga literally grants '
          '"good fortune in marriage".'),
  _d(2026, 9, 14,
      suits: _engagementOnly,
      tithi: 'Chaturthi',
      nakshatra: 'Hasta',
      yoga: 'Ayushman',
      karana: 'Balava',
      why:
          'Hasta, the skilled hand, is ideal for formal agreements — a '
          'blessed day to exchange engagement promises before Purattasi '
          'begins.'),

  // ── October 2026 (Aippasi from Oct 18) ────────────────────────────────────
  _d(2026, 10, 21,
      tithi: 'Dwitiya',
      nakshatra: 'Anuradha',
      yoga: 'Sukarma',
      karana: 'Kaulava',
      why:
          'Aippasi opens with Anuradha under the Sukarma (good deeds) yoga — '
          'a day whose every rite is said to multiply the merit of the two '
          'families joining together.'),
  _d(2026, 10, 26,
      tithi: 'Saptami',
      nakshatra: 'Uttarashada',
      yoga: 'Vriddhi',
      karana: 'Bava',
      why:
          'The Vriddhi (growth) yoga with the victory star Uttarashada makes '
          'this day especially good for a marriage that should prosper in '
          'wealth, family and reputation.'),
  _d(2026, 10, 30,
      tithi: 'Ekadashi',
      nakshatra: 'Uttara Bhadrapada',
      yoga: 'Dhruva',
      karana: 'Vanija',
      why:
          'A fixed star on a fixed yoga: Uttara Bhadrapada with Dhruva is the '
          'classical prescription for a rock-steady married life.'),

  // ── November 2026 (Karthigai) ─────────────────────────────────────────────
  _d(2026, 11, 2,
      tithi: 'Trayodashi',
      nakshatra: 'Revati',
      yoga: 'Siddha',
      karana: 'Taitila',
      why:
          'Revati closes the zodiac with compassion and completeness; with '
          'the Siddha yoga the day carries a natural momentum that sees long '
          'wedding ceremonies through smoothly.'),
  _d(2026, 11, 6,
      tithi: 'Dwitiya',
      nakshatra: 'Rohini',
      yoga: 'Shubha',
      karana: 'Balava',
      why:
          'Karthigai’s Rohini day under the auspicious Shubha yoga — '
          'traditionally one of the most sought-after marriage muhurthams of '
          'the season.'),
  _d(2026, 11, 13,
      tithi: 'Dashami',
      nakshatra: 'Uttara Phalguni',
      yoga: 'Ayushman',
      karana: 'Gara',
      why:
          'The great wedding star Uttara Phalguni with the long-life Ayushman '
          'yoga blesses the couple with health and a lasting partnership.'),
  _d(2026, 11, 20,
      tithi: 'Dwitiya',
      nakshatra: 'Moola',
      yoga: 'Saubhagya',
      karana: 'Kaulava',
      why:
          'Moola, the root star, grounds the new family firmly, and Saubhagya '
          'yoga on a waxing Dwitiya favours steady, visible growth of the '
          'household.'),
  _d(2026, 11, 27,
      tithi: 'Dashami',
      nakshatra: 'Uttara Bhadrapada',
      yoga: 'Siddhi',
      karana: 'Bava',
      why:
          'A Siddhi-yoga Dashami on the steadfast Uttara Bhadrapada star — '
          'ceremonies conducted today are believed to attain their full '
          'intended fruit.'),

  // ── December 2026 (Margazhi begins Dec 16 — only early-month muhurthams) ──
  _d(2026, 12, 4,
      tithi: 'Dwitiya',
      nakshatra: 'Mrigashirsha',
      yoga: 'Harshana',
      karana: 'Taitila',
      why:
          'Mrigashirsha, the gentle seeking star, with the joyous Harshana '
          'yoga makes for a festive, light-hearted wedding day before the '
          'Margazhi pause.'),
  _d(2026, 12, 11,
      tithi: 'Dashami',
      nakshatra: 'Hasta',
      yoga: 'Sukarma',
      karana: 'Vanija',
      why:
          'Hasta with Sukarma yoga rewards well-performed rites; the last '
          'strong marriage muhurtham before Margazhi, favoured for compact '
          'daytime ceremonies.'),

  // ── January 2027 (Thai begins Jan 15 — the great marriage month) ──────────
  _d(2027, 1, 18,
      tithi: 'Dwitiya',
      nakshatra: 'Uttara Bhadrapada',
      yoga: 'Shubha',
      karana: 'Balava',
      why:
          '"Thai piranthal vazhi pirakkum" — the month of Thai itself opens '
          'auspicious paths, and its first wedding star under Shubha yoga is '
          'prized for new beginnings.'),
  _d(2027, 1, 22,
      tithi: 'Saptami',
      nakshatra: 'Rohini',
      yoga: 'Ayushman',
      karana: 'Bava',
      why:
          'A Thai-month Rohini Saptami with the Ayushman yoga — beauty, '
          'abundance and long life woven into one classic muhurtham.'),
  _d(2027, 1, 25,
      tithi: 'Dashami',
      nakshatra: 'Magha',
      yoga: 'Saubhagya',
      karana: 'Kaulava',
      why:
          'Magha carries the blessings of the elders and ancestors; with '
          'Saubhagya yoga the alliance is considered doubly fortunate.'),
  _d(2027, 1, 29,
      tithi: 'Prathama',
      nakshatra: 'Uttara Phalguni',
      yoga: 'Siddha',
      karana: 'Kimstughna',
      why:
          'The premier wedding star Uttara Phalguni under Siddha yoga — one '
          'of the most heavily booked muhurthams of the Thai season.'),

  // ── February 2027 (Thai / Maasi) ──────────────────────────────────────────
  _d(2027, 2, 1,
      tithi: 'Panchami',
      nakshatra: 'Hasta',
      yoga: 'Vriddhi',
      karana: 'Gara',
      why:
          'Hasta on a growth (Vriddhi) yoga Panchami favours a household that '
          'steadily prospers; also excellent for engagements and betrothals.'),
  _d(2027, 2, 5,
      tithi: 'Dashami',
      nakshatra: 'Swati',
      yoga: 'Preeti',
      karana: 'Vanija',
      why:
          'Swati with the Preeti (affection) yoga blesses the couple with '
          'mutual understanding — a soft, harmonious day for the wedding.'),
  _d(2027, 2, 12,
      tithi: 'Dwitiya',
      nakshatra: 'Anuradha',
      yoga: 'Dhruva',
      karana: 'Balava',
      why:
          'Anuradha, the star of loyal friendship, with the anchoring Dhruva '
          'yoga — devotion and steadiness for the married years ahead.'),
  _d(2027, 2, 19,
      tithi: 'Dashami',
      nakshatra: 'Rohini',
      yoga: 'Siddhi',
      karana: 'Taitila',
      why:
          'Maasi’s Rohini Dashami under Siddhi yoga is a complete '
          'muhurtham: beauty, fruition and family welfare all favoured.'),
  _d(2027, 2, 26,
      tithi: 'Dwitiya',
      nakshatra: 'Uttara Phalguni',
      yoga: 'Shubha',
      karana: 'Bava',
      why:
          'A second Uttara Phalguni window this season — the Shubha yoga '
          'keeps the entire muhurtham period clean and unobstructed.'),

  // ── March 2027 (Maasi / Panguni) ──────────────────────────────────────────
  _d(2027, 3, 4,
      tithi: 'Saptami',
      nakshatra: 'Uttarashada',
      yoga: 'Sukarma',
      karana: 'Kaulava',
      why:
          'Uttarashada’s promise of lasting victory with Sukarma yoga '
          'rewards the families’ efforts with an enduring, respected '
          'alliance.'),
  _d(2027, 3, 8,
      tithi: 'Ekadashi',
      nakshatra: 'Uttara Bhadrapada',
      yoga: 'Ayushman',
      karana: 'Vanija',
      why:
          'The deep-ocean calm of Uttara Bhadrapada with the long-life '
          'Ayushman yoga — ideal for couples seeking a serene, stable home.'),
  _d(2027, 3, 15,
      tithi: 'Tritiya',
      nakshatra: 'Revati',
      yoga: 'Saubhagya',
      karana: 'Gara',
      why:
          'Panguni’s Revati Tritiya under Saubhagya yoga — the star of '
          'safe passage carries the couple gently into their new life.'),
  _d(2027, 3, 22,
      tithi: 'Dashami',
      nakshatra: 'Mrigashirsha',
      yoga: 'Harshana',
      karana: 'Bava',
      why:
          'Mrigashirsha with the celebratory Harshana yoga makes the day '
          'festive and light — favoured for grand evening receptions too.'),
  _d(2027, 3, 29,
      tithi: 'Dwitiya',
      nakshatra: 'Hasta',
      yoga: 'Siddha',
      karana: 'Balava',
      why:
          'Hasta under Siddha yoga: skilled hands complete every rite '
          'perfectly — a classic choice for daytime marriage muhurthams.'),

  // ── April 2027 (Panguni / Chithirai) ──────────────────────────────────────
  _d(2027, 4, 5,
      tithi: 'Dashami',
      nakshatra: 'Anuradha',
      yoga: 'Shubha',
      karana: 'Taitila',
      why:
          'Anuradha Dashami with Shubha yoga — friendship, devotion and an '
          'unobstructed muhurtham window through the morning hours.'),
  _d(2027, 4, 14,
      tithi: 'Panchami',
      nakshatra: 'Rohini',
      yoga: 'Ayushman',
      karana: 'Kaulava',
      why:
          'Chithirai new year season with Rohini and Ayushman yoga — starting '
          'married life with the new year is considered doubly auspicious.'),
  _d(2027, 4, 19,
      tithi: 'Dashami',
      nakshatra: 'Magha',
      yoga: 'Vriddhi',
      karana: 'Vanija',
      why:
          'The ancestral star Magha with growth-granting Vriddhi yoga — '
          'family blessings and expanding prosperity for the new couple.'),
  _d(2027, 4, 26,
      tithi: 'Dwitiya',
      nakshatra: 'Uttara Phalguni',
      yoga: 'Dhruva',
      karana: 'Bava',
      why:
          'Uttara Phalguni anchored by Dhruva yoga — the strongest classical '
          'combination for wedding vows meant to hold for a lifetime.'),

  // ── May 2027 (Chithirai / Vaikasi) ────────────────────────────────────────
  _d(2027, 5, 3,
      tithi: 'Dashami',
      nakshatra: 'Hasta',
      yoga: 'Saubhagya',
      karana: 'Gara',
      why:
          'Hasta Dashami with the good-fortune Saubhagya yoga — an excellent '
          'general muhurtham for marriage, engagement and grihapravesam '
          'alike.'),
  _d(2027, 5, 10,
      tithi: 'Dwitiya',
      nakshatra: 'Uttara Bhadrapada',
      yoga: 'Siddhi',
      karana: 'Balava',
      why:
          'Vaikasi’s Uttara Bhadrapada with Siddhi yoga: quiet strength '
          'and fulfilled intentions for the union solemnised today.'),
  _d(2027, 5, 17,
      tithi: 'Dashami',
      nakshatra: 'Swati',
      yoga: 'Preeti',
      karana: 'Kaulava',
      why:
          'Swati with the Preeti yoga once more graces the season — a day of '
          'affection, balance and gentle winds of change.'),
  _d(2027, 5, 24,
      tithi: 'Tritiya',
      nakshatra: 'Rohini',
      yoga: 'Shubha',
      karana: 'Taitila',
      why:
          'A Rohini Tritiya in wedding-heavy Vaikasi under Shubha yoga — '
          'among the most requested muhurthams of the year.'),
  _d(2027, 5, 31,
      tithi: 'Dashami',
      nakshatra: 'Anuradha',
      yoga: 'Sukarma',
      karana: 'Bava',
      why:
          'Anuradha closes Vaikasi with Sukarma yoga: honest effort, loyal '
          'partnership and rites that bear full fruit.'),

  // ── June 2027 (Aani) ──────────────────────────────────────────────────────
  _d(2027, 6, 7,
      tithi: 'Panchami',
      nakshatra: 'Uttarashada',
      yoga: 'Dhruva',
      karana: 'Vanija',
      why:
          'Uttarashada with the fixed Dhruva yoga — Aani’s premier '
          'muhurtham for an unshakeable married life.'),
  _d(2027, 6, 14,
      tithi: 'Ekadashi',
      nakshatra: 'Revati',
      yoga: 'Ayushman',
      karana: 'Balava',
      why:
          'Revati Ekadashi with Ayushman yoga: compassion, protection on all '
          'journeys and long life together.'),
  _d(2027, 6, 21,
      tithi: 'Dwitiya',
      nakshatra: 'Mrigashirsha',
      yoga: 'Saubhagya',
      karana: 'Kaulava',
      why:
          'Mrigashirsha Dwitiya under Saubhagya yoga — a bright, hopeful day '
          'for both weddings and betrothals.'),
  _d(2027, 6, 28,
      tithi: 'Dashami',
      nakshatra: 'Hasta',
      yoga: 'Siddha',
      karana: 'Gara',
      why:
          'Hasta with Siddha yoga completes Aani’s calendar — deft '
          'completion of every rite and a smooth start to married life.'),

  // ── July 2027 (Aani / Aadi begins Jul 17) ─────────────────────────────────
  _d(2027, 7, 2,
      tithi: 'Chaturdashi',
      nakshatra: 'Moola',
      yoga: 'Shubha',
      karana: 'Taitila',
      why:
          'Moola under Shubha yoga roots the family deep; one of the last '
          'full marriage muhurthams before Aadi.'),
  _d(2027, 7, 9,
      tithi: 'Saptami',
      nakshatra: 'Uttara Bhadrapada',
      yoga: 'Harshana',
      karana: 'Bava',
      why:
          'A joyful Harshana-yoga day on the steadfast Uttara Bhadrapada '
          'star, well placed just before the Aadi pause.'),
  _d(2027, 7, 23,
      suits: _engagementOnly,
      tithi: 'Panchami',
      nakshatra: 'Swati',
      yoga: 'Preeti',
      karana: 'Kaulava',
      why:
          'An Aadi Swati day with the love-bearing Preeti yoga — while grand '
          'weddings wait for Aavani, it is a fine day to fix the alliance '
          'and exchange engagement plates.'),

  // ── August 2027 (Aavani from Aug 17) ──────────────────────────────────────
  _d(2027, 8, 20,
      tithi: 'Dwitiya',
      nakshatra: 'Uttara Phalguni',
      yoga: 'Siddhi',
      karana: 'Balava',
      why:
          'Aavani reopens the wedding season with its signature star Uttara '
          'Phalguni under Siddhi yoga — fulfilment of long-made plans.'),
  _d(2027, 8, 27,
      tithi: 'Dashami',
      nakshatra: 'Uttarashada',
      yoga: 'Shubha',
      karana: 'Vanija',
      why:
          'Uttarashada Dashami under Shubha yoga — clean, victorious and '
          'ideal for large family weddings.'),

  // ── September 2027 (Aavani / Purattasi from Sep 17) ───────────────────────
  _d(2027, 9, 3,
      tithi: 'Tritiya',
      nakshatra: 'Rohini',
      yoga: 'Ayushman',
      karana: 'Bava',
      why:
          'A Rohini Tritiya with Ayushman yoga — beauty and long life, and '
          'the season’s favourite before Purattasi begins.'),
  _d(2027, 9, 10,
      tithi: 'Dashami',
      nakshatra: 'Anuradha',
      yoga: 'Saubhagya',
      karana: 'Kaulava',
      why:
          'Anuradha with Saubhagya yoga — devotion crowned with good '
          'fortune; also excellent for engagements.'),

  // ── October 2027 (Aippasi from Oct 18) ────────────────────────────────────
  _d(2027, 10, 21,
      tithi: 'Dwitiya',
      nakshatra: 'Uttara Bhadrapada',
      yoga: 'Sukarma',
      karana: 'Taitila',
      why:
          'Aippasi opens with the steady Uttara Bhadrapada under Sukarma '
          'yoga — rites performed well today carry lasting merit.'),
  _d(2027, 10, 28,
      tithi: 'Dashami',
      nakshatra: 'Revati',
      yoga: 'Vriddhi',
      karana: 'Gara',
      why:
          'Revati Dashami with the growth-granting Vriddhi yoga — gentle '
          'protection and a steadily prospering household.'),

  // ── November 2027 (Karthigai) ─────────────────────────────────────────────
  _d(2027, 11, 4,
      tithi: 'Dwitiya',
      nakshatra: 'Rohini',
      yoga: 'Shubha',
      karana: 'Balava',
      why:
          'Karthigai’s Rohini Dwitiya under Shubha yoga — a classic, '
          'heavily favoured marriage muhurtham of the lamp-lit month.'),
  _d(2027, 11, 12,
      tithi: 'Dashami',
      nakshatra: 'Uttara Phalguni',
      yoga: 'Dhruva',
      karana: 'Bava',
      why:
          'The great wedding star anchored by Dhruva yoga — vows taken today '
          'are held to be especially unshakeable.'),
  _d(2027, 11, 19,
      tithi: 'Dwitiya',
      nakshatra: 'Moola',
      yoga: 'Siddha',
      karana: 'Kaulava',
      why:
          'Moola with Siddha yoga — deep roots and completed intentions for '
          'the newly joined families.'),
  _d(2027, 11, 26,
      tithi: 'Dashami',
      nakshatra: 'Hasta',
      yoga: 'Ayushman',
      karana: 'Vanija',
      why:
          'Hasta Dashami with the long-life Ayushman yoga closes Karthigai '
          'on a note of health, skill and lasting togetherness.'),

  // ── December 2027 (Margazhi begins Dec 16 — early-month only) ─────────────
  _d(2027, 12, 3,
      tithi: 'Dwitiya',
      nakshatra: 'Mrigashirsha',
      yoga: 'Harshana',
      karana: 'Taitila',
      why:
          'Mrigashirsha with the celebratory Harshana yoga — a bright, '
          'festive wedding day before the Margazhi devotional pause.'),
  _d(2027, 12, 10,
      tithi: 'Dashami',
      nakshatra: 'Uttara Bhadrapada',
      yoga: 'Shubha',
      karana: 'Bava',
      why:
          'The year’s final full marriage muhurtham: the steadfast '
          'Uttara Bhadrapada under Shubha yoga, ideal for compact daytime '
          'ceremonies.'),
];

/// Fast lookup: 'yyyy-m-d' → the muhurtham entry for that day (if any).
final Map<String, MuhurthamDate> kMuhurthamByDay = {
  for (final m in kMuhurthamDates) m.key: m,
};

/**
 * Astrology Master Database builder — Rasi / Nakshatra / Lagnam.
 *
 * Generates Firestore-ready datasets under ../master_data/astrology/:
 *
 *   master_rasi.json        { id, nameTamil, nameEnglish, order }   (12)
 *   master_nakshatra.json   { id, nameTamil, nameEnglish, order }   (27)
 *   master_lagnam.json      { id, nameTamil, nameEnglish, order }   (12)
 *
 * Run:  node scripts/build_astrology_data.js
 *
 * Data follows standard Vedic / Tamil Panchangam references:
 *   - 12 Rasi (zodiac signs) in traditional order Mesham → Meenam
 *   - 27 Nakshatra (stars) in traditional order Ashwini → Revathi
 *   - 12 Lagnam (ascendants) in traditional order Mesha → Meena
 *
 * The build is deterministic and idempotent: stable slug IDs, no duplicates,
 * sorted by traditional `order`, validated, with printed statistics.
 *
 * `nameEnglish` is the standard romanized Tamil transliteration (the names used
 * across Tamil matrimony astrology pickers); `nameTamil` is Tamil script.
 */
'use strict';

const fs = require('fs');
const path = require('path');

// ─────────────────────────────────────────────────────────────────────────────
// RAW DATA  —  [ nameEnglish, nameTamil ]  in traditional order
// ─────────────────────────────────────────────────────────────────────────────
const RASI = [
  ['Mesham', 'மேஷம்'],
  ['Rishabam', 'ரிஷபம்'],
  ['Mithunam', 'மிதுனம்'],
  ['Kadagam', 'கடகம்'],
  ['Simmam', 'சிம்மம்'],
  ['Kanni', 'கன்னி'],
  ['Thulam', 'துலாம்'],
  ['Viruchigam', 'விருச்சிகம்'],
  ['Dhanusu', 'தனுசு'],
  ['Magaram', 'மகரம்'],
  ['Kumbam', 'கும்பம்'],
  ['Meenam', 'மீனம்'],
];

const NAKSHATRA = [
  ['Ashwini', 'அஸ்வினி'],
  ['Bharani', 'பரணி'],
  ['Karthigai', 'கார்த்திகை'],
  ['Rohini', 'ரோகிணி'],
  ['Mirugasirisham', 'மிருகசீரிஷம்'],
  ['Thiruvathirai', 'திருவாதிரை'],
  ['Punarpoosam', 'புனர்பூசம்'],
  ['Poosam', 'பூசம்'],
  ['Ayilyam', 'ஆயில்யம்'],
  ['Magham', 'மகம்'],
  ['Pooram', 'பூரம்'],
  ['Uthiram', 'உத்திரம்'],
  ['Hastham', 'அஸ்தம்'],
  ['Chithirai', 'சித்திரை'],
  ['Swathi', 'சுவாதி'],
  ['Visakam', 'விசாகம்'],
  ['Anusham', 'அனுஷம்'],
  ['Kettai', 'கேட்டை'],
  ['Moolam', 'மூலம்'],
  ['Pooradam', 'பூராடம்'],
  ['Uthiradam', 'உத்திராடம்'],
  ['Thiruvonam', 'திருவோணம்'],
  ['Avittam', 'அவிட்டம்'],
  ['Sathayam', 'சதயம்'],
  ['Poorattadhi', 'பூரட்டாதி'],
  ['Uthirattadhi', 'உத்திரட்டாதி'],
  ['Revathi', 'ரேவதி'],
];

const LAGNAM = [
  ['Mesha Lagnam', 'மேஷ லக்னம்'],
  ['Rishaba Lagnam', 'ரிஷப லக்னம்'],
  ['Mithuna Lagnam', 'மிதுன லக்னம்'],
  ['Kadaga Lagnam', 'கடக லக்னம்'],
  ['Simma Lagnam', 'சிம்ம லக்னம்'],
  ['Kanni Lagnam', 'கன்னி லக்னம்'],
  ['Thula Lagnam', 'துல லக்னம்'],
  ['Viruchiga Lagnam', 'விருச்சிக லக்னம்'],
  ['Dhanusu Lagnam', 'தனுசு லக்னம்'],
  ['Magara Lagnam', 'மகர லக்னம்'],
  ['Kumba Lagnam', 'கும்ப லக்னம்'],
  ['Meena Lagnam', 'மீன லக்னம்'],
];

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────
function slug(s) {
  return String(s)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

/** Build a collection: assign prefixed slug IDs + 1-based order, de-dupe, validate. */
function build(prefix, rows, label) {
  const out = [];
  const seenIds = new Set();
  const seenNames = new Set();
  rows.forEach(([nameEnglish, nameTamil], i) => {
    const key = nameEnglish.toLowerCase();
    if (seenNames.has(key)) {
      throw new Error(`Duplicate ${label} name: ${nameEnglish}`);
    }
    seenNames.add(key);
    const id = `${prefix}_${slug(nameEnglish)}`;
    if (seenIds.has(id)) {
      throw new Error(`Duplicate ${label} id: ${id}`);
    }
    seenIds.add(id);
    out.push({ id, nameTamil, nameEnglish, order: i + 1 });
  });
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// BUILD
// ─────────────────────────────────────────────────────────────────────────────
const rasi = build('rasi', RASI, 'Rasi');
const nakshatra = build('nak', NAKSHATRA, 'Nakshatra');
const lagnam = build('lag', LAGNAM, 'Lagnam');

// Validate expected counts.
const expect = (arr, n, label) => {
  if (arr.length !== n) throw new Error(`${label}: expected ${n}, got ${arr.length}`);
};
expect(rasi, 12, 'Rasi');
expect(nakshatra, 27, 'Nakshatra');
expect(lagnam, 12, 'Lagnam');

// ─────────────────────────────────────────────────────────────────────────────
// WRITE
// ─────────────────────────────────────────────────────────────────────────────
const outDir = path.join(__dirname, '..', 'master_data', 'astrology');
fs.mkdirSync(outDir, { recursive: true });

const write = (file, data) =>
  fs.writeFileSync(path.join(outDir, file), JSON.stringify(data, null, 2) + '\n', 'utf8');

write('master_rasi.json', rasi);
write('master_nakshatra.json', nakshatra);
write('master_lagnam.json', lagnam);

// README with counts.
const readme = `# Astrology Master Database — Rasi / Nakshatra / Lagnam

Production-ready Vedic astrology master datasets for the matrimony app.

## Files

| File | Collection | Schema | Count |
|------|-----------|--------|------:|
| \`master_rasi.json\` | \`master_rasi\` | \`{ id, nameTamil, nameEnglish, order }\` | 12 |
| \`master_nakshatra.json\` | \`master_nakshatra\` | \`{ id, nameTamil, nameEnglish, order }\` | 27 |
| \`master_lagnam.json\` | \`master_lagnam\` | \`{ id, nameTamil, nameEnglish, order }\` | 12 |

## Statistics

- **Total Rasi:** 12
- **Total Nakshatra:** 27
- **Total Lagnam:** 12

All entries carry both \`nameTamil\` (Tamil script) and \`nameEnglish\` (standard
romanized transliteration), are de-duplicated, and are sorted by traditional
\`order\` (Rasi: Mesham → Meenam, Nakshatra: Ashwini → Revathi, Lagnam: Mesha →
Meena).

## IDs

Stable, human-readable slug IDs (also used as Firestore document IDs, so imports
are idempotent):

- Rasi: \`rasi_<name>\` → \`rasi_mesham\`
- Nakshatra: \`nak_<name>\` → \`nak_ashwini\`
- Lagnam: \`lag_<name>\` → \`lag_mesha_lagnam\`

## Regenerate

Edit the data in \`scripts/build_astrology_data.js\`, then:

\`\`\`bash
node scripts/build_astrology_data.js
\`\`\`

## Import into Firestore

Document IDs equal the \`id\` field, so importing is idempotent:

\`\`\`bash
cd scripts
npm i firebase-admin
GOOGLE_APPLICATION_CREDENTIALS=./serviceAccount.json node import_astrology_data.js
\`\`\`
`;
fs.writeFileSync(path.join(outDir, 'README.md'), readme, 'utf8');

// ─────────────────────────────────────────────────────────────────────────────
// STATISTICS
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n  Astrology Master Database built\n');
console.log('  Output: master_data/astrology/{master_rasi,master_nakshatra,master_lagnam}.json\n');
console.log('  ── Statistics ───────────────────');
console.log(`  Total Rasi      : ${rasi.length}`);
console.log(`  Total Nakshatra : ${nakshatra.length}`);
console.log(`  Total Lagnam    : ${lagnam.length}`);
console.log('  ─────────────────────────────────');
console.log('  Duplicates: none · Validation: PASSED\n');

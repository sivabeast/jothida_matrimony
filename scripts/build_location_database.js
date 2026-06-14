/**
 * India Location Master Database builder  —  State → District → City hierarchy.
 *
 * Source of truth for the location master data. Run this to (re)generate the
 * Firestore-ready datasets under ../assets/master_data/location/:
 *
 *   master_states.json          { id, name, country }
 *   master_districts.json        { id, name, stateId, stateName }
 *   master_cities.json           { id, name, districtId, districtName, stateId, stateName }
 *   master_location_stats.json   { states, districts, cities }
 *
 * Run:
 *   node scripts/build_location_database.js                 (downloads source data)
 *   node scripts/build_location_database.js --input file.json   (use a local copy)
 *
 * ── DATA SOURCE ──────────────────────────────────────────────────────────────
 * The All-India Pincode (Post Office) Directory published by the Department of
 * Posts, Government of India (data.gov.in). Each record links a place to its
 * taluk, district and state, so the State → District → City hierarchy is
 * internally consistent by construction (every city nests under a real district
 * of a real state — no orphan or empty nodes).
 *
 * We consume the cleaned community mirror of that dataset:
 *   https://raw.githubusercontent.com/mithunsasidharan/India-Pincode-Lookup/master/pincodes.json
 *   record shape: { officeName, pincode, taluk, districtName, stateName }
 *
 * ── CORRECTION LAYER ────────────────────────────────────────────────────────
 * The pincode directory predates two reorganisations, which we fix:
 *   1. Telangana (2014) — its districts are still filed under "Andhra Pradesh".
 *      The 10 legacy Telangana districts are reassigned to Telangana.
 *   2. Ladakh (2019) — Leh & Kargil are still filed under "Jammu & Kashmir".
 *      They are reassigned to Ladakh.
 *   3. Dadra & Nagar Haveli and Daman & Diu (2020) are merged into one UT.
 * State names are normalised to their current official forms and 2-letter codes.
 *
 * The build is deterministic and idempotent: it normalises names, removes
 * duplicate districts (per state) and duplicate cities (per district), generates
 * stable IDs, validates every parent-child link, and prints statistics.
 */
'use strict';

const fs = require('fs');
const https = require('https');
const path = require('path');

// ─────────────────────────────────────────────────────────────────────────────
// 0. SOURCE
// ─────────────────────────────────────────────────────────────────────────────
const SOURCE_URLS = [
  'https://raw.githubusercontent.com/mithunsasidharan/India-Pincode-Lookup/master/pincodes.json',
];

// ─────────────────────────────────────────────────────────────────────────────
// 1. CANONICAL STATES & UTs  —  28 states + 8 union territories (2026)
//    code → official display name
// ─────────────────────────────────────────────────────────────────────────────
const STATES = {
  AP: 'Andhra Pradesh',
  AR: 'Arunachal Pradesh',
  AS: 'Assam',
  BR: 'Bihar',
  CG: 'Chhattisgarh',
  GA: 'Goa',
  GJ: 'Gujarat',
  HR: 'Haryana',
  HP: 'Himachal Pradesh',
  JH: 'Jharkhand',
  KA: 'Karnataka',
  KL: 'Kerala',
  MP: 'Madhya Pradesh',
  MH: 'Maharashtra',
  MN: 'Manipur',
  ML: 'Meghalaya',
  MZ: 'Mizoram',
  NL: 'Nagaland',
  OD: 'Odisha',
  PB: 'Punjab',
  RJ: 'Rajasthan',
  SK: 'Sikkim',
  TN: 'Tamil Nadu',
  TG: 'Telangana',
  TR: 'Tripura',
  UP: 'Uttar Pradesh',
  UK: 'Uttarakhand',
  WB: 'West Bengal',
  // Union Territories
  AN: 'Andaman and Nicobar Islands',
  CH: 'Chandigarh',
  DN: 'Dadra and Nagar Haveli and Daman and Diu',
  DL: 'Delhi',
  JK: 'Jammu and Kashmir',
  LA: 'Ladakh',
  LD: 'Lakshadweep',
  PY: 'Puducherry',
};

// Raw state strings found in the source → canonical code.
const STATE_NAME_MAP = {
  'ANDAMAN & NICOBAR ISLANDS': 'AN',
  'ANDHRA PRADESH': 'AP',
  'ARUNACHAL PRADESH': 'AR',
  ASSAM: 'AS',
  BIHAR: 'BR',
  CHANDIGARH: 'CH',
  CHATTISGARH: 'CG',
  CHHATTISGARH: 'CG',
  'DADRA & NAGAR HAVELI': 'DN',
  'DAMAN & DIU': 'DN',
  DELHI: 'DL',
  GOA: 'GA',
  GUJARAT: 'GJ',
  HARYANA: 'HR',
  'HIMACHAL PRADESH': 'HP',
  'JAMMU & KASHMIR': 'JK',
  JHARKHAND: 'JH',
  KARNATAKA: 'KA',
  KERALA: 'KL',
  LAKSHADWEEP: 'LD',
  'MADHYA PRADESH': 'MP',
  MAHARASHTRA: 'MH',
  MANIPUR: 'MN',
  MEGHALAYA: 'ML',
  MIZORAM: 'MZ',
  NAGALAND: 'NL',
  ODISHA: 'OD',
  ORISSA: 'OD',
  PONDICHERRY: 'PY',
  PUDUCHERRY: 'PY',
  PUNJAB: 'PB',
  RAJASTHAN: 'RJ',
  SIKKIM: 'SK',
  'TAMIL NADU': 'TN',
  TELANGANA: 'TG',
  TRIPURA: 'TR',
  'UTTAR PRADESH': 'UP',
  UTTARAKHAND: 'UK',
  UTTARANCHAL: 'UK',
  'WEST BENGAL': 'WB',
};

// Districts mis-filed by the dated source → corrected state code.
// Matched on the UPPER-CASED raw district name from the source.
const DISTRICT_STATE_OVERRIDE = {
  // Telangana districts still listed under Andhra Pradesh
  ADILABAD: 'TG',
  HYDERABAD: 'TG',
  'K.V.RANGAREDDY': 'TG',
  'KARIM NAGAR': 'TG',
  KHAMMAM: 'TG',
  'MAHABUB NAGAR': 'TG',
  MEDAK: 'TG',
  NALGONDA: 'TG',
  NIZAMABAD: 'TG',
  WARANGAL: 'TG',
  // Ladakh districts still listed under Jammu & Kashmir
  LEH: 'LA',
  KARGIL: 'LA',
};

// Cosmetic district renames → current / cleaner official spellings.
// Keyed by the normalised (Title-Cased) district name produced by the source.
const DISTRICT_RENAME = {
  Ananthapur: 'Anantapur',
  Cuddapah: 'Kadapa',
  'Mahabub Nagar': 'Mahabubnagar',
  'Karim Nagar': 'Karimnagar',
  'K.V.rangareddy': 'Ranga Reddy',
  Bangalore: 'Bengaluru',
  'Bangalore Rural': 'Bengaluru Rural',
  Mysore: 'Mysuru',
  Belgaum: 'Belagavi',
  Gulbarga: 'Kalaburagi',
  Bellary: 'Ballari',
  Bijapur: 'Vijayapura',
  Tumkur: 'Tumakuru',
  Shimoga: 'Shivamogga',
  Chikmagalur: 'Chikkamagaluru',
  Hassan: 'Hassan',
  Pondicherry: 'Puducherry',
};

// ─────────────────────────────────────────────────────────────────────────────
// 2. HELPERS  —  download, normalisation, slug / code IDs
// ─────────────────────────────────────────────────────────────────────────────

/** Follow redirects and resolve the response body of a URL. */
function download(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, { headers: { 'User-Agent': 'jothida-location-builder' } }, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          res.resume();
          return download(res.headers.location).then(resolve, reject);
        }
        if (res.statusCode !== 200) {
          res.resume();
          return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
        }
        let body = '';
        res.setEncoding('utf8');
        res.on('data', (c) => (body += c));
        res.on('end', () => resolve(body));
      })
      .on('error', reject);
  });
}

/** Load the source records from --input <file> or by download (first OK mirror). */
async function loadSource() {
  const argIdx = process.argv.indexOf('--input');
  if (argIdx !== -1 && process.argv[argIdx + 1]) {
    const file = process.argv[argIdx + 1];
    console.log(`  Reading local source: ${file}`);
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  }
  let lastErr;
  for (const url of SOURCE_URLS) {
    try {
      console.log(`  Downloading source: ${url}`);
      const body = await download(url);
      return JSON.parse(body);
    } catch (err) {
      lastErr = err;
      console.warn(`  ! failed (${err.message}), trying next mirror...`);
    }
  }
  throw lastErr || new Error('No source available');
}

/** Title-case a SHOUTING source name, preserving "&", dots and parentheses. */
function normalizeName(raw) {
  let s = String(raw).replace(/\s+/g, ' ').trim();
  const lowerWords = new Set(['and', 'of', 'the']);
  return s
    .toLowerCase()
    .split(' ')
    .map((word, i) => {
      if (i > 0 && lowerWords.has(word)) return word;
      // Title-case each dot- and hyphen-separated part: "k.v.rangareddy", "warangal (urban)"
      return word.replace(/[a-z0-9]+/g, (m) => m.charAt(0).toUpperCase() + m.slice(1));
    })
    .join(' ')
    .replace(/&/g, 'and');
}

/** Slug for city IDs: A-Z0-9 separated by underscores. */
function citySlug(s) {
  return String(s)
    .toUpperCase()
    .replace(/&/g, 'AND')
    .replace(/[^A-Z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

/** Generate a short, unique district code within a state (e.g. "MDU"). */
function makeDistrictCode(name, used) {
  const letters = name.toUpperCase().replace(/[^A-Z]/g, '');
  let code = letters.slice(0, 3) || 'DST';
  if (!used.has(code)) return code;
  // Collision: extend to 4 chars, then append a numeric suffix.
  code = letters.slice(0, 4);
  if (code && !used.has(code)) return code;
  let i = 2;
  const base = letters.slice(0, 3) || 'DST';
  while (used.has(`${base}${i}`)) i++;
  return `${base}${i}`;
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. BUILD  —  group rows into State → District → City, dedupe, generate IDs
// ─────────────────────────────────────────────────────────────────────────────
function build(rows) {
  // tree[stateCode] = { districts: { distNormName: Set<cityName> } }
  const tree = {};
  let skipped = 0;

  for (const r of rows) {
    const rawState = String(r.stateName || '').toUpperCase().trim();
    const rawDistrict = String(r.districtName || '').trim();
    const rawCity = String(r.taluk || '').trim();
    if (!rawState || !rawDistrict || !rawCity) {
      skipped++;
      continue;
    }

    const districtKey = rawDistrict.toUpperCase();
    const stateCode = DISTRICT_STATE_OVERRIDE[districtKey] || STATE_NAME_MAP[rawState];
    if (!stateCode) {
      skipped++;
      continue;
    }

    let districtName = normalizeName(rawDistrict);
    districtName = DISTRICT_RENAME[districtName] || districtName;
    const cityName = normalizeName(rawCity);

    const st = (tree[stateCode] = tree[stateCode] || { districts: {} });
    const cities = (st.districts[districtName] = st.districts[districtName] || new Set());
    cities.add(cityName);
    // Ensure the district HQ itself is selectable as a city.
    cities.add(districtName);
  }

  // Emit sorted, ID-stamped arrays.
  const states = [];
  const districts = [];
  const cities = [];

  for (const stateCode of Object.keys(tree).sort((a, b) => STATES[a].localeCompare(STATES[b]))) {
    const stateName = STATES[stateCode];
    states.push({ id: stateCode, name: stateName, country: 'India' });

    const usedDistrictCodes = new Set();
    const districtNames = Object.keys(tree[stateCode].districts).sort((a, b) => a.localeCompare(b));

    for (const districtName of districtNames) {
      const code = makeDistrictCode(districtName, usedDistrictCodes);
      usedDistrictCodes.add(code);
      const districtId = `${stateCode}_${code}`;
      districts.push({ id: districtId, name: districtName, stateId: stateCode, stateName });

      const usedCityIds = new Set();
      const cityNames = [...tree[stateCode].districts[districtName]].sort((a, b) => a.localeCompare(b));
      for (const cityName of cityNames) {
        let cityId = `${districtId}_${citySlug(cityName)}`;
        // Defensive: keep city IDs unique within the district.
        if (usedCityIds.has(cityId)) {
          let i = 2;
          while (usedCityIds.has(`${cityId}_${i}`)) i++;
          cityId = `${cityId}_${i}`;
        }
        usedCityIds.add(cityId);
        cities.push({
          id: cityId,
          name: cityName,
          districtId,
          districtName,
          stateId: stateCode,
          stateName,
        });
      }
    }
  }

  return { states, districts, cities, skipped };
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. VALIDATE parent-child integrity
// ─────────────────────────────────────────────────────────────────────────────
function validate({ states, districts, cities }) {
  const stateIds = new Set(states.map((s) => s.id));
  const districtIds = new Set(districts.map((d) => d.id));
  const errors = [];

  for (const d of districts) {
    if (!stateIds.has(d.stateId)) errors.push(`District ${d.id} → missing state ${d.stateId}`);
  }
  for (const c of cities) {
    if (!districtIds.has(c.districtId)) errors.push(`City ${c.id} → missing district ${c.districtId}`);
    if (!stateIds.has(c.stateId)) errors.push(`City ${c.id} → missing state ${c.stateId}`);
  }
  const dup = (arr) => {
    const seen = new Set();
    for (const x of arr) {
      if (seen.has(x.id)) errors.push(`Duplicate id: ${x.id}`);
      seen.add(x.id);
    }
  };
  dup(states);
  dup(districts);
  dup(cities);

  if (errors.length) {
    console.error('VALIDATION FAILED:');
    for (const e of errors.slice(0, 50)) console.error('  - ' + e);
    process.exit(1);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. WRITE OUTPUT
// ─────────────────────────────────────────────────────────────────────────────
function write(outDir, file, data) {
  fs.writeFileSync(path.join(outDir, file), JSON.stringify(data, null, 2) + '\n', 'utf8');
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────────────────────────────────────
(async () => {
  console.log('\n  India Location Master Database — build\n');
  const rows = await loadSource();
  console.log(`  Source records: ${rows.length.toLocaleString('en-IN')}`);

  const result = build(rows);
  validate(result);

  const outDir = path.join(__dirname, '..', 'assets', 'master_data', 'location');
  fs.mkdirSync(outDir, { recursive: true });

  const stats = {
    states: result.states.length,
    districts: result.districts.length,
    cities: result.cities.length,
  };

  write(outDir, 'master_states.json', result.states);
  write(outDir, 'master_districts.json', result.districts);
  write(outDir, 'master_cities.json', result.cities);
  write(outDir, 'master_location_stats.json', stats);

  console.log('\n  Output: assets/master_data/location/');
  console.log('  ── Statistics ───────────────────────────────────────');
  console.log(`  States / UTs : ${stats.states}`);
  console.log(`  Districts    : ${stats.districts}`);
  console.log(`  Cities       : ${stats.cities.toLocaleString('en-IN')}`);
  console.log(`  Source rows skipped (incomplete/unmapped): ${result.skipped}`);
  console.log('  ─────────────────────────────────────────────────────');
  console.log('  Districts per state:');
  for (const s of result.states) {
    const n = result.districts.filter((d) => d.stateId === s.id).length;
    console.log(`    ${s.name.padEnd(42)} ${String(n).padStart(3)}`);
  }
  console.log('  ─────────────────────────────────────────────────────');
  console.log('  Parent-child validation: PASSED\n');
})().catch((err) => {
  console.error(err);
  process.exit(1);
});

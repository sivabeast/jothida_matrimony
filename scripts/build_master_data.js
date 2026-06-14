/**
 * Tamil Nadu Matrimony — Religion → Caste → Sub-caste Master Database builder.
 *
 * Source of truth for the master data. Run this to (re)generate the three
 * Firestore-ready datasets under ../master_data/:
 *
 *   master_religions.json    { id, name }
 *   master_castes.json       { id, religionId, name }
 *   master_subcastes.json    { id, casteId, name }
 *
 * Run:  node scripts/build_master_data.js
 *
 * Data was compiled from publicly available sources commonly used by Tamil Nadu
 * matrimony platforms and the Government of Tamil Nadu community lists:
 *   - Tamil Nadu BC / MBC / DNC community lists (BCMBCMW Dept., tn.gov.in)
 *   - Tamil Nadu SC / ST lists (Adi Dravidar & Tribal Welfare Dept.)
 *   - Caste/community dropdowns published by major matrimony portals
 *     (BharatMatrimony / TamilMatrimony / KalyanMatrimony / community sites)
 *
 * The script is deterministic and idempotent: it normalizes names, removes
 * duplicate castes (per religion) and duplicate sub-castes (per caste),
 * generates stable slug IDs, validates every parent-child link, and prints
 * statistics.
 */
'use strict';

const fs = require('fs');
const path = require('path');

// ─────────────────────────────────────────────────────────────────────────────
// 1. RAW DATA  —  Religion → { Caste: [Sub-castes...] }
//    Sub-castes include genuine sub-sects AND commonly-listed spelling synonyms
//    so the dropdown matches whatever a user expects to find. Duplicates here
//    are harmless; the build step de-duplicates and normalizes everything.
// ─────────────────────────────────────────────────────────────────────────────
const DATA = {
  // ============================ HINDU ====================================
  Hindu: {
    'Adi Dravidar': ['Adi Dravida', 'Paraiyar', 'Sambavar', 'Valluvan', 'Pallan'],
    'Agamudayar': ['Agamudayar', 'Arcot', 'Thuluva Vellala', 'Rajakula Agamudayar', 'Servai', 'Maniyakaarar', 'Agamudaya Mudaliar'],
    'Ambalakarar': ['Ambalakarar', 'Ambalakaran', 'Servai'],
    'Arunthathiyar': ['Arunthathiyar', 'Chakkiliyan', 'Madari', 'Madiga', 'Pagadai', 'Thoti', 'Adi Andhra'],
    'Arya Vysya': ['Komati', 'Vaisya', 'Aryavysya', 'Vysya', 'Gavara Komati'],
    'Badaga': ['Badaga', 'Lingayat Badaga', 'Wodeya'],
    'Balija Naidu': ['Balija', 'Balija Naidu', 'Gajula Balija', 'Vada Balija', 'Setti Balija', 'Kavarai'],
    'Bestha': ['Bestha', 'Besta', 'Siviar', 'Gangaputra', 'Boya Bestha'],
    'Bhandari': ['Bhandari', 'Bandari', 'Nayee Brahmin', 'Pronopokari'],
    'Boyar': ['Boyar', 'Boyer', 'Boya', 'Oddar', 'Naika'],
    'Brahmin': [
      'Iyer', 'Iyengar', 'Vadakalai', 'Thenkalai', 'Gurukkal', 'Smartha',
      'Madhwa', 'Vadama', 'Brahacharanam', 'Vathima', 'Ashtasahasram',
      'Mukkani', 'Sri Vaishnava', 'Sankethi', 'Saiva Brahmin', 'Dravida',
      'Deshastha', 'Kannada Brahmin', 'Telugu Brahmin', 'Niyogi', 'Vaidiki',
      'Marathi Brahmin', 'Gujarati Brahmin', 'Saraswat', 'Tuluva', 'Havyaka',
      'Embranthiri', 'Nambudiri', 'Kongu Brahmin', 'Goswami', 'Anavil',
    ],
    'Chettiar': [
      'Nagarathar', 'Nattukottai Chettiar', 'Vaniya Chettiar', 'Devanga Chettiar',
      'Sozhia Chettiar', 'Vellan Chettiar', 'Acharapakkam Chettiar', 'Beri Chettiar',
      'Elur Chettiar', 'Kasukara Chettiar', 'Manjaputhur Chettiar', 'Pattinavar Chettiar',
      'Pannirandam Chettiar', 'Pudukkadai Chettiar', 'Saiva Chettiar', 'Telugu Chettiar',
      'Kongu Chettiar', 'Parvatha Rajakulam', 'Ayira Vaisya', 'Gandla',
      '24 Manai Telugu Chettiar', 'Karpoora Chettiar', 'Senaikudaiyar', 'Kasukkara Chettiar',
    ],
    'Devandra Kula Vellalar': ['Pallar', 'Devendrakulathan', 'Kudumban', 'Kadaiyan', 'Kaladi', 'Pannadi', 'Vathiriyan', 'Devendra Kula Vellalan'],
    'Devanga': ['Devanga', 'Devanga Chettiar', 'Sedar', 'Settukkarar', 'Dhevanga'],
    'Gounder': [
      'Kongu Vellala Gounder', 'Vanniya Kula Kshatriya Gounder', 'Vettuva Gounder',
      'Nattu Gounder', 'Urali Gounder', 'Kurumba Gounder', 'Anuppa Vellala Gounder',
      'Padaithalai Gounder', 'Sanku Gounder', 'Pala Gounder', 'Poosari Gounder',
      'Kongu Gounder', 'Vokkaliga Gounder',
    ],
    'Gramani': ['Gramani', 'Sanar', 'Hindu Nadar'],
    'Isai Vellalar': ['Isai Vellalar', 'Melakkarar', 'Nattuvar', 'Thavil', 'Nagaswaram'],
    'Jangam': ['Jangam', 'Lingayat', 'Veerasaiva'],
    'Kaikolar': ['Sengunthar', 'Kaikolar', 'Senguntha Mudaliyar', 'Senguntha Mudaliar'],
    'Kallar': [
      'Piramalai Kallar', 'Esanattu Kallar', 'Kallar', 'Gandarvakottai Kallar',
      'Kootappal Kallar', 'Periya Suriyur Kallar', 'Ambalakarar', 'Thanjavur Kallar',
    ],
    'Kamma Naidu': ['Kamma', 'Kammavar Naidu', 'Kamma Naidu', 'Choudary', 'Kammavar'],
    'Kannadiyar': ['Kannadiyan', 'Kannada Saineegar', 'Dasapalanji'],
    'Karuneegar': ['Karuneegar', 'Kanakkar', 'Sozhia Karuneegar', 'Kaikkattu Karuneegar'],
    'Konar': ['Konar', 'Idaiyar', 'Ayar', 'Yadava', 'Golla', 'Krishnan Vagaiyara', 'Pillai Konar'],
    'Koteyar': ['Koteyar', 'Kotegara'],
    'Kshatriya Raju': ['Raju', 'Kshatriya Raju', 'Rajaka', 'Razu', 'Surya Vamsam'],
    'Kulalar': ['Kulalar', 'Kuyavar', 'Velar', 'Odde', 'Kummara', 'Kusavan'],
    'Kuravar': ['Kuravan', 'Sidhanar', 'Narikuravar', 'Kurava', 'Koravar'],
    'Kurumbar': ['Kurumba', 'Kuruba Gowda', 'Halumatha', 'Kurumba Gounder', 'Pal Kuruba'],
    'Maravar': ['Maravar', 'Agamudaya Maravar', 'Easanattu Maravar', 'Kondaiyankottai Maravar', 'Sembanad Maravar'],
    'Meenavar': ['Meenavar', 'Pattinavar', 'Parvatharajakulam', 'Sembadavar', 'Mukkuvar', 'Karaiyar', 'Nulayar', 'Mogaveera', 'Besta Meenavar'],
    'Moopanar': ['Moopanar', 'Mooppanar', 'Nattaman', 'Malayaman'],
    'Mudaliar': [
      'Arcot Mudaliar', 'Thuluva Vellala', 'Saiva Mudaliar', 'Senguntha Mudaliar',
      'Isai Vellala Mudaliar', 'Mudaliar Vellalar', 'Agamudaya Mudaliar', 'Kongu Mudaliar',
      'Sozhia Vellalar', 'Karkathar', 'Thondaimandala Mudaliar',
    ],
    'Mukkulathor': ['Agamudayar', 'Kallar', 'Maravar', 'Thevar', 'Mukkulathor'],
    'Mutharaiyar': ['Muthuraja', 'Mutharaiyar', 'Muthuraiyar', 'Mutracha', 'Ambalakarar', 'Servai', 'Thuraiyar'],
    'Nadar': ['Hindu Nadar', 'Gramani', 'Shanar', 'Nadar', 'Kongu Nadar', 'Karukku Pattayam', 'Mel Nadar', 'Nattathi Nadar', 'Santror'],
    'Naicker': ['Vanniya Naicker', 'Telugu Naicker', 'Kannada Naicker', 'Vaduga Naicker', 'Tottiya Naicker', 'Urali Naicker', 'Palayakkara Naicker'],
    'Naidu': ['Balija Naidu', 'Gavara Naidu', 'Kamma Naidu', 'Kapu Naidu', 'Velama Naidu', 'Telaga', 'Yadava Naidu', 'Ediga', 'Tottiyan', 'Munnuru Kapu', 'Perika Naidu'],
    'Nair': ['Nair', 'Menon', 'Kurup', 'Nambiar', 'Pillai', 'Kartha'],
    'Pandaram': ['Pandaram', 'Andi Pandaram', 'Pandaaram'],
    'Pandithar': ['Pandithar', 'Vaidyar', 'Navithar', 'Ambattar'],
    'Parkavakulam': ['Udayar', 'Malayaman', 'Surutiman', 'Nattaman', 'Moopanar'],
    'Pillai': [
      'Saiva Pillai', 'Karkartha Vellalar', 'Thondaimandala Vellalar', 'Arunattu Vellalar',
      'Kodikal Pillai', 'Nanjil Vellalar', 'Sozhia Vellalar', 'Karaikattu Vellalar',
      'Agamudaya Vellalar', 'Pandya Vellalar', 'Illaththu Pillai', 'Vellala Pillai',
    ],
    'Reddiar': ['Reddy', 'Reddiar', 'Ganjam Reddy', 'Motati Reddy', 'Palli Reddy', 'Pakanati', 'Velnati', 'Desuru Reddy', 'Gandla', 'Desai'],
    'Saliyar': ['Saliyar', 'Sali', 'Pattariyar', 'Karaikattu Saliyar', 'Padmasaliyar', 'Sourashtra Sali', 'Sale'],
    'Senaithalaivar': ['Senaithalaivar', 'Senaikudaiyar', 'Illaivaniar', 'Anuppan'],
    'Sourashtra': ['Sourashtra', 'Patnulkaran', 'Pattunoolkarar', 'Khatri', 'Saurashtra'],
    'Udayar': ['Udayar', 'Vellala Udayar', 'Moopanar', 'Gangai Vamsam'],
    'Vannar': ['Vannar', 'Ekali', 'Salavai Thozhilalar', 'Puthirai Vannan', 'Rajaka', 'Dhobi'],
    'Vanniyar': ['Vanniyar', 'Vanniya Kula Kshatriyar', 'Padayachi', 'Palli', 'Naicker', 'Gounder', 'Agnikula Kshatriya', 'Vanniar'],
    'Vellalar': [
      'Karkathar', 'Thondaimandala Saiva Vellalar', 'Arunattu Vellalar', 'Kongu Vellalar',
      'Nanjil Vellalar', 'Sozhia Vellalar', 'Karaikattu Vellalar', 'Pandya Vellalar',
      'Saiva Vellalar', 'Sirukudi Vellalar', 'Panneeru Vellalar', 'Vellan', 'Chozhia Vellalar',
    ],
    'Vettuva Gounder': ['Vettuvar', 'Vettuva Gounder', 'Vettuva'],
    'Vishwakarma': ['Achari', 'Asari', 'Kammalar', 'Kannar', 'Kollar', 'Thattar', 'Thatchar', 'Sirpi', 'Pancha Kammalar', 'Vishwabrahmin', 'Viswakarma'],
    'Yadava': ['Yadava', 'Konar', 'Idaiyar', 'Ayar', 'Golla', 'Asthathra Golla', 'Pakanati Golla'],
    'Yogeeswarar': ['Yogi', 'Yogeeswarar', 'Jogi', 'Yogeeswara'],
    'Veerasaiva Lingayat': ['Lingayat', 'Veerasaiva', 'Jangam', 'Banajiga', 'Sadar Lingayat'],
    'Other Hindu': ['Caste No Bar', 'Other'],
  },

  // ============================ MUSLIM ===================================
  Muslim: {
    'Sunni': ['Sunni', 'Hanafi', 'Shafi', 'Sunni Hanafi', 'Sunni Shafi'],
    'Shia': ['Shia', 'Ithna Ashari', 'Bohra', 'Ismaili', 'Dawoodi Bohra'],
    'Sheikh': ['Sheikh', 'Shaik'],
    'Syed': ['Syed', 'Sayyad', 'Sayyid'],
    'Pathan': ['Pathan', 'Khan', 'Pashtun'],
    'Mughal': ['Mughal', 'Mogal'],
    'Labbai': ['Labbai', 'Lebbai', 'Labba', 'Sunni Labbai'],
    'Marakayar': ['Marakayar', 'Marakkayar', 'Maraikkayar', 'Marakkar'],
    'Rowther': ['Rowther', 'Ravuthar', 'Rawther', 'Ravuther'],
    'Kayalar': ['Kayalar', 'Kayal', 'Kayalan'],
    'Dudekula': ['Dudekula', 'Pinjari', 'Laddaf'],
    'Ansari': ['Ansari', 'Julaha', 'Momin'],
    'Mappila': ['Mappila', 'Mapilla', 'Moplah'],
    'Memon': ['Memon', 'Kutchi Memon'],
    'Dekkani': ['Dekkani', 'Deccani', 'Urdu Muslim'],
    'Other Muslim': ['Tamil Muslim', 'Caste No Bar', 'Other'],
  },

  // ============================ CHRISTIAN ================================
  Christian: {
    'Roman Catholic': ['Roman Catholic', 'Latin Catholic', 'Syrian Catholic', 'RC'],
    'Church of South India': ['CSI', 'Church of South India', 'Anglican'],
    'Protestant': ['Protestant', 'Lutheran', 'Methodist', 'Reformed', 'Presbyterian'],
    'Pentecostal': ['Pentecostal', 'Assembly of God', 'The Pentecostal Mission', 'Indian Pentecostal Church', 'Charismatic'],
    'Baptist': ['Baptist', 'Evangelical Baptist'],
    'Seventh Day Adventist': ['Seventh Day Adventist', 'Adventist'],
    'Born Again': ['Born Again', 'Non Denominational'],
    'Evangelical': ['Evangelical', 'Brethren'],
    'Marthoma': ['Marthoma', 'Mar Thoma'],
    'Jacobite': ['Jacobite', 'Syrian Jacobite'],
    'Orthodox': ['Orthodox', 'Syrian Orthodox', 'Malankara Orthodox'],
    'Syro Malabar': ['Syro Malabar', 'Syro-Malabar'],
    'Syro Malankara': ['Syro Malankara', 'Syro-Malankara'],
    'Knanaya': ['Knanaya', 'Knanaya Catholic', 'Knanaya Jacobite'],
    'Salvation Army': ['Salvation Army'],
    'Nadar Christian': ['Nadar Christian', 'Christian Nadar'],
    'Adi Dravida Christian': ['Adi Dravida Christian', 'Dalit Christian'],
    'Paravar': ['Paravar', 'Bharathar', 'Mukkuvar Christian', 'Fernando'],
    'Vellalar Christian': ['Vellalar Christian', 'Christian Vellalar'],
    'Other Christian': ['Caste No Bar', 'Other'],
  },

  // ============================ JAIN =====================================
  Jain: {
    'Digambar': ['Digambar', 'Digambara'],
    'Svetambar': ['Svetambar', 'Shwetambar', 'Swetambar'],
    'Tamil Jain': ['Tamil Jain', 'Samanar', 'Nainar'],
    'Oswal': ['Oswal', 'Osval'],
    'Bania Jain': ['Bania', 'Vania', 'Vaishya Jain'],
    'Marwari Jain': ['Marwari Jain', 'Marwadi'],
    'Gujarati Jain': ['Gujarati Jain'],
    'Other Jain': ['Sarak', 'Caste No Bar', 'Other'],
  },

  // ============================ SIKH =====================================
  Sikh: {
    'Jat Sikh': ['Jat Sikh', 'Jat'],
    'Khatri Sikh': ['Khatri', 'Khatri Sikh'],
    'Arora': ['Arora', 'Arora Sikh'],
    'Ramgarhia': ['Ramgarhia', 'Ramgharia'],
    'Ahluwalia': ['Ahluwalia', 'Kalal'],
    'Saini': ['Saini'],
    'Mazhabi': ['Mazhabi', 'Majhabi', 'Ramdasia'],
    'Other Sikh': ['Caste No Bar', 'Other'],
  },

  // ============================ BUDDHIST =================================
  Buddhist: {
    'Navayana': ['Navayana', 'Neo Buddhist', 'Ambedkarite Buddhist'],
    'Theravada': ['Theravada', 'Hinayana'],
    'Mahayana': ['Mahayana'],
    'Tamil Buddhist': ['Tamil Buddhist'],
    'Other Buddhist': ['Caste No Bar', 'Other'],
  },

  // ============================ PARSI / ZOROASTRIAN ======================
  Parsi: {
    'Parsi': ['Parsi', 'Zoroastrian'],
    'Irani': ['Irani'],
  },

  // ============================ OTHERS ===================================
  Others: {
    'Inter Caste': ['Inter Caste', 'Inter-Caste'],
    'Spiritual': ['Spiritual', 'Believer in God'],
    'No Religion': ['No Religion', 'Atheist', 'Agnostic'],
    'Brahmo': ['Brahmo Samaj'],
    'Other': ['Caste No Bar', 'Other'],
  },
};

// ─────────────────────────────────────────────────────────────────────────────
// 2. HELPERS  —  normalization, slug IDs
// ─────────────────────────────────────────────────────────────────────────────

/** Normalize a display name: trim, collapse whitespace, Title-Case (preserving
 *  known acronyms), normalize separators. */
const ACRONYMS = new Set(['CSI', 'RC', 'AG', 'TPM', 'SC', 'ST', 'BC', 'MBC', 'DNC']);
function normalizeName(raw) {
  let s = String(raw).replace(/\s+/g, ' ').trim();
  // unify dash spacing e.g. "Syro-Malabar" stays, "Inter - Caste" -> "Inter-Caste"
  s = s.replace(/\s*-\s*/g, '-');
  return s
    .split(' ')
    .map((word) =>
      word
        .split('-')
        .map((part) => {
          const upper = part.toUpperCase();
          if (ACRONYMS.has(upper)) return upper;
          if (/^\d+$/.test(part)) return part; // keep numbers like "24"
          return part.charAt(0).toUpperCase() + part.slice(1).toLowerCase();
        })
        .join('-'),
    )
    .join(' ');
}

/** slugify for stable, human-readable Firestore document IDs. */
function slug(s) {
  return String(s)
    .toLowerCase()
    .replace(/&/g, 'and')
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. BUILD  —  dedupe, normalize, generate IDs, validate
// ─────────────────────────────────────────────────────────────────────────────
const religions = [];
const castes = [];
const subcastes = [];

const religionIds = new Set();
const casteIds = new Set();
const subcasteIds = new Set();

let dupCastes = 0;
let dupSubcastes = 0;

for (const [religionRaw, casteMap] of Object.entries(DATA)) {
  const religionName = normalizeName(religionRaw);
  const religionId = `rel_${slug(religionName)}`;
  if (religionIds.has(religionId)) {
    throw new Error(`Duplicate religion id: ${religionId}`);
  }
  religionIds.add(religionId);
  religions.push({ id: religionId, name: religionName });

  // De-duplicate castes within this religion (case-insensitive on normalized name).
  const seenCasteNames = new Set();

  for (const [casteRaw, subList] of Object.entries(casteMap)) {
    const casteName = normalizeName(casteRaw);
    const casteKey = casteName.toLowerCase();
    if (seenCasteNames.has(casteKey)) {
      dupCastes++;
      continue;
    }
    seenCasteNames.add(casteKey);

    const casteId = `cas_${slug(religionName)}_${slug(casteName)}`;
    if (casteIds.has(casteId)) {
      dupCastes++;
      continue;
    }
    casteIds.add(casteId);
    castes.push({ id: casteId, religionId, name: casteName });

    // De-duplicate sub-castes within this caste.
    const seenSubNames = new Set();
    for (const subRaw of subList) {
      const subName = normalizeName(subRaw);
      const subKey = subName.toLowerCase();
      if (seenSubNames.has(subKey)) {
        dupSubcastes++;
        continue;
      }
      seenSubNames.add(subKey);

      const subId = `sub_${slug(religionName)}_${slug(casteName)}_${slug(subName)}`;
      if (subcasteIds.has(subId)) {
        dupSubcastes++;
        continue;
      }
      subcasteIds.add(subId);
      subcastes.push({ id: subId, casteId, name: subName });
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. VALIDATE parent-child integrity
// ─────────────────────────────────────────────────────────────────────────────
const errors = [];
for (const c of castes) {
  if (!religionIds.has(c.religionId)) {
    errors.push(`Caste ${c.id} references missing religion ${c.religionId}`);
  }
}
for (const s of subcastes) {
  if (!casteIds.has(s.casteId)) {
    errors.push(`Sub-caste ${s.id} references missing caste ${s.casteId}`);
  }
}
if (errors.length) {
  console.error('VALIDATION FAILED:');
  for (const e of errors) console.error('  - ' + e);
  process.exit(1);
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. WRITE OUTPUT
// ─────────────────────────────────────────────────────────────────────────────
const outDir = path.join(__dirname, '..', 'master_data');
fs.mkdirSync(outDir, { recursive: true });

const write = (file, data) =>
  fs.writeFileSync(path.join(outDir, file), JSON.stringify(data, null, 2) + '\n', 'utf8');

write('master_religions.json', religions);
write('master_castes.json', castes);
write('master_subcastes.json', subcastes);

// ─────────────────────────────────────────────────────────────────────────────
// 6. STATISTICS
// ─────────────────────────────────────────────────────────────────────────────
const castesPerReligion = religions.map((r) => ({
  religion: r.name,
  castes: castes.filter((c) => c.religionId === r.id).length,
}));

console.log('\n  Tamil Nadu Matrimony — Master Database built\n');
console.log('  Output: master_data/{master_religions,master_castes,master_subcastes}.json\n');
console.log('  ── Statistics ───────────────────────────────────────');
console.log(`  Total Religions : ${religions.length}`);
console.log(`  Total Castes    : ${castes.length}`);
console.log(`  Total Subcastes : ${subcastes.length}`);
console.log(`  Duplicate castes removed    : ${dupCastes}`);
console.log(`  Duplicate subcastes removed : ${dupSubcastes}`);
console.log('  ─────────────────────────────────────────────────────');
console.log('  Castes per religion:');
for (const row of castesPerReligion) {
  console.log(`    ${row.religion.padEnd(20)} ${String(row.castes).padStart(3)}`);
}
console.log('  ─────────────────────────────────────────────────────');
console.log('  Parent-child validation: PASSED\n');

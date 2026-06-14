/**
 * Import the generated location master datasets into Firestore.
 *
 * Collections created (document IDs = the `id` field, so re-running is idempotent):
 *   master_states     { id, name, country }
 *   master_districts  { id, name, stateId, stateName }
 *   master_cities     { id, name, districtId, districtName, stateId, stateName }
 *
 * Run (from scripts/, after `npm i firebase-admin`):
 *   GOOGLE_APPLICATION_CREDENTIALS=./serviceAccount.json node import_location_data.js
 *
 * Idempotent: documents are written with their stable id via set(), so
 * re-running overwrites in place rather than duplicating.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

const DATA_DIR = path.join(__dirname, '..', 'assets', 'master_data', 'location');
const COLLECTIONS = [
  { collection: 'master_states', file: 'master_states.json' },
  { collection: 'master_districts', file: 'master_districts.json' },
  { collection: 'master_cities', file: 'master_cities.json' },
];

const load = (file) => JSON.parse(fs.readFileSync(path.join(DATA_DIR, file), 'utf8'));

async function importCollection(name, file) {
  const rows = load(file);
  let written = 0;
  // Firestore batches cap at 500 writes.
  for (let i = 0; i < rows.length; i += 450) {
    const batch = db.batch();
    for (const row of rows.slice(i, i + 450)) {
      batch.set(db.collection(name).doc(row.id), row);
      written++;
    }
    await batch.commit();
  }
  console.log(`  ${name.padEnd(18)} imported ${written} docs`);
}

(async () => {
  console.log('Importing location master data into Firestore...');
  for (const { collection, file } of COLLECTIONS) {
    await importCollection(collection, file);
  }
  console.log('Done.');
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});

/**
 * Import the generated master datasets into Firestore.
 *
 * Collections created (document IDs = the `id` field, so re-running is idempotent):
 *   master_religions  { id, name }
 *   master_castes     { id, religionId, name }
 *   master_subcastes  { id, casteId, name }
 *
 * Run (from scripts/, after `npm i firebase-admin`):
 *   GOOGLE_APPLICATION_CREDENTIALS=./serviceAccount.json node import_master_data.js
 *
 * Idempotent: documents are written with their stable slug id via set(), so
 * re-running overwrites in place rather than duplicating.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

const DATA_DIR = path.join(__dirname, '..', 'master_data');
const COLLECTIONS = [
  'master_religions',
  'master_castes',
  'master_subcastes',
];

const load = (file) =>
  JSON.parse(fs.readFileSync(path.join(DATA_DIR, file + '.json'), 'utf8'));

async function importCollection(name) {
  const rows = load(name);
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
  console.log('Importing master data into Firestore...');
  for (const name of COLLECTIONS) {
    await importCollection(name);
  }
  console.log('Done.');
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});

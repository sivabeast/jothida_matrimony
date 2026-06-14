/**
 * Import the astrology master datasets into Firestore.
 *
 * Collections (document IDs = the `id` field, so re-running is idempotent):
 *   master_rasi        { id, nameTamil, nameEnglish, order }
 *   master_nakshatra   { id, nameTamil, nameEnglish, order }
 *   master_lagnam      { id, nameTamil, nameEnglish, order }
 *
 * Run (from scripts/, after `npm i firebase-admin`):
 *   GOOGLE_APPLICATION_CREDENTIALS=./serviceAccount.json node import_astrology_data.js
 */
'use strict';

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

const DATA_DIR = path.join(__dirname, '..', 'master_data', 'astrology');
const COLLECTIONS = ['master_rasi', 'master_nakshatra', 'master_lagnam'];

const load = (file) =>
  JSON.parse(fs.readFileSync(path.join(DATA_DIR, file + '.json'), 'utf8'));

async function importCollection(name) {
  const rows = load(name);
  const batch = db.batch();
  for (const row of rows) {
    batch.set(db.collection(name).doc(row.id), row);
  }
  await batch.commit();
  console.log(`  ${name.padEnd(18)} imported ${rows.length} docs`);
}

(async () => {
  console.log('Importing astrology master data into Firestore...');
  for (const name of COLLECTIONS) {
    await importCollection(name);
  }
  console.log('Done.');
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});

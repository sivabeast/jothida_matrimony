/**
 * Seed the Religion → Caste → Subcaste master data into Firestore.
 *
 * Uploads each record using its `id` field as the Firestore document id, so the
 * app's queries (master_castes where religionId == X, etc.) work directly.
 * Idempotent (set with merge) — safe to re-run.
 *
 * RUN ONCE (after deploying the new firestore.rules), from this folder:
 *   cd jothida_matrimony/master_data
 *   npm init -y && npm i firebase-admin
 *   GOOGLE_APPLICATION_CREDENTIALS=./serviceAccount.json node seed_master_data.js
 */
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

admin.initializeApp();
const db = admin.firestore();

async function seed(file, collection) {
  const items = JSON.parse(fs.readFileSync(path.join(__dirname, file), 'utf8'));
  let batch = db.batch();
  let pending = 0;
  let total = 0;
  for (const item of items) {
    const { id, ...data } = item;
    if (!id) continue;
    batch.set(db.collection(collection).doc(id), data, { merge: true });
    pending++;
    total++;
    if (pending >= 400) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (pending > 0) await batch.commit();
  console.log(`Seeded ${total} documents → ${collection}`);
}

(async () => {
  await seed('master_religions.json', 'master_religions');
  await seed('master_castes.json', 'master_castes');
  await seed('master_subcastes.json', 'master_subcastes');
  console.log('Master data seeding complete.');
  process.exit(0);
})().catch((err) => {
  console.error('Seeding failed:', err);
  process.exit(1);
});

/**
 * One-time data migration — move contact details OUT of public profiles.
 *
 * Before: each `profiles/{id}` document held a `contact` map (mobile/WhatsApp)
 * that any signed-in user could read by browsing.
 * After:  contact details live in `contacts/{userId}` and unlock only after a
 *         mutually-accepted interest (see firestore.rules + connections).
 *
 * This script copies every profile's embedded `contact` into
 * `contacts/{userId}` and then deletes the `contact` field from the profile.
 *
 * RUN ONCE, AFTER deploying the new firestore.rules / storage.rules:
 *   cd jothida_matrimony/scripts
 *   npm init -y && npm i firebase-admin
 *   GOOGLE_APPLICATION_CREDENTIALS=./serviceAccount.json node migrate_contacts.js
 *
 * It is idempotent: re-running it simply finds no remaining `contact` fields.
 */
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

(async () => {
  const snap = await db.collection('profiles').get();
  let moved = 0;
  let skipped = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    const contact = data.contact;
    const userId = data.userId;

    if (!contact || !userId) {
      skipped++;
      continue;
    }

    await db
      .collection('contacts')
      .doc(userId)
      .set(
        { ...contact, userId, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true }
      );

    await doc.ref.update({ contact: admin.firestore.FieldValue.delete() });
    moved++;
  }

  console.log(`Contact migration complete. Moved ${moved}, skipped ${skipped}.`);
  process.exit(0);
})().catch((err) => {
  console.error('Migration failed:', err);
  process.exit(1);
});

# Astrology Master Database — Rasi / Nakshatra / Lagnam

Production-ready Vedic astrology master datasets for the matrimony app.

## Files

| File | Collection | Schema | Count |
|------|-----------|--------|------:|
| `master_rasi.json` | `master_rasi` | `{ id, nameTamil, nameEnglish, order }` | 12 |
| `master_nakshatra.json` | `master_nakshatra` | `{ id, nameTamil, nameEnglish, order }` | 27 |
| `master_lagnam.json` | `master_lagnam` | `{ id, nameTamil, nameEnglish, order }` | 12 |

## Statistics

- **Total Rasi:** 12
- **Total Nakshatra:** 27
- **Total Lagnam:** 12

All entries carry both `nameTamil` (Tamil script) and `nameEnglish` (standard
romanized transliteration), are de-duplicated, and are sorted by traditional
`order` (Rasi: Mesham → Meenam, Nakshatra: Ashwini → Revathi, Lagnam: Mesha →
Meena).

## IDs

Stable, human-readable slug IDs (also used as Firestore document IDs, so imports
are idempotent):

- Rasi: `rasi_<name>` → `rasi_mesham`
- Nakshatra: `nak_<name>` → `nak_ashwini`
- Lagnam: `lag_<name>` → `lag_mesha_lagnam`

## Regenerate

Edit the data in `scripts/build_astrology_data.js`, then:

```bash
node scripts/build_astrology_data.js
```

## Import into Firestore

Document IDs equal the `id` field, so importing is idempotent:

```bash
cd scripts
npm i firebase-admin
GOOGLE_APPLICATION_CREDENTIALS=./serviceAccount.json node import_astrology_data.js
```

# Tamil Nadu Matrimony — Religion → Caste → Sub-caste Master Database

Production-ready master datasets for the matrimony app's dependent
Religion → Caste → Sub-caste dropdowns.

## Files

| File | Schema | Count |
|------|--------|------:|
| `master_religions.json` | `{ id, name }` | 8 |
| `master_castes.json` | `{ id, religionId, name }` | 121 |
| `master_subcastes.json` | `{ id, casteId, name }` | 541 |

## Statistics

- **Total Religions:** 8 — Hindu, Muslim, Christian, Jain, Sikh, Buddhist, Parsi, Others
- **Total Castes:** 121
- **Total Subcastes:** 541

Castes per religion: Hindu 57 · Muslim 16 · Christian 20 · Jain 8 · Sikh 8 ·
Buddhist 5 · Parsi 2 · Others 5.

The Hindu set spans the commonly-used BC / MBC / DNC / SC / ST matrimony
communities of Tamil Nadu (Vanniyar, Mukkulathor/Thevar, Nadar, Gounder,
Chettiar, Mudaliar, Vellalar, Naidu, Reddiar, Vishwakarma, Adi Dravidar,
Arunthathiyar, Devandra Kula Vellalar, etc.).

## IDs

Stable, human-readable slug IDs that also encode the parent link, so
parent-child integrity is guaranteed by construction and imports are idempotent:

- religion: `rel_<religion>` → `rel_hindu`
- caste: `cas_<religion>_<caste>` → `cas_hindu_nadar`
- sub-caste: `sub_<religion>_<caste>_<subcaste>` → `sub_hindu_nadar_gramani`

## Regenerate

The JSON is generated — edit the data in `scripts/build_master_data.js`, not the
JSON by hand, then:

```bash
node scripts/build_master_data.js
```

The build step normalizes names (Title-Case, whitespace, separators, known
acronyms), removes duplicate castes (per religion) and duplicate sub-castes
(per caste), generates IDs, and validates every parent-child link.

## Import into Firestore

Document IDs equal the `id` field, so importing is idempotent (re-run to update
in place — no duplicates):

```bash
cd scripts
npm i firebase-admin
GOOGLE_APPLICATION_CREDENTIALS=./serviceAccount.json node import_master_data.js
```

## Sources

Compiled from publicly available sources commonly used by Tamil Nadu matrimony
platforms and Government of Tamil Nadu community lists:

- Tamil Nadu BC / MBC / DNC community lists (BCMBCMW Dept., tn.gov.in)
- Tamil Nadu SC / ST lists (Adi Dravidar & Tribal Welfare Dept.)
- Caste/community dropdowns published by major matrimony portals

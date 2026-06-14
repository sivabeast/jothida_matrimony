# India Location Master Database — State → District → City

Production-ready location master datasets for the matrimony app's dependent
**State → District → City** dropdowns.

## Files

| File | Schema | Count |
|------|--------|------:|
| `master_states.json` | `{ id, name, country }` | 36 |
| `master_districts.json` | `{ id, name, stateId, stateName }` | 631 |
| `master_cities.json` | `{ id, name, districtId, districtName, stateId, stateName }` | 11,079 |
| `master_location_stats.json` | `{ states, districts, cities }` | — |

```json
// master_states.json
{ "id": "TN", "name": "Tamil Nadu", "country": "India" }

// master_districts.json
{ "id": "TN_MAD", "name": "Madurai", "stateId": "TN", "stateName": "Tamil Nadu" }

// master_cities.json
{ "id": "TN_MAD_MADURAI", "name": "Madurai", "districtId": "TN_MAD",
  "districtName": "Madurai", "stateId": "TN", "stateName": "Tamil Nadu" }
```

## Coverage

- **36** states & union territories — all **28 states + 8 UTs** (2026).
- **631** districts across every state/UT.
- **11,079** cities — taluk headquarters, municipalities, towns and every
  district headquarters, deduplicated per district.

The hierarchy is internally consistent: every city nests under a real district
of a real state, with no orphan or empty nodes.

## Data source

The **All-India Pincode (Post Office) Directory** published by the Department of
Posts, Government of India (data.gov.in). Each record links a place to its
*taluk → district → state*, which is what guarantees the hierarchy holds
together. The build consumes the cleaned community mirror of that dataset:

- `https://raw.githubusercontent.com/mithunsasidharan/India-Pincode-Lookup/master/pincodes.json`
  — record shape `{ officeName, pincode, taluk, districtName, stateName }`.

### Correction layer

The pincode directory predates two state reorganisations, which the builder
fixes so the data reflects the current map of India:

1. **Telangana (2014)** — its 10 legacy districts (Adilabad, Hyderabad,
   Ranga Reddy, Karimnagar, Khammam, Mahabubnagar, Medak, Nalgonda, Nizamabad,
   Warangal) are reassigned from *Andhra Pradesh* to **Telangana**.
2. **Ladakh (2019)** — *Leh* and *Kargil* are reassigned from
   *Jammu & Kashmir* to **Ladakh**.
3. **Dadra & Nagar Haveli and Daman & Diu (2020)** are merged into one UT.

State names are normalised to their current official forms and 2-letter codes;
a few districts are renamed to their modern spellings (e.g. Bangalore →
Bengaluru, Cuddapah → Kadapa).

> Note: district boundaries reflect the source directory's vintage (~631
> districts). Districts created by more recent bifurcations fold into their
> parent district — appropriate and stable for matrimony location dropdowns.

## IDs

Stable, human-readable IDs that also encode the parent link, so parent-child
integrity is guaranteed by construction and imports are idempotent:

- state: `<CODE>` → `TN`
- district: `<STATE>_<ABBR>` → `TN_MAD`
- city: `<STATE>_<ABBR>_<CITY>` → `TN_MAD_MADURAI`

District abbreviations are generated deterministically (first letters, with
collision resolution), unique within each state.

## Regenerate

The JSON is generated — do not edit it by hand. Re-run the builder (downloads
the source, cleans, dedupes, normalises, validates and writes all four files):

```bash
node scripts/build_location_database.js
# or, against a local copy of the source dataset:
node scripts/build_location_database.js --input ./pincodes.json
```

## Import into Firestore

Document IDs equal the `id` field, so importing is idempotent (re-run to update
in place — no duplicates):

```bash
cd scripts
npm i firebase-admin
GOOGLE_APPLICATION_CREDENTIALS=./serviceAccount.json node import_location_data.js
```

This creates three collections — `master_states`, `master_districts`,
`master_cities` — each document keyed by its `id`. Query the dependent
dropdowns with:

```js
db.collection('master_districts').where('stateId', '==', 'TN')
db.collection('master_cities').where('districtId', '==', 'TN_MAD')
```

## Use in the Flutter app

The files ship as bundled assets. Register the folder in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/master_data/location/
```

Load and filter locally (no network needed), or read from Firestore if you
imported them there.

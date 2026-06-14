# Tamil Nakshatra Compatibility Dataset

`master_nakshatra_compatibility.json` — a 27×27 marriage-compatibility dataset
for all Tamil nakshatras, for use in the Jothida Matrimony application.

> **Read this first — how the data was produced.**
> There is **no single book or published table** that pre-labels every one of
> the 27×27 nakshatra pairs as "excellent / good / average / poor." Classical
> Tamil and Vedic sources document the **matching rules** (the Poruthams and
> Kootas); the four-level compatibility grade is *derived* by applying those
> rules to a pair. Accordingly, this dataset is **computed deterministically
> from the documented classical rule tables** — it is **not** invented, and it
> does **not** claim a per-pair citation that does not exist. The rule tables
> themselves are sourced from the references listed below, and the whole file
> can be regenerated and audited from the open generator script.

---

## Files

| File | Purpose |
|------|---------|
| `master_nakshatra_compatibility.json` | The dataset (27 nakshatras × 4 categories). |
| `../../tool/generate_nakshatra_compatibility.dart` | The generator. Encodes the classical rule tables and computes the dataset. Run to reproduce/audit. |
| `NAKSHATRA_COMPATIBILITY_README.md` | This document. |

Regenerate:

```bash
dart run tool/generate_nakshatra_compatibility.dart
```

---

## Sources used

The compatibility rules and classification tables are taken from established
classical references (not random websites):

1. **Traditional Tamil Thirumana Porutham tables** — the standard ten-porutham
   (பத்து பொருத்தம்) marriage-matching system used across Tamil Nadu. Supplies:
   Dina (Tara), Gana, Mahendra, Sthree Dheerga, Yoni, Rajju and Vedha
   poruthams. *(Type: Book / Astrology Table)*
2. **Ashtakoota Guna Milan** — classical Vedic compatibility (after
   *Brihat Parashara Hora Shastra* and standard Muhurta/marriage texts).
   Supplies the **Nadi koota** grouping and the **Yoni koota** animal/enmity
   classification. *(Type: Classical Vedic Reference)*

Each nakshatra record in the JSON carries a `sources` array naming these
references and their type.

---

## Methodology

For every ordered pair **(girl's star → boy's star)** the generator applies the
documented rules and assigns one of four grades. Convention:

- **Top-level key = the girl/bride nakshatra.**
- **Entries inside its buckets = the boy/groom nakshatra.**

Because three poruthams (Dina, Mahendra, Sthree Dheerga) are reckoned by
*counting from the girl's star to the boy's star*, the table is intentionally
**directional/asymmetric** — `rohini → hastham` is not necessarily the same as
`hastham → rohini`. This mirrors real Tamil practice of casting porutham "from
the girl's star."

### Rules applied (all nakshatra-derivable)

| Porutham / Koota | Rule | Effect |
|---|---|---|
| **Rajju** | Same Rajju group between partners | **Critical dosha → `poor`** |
| **Nadi** | Same Nadi group between partners | **Critical dosha → `poor`** |
| **Dina (Tara)** | Count girl→boy, `count % 9 ∈ {2,4,6,8,0}` | +1 favourable |
| **Gana** | Same gana, or Deva↔Manushya | +1 favourable |
| **Yoni** | Same/non-enemy animal | +1 favourable; **enemy caps grade at `average`** |
| **Mahendra** | Count ∈ {4,7,10,13,16,19,22,25} | +1 favourable |
| **Sthree Dheerga** | Count girl→boy `> 9` | +1 favourable |
| **Vedha** | Not a vedha pair | +1 favourable; **vedha caps grade at `average`** |

### Compatibility logic (scoring → category)

1. If **Rajju dosha** (same Rajju) or **Nadi dosha** (same Nadi) → **`poor`**,
   regardless of other factors. These are the two afflictions classically
   treated as grounds to reject a match.
2. Otherwise start from a baseline of **4 points** (Rajju + Nadi both clear,
   weighted 2 each) and add **+1** for each of the six favourable factors
   above (max **10**).
3. Bin the score:
   - **excellent** — score ≥ 9
   - **good** — score 7–8
   - **average** — score 5–6
   - **poor** — score ≤ 4
4. A **Yoni-enemy** or **Vedha** defect caps the result at **`average`** even
   when the numeric score is higher (both are classically significant
   negatives).

This 5-star verdict used elsewhere in the app maps naturally onto the same
grades (Excellent / Good / Average / Poor → ★★★★★ … ★★).

---

## Data layout

```json
{
  "_meta": { "...": "convention, derivation, critical doshas" },
  "rohini": {
    "excellent": ["ashwini", "bharani", "punarpoosam", "pooradam", "poorattadhi"],
    "good":      ["mirugasirisham", "poosam", "..."],
    "average":   [],
    "poor":      ["karthigai", "thiruvathirai", "..."],
    "sources": [
      { "reference": "Traditional Tamil Thirumana Porutham tables ...", "type": "Book / Astrology Table", "notes": "..." },
      { "reference": "Ashtakoota Guna Milan ...", "type": "Classical Vedic Reference", "notes": "..." }
    ]
  }
}
```

Nakshatra keys (lowercase English) match `master_nakshatra.json`:
`ashwini, bharani, karthigai, rohini, mirugasirisham, thiruvathirai,
punarpoosam, poosam, ayilyam, magham, pooram, uthiram, hastham, chithirai,
swathi, visakam, anusham, kettai, moolam, pooradam, uthiradam, thiruvonam,
avittam, sathayam, poorattadhi, uthirattadhi, revathi`.

---

## Record counts

- **Nakshatras (top-level keys):** 27
- **Directed pairs classified:** 702 (27 × 26; self-pairs excluded)
- **Categories per nakshatra:** 4 (always present, partition the other 26 stars)
- **Distribution across all 702 pairs:**
  - excellent: **110**
  - good: **276**
  - average: **46**
  - poor: **270**

The large `poor` share is expected, not a bug: every star shares its **Nadi**
group with 8 other stars and its **Rajju** group with ~5 others, and both are
auto-rejecting doshas. Classical matching is deliberately strict here.

### Validation guarantees

- All 27 nakshatras are covered.
- For each nakshatra the four buckets together contain **exactly the other 26
  stars** — no duplicates, no self-reference, no missing category.
- Consistent lowercase naming aligned with `master_nakshatra.json`.
- Every record carries a documented `sources` array.

---

## Data limitations (please read before relying on this in production)

1. **Rule-derived, not a transcribed lookup table.** The grades are computed
   from the classical rules. Where a published per-pair almanac (panchangam)
   differs, the almanac should be considered authoritative.
2. **Nakshatra-only.** This dataset uses *only* the star (and the rasi/lord and
   Vasya/Bhakoot factors that need the moon-sign are **not** included here).
   A complete porutham reading also weighs Rasi, Rasi-Adhipathi and Vasya
   poruthams, plus Lagnam, Dosham (Chevvai/Manglik) and exact birth details —
   see `lib/core/services/porutham_match.dart` for the app's fuller per-couple
   computation that does use rasi.
3. **Pada (quarter) ignored.** Several refinements (e.g. same-star same-pada
   rules, finer Dina/Tara from the exact pada) require the nakshatra *pada*,
   which a star-only table cannot express.
4. **Regional variation.** Tamil, Kerala and North-Indian traditions differ in
   some Yoni/Rajju/Vedha details and in dosha-cancellation rules. The tables
   here follow the mainstream Tamil ten-porutham + Ashtakoota Nadi/Yoni
   convention; other lineages may grade a few pairs differently.
5. **Scoring thresholds are a documented heuristic.** The 2/2/1… weighting and
   the 9/7/5 score bands are a transparent, consistent binning choice defined
   in the generator — not a figure quoted from a single text. They can be
   tuned in one place (`tool/generate_nakshatra_compatibility.dart`) and the
   dataset regenerated.
6. **Not a substitute for an astrologer.** This supports shortlisting only.
   Final marriage compatibility should be confirmed by a qualified astrologer
   with the full horoscopes.

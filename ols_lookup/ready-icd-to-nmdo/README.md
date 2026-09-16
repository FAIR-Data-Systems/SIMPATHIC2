# REaDY ICD → NMDO mapping (pilot)

**Ask (EURO-NMD, via REaDY project manager):** REaDY (Registry of muscular
DYstrophies — DMD/BMD, SMA, DM, FSHD, LGMD) wants to know whether its clinical
coding can be aligned to NMDO. They shared the two ICD catalogs REaDY draws on
for autocomplete: `ICD11_2025-01-24_EN.xlsx` (WHO ICD-11, English) and
`MKN10_CZ.xlsx` (Czech ICD-10 / MKN-10), plus five per-disease questionnaire
study-structure PDFs.

## What the source files actually are

Both ICD files are **complete national/international catalogs** — 18,351 and
38,814 rows respectively — not a REaDY-specific pick-list. Reading the
questionnaire PDFs confirmed ICD codes are used for a handful of open-ended
fields (hospitalisation reason, "other" comorbidity, cause of death) that
could in principle reference *any* code in either catalog. A full mapping run
would be the complete answer, but at ~1s/query against nmdo-search that's
~57,000 queries — hours of runtime, mostly spent on codes with no
neuromuscular relevance (cholera, pregnancy, injuries, ...).

**This pilot scopes to the block that defines REaDY's five target diseases**:
ICD-11 blocks 8B6x/8C7x/8C8x/8D0x (spinal muscular atrophy, muscular
dystrophies, myotonic disorders, myopathies, neuromuscular junction disorders)
and the equivalent MKN-10 blocks G12, G70–G73. That's 84 + 36 = 120 codes.
The broader open-ended-field question (does NMDO cover arbitrary
comorbidity/hospitalisation codes too?) is still open — see "Next" below.

## Pipeline

```
python3 extract_icd_catalogs.py     # xlsx -> scoped TSV (mockdata/*_scoped.tsv)
ruby map_icd_to_nmdo.rb             # TSV -> nmdo-search -> mapped_*.csv + mapping_stats.json
```

Reuses the spreadsheet-2-CARE conventions: SCORE_THRESHOLD 0.50, and the same
"prefer an exact label/synonym match among top-k candidates over the raw
top-1 score" rerank rule (`pick_exact_match`) used in `build_care_template.py`.

## Results (2026-09-14)

| Catalog | Codes | Mapped ≥0.50 | Mapped to MONDO | Mapped to HP |
|---|---:|---:|---:|---:|
| ICD-11 (English) | 84 | 84 (100%) | 77 | 7 |
| MKN-10 (Czech) | 36 | 36 (100%) | 34 | 2 |

**On "non-HPO" matches — these are expected, not a red flag.** The scoped
codes are disease *diagnoses* (muscular dystrophy, SMA, myopathy subtypes),
so per NMDO's own branch-tells-you-the-type convention (documented in
`../spreadsheet-2-CARE/PIPELINE.md` §3), the correct target is **MONDO**, not
HP — HP is for phenotypes/symptoms, which is a separate, smaller slice of
REaDY's data (free-text symptom fields, not these ICD codes). The 9 matches
that *did* land on HP (7 ICD-11, 2 MKN-10) are catch-all "other/unspecified"
codes or genuinely symptom-shaped concepts (e.g. "Central core disease" →
generic muscle-abnormality terms) — worth a curator's eye, not proof of MONDO
matches being wrong.

**Every catch-all code is a weak match, and that's the real signal.** 9 of
120 codes (4 ICD-11, 5 MKN-10) scored under 0.60 — every one of them is an
"other specified" / "unspecified" / NOS code with no precise single NMDO
term, landing instead on either an over-specific gene-level MONDO term (e.g.
"Other specified secondary myopathies" → "myopathy caused by variation in
POMGNT2", 0.508) or a generic catch-all (→ "neuromuscular disease", 0.515).
Full list in `mockdata/mapping_stats.json`. These are exactly the "imprecise
mapping" cases PIPELINE.md's curation workbook exists to catch — a 100% hit
rate at threshold does not mean 100% precise.

Full per-code output: `mockdata/mapped_icd11.csv`, `mockdata/mapped_mkn10.csv`.

## Next

- Curator review of the 9 sub-0.60 matches and the 9 HP-landed matches above.
- If EURO-NMD wants the open-ended-field question answered too: sample (not
  exhaustively run) the rest of both catalogs to estimate NMDO's real-world
  coverage of comorbidity/hospitalisation/cause-of-death codes, which will
  legitimately be much lower — NMDO is a neuromuscular ontology, not a
  general medical one.
- The actual "symptoms and phenotypes" free-text fields EURO-NMD originally
  asked about live in the questionnaire PDFs, not the ICD files — a separate
  pass once those fields are identified precisely.

## Data hygiene

All source/derived data lives under `mockdata/`, which is git-ignored
repo-wide (see `.gitignore: mockdata/`). Nothing here is committed.

# MYODRAFT CARE-SM mapping — findings and timing (2026-09-15)

This folder was a sandbox for testing spreadsheet-2-CARE against a real,
large, messy registry export — a longitudinal MYODRAFT dump: 25 patients,
**17,431 columns** (Baseline + up to 8 follow-up visits + proxy
questionnaires, checkbox items expanded one-per-option). The exporting
platform is not confirmed — the naming convention (event-numbered segments,
repeat-instance suffixes, checkbox-expanded columns) resembles common EDC
export shapes generally, but checked specifically against REDCap's actual
checkbox convention (`field___1`) and found none of that pattern here (this
file uses `field#Option_label` instead, 373 instances) — so "REDCap" below
should be read as "this style of registry export," not a confirmed platform
identification. Everything that
worked here has been **migrated into `../spreadsheet-2-CARE/`** — this
folder now holds only the source data and this report. See "What moved to
the real project" below.

## Headline: timing

| Stage | Time | Notes |
|---|---:|---|
| Offline column triage (free, no network) | 4–9s | 17,431 columns classified into lanes by value shape alone |
| Live nmdo-search prewarm, healthy run | ~380s (6.3 min) | 16,451–16,627 unique deduplicated queries, batched at 256/request |
| Live nmdo-search prewarm, one degraded run | 1241s (20.7 min) | batch endpoint dropped mid-run (`Connection reset by peer`); fallback to one-at-a-time calls kept it correct but slow — see "Reliability" below |
| Final classification/build pass (cache hits) | ~11–45s | pure computation, no network once prewarmed |
| **Typical end-to-end total** | **~6.5–7 minutes** | for the full 17,431-column dataset, one CARE-SM model |

For comparison: naive one-query-per-column would have been **~4.6 hours**
(16,451 queries × ~1s sequential). The realistic number to tell a user
up front is **"~6-7 minutes per model for a dataset this wide, occasionally
20+ minutes if the search service hiccups mid-run."**

## What moved to the real project (`../spreadsheet-2-CARE/`)

All of it is now default, automatic pipeline behavior — not a flag a user
has to know to set, and not something that depends on a human being in the
loop. Verified **byte-identical output** with `--no-prewarm` vs. the default
path on a known dataset before treating this as safe (see git history for
`profile_columns.py` / `build_care_template.py`).

1. **`HttpSearcher.prewarm()`** — given a set of queries, fetches them via
   `POST .../search_batch` in configurable-size batches (default 256)
   instead of one `GET .../search` per query. Falls back to sequential
   one-at-a-time calls, permanently for the rest of that run, the first time
   the batch endpoint errors — so it degrades gracefully against a
   search service that doesn't have the batch endpoint at all, not just a
   healthy one that happens to be running it.
2. **`collect_literal_queries()`** — a free (StubSearcher, no network) dry
   run that discovers every literal string the real classify() pass will
   query, recomputed directly from each column's own values rather than
   read back off classify()'s report dict (that dict's `sample` field is
   only the first 5 raw values, for display — reading it as a query plan
   silently under-covers what classify() actually queries internally, up to
   20 deduplicated values per SEARCH-lane column. This was a real bug in
   the sandbox version of this script, caught before migrating it: fixed by
   recomputing from `vals` directly instead of trusting the report dict).
3. **`collect_builder_queries()`** (build_care_template.py) — a second,
   targeted prewarm pass for Phenotype/Diagnosis, since those builders walk
   every ROW (uncapped), not just the profiling-stage's capped sample.
4. **`ensure_pid_column()`** — see "No patient ID column" below.
5. Both CLI tools now print offline-triage time, prewarm time, and total
   time to stderr by default — the metric to tell users what to expect from
   their dataset shape, per the request that started this work.

## What we found in the data itself

### 1. No patient/record identifier column at all

The export has **no ID column** — searched all 17,431 headers for anything
resembling `id`/`subject`/`patient`/`record`/`study`; every hit was a
false-positive substring match inside an unrelated field name. Before the
fix below, every builder's `if not pid: continue` guard fired on every row,
so **all 7 CARE-SM models silently emitted zero rows** — no error, just an
empty CSV that looked like "nothing here was mappable."

**Fixed in the real pipeline**: `profile_columns.ensure_pid_column()` now
synthesizes a row-position ID (`ROW_0001`, `ROW_0002`, ...) whenever no
column qualifies as a KEY lane, and every emitted row's `comments` field
(confirmed Optional in the CARE-SM v2 glossary for all 7 models — see
`~/CODE/CARE-Semantic-Model-Version-2/docs/glossary.md`) carries a note that
the ID is synthetic. **This ID is not a real registry identifier** — it's
stable across the CARE-SM CSVs produced by one run (so `Phenotype.csv` row N
and `Diagnosis.csv` row N are the same patient), but will NOT match up with
a previous run's IDs if the source file is ever re-sorted, filtered, or
re-exported. With this fix: Phenotype went from 0 → **15 rows**, Diagnosis
from 0 → **81 rows**.

(Per this repo's diagrams, `comments` attaches to CARE-SM's `Process_` node
via `rdfs:comment` — but the Toolkit's actual RDF-generation code doesn't
appear to consume that column yet. Flagged separately: see
`~/CODE/CARE-Semantic-Model-Version-2/HANDOFF.md`.)

### 2. Opaque internal variable-name headers produce false-positive semantic matches

The BOOLEAN-lane header-search route (designed for and validated against
clean natural-language headers like `cardiomyopathy` or `10MWT`) breaks down
on this dataset's internal variable codes (platform not confirmed — see
note above). Of 15,089 boolean/checkbox
columns, only **1** was correctly tagged Phenotype via header search — but
**321** were tagged Diagnosis, and independent inspection shows this is
almost entirely noise: those 321 columns collapse onto just **34 distinct
target labels**, dominated by obscure rare-disease names (`peroxisome
biogenesis disorder 6B` ×48, `VPS13A-related neurodegenerative disease`
×62, ...) that have nothing to do with the field they supposedly matched
(example: `FU1_1_MotMusFU_1_MotMusFUDat_1` — clearly a **date** field,
"Motor/Muscular Follow-Up Date" — matched `multiple mitochondrial
dysfunctions syndrome 1` at score 0.65, comfortably above the 0.50
threshold). This looks like a garbage-in/garbage-out embedding artifact:
garbled variable-name token soup collapses onto a handful of "attractor"
points in embedding space rather than scattering randomly, and the
single-score threshold used for header matches (unlike the SEARCH lane's
multi-value hit-fraction guard) has no defense against it.

**Not fixed** — this needs either (a) a real data dictionary/codebook from
whatever system exported this, with human-readable field labels to search
against instead of raw variable names, or (b) a stronger guard on the
BOOLEAN/NUMERIC header-match route.
Flagging for curator awareness: **any Diagnosis/Phenotype tag on this
dataset that came from a BOOLEAN-lane header match, not a SEARCH-lane
value match, deserves extra scrutiny.**

### 3. Realistic missingness pushes numeric/date columns into the unreliable SEARCH lane

Two concrete examples, both born out in the Diagnosis output:
- `FU3_1_SystOthFU_1_FUWeight_1` — 25 values, 11 are `NA` (this follow-up
  round wasn't done for those patients) — numeric fraction 0.56, just under
  the 0.6 NUMERIC-lane threshold, so it falls through to SEARCH and gets
  matched to `spastic paraplegia 86` at 0.54.
- `FU3_PROXY_18JR_DOB` / `FU4_PROXY_18JR_DOB` / `FU5_PROXY_18JR_DOB` — dates
  in `DD-MON-YY` format (`23-MAY-77`) that `is_date()` doesn't recognize
  (only ISO/slash formats are covered), and with only 1 non-null value the
  hit-fraction guard (built for multi-value robustness) is trivially 1.0 —
  no protection at all. These matched various rare-disease names and are
  visible in `care_sm_output/Diagnosis.csv`.

**Not fixed** — a real fix would compute the NUMERIC-lane fraction over
non-sentinel values only (excluding `NA`/`unknown`/etc. from the
denominator, not just reporting them) and/or extend `is_date()` to cover
more locale formats. Both are legitimate, generalizable pipeline
improvements surfaced by this dataset's realistic missingness — not done
here since they change classification semantics for every future dataset,
which felt like a decision worth checking in on rather than making
unilaterally.

### 4. What genuinely worked well

The SEARCH-lane free-text columns (which use real cell *values* plus the
hit-fraction guard, not raw header codes) produced some clearly correct
matches: `Base_1_DemoB_1_BMedHisSpec_1` ("medical history, specify") hit
"childhood-onset Steinert myotonic dystrophy" at 0.76 with 0.83 hit-fraction
— exactly right for a myotonic dystrophy registry. The deterministic lanes
(DICTIONARY 1,233, NUMERIC-without-model 539, DROP 372) are unaffected by
either issue above and can be trusted at the same level as any other
dataset this pipeline has processed.

## Reliability note

One of the two live builds (Diagnosis) hit a `Connection reset by peer` on
the batch endpoint partway through, correctly fell back to sequential
one-at-a-time calls, and finished correctly but 3× slower (1241s vs. ~380s).
The fallback is permanent for the rest of a run once triggered — a
transient blip costs the whole remaining runtime at the slow rate rather
than being retried. Worth revisiting if this recurs.

## Files here

- `myodraft.mock` — the source data (converted from the partner's tab-delimited export)
- `profile_live.json` / `profile_live.log` — full column-by-column triage output
- `data_dictionary.json` — per-column variable-type spec
- `care_sm_output/Phenotype.csv`, `Diagnosis.csv` — actual CARE-SM v2 output, synthetic PIDs and all
- `build_phenotype.log`, `build_diagnosis.log` — full run logs with timing

All gitignored under `mockdata/` per project convention — nothing here is committed.

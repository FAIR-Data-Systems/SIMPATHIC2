# 3. Validation Strategy

## Data source

The Jupyter notebook error logs are the sole and comprehensive error trail
for this project — confirmed directly by the project owner. 28 current
`*-errors*` files were enumerated under `SKG_Mapping/{biovista,demokritos,
radboud}/{maps,graph}/`, excluding any path containing `deprecated` or
`backup` (superseded pipeline runs, not the current error trail). Full file
list and counts: [`error_log_summary.json`](error_log_summary.json),
produced by [`enumerate_error_logs.rb`](enumerate_error_logs.rb):

```bash
ruby enumerate_error_logs.rb <path-to-SKG_Mapping> > error_log_summary.json
```

Disposition-on-failure behavior (see Methodology below) was confirmed by
reading the actual mapping notebook source (`.ipynb` cell source), not
inferred from the error logs alone.

## Two pipeline stages, two log locations

Each partner runs two stages, each with its own error trail:
- **`maps/` — entity mapping**: resolving a partner's native identifier
  (UMLS CUI, CHEMBL ID, EFO/Orphanet ID, etc.) to a canonical URI (MONDO,
  PubChem CID, UniProt, ...) via an **external lookup** (OLS4, PubChem,
  BioPortal, Monarch, ...). Failures here are written to the `.map` output
  and the corresponding `-errors.txt`, per "How errors are identified and
  handled" below.
- **`graph/` — relation graphing**: re-reads the partner's raw
  relation-triple files and, for each entity, does a **local lookup against
  the already-built `.map` file from the mapping stage** — no external API
  call is made here. Confirmed by reading the graphing notebook source for
  both Demokritos and Radboud, e.g. (`demokritos/2026 Disease-Gene
  Graphing.ipynb`):
  ```ruby
  disease_mappings = CSV.read('./maps/2026-demokritos-disease-mondo.map', headers: true)
  ...
  disease = disease_mappings.find { |d| d['demokritos_umls'] == disease_id }
  unless disease
    next if failures[disease_id]
    failures[disease_id] = 1
    graphing_errors.write "disease lookup failed #{disease_id}\n"
    next
  end
  ```
  **Correction from an earlier version of this document:** a graphing-stage
  error is *not* a new, independent failure (e.g. not a "transient API
  failure" as previously stated here) — it is the *same* entity-mapping
  failure being re-encountered, restricted to whichever entities actually
  appear in that specific relation-pair's raw triples. If an entity is
  missing from the `.map` file because it failed during entity mapping, it
  is guaranteed to also fail here, deterministically, for the same
  underlying reason.

## Missing triples (simplified summary for the paper)

A simpler, paper-ready framing of the same underlying problem: for each
partner, how many candidate relation triples from their raw source data
were never written to the graph, because at least one of the two entities
failed lookup (or was explicitly excluded by the partner's own graphing
code, e.g. Biovista's deliberate skip of MeSH-lettered gene IDs)?

Computed by [`count_missing_triples.rb`](count_missing_triples.rb), which
replicates each partner's graphing notebooks' exact candidate-row filter
and lookup logic (read from notebook source, not assumed) — including
partner-specific quirks: Demokritos processes disease/drug/gene relation
pairs via two combined-direction notebooks and phenotype relations via six
single-direction notebooks (12 raw files total); Radboud's `disease-gene.csv`
and `drug-disease.csv` each serve two different notebooks (one filtering to
`HP_`-prefixed rows for phenotype relations, one processing all rows
unfiltered — so an `HP_`-prefixed row genuinely double-appears, correctly
as a phenotype relation and spuriously as a failed disease lookup, exactly
as the real pipeline does it); Biovista excludes MeSH-lettered gene IDs and
applies one hardcoded disease-ID harmonization (`C0023264`→`C2931891`) in
several of its notebooks. Full per-notebook breakdown in
[`missing_triples.json`](missing_triples.json).

**Validated**: Radboud's Disease-Gene notebook alone has 72,995 candidate
triples and 32,131 missing, i.e. 40,864 successful triples — this
independently matches the exact count of `IS_ASSOCIATED_WITH`-labeled
graphs found on the live Virtuoso database before that literal was patched
(see [`05_results/README.md`](../05_results/README.md)), since that
notebook was the only source of that relation label. Strong cross-check
that this methodology is sound.

| Partner | Candidate triples | Missing triples | % missing |
|---|---|---|---|
| Radboud | 81,729 | 33,257 | 40.7% |
| Demokritos | 17,702 | 7,148 | 40.4% |
| Biovista | 302,835 | 38,092 | 12.6% |

**Definitional note:** "candidate triples" counts raw source-data rows per
partner's graphing notebook, not deduplicated entity pairs — if the same
entity pair appears in multiple rows (e.g. different PubMed evidence for
the same pair), each row counts separately here. This is a different
denominator than the "both orientations" final KG row count in
[`05_results`](../05_results/README.md) (1,042,001), so the two should not
be compared directly or summed against each other.

## Error volume by partner and stage (entity-mapping vs. relation-graphing error *logs*)

The table below is a different, narrower analysis than "missing triples"
above — it compares log volume between the two pipeline *stages*
(entity-mapping vs. relation-graphing), not candidate-vs-actual triple
counts. Kept for the error-log audit trail; the "Missing triples" table
above is the one to cite in the paper.

The raw log-line counts in an earlier version of this table were replaced
with **distinct entity ID** counts, since a single entity can generate
multiple graphing-stage error *lines* (one per relation-pair file it happens
to appear in — see mechanism 1 below), which inflated the raw line totals
relative to the number of actually-distinct problematic entities.

**No combinatorial doubling within a row.** Confirmed from source
(`demokritos/2026 Disease-Gene Graphing.ipynb`): the graphing code checks
the row's first entity, and if it fails, `next`s immediately — the second
entity is never even looked up for that row:
```ruby
unless disease
  ...
  next   # gene is never checked for this row
end
unless gene
  ...
  next
end
```
So a row contributes **at most one** error line, never two, regardless of
whether both entities would have failed. If anything this *undercounts*
problems (a row where both entities are unmappable only ever surfaces the
first one).

**Two real mechanisms make graphing-stage numbers differ from
entity-mapping-stage numbers** (verified with actual ID-level comparisons,
not assumed):

1. **The same failed entity can generate one error line per relation-pair
   file it appears in.** The `failures` hash that suppresses repeat error
   lines is local to a single graphing notebook run, so a gene that failed
   mapping and appears in both `Disease-Gene` and `Gene-Phenotype` raw
   triples produces one error line in *each* file's separate error log —
   inflating total line count without representing new distinct failures.
2. **Some entities were never attempted at the entity-mapping stage at
   all**, and so have no corresponding mapping-stage failure to
   "re-encounter" — they show up only when the graphing stage looks them up
   and finds nothing. Confirmed concretely: Demokritos's
   `2026 Drug Mapping.ipynb` builds `drug_list.txt` from four raw-data
   files via `awk`/`sed`, with `Drug-Drug triples.tsv` explicitly commented
   out (`# This file contains errors in column 6`) — so a drug that *only*
   appears in `Drug-Drug` triples (e.g. Eicosapentaenoic Acid, `C0000545`)
   was never in the master list, never attempted, never logged as a mapping
   failure, and only surfaces later when a `Phenotype-Drug` graphing pass
   looks it up and finds nothing. These per-entity-type input lists were
   built ad hoc (mixing Ruby, `sed`, and `awk` across different files,
   confirmed by the project owner), not from one consistent, complete
   source, so gaps like this are expected rather than a one-off bug. This
   also independently explains why Radboud (no gene entity-mapping error
   log at all) and Biovista (no gene or phenotype entity-mapping error log)
   show graphing-stage failures for those types with nothing to compare
   against in "Coverage / failure rates" below.

| Partner | Entity-mapping: distinct failed IDs | Graphing: distinct failed IDs referenced | ...explained by a known mapping failure | ...never attempted at mapping stage | Graphing: total error lines (all files) |
|---|---|---|---|---|---|
| Radboud | 3,110 | 1,987 | 1,601 (81%) | 386 (19%) | 2,190 |
| Demokritos | 3,079 | 2,276 | 2,002 (88%) | 274 (12%) | 3,180 |
| Biovista | 72 | 119 | 54 (45%) | 65 (55%) | 355 |

Computed by [`compare_mapping_vs_graphing_errors.rb`](compare_mapping_vs_graphing_errors.rb),
which extracts entity IDs with an explicit, spot-checked parser **per
error-file format** (not a generic heuristic — an earlier draft of this
script used a naive "last whitespace token" rule that silently mis-extracted
IDs from lines with trailing parentheticals or embedded names, producing
wrong counts; caught by cross-checking against hand-verified numbers before
publishing this table). Full output:
[`mapping_vs_graphing_errors.json`](mapping_vs_graphing_errors.json).

(28 files; full per-file line-count breakdown in `error_log_summary.json`.
Note: the "entity-mapping: distinct failed IDs" figures here are
deduplicated across all of a partner's entity-mapping error files combined
— e.g. a drug ID that appears in both Biovista's initial-attempt and
biologics-retry error files counts once — so they differ from summing the
per-file row counts in "Coverage / failure rates" below, which counts rows
per file, not distinct IDs across files.)

**Do not sum any of these columns against each other** — each measures a
different thing (distinct entities on one axis, raw line volume on
another), and, per mechanism 2, a meaningful fraction of graphing-stage
failures (18–55% depending on partner) have no mapping-stage counterpart at
all. Deduplicated **entity-mapping** failure counts and rates (the
meaningful "completeness of coverage" numbers, unaffected by any of this) are in
"Coverage / failure rates" below.

## How errors are identified and handled

Read directly from the mapping notebook source (not inferred). All three
partners' mapping scripts follow the same pattern: attempt a lookup, and on
failure, **write one line to the corresponding `-errors.txt` file and skip
the entity** (Ruby `next`) — the entity is **not** written to the output
`.map` file and is therefore **excluded from that partner's graph entirely**,
with no fallback/placeholder identifier substituted. Example (Radboud disease
mapper, `radboud/map_diseases-mondo.ipynb`):

```ruby
if !res || res[:mondo].empty?
  warn "found no mondo for #{cleanname}"
  e.write "found no mondo for #{cleanname}\n"
  e.flush
  next
end
f.write CSV.generate_line([cleanname, res[:mondo], ...])
```

Same log-then-skip pattern confirmed independently in
`demokritos/2026 Gene Mapping.ipynb`. This means: **every line in an error
log corresponds to exactly one entity dropped from that partner's
contribution to the KG**, not a warning about an entity that was still
included with degraded data. This is an important caveat for "completeness
of coverage" claims in the paper — coverage gaps are traceable 1:1 to named
identifiers in these logs, not silent.

## Normalized error-type breakdown

Top error-type patterns by line count (identifiers stripped/normalized;
full list of 1,002 normalized types in `error_log_summary.json` — the long
tail is dominated by one-off `XREF <CUI> <name>`-style messages from the
Demokritos drug mapper that the normalizer doesn't fully collapse):

| Error type | Count | Partner/stage |
|---|---|---|
| `found no mondo for <id>` | 3,038 | Radboud entity mapping (EFO/Orphanet/BioPortal → MONDO) |
| `disease lookup failed <id>` | 2,663 | Radboud relation graphing |
| `phenotype lookup failed <UMLS_id>` | 1,254 | Demokritos relation graphing |
| `not_found <UMLS_id>` | 928 | Demokritos entity mapping (phenotype) |
| `drug lookup failed <id>` | 883 | Radboud + Biovista relation graphing |
| `gene lookup failed <id>` | 337 | Biovista + Radboud relation graphing |
| `drug lookup failed <UMLS_id>` | 319 | Demokritos relation graphing |
| `FAILED CID lookup for <id>` | 308 | Radboud entity mapping (drug → PubChem CID) |
| `failed UMLS to cid lookup for <id>` | 277 | Demokritos entity mapping (drug) |
| `error getting <id>` | 210 | Demokritos entity mapping (gene) |

## Cross-reference with CHANGES.md

`CHANGES.md` documents several **label-source standardization** fixes
(all three partners forced onto PubChem `property/Title` for drug labels;
MONDO labels via OLS4) and one specific cross-partner **label
inconsistency** resolution (`SUBSTANCE_135346864` / Clexane-Clivarine-Heparin,
still pending partner decision as of the latest entry). It does **not**
document a disposition policy for lookup failures — that was independently
confirmed from source above. It also does not currently document root
causes for the largest error categories (e.g. why ~3,038 EFO/Orphanet
disease IDs have no MONDO cross-reference, or why ~928 UMLS phenotype CUIs
are `not_found`) — those would need a dedicated investigation pass if the
paper wants root-cause explanations rather than just counts.

## Coverage / failure rates (entity-mapping stage)

Computed by [`compute_coverage_rates.rb`](compute_coverage_rates.rb):
`failure_rate = failure_rows / (success_rows + failure_rows)`, using each
partner/entity-type's `.map` (success) file paired with its `-errors` file.
Full output: [`coverage_rates.json`](coverage_rates.json).

**A pairing is only used as a real rate ("verified") if the success and
error files are confirmed to reflect the same input population** — either
matching modification times, or (Radboud/Demokritos gene) a documented,
row-count-preserving label-only patch in `CHANGES.md` that explains a later
mtime on the `.map` file without invalidating the earlier error count. Two
partners' drug pipelines (Radboud, Biovista) do a two-stage lookup — an
initial ID lookup, then a biologics/SID fallback retry for whatever failed —
so the *first-pass* error file overstates true failures; the rate below
uses only the final, post-retry failure count.

| Partner | Entity type | Verified? | Success | Failure | Attempted | Failure rate |
|---|---|---|---|---|---|---|
| Radboud | disease | ✅ | 5,386 | 3,044 | 8,430 | **36.11%** |
| Radboud | drug | ✅ (2-stage, see note) | 1,900 | 66 | 1,966 | **3.36%** |
| Radboud | gene | ❌ no error log for this stage | 742 | — | — | N/A |
| Demokritos | disease | ⚠️ unverified (see note) | 3,440 | 975 | 4,415 | 22.08%* |
| Demokritos | drug | ✅ | 836 | 1,193 | 2,029 | **58.80%** |
| Demokritos | gene | ✅ (patch-verified) | 2,377 | 210 | 2,587 | **8.12%** |
| Demokritos | phenotype | ✅ | 238 | 928 | 1,166 | **79.59%** |
| Biovista | disease | ⚠️ no lookup needed (see note) | 11 | 0 | 11 | 0%* |
| Biovista | drug | ✅ (2-stage, see note) | 435 | 53 | 488 | **10.86%** |
| Biovista | gene | ❌ no error log for this stage | 575 | — | — | N/A |
| Biovista | phenotype | ❌ no error log for this stage | 401 | — | — | N/A |

\* Not a verified same-run rate — see per-row notes in `coverage_rates.json`.
Demokritos disease: success file is ~2 months newer than the error file with
no documented patch explaining the gap (unlike the gene-map case), so we
cannot confirm they're the same run; the 22.08% figure is reference-only.
Biovista disease: the 10-11 core target diseases are supplied directly as
MONDO/xref IDs rather than looked up, so near-zero failures are expected by
construction, not a measured rate.

**Notable for the paper:** Demokritos phenotype (79.6%) and Demokritos drug
(58.8%) have markedly higher failure rates than any other partner/stage.
Demokritos drug is independently flagged in `CHANGES.md` as using a stale
BioPortal label and "needing re-run" (for label quality, not row count) —
worth checking whether a re-run also changes the failure rate before citing
58.8% as final. Radboud disease's 36.1% is dominated by the ~3,038
"found no mondo for" EFO/Orphanet cases noted above, whose expected-vs-actual
nature is still unreviewed.

## Root cause: Demokritos phenotype and drug high failure rates

Investigated by reading the actual mapping notebook code and sampling failed
entries (not guessed).

**Phenotype (928/1,166 = 79.6%), `demokritos/2026 Phenotype Mapping.ipynb`:**
the mapper queries the Monarch API for each UMLS CUI restricted to
`biolink:PhenotypicFeature`, requiring the result's `xref` list to contain
that exact `UMLS:<CUI>` (see `search_hpo(cui)`). All 928 recorded failures
are `not_found` (zero Monarch results), not `xref_mismatch`. Sampling the
failed CUIs' source names (`demokritos/maps/2026-phenotype-mapping-errors.txt`)
shows most are not phenotype concepts at all — e.g. "Rescue", "Emotional",
"Worse", "Early-onset", "Neurological observations", "handicapping
condition". These come from `demokritos/raw-data/*Phenotype*.tsv`, which
appears to be NLP/text-mining-extracted mentions rather than curated
phenotype-ontology terms. **This is a source-data characteristic (extraction
noise), not a mapping-code bug** — these terms were never going to resolve
to an HPO id.

**Drug (1,193/2,029 = 58.8%), `demokritos/2026 Drug Mapping.ipynb`:** 916 of
1,193 failures (77%) are `failed compound name to cid lookup for XREF <CUI>
<name>`, from `map_name_to_cid(name)`, which does an exact PubChem
compound-name→CID lookup. Sampling the failed names shows most are **drug
class/category labels**, not specific compounds — e.g. "Dalfampridine-
containing product", "Adenosine-containing product", "Acetylcholinesterase
inhibitor", "Adrenal Cortex Hormones". PubChem's name lookup only resolves
single chemical substances, so a class-level MeSH/SNOMED term fails by
construction — this is a category/instance mismatch between the source
vocabulary (BioPortal MeSH/SNOMED, which includes class terms) and the
target identifier scheme (PubChem CID, which only has specific compounds),
not a code defect.

Neither of these looks fixable by a small pipeline patch — both stem from
attempting to force-map source data that has no valid target in the
destination scheme. This is directly relevant to the "completeness of
coverage" discussion: these failure rates measure the fraction of *source*
Demokritos mentions that are, by their nature, out of scope for an
ontology/CID mapping, not a gap in the mapping logic's effectiveness. See
also [`04_bias_and_robustness`](../04_bias_and_robustness/README.md), which
uses these as concrete examples of source-specific characteristics.

## What is NOT yet answered here

- Whether the ~3,038 Radboud "found no mondo" cases are mostly out-of-scope
  diseases (expected misses, e.g. non-disease EFO terms) or genuine
  coverage gaps — would need sampling/manual review of a subset.
- Relation-graphing-stage (`graph/`) failure rates — the table above covers
  only the entity-mapping stage; a graphing-stage denominator (candidate
  relation attempts) hasn't been identified/computed yet.
- Root cause for Demokritos phenotype's high (79.6%) and drug's high (58.8%)
  failure rates.

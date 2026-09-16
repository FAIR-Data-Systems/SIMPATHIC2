# 5. Results — Final Unified KG Statistics

## Data source

`Utilities/Queries/SEPT_all_pairs_both_orientations_merged_evidence.csv.large`
— the canonical, deduplicated (merged-evidence) dataset for this paper, per
the top-level [statistics README](../README.md). **Not** the live Virtuoso
endpoint (unchanged since this dump, but not re-queried here).

**Naming note:** the fix described below was originally applied in place to
files named `JUNE_all_pairs_both_orientations_*`. The user has since
preserved those original (pre-fix) files under their `JUNE_` names as
unmodified archival copies, and moved the fixed content this paper actually
uses to new files prefixed `SEPT_`. Every number in this document is
computed from the `SEPT_` files; do not use the `JUNE_`-named files for
anything citation-relevant — they are the pre-fix originals.

Neither file is committed to git and each exists in only one place. All
computation here reads a byte-verified (MD5-checked) copy from a scratch
directory — the actual `SEPT_` file was never opened for writing.

- Format: tab-separated, despite the `.csv` extension.
- Columns: `canonical_entity1_uri  entity1_name  entity1_type
  canonical_entity2_uri  entity2_name  entity2_type  rels  sources  evidence
  entity1_uri  entity2_uri`
- 1,042,001 data rows (matches the count recorded in `CHANGES.md`,
  "Post-patch TSV validation").
- Filename indicates "both orientations": each undirected pair may appear as
  both (A,B) and (B,A) rows, so the row/edge count below is **not**
  deduplicated by direction. This is stated explicitly wherever an edge count
  is reported.

## ✅ Data-quality issue, root-caused and fixed: `rels`/`sources` label duplicates

Originally found: the `rels` and `sources` columns appeared to contain
whitespace-padded duplicates of the same label — e.g. `"TREAT"`, `" TREAT"`,
`"TREAT "` all counted as distinct string values, inflating raw
distinct-value counts (98 apparent relation labels vs. a true 36; 8 apparent
sources vs. the true 3 partners).

**Root-caused:** neither the database nor the file's raw bytes were ever
actually corrupted. `build_ml_set.rb`'s SPARQL query uses
`GROUP_CONCAT(DISTINCT ?rel; SEPARATOR=" | ")`, so a multi-valued cell is
legitimately formatted as `"ASSOCIATED_WITH | CAUSES"` — correct,
human-readable. The apparent duplicates only appeared when something (this
statistics pass's first analysis pass included) split that string on bare
`|` without trimming each piece, e.g. `"A | B".split('|')` → `["A ", " B"]`.
Verified directly: every *single*-valued (non-`|`) `rels`/`sources` cell in
the file had zero padding, before any fix — the padding only ever showed up
as an artifact of parsing multi-valued cells naively.

**Separately, a real (non-whitespace) defect was found and fixed:**
Radboud's `Disease-Gene` graphing notebook hardcoded the literal
`IS_ASSOCIATED_WITH` where every other Radboud notebook and both other
partners use `ASSOCIATED_WITH` for the same conceptual relation (full
investigation below). At the user's request, this was patched directly in
both canonical `.large` files with a script that also trims/dedupes each
`rels` cell (collapsing any accidental same-cell duplicates created by the
typo fix, and incidentally cleaning up the whitespace-parsing artifact
across the whole column as a side effect):

```bash
awk -f fix_associated_with.awk JUNE_all_pairs_both_orientations_merged_evidence.csv.large > /tmp/merged_fixed.tsv \
  && mv /tmp/merged_fixed.tsv JUNE_all_pairs_both_orientations_merged_evidence.csv.large
awk -f fix_associated_with.awk JUNE_all_pairs_both_orientations_split_evidence.csv.large > /tmp/split_fixed.tsv \
  && mv /tmp/split_fixed.tsv JUNE_all_pairs_both_orientations_split_evidence.csv.large
```
Script: [`fix_associated_with.awk`](fix_associated_with.awk). Applied and
verified 2026-09-14: row counts unchanged (1,042,001 / 1,107,422 data rows),
headers intact, zero remaining `IS_ASSOCIATED_WITH`. Checksums:
`SEPT_..._merged_evidence.csv.large` MD5 `1cb03cc0…`,
`SEPT_..._split_evidence.csv.large` MD5 `06f94150…` (the untouched
`JUNE_`-named originals remain at `38bb6dfe…` / `cfe7bda6…`). **The
`sources` column was left untouched** (only `rels`, col 7, was ever
affected by the typo or checked for padding — confirmed no actual padding
existed there either).

**This does not fix the root cause** — Radboud's notebook still hardcodes
`IS_ASSOCIATED_WITH` and the live Virtuoso database still has the old value
on ~40,864 graphs as of this writing. See "Relation-type investigation"
below for the notebook `sed` fix and the SPARQL `UPDATE` patch for the live
database, neither of which has been applied yet — only the `.large` files
partners will re-upload have been patched so far.

Both a **raw** and a **whitespace-trimmed** summary are still provided below
and as JSON files, computed **after** the fix, so the (now much smaller)
remaining raw/trimmed gap is auditable — see the note after the headline
table for why a small raw/trimmed gap is structurally unavoidable even in a
fully clean file.

## Method

`compute_kg_stats.rb` (raw) / `compute_kg_stats_trimmed.rb` (whitespace-
trimmed) stream the file once, computing:
- distinct nodes = distinct `canonical_entity{1,2}_uri` values (union), with
  a sanity check that no URI maps to more than one `entity_type` across rows
  (0 violations found — good internal type-consistency signal)
- node counts per `entity_type`
- distinct `rels` values and per-value row counts (a row's `rels`/`sources`
  can be `|`-delimited multi-valued)
- distinct `sources` values and per-value row counts

Run:
```bash
ruby compute_kg_stats.rb <path-to-large-file>          # raw
ruby compute_kg_stats_trimmed.rb <path-to-large-file>   # whitespace-trimmed
```
Full output: [`kg_stats_summary.json`](kg_stats_summary.json) (raw),
[`kg_stats_summary_trimmed.json`](kg_stats_summary_trimmed.json) (trimmed).

## Headline numbers

| Metric | Value |
|---|---|
| Rows / edges (both orientations, not direction-deduplicated) | 1,042,001 |
| Distinct nodes | 13,459 |
| — Disease | 4,938 |
| — Protein | 2,826 |
| — Gene | 2,821 |
| — Drug | 1,850 |
| — Phenotype | 1,024 |
| Distinct relation types | 35 |
| Distinct source partners | 3 (Biovista, Radboud, Demokritos) |

Top relation types by row count (of 1,042,001 total edges):

| Rank | Relation type | Rows | % of edges |
|---|---|---|---|
| 1 | `ASSOCIATED_WITH` | 1,042,001 | 100.00% |
| 2 | `TARGET` | 12,608 | 1.21% |
| 3 | `COEXISTS_WITH` | 900 | 0.09% |
| 4 | `TREAT` | 818 | 0.08% |
| 5 | `CAUSES` | 735 | 0.07% |
| 6 | `IS_TREATED` | 595 | 0.06% |
| 7 | `INHIBITS` | 544 | 0.05% |
| 8 | `STIMULATES` | 539 | 0.05% |
| 9 | `AFFECTS` | 265 | 0.03% |
| 10 | `ASSOCIATED_WITH__INFER__` | 230 | 0.02% |
| — | *(remaining 25 relation types)* | 1,505 | 0.14% |

`ASSOCIATED_WITH` is now present on 100% of edges (see "ASSOCIATED_WITH as
a universal base relation" below — this was 98.4% until that fix).
Percentages otherwise don't sum to 100% beyond `ASSOCIATED_WITH` itself: a
single edge's `rels` cell can carry more than one relation label (e.g.
`"ASSOCIATED_WITH | CAUSES"`), so the other rows aren't mutually exclusive
against each other. Full breakdown of all 35 types in
[`kg_stats_summary_trimmed.json`](kg_stats_summary_trimmed.json).

Rows by source partner: Biovista 822,758; Radboud 192,210; Demokritos 29,549.

Cite the **trimmed** script's numbers (35 relation types, etc.), not the
raw script's — the raw script naively splits `|`-joined multi-value cells
without trimming whitespace, which inflates its distinct-label count
(96) with parsing artifacts, not real data issues. Kept only to demonstrate
why downstream consumers must `.strip()` after splitting on `|`.

## Relation-type investigation: `ASSOCIATED_WITH` vs `IS_ASSOCIATED_WITH`

You flagged this as likely a typo rather than a real semantic distinction.
Confirmed by reading the graphing notebook source (not guessed):

- **Biovista** hardcodes the literal `"ASSOCIATED_WITH"` in every one of its
  graphing notebooks (`RDF::Statement.new(context_uri, SIMPATHIC['source-relation'],
  RDF::Literal.new("ASSOCIATED_WITH"), ...)`- same string everywhere.
- **Radboud** hardcodes **different literals in different notebooks**:
  `radboud/2026 Radboud Disease-Gene Graphing.ipynb` hardcodes
  `"IS_ASSOCIATED_WITH"`, while `radboud/2026 Radboud Phenotype-Gene
  Graphing.ipynb` hardcodes `"ASSOCIATED_WITH"` — **for the same
  conceptual relation, in the same partner's own codebase.** Radboud's
  Drug-Disease and Drug-Phenotype notebooks separately hardcode `"TREAT"`,
  and Drug-Gene hardcodes `"TARGET"`.
- **Demokritos** does not hardcode a relation string at all — it reads
  `row['RELATION']` directly from its own raw-data TSVs (its source
  knowledge graph's native, richer relation vocabulary), which is why
  Demokritos contributes the long tail of the 36 trimmed relation types
  (`CAUSES`, `STIMULATES`, `compared_with`, etc.) alongside its own
  `ASSOCIATED_WITH` values.

Cross-tabulated actual row counts by label and source (split-evidence file,
one-line-per-evidence-source, so this is a clean per-partner count, not the
merged-file's GROUP_CONCAT ambiguity):

| Relation label | Biovista | Radboud | Demokritos |
|---|---|---|---|
| `ASSOCIATED_WITH` | 885,510 | 16,120 | 24,669 |
| `IS_ASSOCIATED_WITH` | 0 | 162,126 | 0 |

**Conclusion: `IS_ASSOCIATED_WITH` is Radboud's Disease-Gene graphing
notebook using a different hardcoded literal than its own other notebooks
and than the other two partners' convention — this looks like an
inconsistency/copy-paste artifact across Radboud's notebook templates, not
an intentional distinct relation type.**

**Status: patched in the `.large` files (2026-09-14, see above), not yet
patched at the source.** Three places need the fix, in order of durability:

1. **`.large` files** — ✅ done. Both files' `rels` columns now use only
   `ASSOCIATED_WITH`.
2. **Radboud's notebook source** (`radboud/2026 Radboud Disease-Gene
   Graphing.ipynb`) — ❌ not yet applied. Without this, the next full
   notebook re-run reproduces `IS_ASSOCIATED_WITH` again:
   ```bash
   sed -i 's/IS_ASSOCIATED_WITH/ASSOCIATED_WITH/g' "radboud/2026 Radboud Disease-Gene Graphing.ipynb"
   ```
3. **Live Virtuoso database** — ✅ done. Patched via
   [`Utilities/Patches/Fix_IS_ASSOCIATED_WITH_Typo.sparql`](../../Utilities/Patches/Fix_IS_ASSOCIATED_WITH_Typo.sparql)
   + [`.curl`](../../Utilities/Patches/Fix_IS_ASSOCIATED_WITH_Typo.curl),
   run by the user 2026-09-14. Verified read-only afterward: `COUNT` of
   graphs with `simp:source-relation "IS_ASSOCIATED_WITH"` in
   `urn:simpathic:context:all_metadata` is now **0** (was 40,864); `COUNT`
   for `"ASSOCIATED_WITH"` is now 295,387, consistent with the migration.

All three fix locations are now applied. The only remaining gap: nothing
here re-runs `build_ml_set.rb`/`merge_evidence.rb` against the now-corrected
live database — today's `.large` files were patched directly (fix #1
above), not regenerated from a fresh export, so they and the live DB are
both clean but via two different routes. A future fresh export would now
also come out clean, since the notebook (#2) and database (#3) sources are
both fixed.

## Relation-type investigation: directed relations and a generic layer

You noted only Demokritos has genuinely directional relations (`CAUSES`,
`STIMULATES`, `INHIBITS`, `TARGET`, etc. — all read from Demokritos's own
raw data, per above) and asked whether a generic non-directional
`ASSOCIATED_WITH` also exists for those same pairs, which would let
directional Demokritos edges be merged into an undirected layer comparable
to Biovista's/Radboud's (which only ever emit one hardcoded, effectively
undirected, relation per graphing notebook).

Confirmed directly in Demokritos's raw source data
(`demokritos/raw-data/*.tsv`): a generic `ASSOCIATED_WITH` record
**does** coexist alongside a specific directional relation for the same
entity pair in Demokritos's source — but **only for a small minority of
pairs, not broadly**. Checked across all 16 raw-data triples files (pair
key = source/target identifier, ignoring relation, counting pairs that have
both an `ASSOCIATED_WITH` row and at least one other relation type):

| File | Total distinct pairs | Pairs with both ASSOCIATED_WITH + specific relation | % |
|---|---|---|---|
| Gene-Disease | 9,299 | 113 | 1.2% |
| Drug-Disease | 798 | 20 | 2.5% |
| Phenotype-Disease | 912 | 12 | 1.3% |
| Drug-Drug | 81,276 | 37 | <0.1% |
| Drug-Phenotype | 818 | 5 | 0.6% |
| Gene-Phenotype | 971 | 2 | 0.2% |
| Disease-Disease | 4,457 | 3 | 0.1% |
| Disease-Drug, Disease-Gene, Disease-Phenotype, Gene-Drug, Gene-Gene, Gene-Pathway, Phenotype-Drug, Phenotype-Gene | — | 0 | 0% |

**Revised conclusion: the generic `ASSOCIATED_WITH` layer does genuinely
coexist with directional relations in Demokritos's source data, confirming
it's a real (not inferred) part of their extraction — but it covers roughly
1% or less of directional-relation pairs, not a broad parallel layer.** An
undirected "any relation exists" comparison built only from Demokritos's
existing `ASSOCIATED_WITH` rows would therefore **miss the vast majority**
of Demokritos's directional-relation pairs (e.g. only 113 of 9,299
Gene-Disease pairs), not meaningfully merge them. Folding Demokritos's
directional relations (`CAUSES`, `STIMULATES`, `TARGET`, etc.) into an
undirected `ASSOCIATED_WITH`-equivalent layer for fair cross-partner
comparison would require an explicit transformation step (treating any
directional relation as evidence of "associated"), which has not been
built — flagging as a decision needed before any cross-partner
"connectivity" or "overlap" claim that depends on relation type, since the
current raw counts undercount Demokritos's true undirected connectivity
relative to Biovista/Radboud.

**Follow-up: should `ASSOCIATED_WITH` be present on ~100% of edges, as a
universal base relation with specific types layered on top?** Conceptually
yes, but the pipeline doesn't implement it that way. Checked directly
against the final KG (post-fix): **16,720 of 1,042,001 edges (1.6%) have no
`ASSOCIATED_WITH` at all**, only one or more specific relation types.

| Relation type (co-occurring on edges without ASSOCIATED_WITH) | Occurrences | Share of occurrences |
|---|---|---|
| `TARGET` | 12,194 | 71.6% |
| `COEXISTS_WITH` | 829 | 4.9% |
| `TREAT` | 801 | 4.7% |
| `IS_TREATED` | 534 | 3.1% |
| `INHIBITS` | 529 | 3.1% |
| `STIMULATES` | 496 | 2.9% |
| `CAUSES` | 464 | 2.7% |
| *(27 more types, each <2%)* | 1,187 | 7.0% |

(17,034 total label-occurrences across the 16,720 affected edges — slightly
more than the edge count, since a small number of these edges carry more
than one non-`ASSOCIATED_WITH` label, e.g. `"TARGET | CAUSES"`; percentages
are of occurrences, not of the 16,720 edges, for the same reason the
headline relation-type table above doesn't sum to 100%.)

`TARGET` alone accounted for 72% of the occurrences — it is Radboud's hardcoded
Drug-Gene relation literal (see the `ASSOCIATED_WITH`/`IS_ASSOCIATED_WITH`
investigation above), and that notebook, like Radboud's other notebooks
(`TREAT` for Drug-Disease/Drug-Phenotype), only ever writes its one
hardcoded label — never an accompanying base `ASSOCIATED_WITH`. The "base
case" pattern held cleanly for **Biovista** (always `ASSOCIATED_WITH`,
exclusively) but not for **Radboud** (its specific-relation notebooks never
add one) or **Demokritos** (whose relation labels are read per-row from its
own raw-data `RELATION` column — data-driven, not notebook-hardcoded —
so only the rows where that column already said `ASSOCIATED_WITH` had it;
~99% of its specific-relation rows did not).

### ✅ Fixed: ASSOCIATED_WITH added as a universal base relation

Per the project owner: `ASSOCIATED_WITH` is the intended universal base
relation for every edge, with any more specific relation layered on top —
applies to all partners equally, not just Radboud (the original trigger for
this investigation). Confirmed and applied 2026-09-14:

1. **`.large` files — done.** Patched `SEPT_..._split_evidence.csv.large`
   (one row per source, unambiguous) via
   [`add_associated_with_base.awk`](add_associated_with_base.awk), adding
   `ASSOCIATED_WITH` to the `rels` cell of every row that didn't already
   have it, preserving any existing specific relation(s). Regenerated
   `SEPT_..._merged_evidence.csv.large` from the patched split file via
   `Utilities/Queries/merge_evidence.rb` (runs locally, no DB access
   needed — its own Set-based union logic correctly handles pairs shared
   across partners). Verified: row counts unchanged (1,107,422 /
   1,042,001 data rows), **0 edges now lack `ASSOCIATED_WITH`** (was
   16,720). New checksums: `merged_evidence.csv.large` MD5 `d755e0e5…`,
   `split_evidence.csv.large` MD5 `306f542b…`.
2. **Live Virtuoso database — done.** Patched via
   [`Utilities/Patches/Add_Missing_ASSOCIATED_WITH_Base_Relation.sparql`](../../Utilities/Patches/Add_Missing_ASSOCIATED_WITH_Base_Relation.sparql)
   + [`.curl`](../../Utilities/Patches/Add_Missing_ASSOCIATED_WITH_Base_Relation.curl),
   run by the user 2026-09-14. Verified read-only afterward: 0 graphs
   remain without `ASSOCIATED_WITH` (was 13,344: 3,562 Radboud + 9,782
   Demokritos); total graphs with `ASSOCIATED_WITH` went from 295,387 to
   308,731 — an increase of exactly 13,344, confirming the patch applied
   cleanly with no over- or under-application.
3. **Notebook source — done.** Added a second, conditional
   `simp:source-relation` triple (`unless <relation_var> ==
   "ASSOCIATED_WITH"`) immediately after the existing one, in all 12
   affected notebooks: Radboud's Drug-Gene, Drug-Disease, and
   Drug-Phenotype (hardcoded-literal style — companion line always fires
   since these notebooks never hardcode `ASSOCIATED_WITH` itself), and all
   9 of Demokritos's relation-graphing notebooks (Disease-Gene,
   Disease-Phenotype, Drug-Disease, Drug-Gene, Drug-Phenotype,
   Gene-Phenotype, Phenotype-Disease, Phenotype-Drug, Phenotype-Gene —
   data-driven style, so the `unless` guard actually matters: skips adding
   a duplicate when Demokritos's own `RELATION` column already said
   `ASSOCIATED_WITH`). Applied via
   [`Utilities/Patches/patch_radboud_notebooks.py`](../../Utilities/Patches/patch_radboud_notebooks.py)
   and
   [`Utilities/Patches/patch_demokritos_notebooks.py`](../../Utilities/Patches/patch_demokritos_notebooks.py),
   both tested against scratch copies first (diffed to confirm exactly one
   clean insertion per notebook, correct indentation, valid JSON) before
   being applied to the real files. Future re-runs of any of these 12
   notebooks will now write the base tag automatically.

**All three layers confirmed fixed as of 2026-09-14** — `.large` files,
live database, and notebook source are all consistent: every edge now
carries `ASSOCIATED_WITH`.

Historical reproduction of the pre-fix finding (16,720 edges without
`ASSOCIATED_WITH`) — running this now against the current `SEPT_` file
returns 0, since the fix above has been applied:
```bash
awk -F'\t' 'NR>1{
  has_aw = ($7 ~ /(^|\| )ASSOCIATED_WITH( \||$)/)
  if (!has_aw) { c++; split($7,a,"|"); for(i in a){r=a[i]; gsub(/^ +| +$/,"",r); other[r]++} }
} END{ print "edges without ASSOCIATED_WITH:", c; for (r in other) print other[r], r }' \
  SEPT_all_pairs_both_orientations_merged_evidence.csv.large | sort -rn
```

## Query and use-case demonstration

Worked example, per your request: gather all evidence for a specific
Drug–Disease pair from two partners. Picked **Riluzole (PubChem CID 5070)
— Machado-Joseph disease (`MONDO_0007182`)**, a real pair with evidence
from both Demokritos and Biovista (one of 29 Drug-Disease pairs the two
partners share — found via
[`find_demo_pair.rb`](find_demo_pair.rb)).

**From the canonical file** (what actually backs this paper's numbers):
```bash
awk -F'\t' 'NR==1 || (($2=="Riluzole" && $5=="Machado-Joseph disease") || \
  ($5=="Riluzole" && $2=="Machado-Joseph disease"))' \
  SEPT_all_pairs_both_orientations_split_evidence.csv.large
```

| Partner | Relation | Evidence |
|---|---|---|
| Biovista | `ASSOCIATED_WITH` | Biovista evidence link (MEDLINE_STRENGTH_AB / HPO-weighted) — proprietary scored link, not a single citable reference |
| Demokritos | `IS_TREATED` | [PubMed 26990650](https://pubmed.ncbi.nlm.nih.gov/26990650) — a specific, independently citable literature reference |

This single example is a good illustration of a broader, citable pattern:
**Biovista's evidence is a proprietary scored database link, while
Demokritos's evidence is a directly citable PubMed ID** — a real
explainability/provenance difference between partners worth noting in the
paper, not just an artifact of this one pair.

**Equivalent live SPARQL query** (against the Virtuoso endpoint, same
schema `build_ml_set.rb` uses — provided for illustrating KG queryability;
not run for this paper's numbers, since the `.large` file is canonical):
```sparql
PREFIX simp: <urn:simpathic:>
SELECT ?rel ?source ?evidence WHERE {
  GRAPH ?g {
    <https://pubchem.ncbi.nlm.nih.gov/compound/5070> ?p
      <http://purl.obolibrary.org/obo/MONDO_0007182> .
  }
  ?g simp:source-relation ?rel .
  ?g simp:skg-source      ?source .
  OPTIONAL { ?g simp:evidence ?evidence }
}
```

## Not yet computed / needs a decision

- **Graph topology characteristics** (degree distribution, connected
  components, density) — not yet computed; requires deciding whether to
  treat "both orientations" rows as one undirected edge or as directed
  edges, complicated further by the finding above that only Demokritos has
  directional relations and its generic `ASSOCIATED_WITH` layer covers <2%
  of its directional pairs. Flagging before building this so the topology
  numbers use a defensible edge model.
- **Explainability and provenance examples** — the Riluzole/Machado-Joseph
  example above is a first case; a systematic characterization of evidence
  types per partner (proprietary link vs. PMID vs. other) across the whole
  file has not been done.

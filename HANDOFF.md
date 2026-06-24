# SIMPATHIC2 Handoff — 2026-06-24

## Infrastructure

| Thing | Value |
|---|---|
| Virtuoso triple store | `http://57.128.119.57:8890/sparql` |
| SSH access | `ssh ubuntu@57.128.119.57 -p 49999` |
| SSH tunnel (from restricted network) | `ssh -fNL 8890:localhost:8890 ubuntu@57.128.119.57 -p 49999` |
| Virtuoso Conductor (browser) | `http://57.128.119.57:8890/conductor` |
| SPARQL endpoint used by scripts | `http://localhost:8890/sparql` (via tunnel) or direct IP |
| Auth env vars | `VIRTUOSO_USER`, `VIRTUOSO_PASS` (never use `dba`) |

**Important Virtuoso quirk:** The SPARQL user account has write-triple privilege but NOT DROP/CLEAR privilege. All graph deletion must use `DELETE { GRAPH <g> { ?s ?p ?o } } WHERE { GRAPH <g> { ?s ?p ?o } }` — never `DROP` or `CLEAR`. Only the Virtuoso Conductor logged in as `dba` can use `CLEAR GRAPH`.

---

## What is in the triple store right now

The database was **completely purged** today. The only named graph currently present is:

- `urn:mondo:hierarchy` — the MONDO disease ontology hierarchy (used for subclass lookups)

HPO was never loaded. MONDO was confirmed present via:
```sparql
SELECT DISTINCT ?g WHERE { GRAPH ?g { ?s <http://www.w3.org/2000/01/rdf-schema#subClassOf> ?y } }
```
(also returns some Virtuoso system graphs: `http://www.w3.org/2002/07/owl#`, `http://www.w3.org/ns/ldp#`, `http://temp/dummy-graph` — all ignorable)

**All SKG partner data needs to be reloaded** by re-running the graphing notebooks (see below).

---

## What was fixed today (and why)

### 1. Named graph URI collision — CRITICAL FIX

Context/graph URIs were built from entity IDs only (e.g. `urn:simpathic:context:12345_HP_0001234`), with no provider prefix. This meant Biovista and Demokritos could produce identical URIs for different data, and deleting one partner's graphs would silently destroy the other's.

**Fix:** All active graphing notebooks now include a provider prefix in every context URI:
- Biovista → `urn:simpathic:context:bv_<id1>_<id2>`
- Demokritos → `urn:simpathic:context:dem_<id1>_<id2>`
- Radboud → `urn:simpathic:context:rad_<id1>_<id2>`

Files changed (19 notebooks, active ones only — not deprecated/DEP subfolders):
- `SKG_Mapping/biovista/2026 BV *.ipynb` (5 notebooks)
- `SKG_Mapping/biovista/BV *.ipynb` (2 notebooks — Drug-Disease, Drug-Gene; no year prefix)
- `SKG_Mapping/demokritos/2026 *.ipynb` (9 graphing notebooks)
- `SKG_Mapping/radboud/2026 Radboud *.ipynb` (5 notebooks)

**Because the database was purged, all notebooks must be re-run** to reload data with the corrected URIs.

### 2. Graph deletion scripts

- `SKG_Mapping/Utilities/Patches/delete_using_http.rb` — deletes all graphs for one `skg-source` value. Now retries 503 errors (5× exponential backoff), logs failures and continues rather than aborting, uses DELETE instead of DROP.
- `SKG_Mapping/Utilities/Patches/purge_all_graphs.rb` — full purge of all SKG data, keeping MONDO/HPO. Uses 16 parallel threads. Uses DELETE instead of CLEAR/DROP. Run this for a complete wipe.

---

## What still needs to be done (in order)

### Step 1 — Reload all partner data

Re-run all 21 active graphing notebooks in Jupyter:

**Biovista** (`SKG_Mapping/biovista/`):
- `2026 BV Disease-Gene Graphing.ipynb`
- `2026 BV Disease-Phenotype Graphing.ipynb`
- `2026 BV Drug-Phenotype Graphing.ipynb`
- `2026 BV Gene-Phenotype Graphing.ipynb`
- `BV Drug-Disease Graphing.ipynb`
- `BV Drug-Gene Graphing.ipynb`

**Demokritos** (`SKG_Mapping/demokritos/`):
- `2026 Disease-Gene Graphing.ipynb`
- `2026 Disease-Phenotype Graphing.ipynb`
- `2026 Drug-Disease Graphing.ipynb`
- `2026 Drug-Gene Graphing.ipynb`
- `2026 Drug-Phenotype Graphing.ipynb`
- `2026 Gene-Phenotype Graphing.ipynb`
- `2026 Phenotype-Disease Graphing.ipynb`
- `2026 Phenotype-Drug Graphing.ipynb`
- `2026 Phenotype-Gene Graphing.ipynb`

**Radboud** (`SKG_Mapping/radboud/`):
- `2026 Radboud Disease-Gene Graphing.ipynb`
- `2026 Radboud Drug-Disease Graphing.ipynb`
- `2026 Radboud Drug-Gene Graphing.ipynb`
- `2026 Radboud Drug-Phenotype Graphing.ipynb`
- `2026 Radboud Phenotype-Gene Graphing.ipynb`

### Step 2 — Generate canonical disease lookup

```bash
cd SKG_Mapping/Utilities/Queries
ruby generate_canonical_lookup.rb
```

This queries the MONDO hierarchy in `urn:mondo:hierarchy` and writes `canonical_disease.tsv` — a flat mapping from any MONDO disease URI to whichever of the 10 SIMPATHIC target diseases is its ancestor. This file must exist before running `build_ml_set.rb`.

The 10 target diseases are:
| MONDO URI | Disease |
|---|---|
| MONDO_0007182 | Machado-Joseph disease |
| MONDO_0008907 | PMM2-CDG |
| MONDO_0009281 | Glutaryl-CoA dehydrogenase deficiency |
| MONDO_0009723 | Leigh syndrome |
| MONDO_0009945 | Pyridoxine-dependent epilepsy |
| MONDO_0010083 | Succinic semialdehyde dehydrogenase deficiency |
| MONDO_0016107 | Myotonic dystrophy |
| MONDO_0018940 | Congenital myasthenic syndrome |
| MONDO_0019609 | Zellweger spectrum disorders |
| MONDO_0100184 | GTP cyclohydrolase I deficiency |

### Step 3 — Build the ML dataset

```bash
ruby build_ml_set.rb    # ~1 hour; writes JUNE_all_pairs_both_orientations_split_evidence.csv.large
ruby merge_evidence.rb  # fast; writes JUNE_all_pairs_both_orientations_merged_evidence.csv.large
```

The merged CSV now has these columns:
```
canonical_entity1_uri  entity1_name  entity1_type
canonical_entity2_uri  entity2_name  entity2_type
rels  sources  evidence
entity1_uri  entity2_uri
```

The last two columns (`entity1_uri`, `entity2_uri`) show all the original specific URIs that were folded into the canonical, pipe-separated.

---

## Key findings from today's data analysis

- Biovista covers exactly **10 diseases** (the target diseases). Demokritos covers **1,651 diseases** — their source knowledge graph is much broader. This is intentional; all Demokritos data is kept.
- Partners use the same URI schemes (UniProt for genes/proteins, PubChem for drugs, OBO/MONDO for diseases, OBO/HP for phenotypes) — no URI mismatch issues.
- Low cross-partner overlap (553 shared pairs before today's fix) was caused primarily by disease granularity differences — e.g. Radboud uses "MJD type 1" (MONDO_0017174) while Biovista uses "MJD" (MONDO_0007182). The canonical URI fix addresses this.
- Radboud has no evidence codes for any observations.

---

## Useful one-off SPARQL queries

**Check how many SKG graphs are loaded (should be 0 until notebooks are re-run):**
```sparql
SELECT (COUNT(DISTINCT ?g) AS ?n) WHERE {
  GRAPH <urn:simpathic:context:all_metadata> { ?g <urn:simpathic:skg-source> ?src }
}
```

**Check graphs per partner:**
```sparql
SELECT ?src (COUNT(DISTINCT ?g) AS ?n) WHERE {
  GRAPH <urn:simpathic:context:all_metadata> { ?g <urn:simpathic:skg-source> ?src }
} GROUP BY ?src
```

**Verify MONDO hierarchy is intact:**
```sparql
SELECT (COUNT(*) AS ?n) WHERE { GRAPH <urn:mondo:hierarchy> { ?s ?p ?o } }
```

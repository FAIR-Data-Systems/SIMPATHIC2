# Radboud SKG Label Fix — Handoff Note

## Context

This is the SIMPATHIC2 project. Three partners (Radboud, Demokritos, Biovista) each have SKGs about genes, diseases, phenotypes, and drugs. We build "maps" that translate each partner's source namespaces into consolidated ones (MONDO for disease, HPO for phenotype, PubChem for drugs, NCBI/UniProt for genes), then use those maps in graphing notebooks that emit RDF N-Quads.

The bug: `rdfs:label` on consolidated entities was sometimes being set from the **source** ontology rather than from the **consolidated/mapped** namespace. We audited all five Radboud graphing notebooks and traced every label back to its source.

---

## Audit Results (Radboud)

| Entity | URI used | Old label source | Status |
|--------|----------|-----------------|--------|
| Disease | MONDO URI | `prefname` col in `diseases.map` = source ontology label (EFO/DOID/Orphanet prefLabel) | **Needs diseases.map patch (see below)** |
| Drug | PubChem URI | `IUPACname` col in `drugs.map` = PubChem canonical name | ✅ Already correct |
| Phenotype | HPO URI | Live OLS4 lookup via `get_hpo_label()` | ✅ Already correct |
| Gene (NCBI geneid URI) | NCBI Gene URI | `label` col in `genes.map` = **ENSG ID** (bug) | ✅ **Fixed** |
| Protein | UniProt URI | `recommended_full` col in `genes.map` = UniProt full name | ✅ Already correct |

---

## What Was Done This Session

### 1. `genes.map` — patched immediately
- The `label` column was identical to `sourceid` (both were the ENSG ID).
- It now contains the UniProt `recommended_full` protein name.
- Old file backed up as `maps/genes.map.bak`.

### 2. `map-genes.ipynb` — fixed for future regeneration
- Changed `label = match[1]` → `label = res["recommended_full"].to_s`
- Fixed output path: was `./mappings/genes.map` (wrong), now `./maps/genes.map`

### 3. `map_diseases-mondo.ipynb` — fixed for future regeneration + patch cell added
- Added `get_mondo_label(mondo_uri)` function using OLS4/EBI (same service as HPO lookups, no API key needed)
- All three `f.write CSV.generate_line(...)` calls now call `get_mondo_label(mondo_uri) || source_label`
- **New patch cells added at the end of the notebook** — see below

---

## Still To Do: Patch `diseases.map`

Open `map_diseases-mondo.ipynb` in Jupyter and run the **last code cell** (id `17dc259c`).

It will:
1. Read the existing `diseases.map`
2. Deduplicate the ~6,643 unique MONDO URIs (vs ~9,300 total rows)
3. Fetch the canonical MONDO `prefLabel` from OLS4 for each
4. Write `maps/diseases.map.updated` (falls back to existing label if OLS4 returns nothing)
5. Print: `Review, then: mv ./maps/diseases.map.updated ./maps/diseases.map`

**Expected runtime: ~15 minutes.** Once done, rename the file and re-run the five graphing notebooks.

---

## After diseases.map Is Updated: Re-run Graphing Notebooks

All five graphing notebooks need to be re-run to regenerate the `.nq.large` output files:

| Notebook | Output file |
|----------|-------------|
| `Radboud Disease-Gene Graphing.ipynb` | `graph/radboud_disease-gene.nq.large` |
| `Radboud Drug-Disease Graphing.ipynb` | `graph/radboud_drug-disease.nq.large` |
| `Radboud Drug-Gene Graphing.ipynb` | `graph/radboud_drug-gene.nq.large` |
| `2026 Radboud Drug-Phenotype Graphing.ipynb` | `graph/radboud_drug-phenotype.nq.large` |
| `2026 Radboud Phenotype-Gene Graphing.ipynb` | `graph/radboud_phenotype-gene.nq.large` |

---

## Demokritos and Biovista

Not yet audited — same label-source problem likely exists there. Once Radboud is done, repeat the same audit process on their map generation and graphing notebooks.

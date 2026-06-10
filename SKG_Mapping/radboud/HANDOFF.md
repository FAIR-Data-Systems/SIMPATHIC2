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

## Demokritos and Biovista — Audit Complete

Both partners have been audited. Here is the full findings and a prioritised fix list.

---

### Demokritos — one issue only

| Entity | URI | Label source | Status |
|--------|-----|--------------|--------|
| Disease | MONDO URI | `disease['prefname']` from `2026-demokritos-disease-mondo.map` = UMLS source name (e.g. `"abetalipoproteinemia"` lowercase) | ❌ Needs fix |
| Drug | PubChem URI | `drug['IUPACname']` = PubChem canonical name | ✅ Correct |
| Gene (NCBI URI) | NCBI Gene URI | `gene['recommended_full']` (UniProt full name) used directly in notebooks | ✅ Correct |
| Protein | UniProt URI | `gene['recommended_full']` | ✅ Correct |
| Phenotype | HPO URI | `hpo_row['HPO_Name']` from `maps/cui_hpo_lookup.tsv` = HPO canonical name | ✅ Correct |

**Fix needed:** Add a `get_mondo_label()` patch cell to `2026-Disease Mapping.ipynb` (same OLS4 pattern as Radboud). The map is `maps/2026-demokritos-disease-mondo.map` with columns `demokritos_umls, prefname, mondo` — update `prefname` in place.

Affected graphing notebooks (all disease-containing ones):
- `2026 Disease-Gene Graphing.ipynb`
- `2026 Drug-Disease Graphing.ipynb`
- `2026 Disease-Phenotype Graphing.ipynb`
- `2026 Phenotype-Disease Graphing.ipynb`
- `2026 Phenotype-Drug Graphing.ipynb` *(indirectly via drug-disease data)*

---

### Biovista — four issues

| Entity | URI | Label source | Status |
|--------|-----|--------------|--------|
| Disease | MONDO URI | `disease['name']` from `2026-biovista-disease-mondo.map` = Biovista ALL CAPS name e.g. `"MYOTONIC DYSTROPHY TYPE 1"` | ❌ Needs fix |
| Drug | PubChem URI | **Two `rdfs:label` statements written** — both `drug['biovista_label']` (MeSH name) AND `drug['IUPACname']` (PubChem name) | ❌ Bug: double label |
| Gene (NCBI URI) | NCBI Gene URI | `gene['bv_label']` = Biovista abbreviation e.g. `"GPx"` | ❌ Needs fix |
| Protein | UniProt URI | `gene['recommended_full']` | ✅ Correct |
| Phenotype (Drug-Phenotype) | HPO URI | `get_hpo_label()` live OLS4 lookup | ✅ Correct |
| Phenotype (Gene-Phenotype) | HPO URI | `pheno_label` from raw Biovista join file `row['name_1']`/`row['name_2']` — ALL CAPS, not canonical | ❌ Needs fix |

**Biovista map file locations:**
- Disease: `maps/2026-biovista-disease-mondo.map` — columns: `biovista_umls, orphanet, snomed, name, mondo`
- Drugs: `maps/2025-biovista-drugs.map` — columns: `biovista_meshid, biovista_label, CID, IUPACname`
- Genes: `maps/2025-biovista-genes.map` — columns: `bv_geneid, bv_label, geneid, protein, recommended_full, taxon`

---

### Prioritised Fix List (do in this order)

**1. Biovista drugs — remove double label** *(data quality bug)*
In three graphing notebooks, the same PubChem URI gets two `rdfs:label` triples written. Remove the `biovista_label` write line, keep only `iupac_drug_label`.
- `BV Drug-Disease Graphing.ipynb` line ~1883
- `BV Drug-Gene Graphing.ipynb` line ~448
- `2026 BV Drug-Phenotype Graphing.ipynb` line ~257

**2. Biovista genes — replace `bv_label` with `recommended_full`**
Change `biovista_gene_label = RDF::Literal.new(gene['bv_label'])` → `gene['recommended_full']` in:
- `BV Disease-Gene Graphing.ipynb` line ~311
- `BV Drug-Gene Graphing.ipynb` line ~417

**3. Biovista diseases — patch the disease map**
Add `get_mondo_label()` patch cell to `biovista-diseases-2026-Mondo.ipynb`. Column to update is `name` in `maps/2026-biovista-disease-mondo.map`. Same OLS4 approach as Radboud.
Affected graphing notebooks: `BV Disease-Gene Graphing.ipynb`, `BV Drug-Disease Graphing.ipynb`, `2026 BV Gene-Phenotype Graphing.ipynb`.

**4. Demokritos diseases — patch the disease map**
Add `get_mondo_label()` patch cell to `2026-Disease Mapping.ipynb`. Column to update is `prefname` in `maps/2026-demokritos-disease-mondo.map`. Same OLS4 approach as Radboud.

**5. Biovista phenotypes in Gene-Phenotype — replace raw-data label with OLS4 lookup**
`2026 BV Gene-Phenotype Graphing.ipynb` currently sets `hpo_label = RDF::Literal.new(pheno_label)` where `pheno_label` comes from the raw Biovista join file. Replace with `hpo_label = RDF::Literal.new(get_hpo_label(hpo_id))`, copying the pattern already used in `2026 BV Drug-Phenotype Graphing.ipynb`.

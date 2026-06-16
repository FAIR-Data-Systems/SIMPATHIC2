# SKG Label Fix — Handoff Note (all three partners)

## Context

This is the SIMPATHIC2 project. Three partners (Radboud, Demokritos, Biovista) each have SKGs about genes, diseases, phenotypes, and drugs. We build "maps" that translate each partner's source namespaces into consolidated ones (MONDO for disease, HPO for phenotype, PubChem for drugs, NCBI/UniProt for genes), then use those maps in graphing notebooks that emit RDF N-Quads.

The bug: `rdfs:label` on consolidated entities was sometimes being set from the **source** ontology rather than from the **consolidated/mapped** namespace. We audited all three partners and fixed what we could. Remaining fixes and the full upload sequence are described below.

**Work in progress: `map_diseases-mondo.ipynb` (Radboud) is currently running a from-scratch re-generation of `diseases.map`. Expected runtime ~several hours. Do not touch that file until it finishes.**

---

## Overall Status by Partner

### Radboud

| Entity | Label column | Status |
|--------|-------------|--------|
| Disease | `prefname` in `diseases.map` | ⏳ Map being regenerated (from-scratch run in progress) |
| Drug | `IUPACname` in `drugs.map` | ✅ Correct |
| Phenotype | Live OLS4 via `get_hpo_label()` | ✅ Correct |
| Gene (NCBI URI) | `label` in `genes.map` | ✅ Fixed (was ENSG ID, now = `recommended_full`) |
| Protein (UniProt URI) | `recommended_full` in `genes.map` | ✅ Correct |

### Biovista

| Entity | Label column | Status |
|--------|-------------|--------|
| Disease | `name` in `2026-biovista-disease-mondo.map` | ❌ Still ALL CAPS Biovista names — needs `get_mondo_label()` patch |
| Drug | `IUPACname` in `2025-biovista-drugs.map` | ✅ Correct |
| Gene (NCBI URI) | `recommended_full` in `2025-biovista-genes.map` | ✅ Fixed (was `bv_label` abbreviation) |
| Protein (UniProt URI) | `recommended_full` in `2025-biovista-genes.map` | ✅ Correct |
| Phenotype (Drug-Phenotype) | raw `pheno_label` from Biovista join file | ❌ Needs OLS4 fix (see note below) |
| Phenotype (Gene-Phenotype) | raw `pheno_label` from Biovista join file | ❌ Needs OLS4 fix |

> **Note:** The previous audit marked Drug-Phenotype as ✅ (claimed it used `get_hpo_label()`), but inspection of the actual code shows it uses `hpo_label = RDF::Literal.new(pheno_label)` — raw Biovista ALL CAPS labels. Both Drug-Phenotype and Gene-Phenotype notebooks need the same OLS4 fix.

### Demokritos

| Entity | Label column | Status |
|--------|-------------|--------|
| Disease | `prefname` in `2026-demokritos-disease-mondo.map` | ❌ Still UMLS source names — needs `get_mondo_label()` patch |
| Drug | `IUPACname` in `2026-drug-mappings.map` | ✅ Correct |
| Gene (NCBI URI) | `recommended_full` in `2026-gene-mappings.map` | ✅ Correct |
| Protein (UniProt URI) | `recommended_full` in `2026-gene-mappings.map` | ✅ Correct |
| Phenotype | `HPO_Name` from `cui_hpo_lookup.tsv` | ✅ Correct |

---

## What Was Done in the Most Recent Session

1. **`BV Drug-Disease Graphing.ipynb`** — removed the `drug_label` (Biovista MeSH name) `rdfs:label` write; kept only `iupac_drug_label`.
2. **`BV Drug-Gene Graphing.ipynb`** — same double-label fix for drugs; also changed `biovista_gene_label` source from `gene['bv_label']` → `gene['recommended_full']`.
3. **`2026 BV Drug-Phenotype Graphing.ipynb`** — same double-label fix for drugs.
4. **`BV Disease-Gene Graphing.ipynb`** — changed `biovista_gene_label` from `gene['bv_label']` → `gene['recommended_full']`.
5. **`SKG_Mapping/Label-Sanity-Check.ipynb`** — new notebook that spot-checks 10 random rows per entity type per partner against the authoritative API (OLS4/UniProt/PubChem) before the graphing notebooks are run. See run-order instructions inside it.

---

## Go-Forward Plan (do in this order)

### Step 1 — Wait for Radboud `diseases.map` to finish

The mapping notebook is running. When it completes, `maps/diseases.map` will have columns `source, mondo, prefname` with canonical MONDO labels.

### Step 2 — Run Label-Sanity-Check.ipynb

Open `SKG_Mapping/Label-Sanity-Check.ipynb` (Ruby / ruby3 kernel).

- Run **Setup** cell first.
- Run the **Radboud genes** and **Radboud drugs** cells (these are ready now).
- Run the **Radboud diseases** cell (only after Step 1 completes).
- Run the **Biovista genes**, **Biovista drugs**, **Demokritos genes**, **Demokritos drugs** cells (all ready now).
- Hold the **Biovista diseases** and **Demokritos diseases** cells until Steps 4 & 5.

Investigate any `✗` mismatches before proceeding.

### Step 3 — Run Radboud graphing notebooks + upload

Run all five Radboud graphing notebooks to regenerate `.nq.large` files:

| Notebook | Output |
|----------|--------|
| `Radboud Disease-Gene Graphing.ipynb` | `graph/radboud_disease-gene.nq.large` |
| `Radboud Drug-Disease Graphing.ipynb` | `graph/radboud_drug-disease.nq.large` |
| `Radboud Drug-Gene Graphing.ipynb` | `graph/radboud_drug-gene.nq.large` |
| `2026 Radboud Drug-Phenotype Graphing.ipynb` | `graph/radboud_drug-phenotype.nq.large` |
| `2026 Radboud Phenotype-Gene Graphing.ipynb` | `graph/radboud_phenotype-gene.nq.large` |

**Before uploading:** ask Claude to write `Utilities/Patches/Delete_Radboud_Labels.sparql` + `.curl` — a SPARQL UPDATE that removes all `rdfs:label` triples from every graph tagged `simp:skg-source "Radboud"` in Virtuoso.

Upload sequence:
1. Run the DELETE labels SPARQL against Virtuoso (`http://57.128.119.57:8890/sparql`).
2. Upload the five `.nq.large` files normally — non-label triples already in Virtuoso will auto-dedup.

### Step 4 — Patch Biovista disease map

Open `biovista/biovista-diseases-2026-Mondo.ipynb` and add a `get_mondo_label()` patch cell (same OLS4 pattern as Radboud's `map_diseases-mondo.ipynb`). The column to update is `name` in `maps/2026-biovista-disease-mondo.map`.

Then run the **Biovista diseases** cell in `Label-Sanity-Check.ipynb`.

### Step 5 — Patch Demokritos disease map

Open `demokritos/2026-Disease Mapping.ipynb` and add a `get_mondo_label()` patch cell. The column to update is `prefname` in `maps/2026-demokritos-disease-mondo.map`.

Then run the **Demokritos diseases** cell in `Label-Sanity-Check.ipynb`.

### Step 6 — Fix Biovista HPO phenotype labels

Two notebooks still use raw Biovista ALL CAPS phenotype labels. Both need `get_hpo_label()` added (copy from `2026 Radboud Drug-Phenotype Graphing.ipynb` cell 7) and a memoisation cache to avoid thousands of redundant API calls.

- `2026 BV Gene-Phenotype Graphing.ipynb` — replace `hpo_label = RDF::Literal.new(pheno_label)` with `get_hpo_label(pheno_id)`; `pheno_id` is already in `HP_XXXXXXX` format at that point in the code.
- `2026 BV Drug-Phenotype Graphing.ipynb` — same fix.

### Step 7 — Run Biovista graphing notebooks + upload

Same pattern as Step 3. Affected graphing notebooks:
- `BV Disease-Gene Graphing.ipynb`
- `BV Drug-Disease Graphing.ipynb`
- `BV Drug-Gene Graphing.ipynb`
- `2026 BV Drug-Phenotype Graphing.ipynb`
- `2026 BV Gene-Phenotype Graphing.ipynb`

Ask Claude for `Delete_Biovista_Labels.sparql` + `.curl` before uploading. Biovista source string in Virtuoso: `"Biovista"`.

### Step 8 — Run Demokritos graphing notebooks + upload

Same pattern. Ask Claude for `Delete_Demokritos_Labels.sparql` + `.curl`. Demokritos source string in Virtuoso: `"Demokritos"`.

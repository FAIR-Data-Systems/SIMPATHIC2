# SKG_Mapping — Change Log and Run Instructions

This document covers all structural changes made to the mapping notebooks and map
files during the April–June 2026 label-consistency audit, together with complete
instructions for running the full pipeline from scratch.

---

## Background: What the pipeline does

Three partner SKGs (Radboud, Biovista, Demokritos) each contain edges between
biological entities (genes, diseases, phenotypes, drugs) expressed in
partner-specific vocabularies. This mapping pipeline:

1. **Translates** each partner's source identifiers into consolidated namespaces:
   - Disease → MONDO (`http://purl.obolibrary.org/obo/MONDO_*`)
   - Phenotype → HPO (`http://purl.obolibrary.org/obo/HP_*`)
   - Drug → PubChem CID (`https://pubchem.ncbi.nlm.nih.gov/compound/*`)
   - Gene/Protein → NCBI Entrez Gene URI + UniProt URI

2. **Assigns canonical `rdfs:label` values** for each consolidated entity from
   authoritative external databases (MONDO via OLS4, HPO via OLS4, PubChem
   `property/Title`, UniProt recommended protein name).

3. **Emits RDF N-Quads** (`.nq.large` files) via IRuby graphing notebooks, which
   are uploaded to Virtuoso (`http://57.128.119.57:8890/sparql`).

The sanity-check notebook `Label-Sanity-Check.ipynb` compares labels across all
three partners for a random sample of overlapping entities. All `✓` rows confirm
that when multiple partners reference the same CID/MONDO/HP/gene, their
`rdfs:label` is identical.

---

## Label policy (canonical source for each entity type)

| Entity type  | Canonical namespace   | Label source                                   |
|--------------|-----------------------|------------------------------------------------|
| Disease      | MONDO                 | OLS4 API (`api.ontology.org/v2/ontologies/mondo/terms/{id}`, field `label`) |
| Phenotype    | HPO                   | OLS4 API (`api.ontology.org/v2/ontologies/hp/terms/{id}`, field `label`) |
| Drug         | PubChem CID           | PubChem `property/Title` (= RecordTitle), with leading stereo prefix stripped (see §Gene/Drug notes) |
| Gene (NCBI)  | NCBI Entrez Gene URI  | UniProt recommended protein full name (`proteinDescription.recommendedName.fullName.value`) via UniProt REST API |
| Protein      | UniProt URI           | Same UniProt recommended protein full name     |

### Stereo prefix stripping for drugs

PubChem RecordTitle sometimes includes leading stereochemistry prefixes that are
not part of the conventional drug name (e.g. `L-Tryptophan`, `(S)-Ibuprofen`,
`(+/-)-Warfarin`). All three partner drug mapping notebooks apply:

```ruby
STEREO_PREFIX = /\A(?:(?:[LlDd]-)|(?:\([RrSsEeZz\+\-RS]\)-)|(?:\(\+\/\-\)-))+/
title.gsub(STEREO_PREFIX, '')
```

This is applied at map-generation time (not at graph-generation time). The map
files store the already-stripped label in their `IUPACname` column.

---

## Changes made — June 2026 label-consistency audit

### Problem discovered

A cross-partner sanity check (`Label-Sanity-Check.ipynb`) revealed that
`rdfs:label` on consolidated entities differed between partners for the same
identifier. Root causes:

- **Genes**: each partner was using a different naming source.
  Demokritos used NCBI mygene.info gene descriptions (e.g. "ataxin 3").
  Biovista used a mix of reviewed and unreviewed UniProt entries, and had
  multiple rows per gene when a gene had protein isoforms, causing non-canonical
  rows to be selected at graph time.
  The correct label for a gene is the **UniProt recommended protein full name**
  for its canonical Swiss-Prot accession (e.g. "Ataxin-3").

- **Drugs**: each partner used a different labelling database.
  Biovista used MeSH preferred labels.
  Demokritos used UMLS/BioPortal `prefLabel`.
  Radboud used PubChem `RecordTitle`.
  These databases disagree on stereochemistry ("L-Tryptophan" vs "Tryptophan"),
  class vs. specific compound ("Nitrogen Oxides" vs. "Nitric Oxide"), and
  occasionally on the conventional name entirely ("Epoprostenol" vs. "Prostacyclin").
  The fix was to standardise all three on PubChem `property/Title` for the CID,
  since PubChem is the authoritative database for the PubChem CID identifier.

---

### Demokritos — Gene labels

**File:** `demokritos/2026 Gene Mapping.ipynb`

**Cell `37dd511c`** (core mapping function `map_cui_to_geneinfo`) — **rewritten**:
- Added `get_uniprot_protein_name(accession)` function that calls
  `https://rest.uniprot.org/uniprotkb/{accession}?format=json` and extracts
  `proteinDescription.recommendedName.fullName.value`.
- `map_cui_to_geneinfo` now calls this for the Swiss-Prot accession returned by
  mygene.info, and uses the result as `recommended_full`. Falls back to
  mygene.info `name` if the UniProt call fails.
- Previously the code used `hit.dig('name')` from mygene.info, which returns
  NCBI gene descriptions (lower-case, unofficial, sometimes wrong).

**Cell `7a99c64b`** (patch cell, **already run**):
- Batch-fetches UniProt recommended names for all 2377 rows in
  `maps/2026-gene-mappings.map` using `https://rest.uniprot.org/uniprotkb/search`
  with batches of 50 accessions.
- Writes corrected `recommended_full` back to the map.
- **This patch is a one-time backfill.** Future runs of the mapping notebook will
  produce correct names directly without needing this cell.

---

### Biovista — Gene labels

**File:** `biovista/biovista-gene-2025.ipynb`

**Problem:** The SPARQL query against `https://sparql.uniprot.org/sparql/` was
fetching `?protein a up:Protein`, which includes both Swiss-Prot reviewed entries
and TrEMBL unreviewed entries. When a gene had multiple protein records, the
non-canonical TrEMBL isoform was sometimes returned first, giving wrong labels
(e.g. gene 4287 returned "ubiquitinyl hydrolase 1" instead of "Ataxin-3", gene
27010 returned "Thiamine pyrophosphokinase" instead of "Thiamine pyrophosphokinase 1").
Additionally, there were multiple rows per `bv_geneid` in the map when a gene had
multiple protein isoforms, causing the `find` selector in graphing notebooks to
pick whichever row appeared first.

**Cell `21e34242`** (SPARQL query) — **updated**:
- Changed `?protein a up:Protein` to `?protein a up:Reviewed_Protein`.
- This restricts results to Swiss-Prot reviewed entries only, excluding TrEMBL
  unreviewed sequences. Future map regenerations will only write reviewed entries.

**Cell `5dfc3ca5`** (SPARQL execution + write) — **updated**:
- Changed the batch result assertion from `abort "..." unless result.size >= 20`
  to `warn "Batch returned no results — some genes may lack a reviewed UniProt entry" if result.size == 0`.
- Rationale: after filtering to `up:Reviewed_Protein`, some gene batches may
  legitimately return fewer than 20 results, so aborting on size < 20 was wrong.

**Cell `2a62a6c3`** (protein name patch cell, **new, already run**):
- Batch-fetches UniProt recommended protein names for all accessions in
  `maps/2025-biovista-genes.map` using the UniProt search endpoint.
- Updates `recommended_full` column with the canonical protein name.

**Cell `13133d52`** (dedup cell, **new, already run**):
- Deduplicates the map to one row per `bv_geneid`, keeping the canonical
  Swiss-Prot O/P/Q-prefix accession.
- Canonical Swiss-Prot accessions match `/^[OPQ]\d[A-Z0-9]{3}\d$/` (6 chars,
  O/P/Q prefix). Other 6-char accessions rank second; 10-char TrEMBL accessions
  rank last.
- Map shrank from 958 rows to 575 rows.
- **This cell should be run once after every future map regeneration** to ensure
  only one row per gene reaches the graphing notebooks.

---

### Radboud — Drug labels

**File:** `radboud/map-drugs.ipynb`

**Cell `c90a517c`** (core functions) — **updated**:
- `get_more_metadata(cid)` was already using PubChem `pug_view/RecordTitle`.
- Updated the comment to state that all three partners now use PubChem
  RecordTitle as the canonical drug label source.
- `STEREO_PREFIX` regex defined here and applied in `get_more_metadata`.

**Cell `21703b72`** (patch cell, **new, already run**):
- Batch-fetches PubChem `property/Title` for all 1658 numeric CIDs in
  `maps/drugs.map` (100 CIDs per request, 17 batches).
- Applies `STEREO_PREFIX` strip and writes corrected `IUPACname` back to the
  map. 242 SUBSTANCE_* rows (biologics without numeric CIDs) are left unchanged.
- **This patch is a one-time backfill** of the existing map. Future runs of the
  main mapping cell `4c5082df` will call `get_more_metadata()` which already
  uses RecordTitle, so they will also produce correct labels directly.

---

### Biovista — Drug labels

**File:** `biovista/biovista-drug-2025.ipynb`

**Problem:** The main mapping loop was using the MeSH preferred label (`json['label']`
fetched from `https://id.nlm.nih.gov/mesh/{id}.json`) as `IUPACname`. MeSH
preferred labels often differ from PubChem RecordTitle: they may use class names
("Nitrogen Oxides" for a specific nitric oxide CID), omit stereochemistry
position indicators ("Fluorouracil" where PubChem says "5-Fluorouracil"), or
use alternative conventional names ("Epoprostenol" where PubChem says "Prostacyclin").

**New cell `e7510f73`** (inserted after markdown cell `3d2d33f5`) — **new**:
```ruby
STEREO_PREFIX = /\A(?:(?:[LlDd]-)|(?:\([RrSsEeZz\+\-RS]\)-)|(?:\(\+\/\-\)-))+/

def get_pubchem_title(cid)
  return nil unless cid.to_s =~ /^\d+$/
  url = "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/#{cid}/property/Title/JSON"
  resp = RestClient::Request.execute(method: :get, url: url, timeout: 15)
  return nil unless resp.code == 200
  JSON.parse(resp.body).dig('PropertyTable', 'Properties', 0, 'Title')
rescue
  nil
end
```

**Cell `b138146a-af37-41d3-9793-71b9dc00c642`** (main mapping loop) — **updated**:
- The `cids.each` block at the end of the loop now calls `get_pubchem_title(cid)`
  and stores the result (with stereo strip) as `iupac_label` for the `IUPACname`
  column.
- Falls back to the MeSH `name` only if the PubChem API call returns nil (network
  failure or CID not found).
- The now-unused `map_cid_to_iupacname(cid)` branch for `name == "UNKNOWN"` has
  been removed.

**Map file `maps/2025-biovista-drugs.map` — NOT YET UPDATED.**
The notebook must be re-run to regenerate this file with PubChem labels.

---

### Demokritos — Drug labels

**File:** `demokritos/2026 Drug Mapping.ipynb`

**Problem:** The main mapping loop used `hash[:name]` (= the BioPortal/UMLS
`prefLabel` from `map_umls_to_cid`) as `IUPACname`. BioPortal prefLabels come
from MeSH and SNOMED-CT and suffer the same class-vs-specific and naming
convention mismatches as described for Biovista above.

**New cell `a8945a1a`** (inserted after markdown cell `3d2d33f5`) — **new**:
Same `get_pubchem_title()` + `STEREO_PREFIX` helper as Biovista above.

**Cell `e4bfd527`** (main write loop) — **updated**:
- After `cid = hash[:cid]`, now calls `get_pubchem_title(cid)` and uses the
  result (with stereo strip) as `iupacname`.
- Falls back to `hash[:name]` (BioPortal prefLabel) if PubChem returns nil.

**Map file `maps/2026-drug-mappings.map` — NOT YET UPDATED.**
The notebook must be re-run to regenerate this file with PubChem labels.

---

## Current status of map files (as of June 2026)

| Partner    | Map file                              | IUPACname / recommended_full source  | Up to date? |
|------------|---------------------------------------|--------------------------------------|-------------|
| Radboud    | `radboud/maps/drugs.map`              | PubChem RecordTitle (patched)        | ✅          |
| Radboud    | `radboud/maps/genes.map`              | UniProt recommended name             | ✅          |
| Radboud    | `radboud/maps/diseases.map`           | MONDO label via OLS4                 | ✅          |
| Biovista   | `biovista/maps/2025-biovista-drugs.map`   | **MeSH label (stale)**          | ❌ Needs re-run |
| Biovista   | `biovista/maps/2025-biovista-genes.map`   | UniProt recommended name (patched)   | ✅          |
| Biovista   | `biovista/maps/2026-biovista-disease-mondo.map` | MONDO label via OLS4       | ✅          |
| Demokritos | `demokritos/maps/2026-drug-mappings.map`  | **BioPortal prefLabel (stale)** | ❌ Needs re-run |
| Demokritos | `demokritos/maps/2026-gene-mappings.map`  | UniProt recommended name (patched)   | ✅          |
| Demokritos | `demokritos/maps/2026-demokritos-disease-mondo.map` | MONDO label via OLS4 | ✅          |

## Open items from previous audit (see also `radboud/HANDOFF.md`)

The following were identified before the drug-label work and are still pending:

| Item | Status |
|------|--------|
| Biovista disease map — still ALL CAPS Biovista names, needs `get_mondo_label()` patch | ❌ Pending |
| Biovista `2026 BV Drug-Phenotype Graphing.ipynb` — uses raw Biovista ALL CAPS phenotype labels; needs OLS4 `get_hpo_label()` | ❌ Pending |
| Biovista `2026 BV Gene-Phenotype Graphing.ipynb` — same HPO label issue | ❌ Pending |
| Demokritos disease map — still UMLS source names, needs `get_mondo_label()` patch | ❌ Pending |

---

## From-scratch run instructions

Run the notebooks in the order below within each partner. All notebooks use the
**ruby3** kernel (IRuby). Each notebook must be run **top to bottom** (Kernel →
Restart & Run All, or cell by cell in order).

### API keys and environment

The Demokritos drug mapping notebook reads `ENV["APIKEY"]` for BioPortal. Set this
before starting the Jupyter server:
```bash
export APIKEY=<your-bioportal-api-key>
```

---

### 1. Radboud

#### 1a. Build maps

| Notebook | Output | Notes |
|----------|--------|-------|
| `radboud/map_diseases-mondo.ipynb` | `radboud/maps/diseases.map` | Slow (~several hours). Calls MONDO OLS4 for every disease. |
| `radboud/map-drugs.ipynb` | `radboud/maps/drugs.map` | Calls PubChem per ChEMBL ID. After main loop, run the biologics fallback cell (`5972d0ef`) for drugs that failed CID lookup. The patch cell (`21703b72`) is a one-time backfill and does NOT need to be re-run. |
| `radboud/map-genes.ipynb` | `radboud/maps/genes.map` | Calls Ensembl + UniProt. |

#### 1b. Run graphing notebooks

| Notebook | Output |
|----------|--------|
| `radboud/2026 Radboud Disease-Gene Graphing.ipynb` | `radboud/graph/2026_radboud_disease-gene.nq.large` |
| `radboud/2026 Radboud Drug-Disease Graphing.ipynb` | `radboud/graph/2026_drug-disease.nq.large` |
| `radboud/2026 Radboud Drug-Gene Graphing.ipynb` | `radboud/graph/2026_drug-gene.nq.large` |
| `radboud/2026 Radboud Drug-Phenotype Graphing.ipynb` | `radboud/graph/2026_drug-phenotype.nq.large` |
| `radboud/2026 Radboud Phenotype-Gene Graphing.ipynb` | `radboud/graph/2026_phenotype-gene.nq.large` |

---

### 2. Biovista

#### 2a. Build maps

| Notebook | Output | Notes |
|----------|--------|-------|
| `biovista/biovista-diseases-2026-Mondo.ipynb` | `biovista/maps/2026-biovista-disease-mondo.map` | Calls MONDO OLS4. |
| `biovista/biovista-drug-2025.ipynb` | `biovista/maps/2025-biovista-drugs.map` | Calls MeSH for CID lookup, then PubChem `property/Title` for each CID. Slow (~477 drugs × 3 API calls + per-CID title fetch). |
| `biovista/biovista-gene-2025.ipynb` | `biovista/maps/2025-biovista-genes.map` | Calls UniProt SPARQL endpoint for reviewed proteins. **After the main SPARQL loop completes, also run the dedup cell (`13133d52`)** to collapse to one row per gene. The protein name patch cell (`2a62a6c3`) does NOT need to be re-run (its logic is now built into the core). |
| `biovista/biovista-phenotypes.ipynb` | `biovista/maps/2025-biovista-phenotypes.map` | — |
| `biovista/biovista-pathways-2025.ipynb` | `biovista/maps/2025-biovista-pathways.map` | — |

#### 2b. Run graphing notebooks

| Notebook | Output |
|----------|--------|
| `biovista/2026 BV Disease-Gene Graphing.ipynb` | `biovista/graph/2026_disease-gene.nq.large` |
| `biovista/BV Drug-Disease Graphing.ipynb` | `biovista/graph/2026_biovista_drug-disease.nq.large` |
| `biovista/BV Drug-Gene Graphing.ipynb` | `biovista/graph/2026_biovista_drug-gene.nq.large` |
| `biovista/2026 BV Drug-Phenotype Graphing.ipynb` | `biovista/graph/2026_drug-phenotype.nq.large` |
| `biovista/2026 BV Gene-Phenotype Graphing.ipynb` | *(no `.nq.large` found — check output path)* |

> **Note:** `2026 BV Drug-Phenotype Graphing.ipynb` and `2026 BV Gene-Phenotype Graphing.ipynb`
> still use raw Biovista ALL CAPS phenotype labels (`hpo_label = RDF::Literal.new(pheno_label)`).
> These need an OLS4 `get_hpo_label()` fix before the next upload (see `radboud/HANDOFF.md` §Step 6).
> Run them anyway to produce current graph files, but flag for fix before uploading.

---

### 3. Demokritos

#### 3a. Build maps

| Notebook | Output | Notes |
|----------|--------|-------|
| `demokritos/2026-Disease Mapping.ipynb` | `demokritos/maps/2026-demokritos-disease-mondo.map` | Calls MONDO OLS4. |
| `demokritos/2026 Drug Mapping.ipynb` | `demokritos/maps/2026-drug-mappings.map` | Calls BioPortal for CUI→prefLabel→CID, then PubChem `property/Title` for each CID. Requires `APIKEY` env var. ~1213 CUIs, multiple API calls each. Allow several hours. |
| `demokritos/2026 Gene Mapping.ipynb` | `demokritos/maps/2026-gene-mappings.map` | Calls mygene.info then UniProt REST per gene. The patch cell (`7a99c64b`) does NOT need to be re-run. |
| `demokritos/2026 Phenotype Mapping.ipynb` | *(check output)* | — |

#### 3b. Run graphing notebooks

| Notebook | Output |
|----------|--------|
| `demokritos/2026 Disease-Gene Graphing.ipynb` | `demokritos/graph/2026-disease-gene.nq.large` |
| `demokritos/2026 Drug-Disease Graphing.ipynb` | `demokritos/graph/2026-demokritos_drug-disease.nq.large` |
| `demokritos/2026 Drug-Gene Graphing.ipynb` | `demokritos/graph/2026-demokritos_drug-gene.nq.large` |
| `demokritos/2026 Drug-Phenotype Graphing.ipynb` | `demokritos/graph/2026-drug-phenotype.nq.large` |
| `demokritos/2026 Gene-Phenotype Graphing.ipynb` | `demokritos/graph/2026-gene-phenotype.nq.large` |
| `demokritos/2026 Phenotype-Disease Graphing.ipynb` | `demokritos/graph/2026-phenotype-disease.nq.large` |
| `demokritos/2026 Phenotype-Drug Graphing.ipynb` | `demokritos/graph/2026-phenotype-drug.nq.large` |
| `demokritos/2026 Phenotype-Gene Graphing.ipynb` | `demokritos/graph/2026-phenotype-gene.nq.large` |

---

### 4. Sanity check (run between mapping and uploading)

Open `Label-Sanity-Check.ipynb`. Run each cell in order. Every entity type
should show ≥ 90% `✓` matches. Investigate any `✗` before uploading. The check
compares all partners that share a given identifier and flags cases where the
label differs.

---

### 5. Upload to Virtuoso

Before uploading any partner's graphs, delete the existing `rdfs:label` triples
for that partner from Virtuoso (to avoid duplicate labels). The SPARQL UPDATE
pattern is:

```sparql
DELETE {
  GRAPH ?g { ?s <http://www.w3.org/2000/01/rdf-schema#label> ?label }
}
WHERE {
  GRAPH ?g {
    ?s <http://www.w3.org/2000/01/rdf-schema#label> ?label .
    ?g <http://simpathic.eu/skg-source> "Radboud"   # change per partner
  }
}
```

Post via: `curl -X POST http://57.128.119.57:8890/sparql -d 'query=...'`

Then upload the `.nq.large` files normally; non-label triples already in
Virtuoso will be deduplicated automatically.

---

## Notes on specific naming surprises

- **Fluorouracil vs 5-Fluorouracil**: PubChem RecordTitle for CID 3385 is
  "5-Fluorouracil" (the position indicator is part of the IUPAC-preferred name).
  MeSH and UMLS use "Fluorouracil" as a shorthand. After all three notebooks are
  re-run, all three partners will output "5-Fluorouracil". This is correct.

- **Prostacyclin vs Epoprostenol**: PubChem uses "Prostacyclin" as the RecordTitle.
  MeSH uses "Epoprostenol" (the INN). Both refer to PGI2. After re-run, all three
  partners will use "Prostacyclin".

- **Glimepiride**: PubChem CID 3476 RecordTitle is a systematic CAS-style name, not
  the INN "Glimepiride". This is a quirk of PubChem's nomenclature for this
  compound. All three partners will agree on the same long name after re-run.
  This can be fixed in a future pass by looking up the INN separately, but
  consistency across partners is the primary goal.

- **The prion protein (gene 4267 / PRNP)**: mygene.info returns the Swiss-Prot
  accession as an Array `["P04156"]` rather than a string. The Demokritos gene
  mapping core function handles this with `protein = protein.first if protein.is_a?(Array)`.

---

## Changes made — 2026-06-23/24 (database purge + URI collision fix + ML dataset)

### Database purged

The Virtuoso triple store was fully wiped using the Conductor's SPARQL editor
(logged in as `dba`) with two queries:

```sparql
-- 1. Delete all SKG data graphs
DELETE { GRAPH ?g { ?s ?p ?o } }
WHERE {
  GRAPH ?g { ?s ?p ?o }
  FILTER(CONTAINS(STR(?g), "simpathic"))
  FILTER(?g != <urn:simpathic:context:all_metadata>)
}

-- 2. Clear the metadata graph
CLEAR GRAPH <urn:simpathic:context:all_metadata>
```

The `CLEAR GRAPH` was used for step 2 because `DELETE WHERE` on the metadata
graph (~2 million entries) hit Virtuoso's internal hash dictionary limit.
`CLEAR GRAPH` is only available to `dba` via the Conductor; normal user accounts
must use `DELETE { GRAPH ... } WHERE { ... }`.

**All partner data must be reloaded** by re-running the graphing notebooks (see
run instructions above).

---

### CRITICAL: Named graph URI collision — fixed in all graphing notebooks

**Problem:** Context/graph URIs were built from entity IDs only:
`urn:simpathic:context:<id1>_<id2>`. Because Biovista and Demokritos both use
PubChem CIDs for drugs and MONDO URIs for diseases, they could produce identical
context URIs for unrelated observations. Deleting one partner's graphs via
`skg-source` would destroy data from another partner if any context graph was
shared.

**Fix:** All active graphing notebooks now embed a provider prefix in the context
URI immediately after `urn:simpathic:context:`:

| Partner | Old pattern | New pattern |
|---|---|---|
| Biovista | `urn:simpathic:context:#{id1}_#{id2}` | `urn:simpathic:context:bv_#{id1}_#{id2}` |
| Demokritos | `urn:simpathic:context:#{id1}_#{id2}` | `urn:simpathic:context:dem_#{id1}_#{id2}` |
| Radboud | `urn:simpathic:context:#{id1}_#{id2}` | `urn:simpathic:context:rad_#{id1}_#{id2}` |

Note: the Biovista Gene-Phenotype notebook already used `bv_` (introduced
earlier) and was left unchanged.

**19 notebooks changed** (active notebooks only; `deprecated/` and `DEP/`
subfolders not touched):
- `biovista/2026 BV Disease-Gene Graphing.ipynb`
- `biovista/2026 BV Disease-Phenotype Graphing.ipynb`
- `biovista/2026 BV Drug-Phenotype Graphing.ipynb`
- `biovista/BV Drug-Disease Graphing.ipynb`
- `biovista/BV Drug-Gene Graphing.ipynb`
- `demokritos/2026 Disease-Gene Graphing.ipynb`
- `demokritos/2026 Disease-Phenotype Graphing.ipynb`
- `demokritos/2026 Drug-Disease Graphing.ipynb`
- `demokritos/2026 Drug-Gene Graphing.ipynb`
- `demokritos/2026 Drug-Phenotype Graphing.ipynb`
- `demokritos/2026 Gene-Phenotype Graphing.ipynb`
- `demokritos/2026 Phenotype-Disease Graphing.ipynb`
- `demokritos/2026 Phenotype-Drug Graphing.ipynb`
- `demokritos/2026 Phenotype-Gene Graphing.ipynb`
- `radboud/2026 Radboud Disease-Gene Graphing.ipynb`
- `radboud/2026 Radboud Drug-Disease Graphing.ipynb`
- `radboud/2026 Radboud Drug-Gene Graphing.ipynb`
- `radboud/2026 Radboud Drug-Phenotype Graphing.ipynb`
- `radboud/2026 Radboud Phenotype-Gene Graphing.ipynb`

---

### Deletion utility scripts — fixed

**`Utilities/Patches/delete_using_http.rb`** (delete graphs for one `skg-source`):
- Added exponential-backoff retry on 503 (up to 5 retries, starting at 10 s).
- Changed behaviour on failure from `abort` to log-and-continue; failures are
  summarised at the end and script exits with code 1.
- Replaced `DROP SILENT GRAPH <g>` with
  `DELETE { GRAPH <g> { ?s ?p ?o } } WHERE { GRAPH <g> { ?s ?p ?o } }` because
  the SPARQL user account has write-triple privilege but not DROP privilege.
- Fixed `WITH <simp:context:all_metadata>` (literal prefix URI) to
  `WITH <urn:simpathic:context:all_metadata>` (fully expanded URI).
- Added a final verification SELECT to confirm zero graphs remain after the run.

**`Utilities/Patches/purge_all_graphs.rb`** (full purge, keep ontology graphs):
- Changed `CLEAR GRAPH <g>` to `DELETE { GRAPH <g> { ?s ?p ?o } } WHERE { ... }`
  for the same permission reason as above.
- Changed `CLEAR GRAPH <annotation_graph>` to
  `WITH <annotation_graph> DELETE { ?s ?p ?o } WHERE { ?s ?p ?o }`.
- Added same exponential-backoff retry logic on 503/network errors.
- Excluded `all_metadata` from the data-graph discovery query to avoid
  attempting to clear it twice.
- Kept existing 16-thread parallel architecture.

---

### ML dataset — canonical disease URI mapping added

**Problem identified via data analysis:** Partners operate at different levels of
MONDO granularity. Radboud uses disease subtypes (e.g. MONDO_0017174
"MJD type 1") while Biovista uses the parent disease (MONDO_0007182
"Machado-Joseph disease"). These were treated as different entities during
merging, suppressing cross-partner overlap.

**Analysis findings:**
- Biovista covers exactly 10 diseases (the target diseases).
- Demokritos covers 1,651 diseases — its source knowledge graph is broader.
  Only 7 of Biovista's 10 target diseases appear as exact matches in Demokritos;
  the remaining 3 appear as subclass matches. All Demokritos data is kept.
- All three partners use the same URI schemes (UniProt, PubChem, OBO), so there
  is no identifier mismatch.
- Prior cross-partner overlap was only 553 unique pairs (out of 538 K total).

**Fix — three new/modified scripts in `Utilities/Queries/`:**

`generate_canonical_lookup.rb` *(new)*:
- Queries the MONDO hierarchy graph (`urn:mondo:hierarchy`) using
  `rdfs:subClassOf+` to find all descendants of the 10 target diseases.
- Outputs `canonical_disease.tsv` (two columns: `specific_uri`, `canonical_uri`).
- Diseases not in any target disease's subtree are not written; consuming
  scripts default to identity for those.
- Run once after reloading MONDO, before running `build_ml_set.rb`.

`build_ml_set.rb` *(modified)*:
- Loads `canonical_disease.tsv` at startup.
- Adds two new output columns: `canonical_entity1_uri` and `canonical_entity2_uri`.
- For Disease entities: canonical = lookup result; for all others: canonical = exact URI.
- SPARQL endpoint now reads `ENV['SPARQL_ENDPOINT']` with fallback to
  `http://localhost:8890/sparql` (SSH tunnel default).

`merge_evidence.rb` *(modified)*:
- Groups on `[canonical_entity1_uri, entity1_type, canonical_entity2_uri, entity2_type]`
  instead of exact URIs, so subclass diseases fold into their parent target disease.
- Adds `entity1_uri` and `entity2_uri` output columns listing all specific URIs
  that were folded into each canonical pair (pipe-separated, for traceability).
- Backward-compatible: falls back to exact URIs if the input lacks canonical columns.

**Output columns of `merged_evidence.csv.large` are now:**
```
canonical_entity1_uri  entity1_name  entity1_type
canonical_entity2_uri  entity2_name  entity2_type
rels  sources  evidence
entity1_uri  entity2_uri
```

---

## Changes made — 2026-06-26 (Biovista drug map CID correction)

### Root cause of Trolox/2-Bromopyridine mismatch — systemic PubChem bug

**Trigger:** Partner email thread flagged "2-Bromopyridine" appearing as a drug
for Trolox-related phenotypes. Investigation confirmed the mapping error was in
`biovista/maps/2026-biovista-drugs.map`: entry C010643 (6-hydroxy-2,5,7,8-
tetramethylchroman-2-carboxylic acid / Trolox) was mapped to PubChem CID 2724044
("2-Bromopyridine 1-oxide hydrochloride") instead of CID 40634 (Trolox).

**Root cause:** PubChem's `xref/RegistryID` cross-reference database contains
incorrect entries for many MeSH C-prefix Supplementary Chemical Records (SCRs).
C-prefix entries are "supplementary" MeSH concepts not in the main MeSH hierarchy.
When the pipeline queries `https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/
xref/RegistryID/{C_ID}/cids/JSON`, PubChem returns a CID for a wrong compound for
a significant fraction of C-prefix entries. All affected C-prefix entries also had
no CAS registry number in MeSH (`registryNumber: null`), so the CAS-based fallback
(method 2) was skipped. The name-search fallback (method 3) was never reached
because method 1 returned a (wrong) result.

**Scope:** 21 of 93 C-prefix entries in the drug map had wrong CIDs due to this
bug. A further 18 were flagged as suspicious but were confirmed correct (synonyms
and abbreviations). 2 entries (digoxin Fab fragments, calpain inhibitors) were
proteins/classes that should not be in the drug map.

**Fixes:**

`biovista/maps/2026-biovista-drugs.map` — **corrected in place** (backup at
`2026-biovista-drugs.map.bak`):
- 21 CIDs corrected by re-querying PubChem by name (method 3 of pipeline).
- 2 non-small-molecule entries removed (digoxin Fab fragments, calpain inhibitors).
- 4 duplicate rows collapsed (entries where multiple wrong CIDs now both resolve
  to the same correct CID after name search).
- Net row count: 417 → 408.

Corrected entries include (old CID → new CID):
| MeSH ID | Compound | Old CID | New CID |
|---------|----------|---------|---------|
| C010643 | Trolox | 2724044 | 40634 |
| C031149 | glycolic acid | 18210 | 757 |
| C024989 | coenzyme Q10 | 248961 | 5281915 |
| C003223 | propionylcarnitine | 7376 | 107738 |
| C054207 | etomoxir | 11094883 | 9840324 |
| C020549 | zomepirac | 608487 | 5733 |
| C004742 | daidzein | 67325 | 5281708 |
| C008088 | alfacalcidol | 97794 | 5282181 |
| C031385 | anthranilic acid | 46942323 | 227 |
| C059659 | technetium Tc 99m bicisate | 12807830 | 155491161 |
| C016030 | pantogab | 10888467 | 2527 |
| C009265 | carbidopa-levodopa | 268563 | 104778 |
| C033668 | calpastatin | 88324 | 90488788 |
| C045651 | epigallocatechin gallate | 2737204 | 65064 |
| C038131 | epalrestat | 465065 | 1549120 |
| C030614 | picolinic acid | 21026 | 1018 |
| C033110 | RV 538 | 4715030 | 114736 |
| C031349 | 7-OH-DPAT | 53234195 | 1219 |
| C032727 | piperidine | 21073920 | 8082 |

`biovista/biovista-drug-2026.ipynb` — **cell 11 patched**:
- The `xref/RegistryID` lookup (method 1) is now skipped for C-prefix MeSH entries.
  The pipeline falls directly to CAS lookup (method 2) then name search (method 3).
- This prevents the PubChem cross-reference bug from silently producing wrong CIDs
  in future map regenerations.

**Impact on existing graph data:** The Biovista drug graphing notebooks will need
to be re-run after the database is reloaded (see step 1 of the ML dataset
regeneration workflow). The corrected map is already in place.

---

### Biovista — "Compound" type entities silently dropped

**Trigger:** Partner email flagged missing drugs: Doconexent, Trehalose, Lactose,
Vatiquinone. Investigation showed all four are present in the raw Biovista KG
(`bv-kg-20260617.large`) but absent from the drug map and all graph outputs.

**Root cause:** Biovista's raw KG uses `type == "Compound"` for 5 entries
(Trehalose D014199, Lactose D007785, Docosahexaenoic Acids D004281,
alpha-tocotrienol quinone / Vatiquinone C571746, diosmetin C039602) instead of
`type == "Drug"`. The mapping notebook (cell 7) and all three drug graphing
notebooks filtered exclusively on `type == "Drug"`, so these entries were
silently skipped — no entries in the errors file because the filter runs before
any error-logging code.

The 5 entries account for 1,958 rows in the raw KG (1,257 Compound→Gene,
689 Compound→Phenotype, 12 Disease→Compound).

**Fix — 4 notebooks patched:**

`biovista/biovista-drug-2026.ipynb` — cell 7: changed `row["type_X"] == "Drug"`
to `["Drug", "Compound"].include?(row["type_X"])` so these entries now enter
`meshdrugs` and are processed through the MeSH→CID lookup.

`biovista/BV Drug-Disease Graphing.ipynb` — same filter fix in the main loop.

`biovista/BV Drug-Gene Graphing.ipynb` — same filter fix in the main loop.

`biovista/2026 BV Drug-Phenotype Graphing.ipynb` — same filter fix in the main loop.

**Next step:** Re-run `biovista-drug-2026.ipynb` to regenerate the drug map
(the 5 Compound entries will now be looked up and added). Then re-run the three
drug graphing notebooks to produce graph files that include these drugs.

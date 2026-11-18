# SKG_Mapping — TODO

Items from partner feedback following a project meeting (added 2026-11-18).
Priority order is still to be set by Mark; numbering below is only for reference.

---

## 1. GENE NODE NAMES — use gene symbol, not protein name

Many gene nodes carry the protein name as their label instead of the gene symbol:

- "1-phosphatidylinositol 4,5-bisphosphate phosphodiesterase epsilon-1" → should be `PLCE1`
- "4-aminobutyrate aminotransferase, mitochondrial" → should be `ABAT`

**Note:** this is current policy, not a bug. The June 2026 label audit (`CHANGES.md` §Label policy)
deliberately set gene labels to the UniProt recommended protein full name so that all three partners
would agree. Changing it reverses that decision across all three partners' gene maps and graphing
notebooks.

**Open question:** should the symbol *replace* the protein name as `rdfs:label`, or be added
alongside it (e.g. symbol as `rdfs:label`, protein name as `skos:altLabel`)?

**Findings 2026-11-18:**

- Dumps and partner graphs in Virtuoso are *consistent* (all protein names, all three partners).
  The "mixture" partners saw is most likely from the stale `<http://temp/dummy-graph>` (≈6.8M triples:
  old MONDO + reasoner output + 1,492 gene nodes with pre-June labels — Ensembl IDs, symbols, NCBI
  descriptions). It survived the June purge (URI lacks "simpathic"). Proposed: delete it (awaiting OK).
- No recorded rationale for choosing protein names. Probable cause: all three gene maps come from a
  UniProt SPARQL query with no symbol column, plus 136 of Biovista's 575 genes are non-human (39 taxa)
  and have no HGNC symbol. But NCBI official symbols exist for all species, so that does not justify it.
- Protein names *hide* the species: 48 non-human genes share an identical label with a human gene node
  (e.g. rat 81632 and human 18 are both "4-aminobutyrate aminotransferase, mitochondrial").

**Open question (for partners):** what to do with non-human genes — map to human orthologs (folds
evidence together), keep with species made visible, or drop?

**Status 2026-11-18:** on hold, waiting for the partners to choose between keeping protein names or
dropping non-human genes and going back to HGNC symbols. Non-human genes stay for now; all gene nodes
carry `simp:in-taxon` (verified live: 136 non-human, all Biovista).

## 1b. CLEAN UP THE TWO "DUMMY" GRAPHS IN VIRTUOSO (found 2026-11-18)

- `<http://temp/dummy-graph>` (6.77M triples): a one-off load of an old GraphDB export, inferred
  statements included (`ontotext.com/_allTypes` etc.). It holds an old MONDO base with reasoner output,
  self-`owl:sameAs`/`rdfs:Resource` types on old unprefixed context URIs, and pre-June gene, protein and
  drug labels. Nothing current reads it; it is the source of the mixed gene labels. → delete all
  (probably needs `dba` `CLEAR GRAPH`, given the June hash-limit experience).
- `<urn:dummy>` (23,500 triples): where the bulk loader puts triples that have no graph name. This one
  contains **live data** that `build_ml_set.rb` reads (its metadata patterns are not limited to one graph):
  - 9,346 old unprefixed contexts (11,750 triples) whose data graphs no longer exist → delete.
  - 9,346 current `dem_` contexts: 7,842 triples duplicated in `all_metadata` → delete; 3,908 present
    *only* here (1,708 `source-relation`, 2,200 PubMed `evidence`) → move to `all_metadata`.
  - Root cause: `evidence` / `source-relation` statements without `graph_name:` in Demokritos
    Disease-Gene, Drug-Disease, Drug-Gene. (Radboud's similar lines are commented out — fine.)
  - **Status 2026-11-18:** notebooks ✅ patched; `.nq.large` files ✅ patched (backups in
    `demokritos/graph/deprecated/`); Virtuoso ✅ `<urn:dummy>` emptied, metadata moved (verified).
    `<http://temp/dummy-graph>` ✅ cleared by Mark 2026-11-18 and verified. See `CHANGES.md` 2026-11-18.

## 5. LICENSING OF THE REPUBLISHED MERGED DATA (do LAST, after the other items)

Mark's request (2026-11-18): check UniProt's usage licence and advise whether it limits the licence
we can use to republish the merged SKG data (Virtuoso endpoint, ML dumps).

Scope to check when we get to it. Each is a source of labels or identifiers in the merged data;
verify the current terms rather than relying on memory:

- **UniProt: check CAREFULLY.** Gene and protein labels (recommended full names) and URIs.
  Mark: UniProt has a history of licence "rug-pulls". Check the current terms, any change
  history, and whether the terms in force when we fetched the data (June 2026) are what bind us.
- **MONDO**: disease labels and the `urn:mondo:hierarchy` graph.
- **HPO**: phenotype labels. HPO has its own licence terms, separate from the usual OBO
  CC licences (see the HPO note below).
- **PubChem / NCBI**: drug titles and CIDs. NCBI Gene: gene IDs (and gene symbols, if item 1
  goes that way).
- **UMLS / MeSH: the tricky one.** Mark recalls we took this data from OBO sources rather than
  the UMLS API; if OBO mis-licenses it, that's on OBO, not us. To confirm against the code at
  audit time, since `CHANGES.md` records two possible exceptions:
  (a) `demokritos/2026 Drug Mapping.ipynb` calls the **BioPortal REST API** (`APIKEY`) for
  CUI → prefLabel → CID, and falls back to the BioPortal `prefLabel` as the drug label when
  PubChem returns nothing, so a few republished labels may be UMLS-derived;
  (b) `biovista/biovista-drug-2026.ipynb` reads MeSH directly from `id.nlm.nih.gov/mesh`.
  Check: how many republished labels come from (a), and NLM's terms for MeSH RDF in (b).
- **HPO: tricky licence**, check carefully.
- **The partners' own data**: all three partners have already agreed to a very permissive licence
  (Mark, 2026-11-18). That doesn't lift the constraints imposed by the sources above.

Output: a short recommendation of a compatible licence for the merged data, plus the attribution
statement it would need.

## 2. DISEASE/PHENOTYPE NODES — same concept as two nodes

Some concepts appear both as a disease (MONDO) and as a phenotype (HPO) node, e.g. glaucoma:
`MONDO_0005041` and `HP_0000501`.

**To investigate:** which partner(s)/notebooks produce the duplicates (likely Demokritos, where one
UMLS CUI can be mapped to both MONDO and HPO), and how many there are.

**Open question:** merge into one node (which namespace wins?) or keep both and link them
(e.g. `skos:exactMatch`, via MONDO↔HP xrefs / Monarch SSSOM)?

## 3. SYNONYM REL TYPES — strip `__INFER__` / `__SPEC__` suffixes

Demokritos relation types carry suffixes that should be merged into the base relation, e.g.
`ASSOCIATED_WITH__INFER__` → `ASSOCIATED_WITH`, `CAUSES__SPEC__` → `CAUSES`.
Partner suggestion: any relation containing `__INFER__` or `__SPEC__` is renamed to the base name.

Verified 2026-11-18: the suffixes come from the raw data (`demokritos/raw-data/*.tsv`, 20 distinct
suffixed types, e.g. 187× `ASSOCIATED_WITH__INFER__`, 178× `COEXISTS_WITH__SPEC__`). The graphing
notebooks copy `row['RELATION']` through unchanged, so they are in the on-disk `demokritos/graph/*.nq.large`
files and in live Virtuoso.

Fix will touch the same three layers as the 2026-09-14 ASSOCIATED_WITH fix:

1. Demokritos graphing notebooks (strip the suffix when reading `RELATION`).
2. Live Virtuoso (`simp:source-relation` values in `urn:simpathic:context:all_metadata`).
3. The `.large` ML dump CSVs (`rels` column), then regenerate the merged file.

**Status 2026-11-18:** decided to discard the suffix. Also `ISA` → `IS_A` and lowercase → UPPERCASE
(Mark). `.nq.large` ✅, notebooks ✅, NOV dumps ✅, Virtuoso ✅ (run by Mark in Conductor,
verified: `source-relation` 314,462 → 314,357, 0 messy). **Done.** See `CHANGES.md`.

## 3b. Follow-ups found while doing item 3 (2026-11-18)

- `.nq.large` files lack the `ASSOCIATED_WITH` base relation on 5,442 graphs (Radboud 3,562,
  Demokritos 1,880). Virtuoso and the dumps are fine. **Decided 2026-11-18 (Mark): do NOT patch.**
  Data the partners have already used (the September state) is kept unchanged as a provenance
  record, even where it's wrong. If these files are ever reloaded, re-apply
  `Add_Missing_ASSOCIATED_WITH_Base_Relation.sparql` afterwards.
- ✅ Done 2026-11-18: the September `.nq.large` originals are restored under their own names;
  the corrected copies are in `demokritos/graph/NOV-20261118/` (see `CHANGES.md` "Provenance").
- ✅ Stray `|` in `rels` (866 SEPT rows): caused by an awk regex bug in the Sept patch. Fixed in the
  NOV dumps and verified row by row against JUNE; SEPT kept as-is; awk script fixed. See `CHANGES.md`.

## 4. ADD DRUG-GENE HITS — WP3 drug screening results

Add WP3 drug screening results as `DRUG -TARGET-> GENE` edges for all rows with `hit_class = 1`.
There are three CSVs, one per gene: GCH1, ALDH5A1, SURF1.

**Blocked:** the link to the three CSVs was not included in the forwarded message; need the files.

**To decide:** new `skg-source` value and context-URI prefix (e.g. `wp3_`); how drugs are identified
in the CSVs (will need mapping to PubChem CID like the other partners); whether to also emit the
`ASSOCIATED_WITH` base relation (required on every edge per project policy).

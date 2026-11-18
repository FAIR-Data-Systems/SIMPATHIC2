# SKG licensing assessment (TODO item 5)

**Question (Mark, 2026-11-18):** do the licences of the sources we used limit the licence under
which we can republish the merged SKG (the public Virtuoso endpoint and the ML dumps)? The
partners have already agreed to a very permissive licence for their own contributions, but that
can't lift constraints imposed by upstream sources.

Assessment by Claude, 2026-11-18. Not legal advice; the open questions at the end need a
partner's or NLM's answer, not just reading.

## Short answer

- **We can't release the merged SKG as CC0.** MONDO and UniProt require attribution (CC BY 4.0),
  and HPO has its own custom conditions. We can't waive those for content we republish.
- **Recommended: CC BY 4.0 for the merged SKG**, with a NOTICE file that gives each source's
  attribution and states that HPO-derived content stays under the HPO licence. That's compatible
  with everything below, provided we do three things first:
  1. replace the 176 ChEMBL-sourced substance labels (share-alike);
  2. record the HPO version and add the HPO statement and logo;
  3. resolve the UMLS/SemMedDB question for Demokritos (see the open questions).
- **UniProt "rug-pull" risk: low for the data we already hold.** CC BY 4.0 grants are
  irrevocable (licence §2(a)(1)), so data obtained under CC BY 4.0 stays usable on those terms
  even if UniProt changes its licence later. Keep a dated copy of the licence as evidence (below).
- **UMLS is the real risk, and it isn't labels.** Every republished label comes from MONDO, HPO,
  PubChem or UniProt (checked below). What remains is (a) 4,689 UMLS CUIs republished as
  `simp:original-id` literals and (b) Demokritos relations that appear to be SemMedDB-derived.

## What we republish, and where each part came from (checked 2026-11-18)

| Content | Source | Check |
|---|---|---|
| Disease URIs + labels | MONDO | 5,489 of 5,503 labels are MONDO's own label; the other 14 are older MONDO wording |
| Phenotype URIs + labels | HPO | 1,203 of 1,206 labels verbatim in HPO release 2026-09-01; 3 are older HPO labels that HPO has since renamed. Not altered by us |
| Drug URIs + labels (CID) | PubChem | all except 3 equal PubChem's Title (3 are synonyms or brand names: "Vitamin E", "Prilosec", one IUPAC name) |
| Drug labels, 176 Radboud substances with no CID | **ChEMBL API** (`radboud/map-drugs.ipynb`, `map_chembl_to_name`) | e.g. "Fragmin", "Refludan" |
| Gene/protein URIs + labels | UniProt (recommended names); NCBI Gene IDs | — |
| Taxon URIs | UniProt taxonomy | — |
| `simp:original-id` literals | partner source IDs: **UMLS CUIs** (Demokritos 4,591, Biovista 98), MeSH (Biovista ~444), Orphanet (3,160), ChEMBL (1,278), Ensembl (723), EFO, MONDO, HP, DOID | — |
| Relations + evidence (PubMed URLs) | Radboud: **Open Targets Platform**; Demokritos: PubMed extraction, UMLS CUIs, relation names in **SemMedDB style** (`__INFER__`/`__SPEC__`); Biovista: own literature mining | partners' own provenance |
| `urn:mondo:hierarchy` graph (full MONDO 2025-12-02 release) | MONDO | republished as-is |

## Source by source

| Source | Licence (where read, date) | What it requires of us |
|---|---|---|
| **UniProt** | CC BY 4.0 "to all copyrightable parts of our databases" (rest.uniprot.org/help/license, last modified 2024-12-18). Previously CC BY-ND 3.0 (Creative Commons case study; UniProt NAR 2019 "recently updated ... to CC-BY (4.0)") | Attribution + citation; patents/third-party-rights disclaimer |
| **HPO** | Custom licence (hpo.jax.org License page, site v2.1.5, text supplied by Mark 2026-11-18; same as the legacy github.io page) | (1) acknowledge + cite the HPO Consortium; (2) publicly displayed HPO content must state the **date/version**; (3) **no alteration** of HPO content or logical relationships; (4) statement "This service/product uses the Human Phenotype Ontology (version information)…" + **HPO logo** |
| **MONDO** | CC BY 4.0 (OBO Foundry; mondo.monarchinitiative.org) | Attribution. MONDO's own xrefs to restricted sources (UMLS, SNOMED CT, MedDRA, OMIM) are MONDO's responsibility under its licence; we republish MONDO as released |
| **PubChem / NCBI Gene** | NCBI places "no restrictions on the use or distribution" of molecular data, but some depositor data may carry third-party rights (ncbi.nlm.nih.gov/home/about/policies) | NCBI's disclaimer and copyright notice must be evident to users. Rate limits when fetching |
| **Open Targets Platform** (Radboud) | CC0 1.0 (platform-docs.opentargets.org/licence) | None (attribution good practice). OT notes its upstream sources agreed to unrestricted use *by OT users* |
| **ChEMBL** | CC BY-SA 3.0 (chembl.gitbook.io) | **Share-alike**: adaptations must be BY-SA. Affects the 176 substance labels we took directly from ChEMBL. ChEMBL IDs alone are identifiers |
| **MeSH** (Biovista drug mapping, MeSH IDs) | NLM terms: free; acknowledge NLM; don't imply endorsement; state the MeSH version or that the data may not be current (nlm.nih.gov … terms_and_conditions_mesh, reviewed 2018-10-04) | Attribution + version statement |
| **Orphanet** (Radboud IDs; mapping) | CC BY 4.0 (orphadata.com) | Attribution; "Orphanet" is a registered trademark |
| **EFO** | Apache 2.0 per the Open Targets licence table (not confirmed from an EFO licence file) | Attribution notice |
| **UMLS** (CUIs; Demokritos/Biovista inputs; BioPortal lookups) | UMLS Metathesaurus License Agreement, 2026AB, dated 11/02/2026 (uts.nlm.nih.gov/uts/assets/LicenseAgreement.pdf) | §3: no distribution of the Metathesaurus "or subsets of it" except as an integral part of an application built for another purpose. §10: acknowledge NLM + version. §11c: applications must *include* UMLS identifiers so sources can be traced. §12: per-source categories, e.g. **MEDCIN = Category 3** (internal use only; nothing publicly accessible); **SNOMED CT = Appendix 2** (affiliate licence; free in member territories). We republish CUIs but no UMLS strings |
| **SemMedDB** | Download requires a UMLS (UTS) account; the page states no redistribution terms; final release semmedVER43_R, no longer maintained after 2024-12-31 (lhncbc.nlm.nih.gov SemMedDB_download) | Unclear; treat as UMLS-licensed until NLM says otherwise |

## Recommended actions

1. **Replace the 176 ChEMBL substance labels** with PubChem Substance names (we already have the
   SIDs) or with the ChEMBL ID as label. That removes the only share-alike content. Like the
   other fixes, this goes into a new version, not the September files.
2. **HPO compliance:** add the HPO citation, the statement with the HPO version, and the logo to
   the endpoint's landing page / dataset metadata. Refresh the 3 outdated HP labels to the stated
   release, so that "version X" is true for every label.
3. **NOTICE / attribution file** with the dumps and on the endpoint: UniProt, MONDO, HPO (as
   above), NCBI disclaimer, Orphanet, EFO, MeSH (NLM + version), Open Targets, and NLM/UMLS
   (year + version) if CUIs stay in.
4. **Archive dated copies of each licence text** (UniProt help page, HPO page, UMLS 2026AB PDF,
   NCBI policy) alongside the data, as provenance for the terms in force when we obtained it.
   This is the practical defence against a later licence change.
5. **License the merged SKG as CC BY 4.0**, stating that HPO-derived content remains under the
   HPO licence. CC 4.0 licences also cover EU sui generis database rights, which matters for an
   EU-based publisher.

## Open questions (need answers, not more reading)

1. **Demokritos:** were your triples built from **SemMedDB / SemRep**? The relation vocabulary
   and the `__INFER__`/`__SPEC__` suffixes suggest so. If yes, under what terms did you obtain it,
   and did you check redistribution? This decides whether ~10k Demokritos edges can go under CC BY.
2. **CUIs in `simp:original-id`** (4,689): keep them public, or remove them from the public release
   (keeping them internally)? Removing them is the low-risk option; §11c arguably supports keeping
   them, since CUIs are identifiers and not vocabulary content, but that's an interpretation.
   NLM could be asked.
3. **Biovista:** its raw data tags UMLS concepts with source vocabularies including `SNOMEDCT_US`
   and `MEDCIN`. We republish only 98 Biovista CUIs and no strings, so exposure is small. Confirm
   with Biovista that its own outputs are cleared for redistribution under the agreed licence.

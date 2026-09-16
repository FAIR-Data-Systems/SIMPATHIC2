# SKG Mapping — Evaluation & Assessment Statistics

This folder collects, with full provenance, every number and claim used in the
paper's "Evaluation and Assessment" and "Results" sections. Each subfolder
corresponds to one reviewnote subsection and contains:

- a `README.md` stating **exactly** what data source was used (a log file, a
  live SPARQL query, or a specific input file) and why, so every number is
  reproducible and auditable during peer review;
- the script(s)/query(ies) that produced each number;
- the raw output, where practical to store.

## Canonical data sources (agreed 2026-09-14)

- **Results / KG statistics**: `Utilities/Queries/SEPT_all_pairs_both_orientations_merged_evidence.csv.large`
  is the canonical dataset for this paper (not the live Virtuoso endpoint,
  which has not changed since this dump but is not re-queried for these
  numbers). The `SEPT_` prefix marks the corrected file (the
  `IS_ASSOCIATED_WITH`/`ASSOCIATED_WITH` fix — see `05_results/README.md`
  — applied 2026-09-14); the original `JUNE_all_pairs_both_orientations_*`
  files are kept as unmodified archival copies and are **not** the current
  canonical source. Neither file is committed to git (too large) — both
  exist in only one place, are read-only for all scripts in this folder,
  and nothing here ever moves, renames, or overwrites them.
- **Error/consistency handling**: the Jupyter notebook error logs
  (`*/maps/*-errors*`) are the sole and comprehensive error trail — confirmed
  by the project owner as complete.
- **Disease overlap gold standard**: the 10 target diseases, with
  `Utilities/Queries/canonical_disease.tsv` (generated from the MONDO
  `rdfs:subClassOf+` hierarchy in Virtuoso) providing the exact-match vs.
  subclass-match distinction. Overlap measures for other entity types (drug,
  gene, phenotype) have no such canonicalization and are reported as
  exact-URI-match only, with that limitation stated explicitly.

## Subsections

1. [01_implementation_details](01_implementation_details/README.md) — software stack, versions, infrastructure, pipeline execution
2. [02_evaluation_methodology](02_evaluation_methodology/README.md) — objectives and quantitative metrics
3. [03_validation_strategy](03_validation_strategy/README.md) — validation, error/conflict handling
4. [04_bias_and_robustness](04_bias_and_robustness/README.md) — bias sources and limitations
5. [05_results](05_results/README.md) — final KG statistics, topology, use-case queries

## Ground rule

No number goes into the paper without a README entry here naming its exact
source and the command used to generate it. When in doubt about which source
is authoritative, we ask before computing — see git/conversation history for
the decisions above.

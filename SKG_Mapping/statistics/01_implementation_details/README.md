# 1. Implementation Details

## Data sources for this section

- Repository introspection (installed gem list, `ruby -v`, notebook
  `kernelspec` metadata) — run 2026-09-14, commands below.
- Hardware specs supplied directly by the project owner (not derivable from
  the repo): analytical-run workstation and Virtuoso server.
- `SKG_Mapping/CHANGES.md` for pipeline-execution/operational history
  (e.g. SPARQL write-permission workaround, endpoint configuration).

## Software stack

| Component | Version | Source |
|---|---|---|
| Ruby | 3.2.4 (x86_64-linux) | `ruby -v` |
| Notebook kernel | `ruby3` — "Ruby 3 (iruby kernel)" | notebook `metadata.kernelspec`, e.g. `demokritos/2026 Disease-Gene Graphing.ipynb` |
| linkeddata gem | 3.3.3 | `gem list linkeddata` |
| rdf.rb gem | 3.3.4 | `gem list rdf` |
| rest-client gem | 2.1.0 | `gem list rest-client` |
| json gem | 2.21.2 | `gem list json` |
| require_all gem | 3.0.0 | `gem list require_all` |
| Triplestore | Virtuoso Open-Source `07.20.3242` (Linux, x86_64-ubuntu_noble) | `Server:` HTTP response header from the live SPARQL endpoint, `curl -I http://57.128.119.57:8890/sparql`, 2026-09-14 |

## Computational infrastructure

**Development / analytical-run workstation** (where mapping notebooks and
ML-set build scripts were executed): HP Spectre 15, Intel i7, running Linux
Mint in a VM. *(Provided directly by the project owner.)*

**Virtuoso triplestore server**:
- CPU: Intel Xeon-E 2386G, 6 cores / 12 threads, 3.5 GHz base / 4.7 GHz boost
- RAM: 32 GB ECC, 3200 MHz
- Storage: 2× 960 GB NVMe SSD, soft RAID

*(Provided directly by the project owner.)*

## Pipeline operationalization

- Each partner's data is loaded into Virtuoso as a separate named graph per
  entity-relation pair (e.g. `Disease-Gene`, `Drug-Phenotype`), produced by
  the corresponding partner-specific Jupyter notebook
  (`{biovista,demokritos,radboud}/2026 ... Graphing.ipynb`).
- The SPARQL endpoint is accessed over an SSH tunnel to
  `http://localhost:8890/sparql` by default (`ENV['SPARQL_ENDPOINT']`
  override supported) — see `CHANGES.md`, "ML dataset — canonical disease URI
  mapping added" entry.
- Graph deletion/reload utilities (`Utilities/Patches/delete_using_http.rb`,
  `purge_all_graphs.rb`) use `DELETE {...} WHERE {...}` rather than
  `DROP`/`CLEAR GRAPH`, because the SPARQL service account has write-triple
  privilege but not DROP privilege — see `CHANGES.md`, "Deletion utility
  scripts — fixed".
- The unified ML-ready dataset is produced by
  `Utilities/Queries/build_ml_set.rb` (queries Virtuoso, canonicalizes
  disease URIs via `canonical_disease.tsv`) followed by
  `Utilities/Queries/merge_evidence.rb` (groups/deduplicates evidence into
  the merged-evidence output). Original outputs:
  `JUNE_all_pairs_both_orientations_{split,merged}_evidence.csv.large`
  (kept as unmodified archival copies); the corrected files this paper
  actually cites are `SEPT_all_pairs_both_orientations_{split,merged}_evidence.csv.large`
  — see `05_results/README.md` for the fix applied.

## Reproduction commands

```bash
ruby -v
gem list linkeddata rdf rest-client json require_all
curl -sI http://57.128.119.57:8890/sparql   # Server: header gives Virtuoso version
python3 -c "import json; print(json.load(open('demokritos/2026 Disease-Gene Graphing.ipynb'))['metadata']['kernelspec'])"
```

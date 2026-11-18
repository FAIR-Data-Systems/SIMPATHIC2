# HP-as-disease → MONDO: candidate synonym patch (TODO item 2)

Claude's **best-guess** candidates, in the partners' synonym patch-file format
(`canonical_url, synonym_url, type, names, note`), for expert review. **Nothing here has
been applied to the data.** The partners' combined patch file will be applied in one go
once it's finished.

## The problem

Radboud's Disease column mixes six identifier namespaces: Orphanet (4,412), EFO (2,829),
MONDO (1,181), HP (909), plus NCIT/OTAR/DOID/OBI strays. What the Radboud code did with each
(audited 2026-11-18):

| Namespace | How it was mapped (`radboud/map_diseases-mondo.ipynb`) | Raw rows (Disease-Gene + Drug-Disease) | → MONDO | Dropped |
|---|---|---|---|---|
| Orphanet | BioPortal ORDO → its MONDO mappings; fallback: Monarch mappings API | 35,127 | 33,819 | 1,308 |
| EFO | BioPortal EFO preferred label → **exact-label** search in MONDO only | 28,188 | **1,198** | **26,990** (incl. 697 of 701 Drug-Disease rows) |
| DOID | BioPortal DOID → MONDO mapping | 164 | 164 | 0 |
| NCIT / OTAR / OBI | rejected up front (`map_id_to_disease` accepts only EFO, DOID, MONDO, Orphanet) | 1 / 82 / 333 | 0 | 416 |
| MONDO | kept | 5,821 | 5,821 | 0 |
| **HP** | not in the disease map, so dropped by the disease notebooks, **but** picked up by the Radboud Phenotype-Gene and Drug-Phenotype notebooks (`next unless ...match(/HP_/)`) and turned into **HP Phenotype nodes** | 4,397 | — | 0 |

No namespace other than HP was kept in its original form: each was either converted to MONDO or
dropped. The EFO loss is a separate issue (see TODO item 2, follow-ups).

Live store (2026-11-18): every Disease node is MONDO, every Phenotype node is HP, and no URI
is typed as both. So a duplicate is a concept that exists as a MONDO disease node *and*
an HP phenotype node.

## Scope (Mark, 2026-11-18)

Patch **only where an HP term is used as a disease**, i.e. Radboud's Disease column. Biovista
and Demokritos HP terms are genuine phenotypes. HP URIs are shared between partners, so a row
must **not** be applied as a global URI merge: it applies only to Radboud's graphs
(`urn:simpathic:context:rad_*`). Applying a row means the HP node in those Radboud
Phenotype-Gene / Drug-Phenotype graphs becomes the MONDO disease node.

## Files

- `HP_to_MONDO_candidates_2026-11-18.tsv`: **the patch candidates**. 38 rows, one per Radboud
  HP-as-disease term with a MONDO disease **already in the SKG** (28 HIGH, 10 MEDIUM). Only 38 of
  Radboud's 382 HP-as-disease nodes have such a match.
- `HP_to_MONDO_candidates_2026-11-18_NOT-FOR-PATCH_other-partners.tsv`: 89 information-only pairs
  where a Biovista/Demokritos *phenotype* matches a MONDO disease (incl. the partner's glaucoma
  example HP_0000501 ⇄ MONDO_0005041). **Information only, permanently:** the project PI decided
  (reported by Mark, 2026-11-18) that the graph will never link or merge a concept "as disease" with
  the same concept "as phenotype/symptom". Never apply these rows.
- `build_hp_mondo_patch.rb`: generator (tiers, hand-review flags, accepted tier-C pairs, scope split).
- `inputs/`: the Virtuoso exports it reads (queries below).

## Method (both nodes must already exist in the SKG)

- **Tier A:** MONDO itself cross-references the HP term (`oboInOwl:hasDbXref HP:…`, almost all
  annotated `MONDO:otherHierarchy` = the phenotype-side counterpart of the disease).
- **Tier B:** the HP label exactly matches the MONDO label or a MONDO exact synonym (case/punctuation-normalised).
- **Tier C:** word-overlap near-matches judged by hand. Most were rejected (subtypes such as
  "Dystonia" → "dystonia 5"; findings vs diseases such as "Glutaric aciduria" → GA1; unrelated
  word overlap). The accepted ones are listed with reasons in the script.
- A/B matches that are broader or narrower than they look are downgraded, with a CAUTION in the note.

## Regenerating `inputs/` (anonymous `/sparql` endpoint, TSV output)

```sparql
# hp_nodes.tsv / mondo_nodes.tsv  (swap Phenotype for Disease)
SELECT DISTINCT ?e ?label ?src WHERE {
  GRAPH ?c { ?e a <https://w3id.org/biolink/vocab/Phenotype> ; rdfs:label ?label }
  GRAPH <urn:simpathic:context:all_metadata> { ?c <urn:simpathic:skg-source> ?src } }

# mondo_names.tsv  (labels + exact synonyms from the full MONDO release)
SELECT ?m ?s WHERE { GRAPH <urn:mondo:hierarchy> {
  { ?m rdfs:label ?s } UNION { ?m oboInOwl:hasExactSynonym ?s } }
  FILTER(STRSTARTS(STR(?m), "http://purl.obolibrary.org/obo/MONDO_")) }

# mondo_hp_xrefs.tsv  (MONDO -> HP xrefs with their axiom source annotations)
SELECT ?m ?x (GROUP_CONCAT(DISTINCT STR(?src); separator="|") AS ?srcs) WHERE {
  GRAPH <urn:mondo:hierarchy> { ?m oboInOwl:hasDbXref ?x . FILTER(STRSTARTS(STR(?x), "HP:"))
    OPTIONAL { ?ax owl:annotatedSource ?m ; owl:annotatedProperty oboInOwl:hasDbXref ;
                   owl:annotatedTarget ?x ; oboInOwl:source ?src } } } GROUP BY ?m ?x
```

Then: `ruby build_hp_mondo_patch.rb inputs HP_to_MONDO_candidates_<date>.tsv`

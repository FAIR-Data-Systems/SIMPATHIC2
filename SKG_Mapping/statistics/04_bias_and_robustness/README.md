# 4. Bias and Robustness Analysis

## Approach

Per the project owner: this is primarily a discursive section, not a
computed-metric section. The dataset is *intentionally* biased — bias is
inherited from the source SKGs (Biovista, Radboud, Demokritos), not
introduced by the integration process itself, and that is stated plainly
here rather than treated as a flaw to quantify. No statistics are invented
for this section; every claim below is backed by a concrete finding from
[`03_validation_strategy`](../03_validation_strategy/README.md) or
[`CHANGES.md`](../../CHANGES.md).

## Documented source-specific characteristics affecting mapping/integration

**Demokritos's phenotype source data includes non-ontological extracted
phrases.** Investigation of Demokritos's 79.6% phenotype-mapping failure
rate (see `03_validation_strategy`) found that most failures are not
mapping-code shortcomings — the source `raw-data/*Phenotype*.tsv` files
contain NLP/text-mining-extracted mentions such as "Rescue", "Emotional",
"Worse", "Early-onset", which are not phenotype-ontology concepts and could
never resolve to an HPO id. This reflects Demokritos's construction method
(literature text-mining) as distinct from Radboud/Biovista's curated-source
approach, and biases Demokritos's contribution toward noisier,
lower-precision phenotype coverage.

**Demokritos's drug source vocabulary includes class-level terms that
PubChem's exact-compound lookup cannot resolve.** 77% of Demokritos drug-
mapping failures are attempts to resolve category labels (e.g. "Adrenal
Cortex Hormones", "Acetylcholinesterase inhibitor", "X-containing product")
to a single PubChem CID — a scheme mismatch between the source vocabulary
(BioPortal MeSH/SNOMED, which includes class terms) and the target
identifier space (PubChem CID, specific compounds only). This is a
structural source/target vocabulary mismatch, not a fixable bug, and it
biases Demokritos's drug coverage toward missing entire therapeutic classes
that other partners may represent via specific member compounds instead.

**Disease-granularity mismatch across partners (already identified and
partially corrected).** Per `CHANGES.md` ("ML dataset — canonical disease
URI mapping added"), partners operate at different levels of MONDO
granularity: Radboud uses disease subtypes (e.g. "MJD type 1") while
Biovista uses the parent disease (e.g. "Machado-Joseph disease"). This was
mitigated for disease entities via `canonical_disease.tsv` (see
[`02_evaluation_methodology`](../02_evaluation_methodology/README.md)), but
no equivalent canonicalization exists for drug, gene, or phenotype entities
— so an analogous granularity bias may exist there too, unmeasured.

**Cross-partner label inconsistency (pending decision).** `CHANGES.md`
documents `SUBSTANCE_135346864` resolving to three different `rdfs:label`
values from three partners (Radboud: "Clexane"/"Clivarine" — specific brand
names; Biovista: "Heparin" — the generic drug class) for what is, in the
KG, a single merged node. This is a concrete example of how partners'
differing labeling conventions (specific brand vs. generic class) can
collide once entities are merged by identifier — still unresolved as of the
latest `CHANGES.md` entry.

## Partner size/coverage imbalance

From [`05_results`](../05_results/README.md): rows contributed by source
(merged-evidence file, trimmed labels) are heavily skewed toward Biovista
(822,758 rows, 79%) versus Radboud (192,210, 18%) and Demokritos (29,549,
3%). This reflects each partner's underlying source SKG size, not an
artifact of the integration process — stated here as a scale fact, not
attributed to any particular cause without further investigation.

## Limitations for downstream analyses

- Any ML/analytics use of this KG should account for Demokritos's
  phenotype/drug contributions being systematically filtered toward
  ontology-mappable concepts — the ~79.6%/58.8% of source mentions that
  didn't map are simply absent, not represented with lower confidence or
  flagged as excluded within the graph itself.
- The row-count imbalance across partners means naive aggregate statistics
  (e.g. "the KG shows X% of Disease-Drug associations have evidence Y") will
  be dominated by Biovista's contribution unless explicitly stratified by
  source.
- No general-purpose scheme exists yet to distinguish "confirmed absent"
  from "not yet attempted" for entities outside all three partners' initial
  target/input lists.

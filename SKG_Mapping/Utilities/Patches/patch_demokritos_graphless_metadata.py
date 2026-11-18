#!/usr/bin/env python3
"""
Add `graph_name: general_context` to the three simp:evidence / simp:source-relation
statements that were written WITHOUT a graph in three Demokritos graphing notebooks.

Why (found 2026-11-18): without a graph name these triples are written to the
.nq.large files as plain triples, so Virtuoso's bulk loader drops them into its
default graph <urn:dummy> instead of <urn:simpathic:context:all_metadata>.
build_ml_set.rb happens to still see them (its metadata patterns are not
graph-scoped), but they are in the wrong place. The live data and the on-disk
.nq.large files are fixed separately (see Fix_URN_Dummy_Graph.* and
patch_demokritos_graphless_nquads.rb); this patch only makes sure a future
re-run of the notebooks produces correct output.

Raw-text replacement on the .ipynb file (strings are matched in their JSON-escaped
form), so nothing else in the notebook changes. Each replacement must match
exactly once per notebook, or the notebook is left untouched.

Usage:  python3 patch_demokritos_graphless_metadata.py [notebook_dir]
        (default notebook_dir: ../../demokritos)
"""
import json
import sys
from pathlib import Path

NOTEBOOKS = [
    "2026 Disease-Gene Graphing.ipynb",
    "2026 Drug-Disease Graphing.ipynb",
    "2026 Drug-Gene Graphing.ipynb",
]

# (old, new) in JSON-escaped form, exactly as they appear in the .ipynb text
REPLACEMENTS = [
    ('RDF::URI.new(evidence_url)) if evidence_url',
     'RDF::URI.new(evidence_url), graph_name: general_context) if evidence_url'),
    ('RDF::Literal.new(source_relation))\\n',
     'RDF::Literal.new(source_relation), graph_name: general_context)\\n'),
    ('RDF::Literal.new(\\"ASSOCIATED_WITH\\")) unless source_relation',
     'RDF::Literal.new(\\"ASSOCIATED_WITH\\"), graph_name: general_context) unless source_relation'),
]


def main():
    nb_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent / "../../demokritos"
    failed = False
    for name in NOTEBOOKS:
        path = nb_dir / name
        text = path.read_text(encoding="utf-8")
        new = text
        problems = []
        for old, rep in REPLACEMENTS:
            n = new.count(old)
            if n != 1:
                problems.append(f"expected 1 match, found {n}: {old!r}")
            else:
                new = new.replace(old, rep)
        if problems:
            failed = True
            print(f"SKIPPED {name}:")
            for p in problems:
                print(f"    {p}")
            continue
        json.loads(new)  # must still be valid JSON
        path.write_text(new, encoding="utf-8")
        print(f"patched {name}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

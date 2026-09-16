import json
import re

targets = [
    "/home/osboxes/CODE/SIMPATHIC2/SKG_Mapping/demokritos/2026 Disease-Gene Graphing.ipynb",
    "/home/osboxes/CODE/SIMPATHIC2/SKG_Mapping/demokritos/2026 Disease-Phenotype Graphing.ipynb",
    "/home/osboxes/CODE/SIMPATHIC2/SKG_Mapping/demokritos/2026 Drug-Disease Graphing.ipynb",
    "/home/osboxes/CODE/SIMPATHIC2/SKG_Mapping/demokritos/2026 Drug-Gene Graphing.ipynb",
    "/home/osboxes/CODE/SIMPATHIC2/SKG_Mapping/demokritos/2026 Drug-Phenotype Graphing.ipynb",
    "/home/osboxes/CODE/SIMPATHIC2/SKG_Mapping/demokritos/2026 Gene-Phenotype Graphing.ipynb",
    "/home/osboxes/CODE/SIMPATHIC2/SKG_Mapping/demokritos/2026 Phenotype-Disease Graphing.ipynb",
    "/home/osboxes/CODE/SIMPATHIC2/SKG_Mapping/demokritos/2026 Phenotype-Drug Graphing.ipynb",
    "/home/osboxes/CODE/SIMPATHIC2/SKG_Mapping/demokritos/2026 Phenotype-Gene Graphing.ipynb",
]

# Pattern A: single-line "graph << RDF::Statement.new(context_uri, SIMPATHIC['source-relation'], RDF::Literal.new(relation), ... graph_name: general_context)"
single_line_re = re.compile(
    r"^(\s*)graph << RDF::Statement\.new\(context_uri, SIMPATHIC\['source-relation'\], "
    r"RDF::Literal\.new\((\w+)\),(\s*)graph_name: general_context\)\s*$"
)

# Pattern B: two-line "graph << RDF::Statement.new(context_uri, SIMPATHIC['source-relation'],\n" + "RDF::Literal.new(source_relation))\n" (no graph_name)
two_line_first_re = re.compile(
    r"^(\s*)graph << RDF::Statement\.new\(context_uri, SIMPATHIC\['source-relation'\],\s*$"
)
two_line_second_re = re.compile(
    r"^(\s*)RDF::Literal\.new\((\w+)\)\)\s*$"
)

for path in targets:
    with open(path, encoding='utf-8') as f:
        nb = json.load(f)

    changed = False
    for cell in nb.get('cells', []):
        src = cell.get('source', [])
        if not isinstance(src, list):
            continue
        new_src = []
        i = 0
        while i < len(src):
            line = src[i]
            new_src.append(line)

            m = single_line_re.match(line)
            if m:
                indent, var, gap = m.group(1), m.group(2), m.group(3)
                companion = (
                    f"{indent}graph << RDF::Statement.new(context_uri, SIMPATHIC['source-relation'], "
                    f"RDF::Literal.new(\"ASSOCIATED_WITH\"),{gap}graph_name: general_context) "
                    f"unless {var} == \"ASSOCIATED_WITH\"\n"
                )
                new_src.append(companion)
                changed = True
                print(f"{path}: [single-line, var={var}] inserted companion")
                i += 1
                continue

            m1 = two_line_first_re.match(line)
            if m1 and i + 1 < len(src):
                next_line = src[i + 1]
                m2 = two_line_second_re.match(next_line)
                if m2:
                    indent, var = m1.group(1), m2.group(2)
                    new_src.append(next_line)  # keep original second line
                    companion = (
                        f"{indent}graph << RDF::Statement.new(context_uri, SIMPATHIC['source-relation'], "
                        f"RDF::Literal.new(\"ASSOCIATED_WITH\")) unless {var} == \"ASSOCIATED_WITH\"\n"
                    )
                    new_src.append(companion)
                    changed = True
                    print(f"{path}: [two-line, var={var}] inserted companion")
                    i += 2
                    continue
            i += 1
        cell['source'] = new_src

    if changed:
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(nb, f, indent=1, ensure_ascii=True)
            f.write('\n')
        print(f"  -> wrote {path}")
    else:
        print(f"  -> NO CHANGE for {path} (pattern not matched!)")

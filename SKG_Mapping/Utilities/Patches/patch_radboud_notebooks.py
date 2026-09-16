import json
import re
import sys

targets = [
    "/home/osboxes/CODE/SIMPATHIC2/SKG_Mapping/radboud/2026 Radboud Drug-Gene Graphing.ipynb",
    "/home/osboxes/CODE/SIMPATHIC2/SKG_Mapping/radboud/2026 Radboud Drug-Disease Graphing.ipynb",
    "/home/osboxes/CODE/SIMPATHIC2/SKG_Mapping/radboud/2026 Radboud Drug-Phenotype Graphing.ipynb",
]

pattern = re.compile(r"""SIMPATHIC\['source-relation'\],\s*RDF::Literal\.new\("([A-Z_]+)"\)""")

for path in targets:
    with open(path, encoding='utf-8') as f:
        nb = json.load(f)

    changed = False
    for cell in nb.get('cells', []):
        src = cell.get('source', [])
        if not isinstance(src, list):
            continue
        new_src = []
        for line in src:
            new_src.append(line)
            m = pattern.search(line)
            if m and m.group(1) != 'ASSOCIATED_WITH':
                # build companion line with same leading whitespace, ASSOCIATED_WITH instead
                leading_ws = re.match(r'^(\s*)', line).group(1)
                companion = line.replace(f'RDF::Literal.new("{m.group(1)}")', 'RDF::Literal.new("ASSOCIATED_WITH")')
                # ensure single leading whitespace matches original (already does via replace)
                new_src.append(companion)
                changed = True
                print(f"{path}: inserted ASSOCIATED_WITH companion after {m.group(1)} line")
        cell['source'] = new_src

    if changed:
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(nb, f, indent=1, ensure_ascii=True)
            f.write('\n')
        print(f"  -> wrote {path}")
    else:
        print(f"  -> NO CHANGE for {path} (pattern not found or already fixed)")

#!/usr/bin/env python3
"""
Normalise the Demokritos RELATION value as it is read, in all 9 Demokritos
relation-graphing notebooks (2026-11-18), so a future re-run produces the same
relation names as the patched Virtuoso data and .nq.large files:
    X__INFER__ -> X,  X__SPEC__ -> X,  ISA -> IS_A,  lowercase -> UPPERCASE

Rewrites the single live (non-commented) line
    <var> = row['RELATION']
to
    <var> = row['RELATION']&.sub(/__(INFER|SPEC)__\\z/, '')&.sub(/\\AISA\\z/, 'IS_A')&.upcase  # ...
(safe navigation keeps a missing RELATION as nil, exactly as before).

Raw-text edit of the .ipynb (JSON-escaped form), so nothing else changes. Each
notebook must contain exactly one live match, or it is left untouched.
Notebooks are only patched, not run (see memory: patch data, don't re-run).

Usage:  python3 patch_demokritos_relation_names_notebooks.py [notebook_dir]
"""
import glob
import json
import re
import sys
from pathlib import Path

# JSON-escaped: in the file a Ruby backslash appears as two characters "\\".
NEW_EXPR = ("row['RELATION']&.sub(/__(INFER|SPEC)__\\\\z/, '')&.sub(/\\\\AISA\\\\z/, 'IS_A')&.upcase"
            "  # normalised 2026-11-18, see CHANGES.md")
LIVE = re.compile(r'(?<!# )(\b\w+ *= )row\[\'RELATION\'\](\\n)')


def main():
    nb_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent / "../../demokritos"
    notebooks = sorted(glob.glob(str(nb_dir / "2026*Graphing.ipynb")))
    failed = False
    for path in notebooks:
        name = Path(path).name
        text = Path(path).read_text(encoding="utf-8")
        if "row['RELATION']" not in text:
            continue
        matches = LIVE.findall(text)
        if len(matches) != 1:
            print(f"SKIPPED {name}: expected 1 live RELATION line, found {len(matches)}")
            failed = True
            continue
        new = LIVE.sub(lambda m: m.group(1) + NEW_EXPR + m.group(2), text)
        json.loads(new)  # must still be valid JSON
        Path(path).write_text(new, encoding="utf-8")
        print(f"patched {name}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

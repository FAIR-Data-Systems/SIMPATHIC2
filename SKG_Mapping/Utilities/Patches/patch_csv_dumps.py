#!/usr/bin/env python3
"""
patch_csv_dumps.py — in-place fixes for the two JUNE ML dump files.

Fixes applied:
  1. Remove TREAT_EXPANSIVE from the 'rels' column (col 7, 0-indexed col 6).
     Virtuoso was patched; this aligns the CSVs to match.
  2. Replace the bad HP_0002140 OLS4-error label with "Ischemic stroke"
     in entity1_name and entity2_name columns (cols 2 and 5).

Patterns (all verified by inspection before running):

Split file:
  rels: "TREAT | TREAT_EXPANSIVE"               → "TREAT"
  name: "no HPO match found for HP_0002140"     → "Ischemic stroke"

Merged file:
  rels: "TREAT | TREAT_EXPANSIVE"               → "TREAT"
  rels: "ASSOCIATED_WITH | TREAT | TREAT_EXPANSIVE" → "ASSOCIATED_WITH | TREAT"
  rels: "IS_TREATED | TREAT | TREAT_EXPANSIVE"  → "IS_TREATED | TREAT"
  name: "no HPO match found for HP_0002140"     → "Ischemic stroke"
"""

import csv
import os
import sys
import tempfile

QUERIES_DIR = os.path.dirname(os.path.abspath(__file__)).replace(
    'Utilities/Patches', 'Utilities/Queries'
)

FILES = [
    os.path.join(QUERIES_DIR, 'JUNE_all_pairs_both_orientations_split_evidence.csv.large'),
    os.path.join(QUERIES_DIR, 'JUNE_all_pairs_both_orientations_merged_evidence.csv.large'),
]

RELS_REPLACEMENTS = {
    'TREAT | TREAT_EXPANSIVE':                   'TREAT',
    'ASSOCIATED_WITH | TREAT | TREAT_EXPANSIVE': 'ASSOCIATED_WITH | TREAT',
    'IS_TREATED | TREAT | TREAT_EXPANSIVE':      'IS_TREATED | TREAT',
}

BAD_LABEL  = 'no HPO match found for HP_0002140'
GOOD_LABEL = 'Ischemic stroke'

# Column indices (0-based): entity1_name=1, entity2_name=4, rels=6
RELS_COL       = 6
ENTITY1_NAME   = 1
ENTITY2_NAME   = 4


def patch_file(path):
    print(f'\nPatching: {os.path.basename(path)}')
    rels_fixes = 0
    label_fixes = 0
    total_rows = 0

    tmp = path + '.patching'
    try:
        with open(path, newline='', encoding='utf-8') as infile, \
             open(tmp,  'w', newline='', encoding='utf-8') as outfile:

            reader = csv.reader(infile, delimiter='\t')
            writer = csv.writer(outfile, delimiter='\t', lineterminator='\n')

            header = next(reader)
            writer.writerow(header)

            for row in reader:
                total_rows += 1

                # Fix rels column
                if len(row) > RELS_COL and row[RELS_COL] in RELS_REPLACEMENTS:
                    row[RELS_COL] = RELS_REPLACEMENTS[row[RELS_COL]]
                    rels_fixes += 1

                # Fix entity name columns
                for col in (ENTITY1_NAME, ENTITY2_NAME):
                    if len(row) > col and row[col] == BAD_LABEL:
                        row[col] = GOOD_LABEL
                        label_fixes += 1

                writer.writerow(row)

        os.replace(tmp, path)
        print(f'  rels fixes:  {rels_fixes}')
        print(f'  label fixes: {label_fixes}')
        print(f'  total rows:  {total_rows}')

    except Exception as e:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise


for f in FILES:
    if not os.path.exists(f):
        print(f'MISSING: {f}', file=sys.stderr)
        sys.exit(1)

for f in FILES:
    patch_file(f)

print('\nDone.')

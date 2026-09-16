#!/usr/bin/env python3
"""
extract_icd_catalogs.py — pull the two REaDY ICD catalogs out of their source
.xlsx files and write them as plain TSV, filtered down to the core
neuromuscular-disease block relevant to REaDY's five conditions (DMD/BMD, SMA,
DM, FSHD, LGMD).

Source files (not committed — see mockdata/.gitignore):
  mockdata/ICD11_2025-01-24_EN.xlsx   18,352 rows, full WHO ICD-11 catalog
  mockdata/MKN10_CZ.xlsx              38,815 rows, full Czech ICD-10 (MKN-10)

Why filtered, not the full catalog: at ~1s/query against nmdo-search, mapping
all ~57,000 rows would take hours and mostly query codes with no neuromuscular
relevance (cholera, pregnancy, injuries, ...). The REaDY questionnaires do use
ICD codes for a few open-ended fields (hospitalisation reason, "other"
comorbidity, cause of death) that could in principle reference ANY code in
either catalog — so a full run would be more complete, but this first pass
scopes to the block that actually defines REaDY's five target diseases:

  ICD-11 chapter 8 blocks 8B6x/8C7x/8C8x/8D0x — spinal muscular atrophy,
    muscular dystrophies, myotonic disorders, (myasthenic/other) myopathies,
    neuromuscular junction disorders.
  ICD-10 (MKN-10) blocks G12, G70-G73 — the equivalent Czech coding block.

Usage: python3 extract_icd_catalogs.py
"""
import csv
import os
import openpyxl

HERE = os.path.dirname(os.path.abspath(__file__))
MOCKDATA = os.path.join(HERE, "mockdata")

ICD11_SRC = os.path.join(MOCKDATA, "ICD11_2025-01-24_EN.xlsx")
MKN10_SRC = os.path.join(MOCKDATA, "MKN10_CZ.xlsx")

ICD11_PREFIXES = ("8B6", "8C7", "8C8", "8D0")
MKN10_PREFIXES = ("G12", "G70", "G71", "G72", "G73")


def extract_icd11():
    wb = openpyxl.load_workbook(ICD11_SRC, read_only=True, data_only=True)
    ws = wb["List1"]
    rows = ws.iter_rows(values_only=True)
    header = next(rows)
    out_all, out_scoped = [], []
    for r in rows:
        code, label = r[7], r[8]
        if not code or not label:
            continue
        rec = {"code": code, "label": label, "chapter": r[1], "grouping1": r[2]}
        out_all.append(rec)
        if str(code).startswith(ICD11_PREFIXES):
            out_scoped.append(rec)
    return header, out_all, out_scoped


def extract_mkn10():
    wb = openpyxl.load_workbook(MKN10_SRC, read_only=True, data_only=True)
    ws = wb["MKN10_ICD10"]
    rows = ws.iter_rows(values_only=True)
    header = next(rows)
    out_all, out_scoped = [], []
    for r in rows:
        code, label = r[1], r[2]
        if not code or not label:
            continue
        rec = {"code": code, "label": label}
        out_all.append(rec)
        if str(code).startswith(MKN10_PREFIXES):
            out_scoped.append(rec)
    return header, out_all, out_scoped


def write_tsv(path, rows, fields):
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, delimiter="\t")
        w.writeheader()
        for r in rows:
            w.writerow(r)


def main():
    _, icd11_all, icd11_scoped = extract_icd11()
    _, mkn10_all, mkn10_scoped = extract_mkn10()

    write_tsv(os.path.join(MOCKDATA, "icd11_scoped.tsv"), icd11_scoped,
              ["code", "label", "chapter", "grouping1"])
    write_tsv(os.path.join(MOCKDATA, "mkn10_scoped.tsv"), mkn10_scoped,
              ["code", "label"])

    print(f"ICD-11 total rows: {len(icd11_all)}, scoped to neuromuscular block: {len(icd11_scoped)}")
    print(f"MKN-10 total rows: {len(mkn10_all)}, scoped to neuromuscular block: {len(mkn10_scoped)}")
    print("Wrote mockdata/icd11_scoped.tsv and mockdata/mkn10_scoped.tsv")


if __name__ == "__main__":
    main()

# Adds "ASSOCIATED_WITH" as a base relation to the rels column (col 7) of
# JUNE_all_pairs_both_orientations_split_evidence.csv.large wherever it is
# not already present, regardless of partner (ASSOCIATED_WITH is the
# universal base relation for every edge -- confirmed by project owner
# 2026-09-14). Preserves any existing specific relation(s) already there.
BEGIN { FS = OFS = "\t" }
NR == 1 { print; next }
{
  # BUG FIXED 2026-11-18: this line was  split($7, parts, " | ")  -- awk treats a
  # multi-character separator as a regex, and " | " means "space OR space", so cells
  # were split on single spaces and "A | B" came out as "A | | | B" (866 rows of the
  # SEPT split dump). SEPT is kept as-is for provenance; the NOV dumps are clean.
  # "[|]" makes the pipe a literal character.
  n = split($7, parts, / [|] /)
  has_aw = 0
  out = ""
  count = 0
  for (i = 1; i <= n; i++) {
    v = parts[i]
    gsub(/^[ \t]+|[ \t]+$/, "", v)
    if (v == "") continue
    if (v == "ASSOCIATED_WITH") has_aw = 1
    out = (count == 0) ? v : out " | " v
    count++
  }
  if (!has_aw) {
    out = (count == 0) ? "ASSOCIATED_WITH" : out " | ASSOCIATED_WITH"
  }
  $7 = out
  print
}

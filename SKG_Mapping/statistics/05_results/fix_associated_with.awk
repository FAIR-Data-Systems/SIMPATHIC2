# Fixes the IS_ASSOCIATED_WITH / ASSOCIATED_WITH typo in the rels column
# (col 7) of JUNE_all_pairs_both_orientations_{merged,split}_evidence.csv.large,
# then re-splits on '|', trims whitespace from each value, deduplicates
# (preserving first-seen order), and rejoins with " | ".
# This also incidentally normalizes any other whitespace-padding duplicates
# already present in the rels column (e.g. "ASSOCIATED_WITH " vs
# " ASSOCIATED_WITH"), not just the IS_ASSOCIATED_WITH case -- since the
# column is fully re-parsed for every row regardless of cause.
BEGIN { FS = OFS = "\t" }
NR == 1 { print; next }
{
  gsub(/IS_ASSOCIATED_WITH/, "ASSOCIATED_WITH", $7)
  n = split($7, parts, "|")
  delete seen
  out = ""
  count = 0
  for (i = 1; i <= n; i++) {
    v = parts[i]
    gsub(/^[ \t]+|[ \t]+$/, "", v)
    if (v == "" || (v in seen)) continue
    seen[v] = 1
    out = (count == 0) ? v : out " | " v
    count++
  }
  $7 = out
  print
}

# Normalise messy Demokritos relation names in the `rels` column of the ML split
# dump, matching Fix_Demokritos_Relation_Names.sparql (2026-11-18):
#   X__INFER__ -> X,  X__SPEC__ -> X,  ISA -> IS_A,  lowercase -> UPPERCASE
# Same explicit 15-entry mapping; any other suffixed/lowercase value aborts.
# A renamed value is dropped if its target is already in the cell
# ("ASSOCIATED_WITH__INFER__ | ASSOCIATED_WITH" -> "ASSOCIATED_WITH").
# Also removes the stray '|' tokens introduced into SEPT by the Sept awk patch
# ("A | | | B" -> "A | B"; 866 rows). Nothing else in any cell changes.
#
# Writes a NEW file (input untouched), following the JUNE_ -> SEPT_ precedent:
#   ruby patch_relation_names_in_dump.rb SEPT_..._split_evidence.csv.large NOV_..._split_evidence.csv.large
# then regenerate the merged file:  ruby merge_evidence.rb NOV_..._split_evidence.csv.large
#
# Plain tab split (the dump has no quote characters and a fixed 11 columns;
# both are checked), so every other byte of every row is copied unchanged.

MAP = {
  'ASSOCIATED_WITH__INFER__' => 'ASSOCIATED_WITH', 'ASSOCIATED_WITH__SPEC__' => 'ASSOCIATED_WITH',
  'INTERACTS_WITH__INFER__' => 'INTERACTS_WITH',   'INTERACTS_WITH__SPEC__' => 'INTERACTS_WITH',
  'AFFECTS__SPEC__' => 'AFFECTS',     'CAUSES__SPEC__' => 'CAUSES',
  'COEXISTS_WITH__SPEC__' => 'COEXISTS_WITH', 'DISRUPTS__SPEC__' => 'DISRUPTS',
  'INHIBITS__SPEC__' => 'INHIBITS',   'PREVENTS__SPEC__' => 'PREVENTS',
  'PRODUCES__SPEC__' => 'PRODUCES',   'STIMULATES__SPEC__' => 'STIMULATES',
  'ISA' => 'IS_A', 'compared_with' => 'COMPARED_WITH', 'higher_than' => 'HIGHER_THAN'
}.freeze
MESSY = ->(v) { v =~ /__(INFER|SPEC)__\z/ || v == 'ISA' || v != v.upcase }
SEP = ' | '

input, output = ARGV
abort 'usage: ruby patch_relation_names_in_dump.rb INPUT OUTPUT' unless input && output
abort "#{output} already exists; refusing to overwrite" if File.exist?(output)

rows = changed = 0
File.open(output, 'w') do |out|
  File.foreach(input).with_index do |line, i|
    if i.zero?
      cols = line.chomp.split("\t", -1)
      REL = cols.index('rels') or abort 'no rels column'
      NCOL = cols.size
      out << line
      next
    end
    abort "line #{i + 1}: quote character found; tab split not safe" if line.include?('"')
    f = line.chomp("\n").split("\t", -1)
    abort "line #{i + 1}: #{f.size} columns, expected #{NCOL}" unless f.size == NCOL
    rows += 1
    # Drop stray '|' tokens. They were introduced by the 2026-09-14 add_associated_with_base.awk:
    # awk split($7, parts, " | ") treats " | " as the regex "space OR space", so multi-relation
    # cells were split on single spaces and re-joined as "A | | | B". JUNE has none of these.
    orig = f[REL].split(SEP, -1).reject { |v| v == '|' }
    orig.each do |v|
      next if MAP.key?(v)
      abort "line #{i + 1}: unexpected relation value #{v.inspect} not in mapping" if MESSY.call(v)
    end
    # Only renamed values are de-duplicated: a renamed value is dropped if its target
    # is already in the cell. Every other token (including stray '|') is kept exactly.
    unmapped = orig.reject { |v| MAP.key?(v) }
    added = []
    vals = orig.filter_map do |v|
      next v unless MAP.key?(v)
      t = MAP[v]
      next nil if unmapped.include?(t) || added.include?(t)
      added << t
      t
    end
    new_rels = vals.join(SEP)
    if new_rels != f[REL]
      changed += 1
      f[REL] = new_rels
    end
    out << f.join("\t") << "\n"
  end
end
puts "#{rows} rows written to #{output}; #{changed} rels cells changed"

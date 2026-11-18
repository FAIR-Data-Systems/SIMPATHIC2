# Normalise messy Demokritos simp:source-relation values in the on-disk .nq.large
# files, matching Fix_Demokritos_Relation_Names.sparql (2026-11-18):
#   X__INFER__ -> X,  X__SPEC__ -> X,  ISA -> IS_A,  lowercase -> UPPERCASE
# Uses the same explicit 15-entry mapping as the SPARQL patch; any other suffixed
# or lowercase value found aborts the run, so nothing unexpected is renamed.
#
# Only lines whose predicate is <urn:simpathic:source-relation> are touched. If a
# rename makes a line an exact duplicate of another line in the file (the graph
# already had the base relation), the duplicate is dropped.
# Originals are backed up to demokritos/graph/deprecated/<name>.BEFORE-relnames-<date>.nq.large
# (.nq.large files are git-ignored, so the backup is the only copy).
#
# Usage (from SKG_Mapping/):  ruby Utilities/Patches/patch_demokritos_relation_names.rb [--dry-run]

require 'fileutils'
require 'date'
require 'set'

GRAPH_DIR = File.expand_path('../../demokritos/graph', __dir__)
MAP = {
  'ASSOCIATED_WITH__INFER__' => 'ASSOCIATED_WITH', 'ASSOCIATED_WITH__SPEC__' => 'ASSOCIATED_WITH',
  'INTERACTS_WITH__INFER__' => 'INTERACTS_WITH',   'INTERACTS_WITH__SPEC__' => 'INTERACTS_WITH',
  'AFFECTS__SPEC__' => 'AFFECTS',     'CAUSES__SPEC__' => 'CAUSES',
  'COEXISTS_WITH__SPEC__' => 'COEXISTS_WITH', 'DISRUPTS__SPEC__' => 'DISRUPTS',
  'INHIBITS__SPEC__' => 'INHIBITS',   'PREVENTS__SPEC__' => 'PREVENTS',
  'PRODUCES__SPEC__' => 'PRODUCES',   'STIMULATES__SPEC__' => 'STIMULATES',
  'ISA' => 'IS_A', 'compared_with' => 'COMPARED_WITH', 'higher_than' => 'HIGHER_THAN'
}.freeze
REL_LINE = /\A(<[^>]*> <urn:simpathic:source-relation> )"([^"\\]*)"(.*)\z/m
MESSY = ->(v) { v =~ /__(INFER|SPEC)__\z/ || v == 'ISA' || v != v.upcase }

abort <<~MSG unless ARGV.include?('--dry-run')
  ALREADY APPLIED 2026-11-18. The corrected files are in demokritos/graph/NOV-20261118/.
  The files in demokritos/graph/ are the September originals the partners used, restored
  on purpose as a provenance record. They must NOT be modified in place (Mark, 2026-11-18).
  Only --dry-run is allowed.
MSG
dry_run = ARGV.include?('--dry-run')
stamp = Date.today.strftime('%Y%m%d')
grand = Hash.new(0)

Dir[File.join(GRAPH_DIR, '*.nq.large')].sort.each do |path|
  name = File.basename(path)
  renamed = Hash.new(0)
  dropped = 0
  seen_rel = Set.new
  out = []
  File.foreach(path) do |line|
    m = REL_LINE.match(line)
    unless m
      out << line
      next
    end
    value = m[2]
    if MAP.key?(value)
      renamed[value] += 1
      line = "#{m[1]}\"#{MAP[value]}\"#{m[3]}"
    elsif MESSY.call(value)
      abort "#{name}: unexpected relation value #{value.inspect} not in mapping; nothing written for this or later files."
    end
    if seen_rel.include?(line)
      dropped += 1
      next
    end
    seen_rel << line
    out << line
  end
  next if renamed.empty?

  total = renamed.values.sum
  grand[:renamed] += total
  grand[:dropped] += dropped
  puts "#{name}: #{total} renamed (#{renamed.map { |k, v| "#{k}=#{v}" }.join(', ')}); #{dropped} now-duplicate lines dropped"
  next if dry_run

  backup = File.join(GRAPH_DIR, 'deprecated', name.sub(/\.nq\.large\z/, ".BEFORE-relnames-#{stamp}.nq.large"))
  abort "Backup #{backup} already exists; refusing to overwrite it." if File.exist?(backup)
  FileUtils.cp(path, backup, preserve: true)
  tmp = "#{path}.tmp"
  File.write(tmp, out.join)
  File.rename(tmp, path)
  puts "    backup: #{backup}"
end
puts "TOTAL: #{grand[:renamed]} renamed, #{grand[:dropped]} duplicates dropped"
puts(dry_run ? 'DRY RUN - no files written' : 'done')

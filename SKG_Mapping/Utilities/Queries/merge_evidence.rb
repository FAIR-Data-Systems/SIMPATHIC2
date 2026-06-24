#!/usr/bin/env ruby
# merge_evidence.rb
# Collapses the split-evidence ML export into one row per unique entity pair.
#
# Grouping key: [canonical_entity1_uri, entity1_type, canonical_entity2_uri, entity2_type]
# This means disease subclasses (e.g. "MJD type 1") are folded into their
# parent target disease (e.g. "MJD") before merging, so cross-partner
# observations about the same disease cluster are united in one row.
# For non-Disease entities (and diseases outside the 10-disease subtree),
# canonical URI == exact URI, so behaviour is unchanged.
#
# Input:  JUNE_all_pairs_both_orientations_split_evidence.csv.large
# Output: JUNE_all_pairs_both_orientations_merged_evidence.csv.large
#
# Usage:
#   ruby merge_evidence.rb
#   ruby merge_evidence.rb path/to/input.csv.large

require 'csv'
require 'set'

INPUT        = ARGV[0] || 'JUNE_all_pairs_both_orientations_split_evidence.csv.large'
OUTPUT       = INPUT.sub('split_evidence', 'merged_evidence')
EVIDENCE_SEP = '|||'.freeze
LIST_SEP     = ' | '.freeze

COLUMNS = %w[
  canonical_entity1_uri entity1_name entity1_type
  canonical_entity2_uri entity2_name entity2_type
  rels sources evidence
  entity1_uri entity2_uri
].freeze

abort "Input file not found: #{INPUT}" unless File.exist?(INPUT)

# Check whether the input has the canonical columns (produced by updated build_ml_set.rb).
# Fall back to using exact URIs as canonicals if not present (backward compatibility).
headers = CSV.open(INPUT, col_sep: "\t", &:first)
HAS_CANONICAL = headers.include?('canonical_entity1_uri')
warn 'NOTE: input lacks canonical_* columns — using exact URIs as canonicals.' unless HAS_CANONICAL

puts "Reading #{INPUT} ..."

# Key: [canonical_entity1_uri, entity1_type, canonical_entity2_uri, entity2_type]
grouped = {}
total   = 0

CSV.foreach(INPUT, col_sep: "\t", headers: true) do |row|
  e1_uri       = row['entity1']
  e2_uri       = row['entity2']
  e1_canonical = HAS_CANONICAL ? (row['canonical_entity1_uri'] || e1_uri) : e1_uri
  e2_canonical = HAS_CANONICAL ? (row['canonical_entity2_uri'] || e2_uri) : e2_uri
  e1_type      = row['entity1_type']
  e2_type      = row['entity2_type']

  key = [e1_canonical, e1_type, e2_canonical, e2_type]

  entry = grouped[key] ||= {
    entity1_name: row['entity1_name'],
    entity2_name: row['entity2_name'],
    rels: Set.new,
    sources: Set.new,
    evidence: Set.new,
    entity1_uris: Set.new,
    entity2_uris: Set.new
  }

  row['rels']&.split(LIST_SEP)&.each    { |v| entry[:rels]    << v.strip }
  row['sources']&.split(LIST_SEP)&.each { |v| entry[:sources] << v.strip }

  ev = row['evidence']
  entry[:evidence] << ev if ev && !ev.strip.empty?

  # Track all specific URIs that folded into this canonical pair (for traceability)
  entry[:entity1_uris] << e1_uri if e1_uri
  entry[:entity2_uris] << e2_uri if e2_uri

  total += 1
  print "\r  #{total} rows read..." if (total % 50_000).zero?
end

puts "\r  #{total} input rows read.   "
puts "  #{grouped.size} unique canonical entity pairs"
puts "Writing #{OUTPUT} ..."

written = 0
CSV.open(OUTPUT, 'w', col_sep: "\t") do |csv|
  csv << COLUMNS
  grouped.each do |(e1_canonical, e1_type, e2_canonical, e2_type), entry|
    csv << [
      e1_canonical,
      entry[:entity1_name],
      e1_type,
      e2_canonical,
      entry[:entity2_name],
      e2_type,
      entry[:rels].sort.join(LIST_SEP),
      entry[:sources].sort.join(LIST_SEP),
      entry[:evidence].to_a.join(EVIDENCE_SEP),
      entry[:entity1_uris].sort.join(LIST_SEP),
      entry[:entity2_uris].sort.join(LIST_SEP)
    ]
    written += 1
  end
end

puts "Done — #{written} rows written to #{OUTPUT}"
puts "Compression ratio: #{total} → #{written} rows (#{(100.0 * written / total).round(1)}% of input)"

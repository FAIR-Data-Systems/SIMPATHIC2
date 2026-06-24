#!/usr/bin/env ruby
# merge_evidence.rb
# Collapses the split-evidence ML export into one row per unique entity pair.
#
# Input:  JUNE_all_pairs_both_orientations_split_evidence.csv.large
#         (tab-delimited, one row per entity-pair + evidence combination)
#
# Output: JUNE_all_pairs_merged_evidence.csv.large
#         (tab-delimited, one row per entity pair)
#         - evidence values joined with |||
#         - rels and sources union-merged across all evidence rows for the pair
#
# Usage:
#   ruby merge_evidence.rb
#   ruby merge_evidence.rb path/to/input.csv.large   # optional override

require 'csv'
require 'set'

INPUT        = ARGV[0] || 'JUNE_all_pairs_both_orientations_split_evidence.csv.large'
OUTPUT       = INPUT.sub('split_evidence', 'merged_evidence')
EVIDENCE_SEP = '|||'
LIST_SEP     = ' | '

COLUMNS = %w[entity1 entity1_name entity1_type entity2 entity2_name entity2_type rels sources evidence].freeze

abort "Input file not found: #{INPUT}" unless File.exist?(INPUT)

puts "Reading #{INPUT} ..."

# Key: [entity1_uri, entity1_type, entity2_uri, entity2_type]
# Value: { names, rels, sources, evidence } — all sets except the name strings
grouped = {}
total   = 0

CSV.foreach(INPUT, col_sep: "\t", headers: true) do |row|
  key = [row['entity1'], row['entity1_type'], row['entity2'], row['entity2_type']]

  entry = grouped[key] ||= {
    entity1_name: row['entity1_name'],
    entity2_name: row['entity2_name'],
    rels:         Set.new,
    sources:      Set.new,
    evidence:     Set.new
  }

  # rels and sources may already be LIST_SEP-joined from GROUP_CONCAT — split and union
  row['rels']&.split(LIST_SEP)&.each    { |v| entry[:rels]    << v.strip }
  row['sources']&.split(LIST_SEP)&.each { |v| entry[:sources] << v.strip }

  ev = row['evidence']
  entry[:evidence] << ev if ev && !ev.strip.empty?

  total += 1
  print "\r  #{total} rows read..." if (total % 50_000).zero?
end

puts "\r  #{total} input rows read.   "
puts "  #{grouped.size} unique entity pairs"
puts "Writing #{OUTPUT} ..."

written = 0
CSV.open(OUTPUT, 'w', col_sep: "\t") do |csv|
  csv << COLUMNS
  grouped.each do |(entity1, entity1_type, entity2, entity2_type), entry|
    csv << [
      entity1,
      entry[:entity1_name],
      entity1_type,
      entity2,
      entry[:entity2_name],
      entity2_type,
      entry[:rels].sort.join(LIST_SEP),
      entry[:sources].sort.join(LIST_SEP),
      entry[:evidence].to_a.join(EVIDENCE_SEP)
    ]
    written += 1
  end
end

puts "Done — #{written} rows written to #{OUTPUT}"
puts "Compression ratio: #{total} → #{written} rows (#{(100.0 * written / total).round(1)}% of input)"

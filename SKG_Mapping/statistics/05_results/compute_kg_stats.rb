#!/usr/bin/env ruby
# Streams JUNE_all_pairs_both_orientations_merged_evidence.csv.large (read-only)
# and computes summary KG statistics. Never opens the file for writing.
require 'set'
require 'json'

path = ARGV[0] or abort "usage: compute_kg_stats.rb <path>"

nodes = Set.new
node_type = {}          # canonical_uri => type (sanity check: 1 type per uri)
type_counts = Hash.new(0)   # entity_type => count of distinct canonical URIs of that type
rel_counts = Hash.new(0)    # relation label => row count
source_counts = Hash.new(0) # source label => row count
row_count = 0
multi_type_uris = 0

File.foreach(path, encoding: 'utf-8') do |line|
  row_count += 1
  next if row_count == 1 # header
  cols = line.chomp("\n").split("\t", -1)
  # canonical_entity1_uri entity1_name entity1_type canonical_entity2_uri entity2_name entity2_type rels sources evidence entity1_uri entity2_uri
  c1, _n1, t1, c2, _n2, t2, rels, sources, _evidence, _u1, _u2 = cols

  [[c1, t1], [c2, t2]].each do |uri, type|
    if nodes.add?(uri)
      node_type[uri] = type
      type_counts[type] += 1
    elsif node_type[uri] != type
      multi_type_uris += 1
    end
  end

  rels.to_s.split('|').each { |r| rel_counts[r] += 1 } unless rels.nil? || rels.empty?
  sources.to_s.split('|').each { |s| source_counts[s] += 1 } unless sources.nil? || sources.empty?
end

data_rows = row_count - 1

summary = {
  file: path,
  data_rows_edges_both_orientations: data_rows,
  distinct_nodes: nodes.size,
  distinct_entity_types: type_counts.size,
  entity_type_node_counts: type_counts.sort_by { |_,v| -v }.to_h,
  distinct_relation_labels: rel_counts.size,
  relation_label_row_counts: rel_counts.sort_by { |_,v| -v }.to_h,
  distinct_source_labels: source_counts.size,
  source_label_row_counts: source_counts.sort_by { |_,v| -v }.to_h,
  uris_with_inconsistent_type_across_rows: multi_type_uris
}

puts JSON.pretty_generate(summary)

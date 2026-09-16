require 'set'
require 'json'
path = ARGV[0] or abort "usage: compute_kg_stats_trimmed.rb <path>"

nodes = Set.new
node_type = {}
type_counts = Hash.new(0)
rel_counts = Hash.new(0)
source_counts = Hash.new(0)
row_count = 0

File.foreach(path, encoding: 'utf-8') do |line|
  row_count += 1
  next if row_count == 1
  cols = line.chomp("\n").split("\t", -1)
  c1, _n1, t1, c2, _n2, t2, rels, sources, = cols

  [[c1, t1], [c2, t2]].each do |uri, type|
    if nodes.add?(uri)
      node_type[uri] = type
      type_counts[type] += 1
    end
  end

  rels.to_s.split('|').each { |r| r2 = r.strip; rel_counts[r2] += 1 unless r2.empty? }
  sources.to_s.split('|').each { |s| s2 = s.strip; source_counts[s2] += 1 unless s2.empty? }
end

summary = {
  file: path,
  data_rows_edges_both_orientations: row_count - 1,
  distinct_nodes: nodes.size,
  entity_type_node_counts: type_counts.sort_by { |_,v| -v }.to_h,
  distinct_relation_labels_trimmed: rel_counts.size,
  relation_label_row_counts_trimmed: rel_counts.sort_by { |_,v| -v }.to_h,
  distinct_source_labels_trimmed: source_counts.size,
  source_label_row_counts_trimmed: source_counts.sort_by { |_,v| -v }.to_h
}
puts JSON.pretty_generate(summary)

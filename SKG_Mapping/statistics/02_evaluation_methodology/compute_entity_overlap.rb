#!/usr/bin/env ruby
# Computes pairwise entity overlap (exact URI match only -- no canonicalization
# hierarchy exists for these types) for Drug, Gene, Phenotype, Protein, using
# the split-evidence file (one-line-per-evidence-source, so 'sources' is
# single-valued for ~99.9% of rows -- cleaner per-partner attribution than
# the merged-evidence file, where multiple partners' rels/sources get
# GROUP_CONCAT'd onto one row).
require 'set'
require 'json'

path = ARGV[0] or abort "usage: compute_entity_overlap.rb <split_evidence.large>"

partners = %w[Biovista Radboud Demokritos]
types = %w[Drug Gene Phenotype Protein]

# type => partner => Set(canonical_uri => name)  (keep one name example per uri)
seen = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = {} } }

File.foreach(path, encoding: 'utf-8').with_index do |line, i|
  next if i == 0
  cols = line.chomp("\n").split("\t", -1)
  # entity1 entity1_name entity1_type entity2 entity2_name entity2_type rels sources evidence canonical_entity1_uri canonical_entity2_uri
  _e1, n1, t1, _e2, n2, t2, _rels, sources, _ev, c1, c2 = cols
  row_partners = sources.to_s.split('|').map(&:strip).reject(&:empty?)

  [[c1, t1, n1], [c2, t2, n2]].each do |uri, type, name|
    next unless types.include?(type)
    row_partners.each do |p|
      next unless partners.include?(p)
      seen[type][p][uri] ||= name
    end
  end
end

results = {}
types.each do |type|
  sets = partners.each_with_object({}) { |p, h| h[p] = seen[type][p].keys.to_set }
  pairwise = {}
  partners.combination(2).each do |a, b|
    inter = sets[a] & sets[b]
    union = sets[a] | sets[b]
    pairwise["#{a}/#{b}"] = {
      a_count: sets[a].size, b_count: sets[b].size,
      intersection: inter.size, union: union.size,
      jaccard_pct: union.empty? ? nil : (inter.size.to_f / union.size * 100).round(2),
      # overlap coefficient: intersection / smaller set -- more meaningful when set sizes differ a lot
      overlap_coeff_pct: [sets[a].size, sets[b].size].min.zero? ? nil :
        (inter.size.to_f / [sets[a].size, sets[b].size].min * 100).round(2)
    }
  end
  results[type] = {
    counts: partners.each_with_object({}) { |p, h| h[p] = sets[p].size },
    pairwise: pairwise
  }
end

puts JSON.pretty_generate(results)

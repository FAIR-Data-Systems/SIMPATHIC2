#!/usr/bin/env ruby
# Computes, for each of the 10 gold-standard target diseases and each
# partner, whether that partner contributed: an EXACT match (specific_uri ==
# canonical target URI), a SUBCLASS match only (specific_uri is a descendant
# per canonical_disease.tsv), or NEITHER. Read-only against the scratch copy
# of the merged-evidence .large file and canonical_disease.tsv.
require 'set'
require 'json'

lookup_path = ARGV[0] or abort "usage: compute_disease_overlap.rb <canonical_disease.tsv> <merged_evidence.large>"
evidence_path = ARGV[1] or abort "usage: compute_disease_overlap.rb <canonical_disease.tsv> <merged_evidence.large>"

specific_to_canonical = {}
File.foreach(lookup_path, encoding: 'utf-8').with_index do |line, i|
  next if i == 0
  spec, canon = line.chomp.split("\t")
  specific_to_canonical[spec] = canon
end

targets = specific_to_canonical.values.uniq.sort
partners = %w[Biovista Radboud Demokritos]

# target_uri => partner => :exact | :subclass | nil (choose best if multiple rows)
coverage = Hash.new { |h, k| h[k] = {} }
# also track, per target, the distinct specific disease URIs seen per partner (for transparency)
specific_uris_seen = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = Set.new } }

File.foreach(evidence_path, encoding: 'utf-8').with_index do |line, i|
  next if i == 0
  cols = line.chomp("\n").split("\t", -1)
  c1, _n1, t1, c2, _n2, t2, _rels, sources, _ev, u1, u2 = cols
  row_partners = sources.to_s.split('|').map(&:strip).reject(&:empty?)

  [[c1, t1, u1], [c2, t2, u2]].each do |canon_uri, type, specific_uri_field|
    next unless type == 'Disease'
    next unless targets.include?(canon_uri)
    # entity_uri can be a '|'-delimited list of specific URIs folded into
    # this canonical pair (see CHANGES.md) -- evaluate each individually.
    specific_uri_field.to_s.split('|').map(&:strip).reject(&:empty?).each do |specific_uri|
      match_kind = (specific_uri == canon_uri) ? :exact : :subclass
      row_partners.each do |p|
        next unless partners.include?(p)
        specific_uris_seen[canon_uri][p] << specific_uri
        cur = coverage[canon_uri][p]
        # exact beats subclass if both occur across different rows/URIs
        coverage[canon_uri][p] = match_kind if cur.nil? || (cur == :subclass && match_kind == :exact)
      end
    end
  end
end

per_target = targets.map do |t|
  {
    target: t,
    partners: partners.each_with_object({}) { |p, h|
      h[p] = {
        match: coverage[t][p]&.to_s || 'none',
        specific_uris: specific_uris_seen[t][p].to_a
      }
    }
  }
end

# summary counts
summary = partners.each_with_object({}) do |p, h|
  exact = targets.count { |t| coverage[t][p] == :exact }
  subclass = targets.count { |t| coverage[t][p] == :subclass }
  none = targets.size - exact - subclass
  h[p] = { exact: exact, subclass_only: subclass, none: none, total_targets: targets.size }
end

puts JSON.pretty_generate({ targets: targets, per_target: per_target, summary: summary })

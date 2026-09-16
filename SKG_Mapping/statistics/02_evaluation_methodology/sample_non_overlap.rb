#!/usr/bin/env ruby
require 'set'
require 'json'

path = ARGV[0]
target_type = ARGV[1] # e.g. Phenotype

partners = %w[Biovista Radboud Demokritos]
seen = Hash.new { |h, k| h[k] = {} } # partner => uri => name

File.foreach(path, encoding: 'utf-8').with_index do |line, i|
  next if i == 0
  cols = line.chomp("\n").split("\t", -1)
  _e1, n1, t1, _e2, n2, t2, _rels, sources, _ev, c1, c2 = cols
  row_partners = sources.to_s.split('|').map(&:strip).reject(&:empty?)
  [[c1, t1, n1], [c2, t2, n2]].each do |uri, type, name|
    next unless type == target_type
    row_partners.each { |p| seen[p][uri] ||= name if partners.include?(p) }
  end
end

sets = partners.each_with_object({}) { |p, h| h[p] = seen[p].keys.to_set }

partners.each do |p|
  others = (partners - [p]).flat_map { |o| sets[o].to_a }.to_set
  only = sets[p] - others
  puts "=== #{target_type} only in #{p}: #{only.size} / #{sets[p].size} ==="
  only.to_a.sample(15, random: Random.new(42)).each { |uri| puts "  #{seen[p][uri]}  (#{uri})" }
  puts
end

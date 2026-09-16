#!/usr/bin/env ruby
# Enumerates every *-errors* file under SKG_Mapping, excluding deprecated/
# backup paths (those reflect superseded pipeline runs, not the current
# error trail). For each current file: line count, partner, pipeline stage
# (entity mapping vs. relation graphing), and a normalized error-type
# breakdown (message with trailing identifiers stripped).
require 'json'
require 'find'

root = ARGV[0] or abort "usage: enumerate_error_logs.rb <SKG_Mapping root>"

EXCLUDE_RE = /deprecated|backup/i

files = []
Find.find(root) do |path|
  next unless File.file?(path)
  next unless path =~ /error/i
  next if path =~ /\.ipynb_checkpoints/
  next if path =~ %r{/statistics/}
  next if EXCLUDE_RE.match?(path)
  files << path
end
files.sort!

def partner_of(path)
  return 'Biovista' if path =~ %r{/biovista/}
  return 'Demokritos' if path =~ %r{/demokritos/}
  return 'Radboud' if path =~ %r{/radboud/}
  'Unknown'
end

def stage_of(path)
  path =~ %r{/maps/} ? 'entity_mapping' : (path =~ %r{/graph/} ? 'relation_graphing' : 'unknown')
end

# Normalize a line to an error-type key by stripping trailing identifiers/
# parenthetical names, keeping the leading message shape.
def normalize(line)
  l = line.strip
  return nil if l.empty?
  # UMLS/CURIE style: "label\tUMLS:C0000000\tname" -> keep label + UMLS: marker
  if l.include?("\t")
    parts = l.split("\t")
    return parts[0].strip + (parts[1] =~ /^[A-Za-z]+:/ ? " <#{parts[1][/^[A-Za-z]+/]}_id>" : "")
  end
  # strip a trailing parenthetical, e.g. "(Liver Extracts)"
  l = l.sub(/\s*\([^)]*\)\s*$/, '')
  # strip a trailing bare identifier token (last whitespace-separated token
  # if it looks like an ID: alnum/underscore/colon, no spaces)
  tokens = l.split(' ')
  if tokens.size > 1 && tokens.last =~ /\A[A-Za-z0-9_:.\-]+\z/ && tokens.last =~ /[0-9]/
    tokens.pop
    l = tokens.join(' ') + ' <id>'
  end
  l
end

per_file = []
error_type_counts = Hash.new(0)
partner_stage_counts = Hash.new(0)
total_lines = 0

files.each do |f|
  lines = File.readlines(f, encoding: 'utf-8').map(&:chomp).reject(&:empty?)
  n = lines.size
  total_lines += n
  partner = partner_of(f)
  stage = stage_of(f)
  partner_stage_counts["#{partner}/#{stage}"] += n
  lines.each do |line|
    norm = normalize(line)
    error_type_counts[norm] += 1 if norm
  end
  per_file << {
    file: f.sub(root + '/', ''),
    partner: partner,
    stage: stage,
    line_count: n
  }
end

summary = {
  root: root,
  excluded_pattern: EXCLUDE_RE.source,
  file_count: files.size,
  total_error_lines: total_lines,
  per_file: per_file,
  partner_stage_totals: partner_stage_counts.sort_by { |_, v| -v }.to_h,
  normalized_error_type_counts: error_type_counts.sort_by { |_, v| -v }.to_h
}

puts JSON.pretty_generate(summary)

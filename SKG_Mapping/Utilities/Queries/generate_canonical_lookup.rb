#!/usr/bin/env ruby
# generate_canonical_lookup.rb
#
# Queries the MONDO hierarchy in Virtuoso to build a flat lookup:
#   specific_disease_uri  ->  canonical_disease_uri
#
# "Canonical" means one of the 10 SIMPATHIC target diseases.
# Any disease that is a (transitive) subclass of a target gets mapped to it.
# Diseases that are already a target map to themselves (identity).
# All other diseases are not written to the file — they are handled as
# identity by default in the consuming scripts.
#
# Usage:
#   ruby generate_canonical_lookup.rb
# Output:
#   canonical_disease.tsv  (two columns: specific_uri  canonical_uri)

require 'net/http'
require 'uri'
require 'json'
require 'csv'

ENDPOINT = ENV['SPARQL_ENDPOINT'] || 'http://localhost:8890/sparql'
OUTPUT   = 'canonical_disease.tsv'

TARGET_DISEASES = %w[
  http://purl.obolibrary.org/obo/MONDO_0007182
  http://purl.obolibrary.org/obo/MONDO_0008907
  http://purl.obolibrary.org/obo/MONDO_0009281
  http://purl.obolibrary.org/obo/MONDO_0009723
  http://purl.obolibrary.org/obo/MONDO_0009945
  http://purl.obolibrary.org/obo/MONDO_0010083
  http://purl.obolibrary.org/obo/MONDO_0016107
  http://purl.obolibrary.org/obo/MONDO_0018940
  http://purl.obolibrary.org/obo/MONDO_0019609
  http://purl.obolibrary.org/obo/MONDO_0100184
].freeze

values_block = TARGET_DISEASES.map { |u| "    (<#{u}>)" }.join("\n")

# rdfs:subClassOf+ = one-or-more (proper subclasses only).
# We add the targets themselves separately so the file covers identity too.
query = <<~SPARQL
  PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

  SELECT DISTINCT ?specific ?canonical
  WHERE {
    VALUES (?canonical) {
#{values_block}
    }
    GRAPH <urn:mondo:hierarchy> {
      ?specific rdfs:subClassOf+ ?canonical .
    }
  }
SPARQL

puts "Querying Virtuoso for MONDO subclass hierarchy..."

uri = URI(ENDPOINT)
http = Net::HTTP.new(uri.host, uri.port)
req  = Net::HTTP::Post.new(uri)
req['Content-Type'] = 'application/x-www-form-urlencoded'
req['Accept']       = 'application/sparql-results+json'
req.body = 'query=' + URI.encode_www_form_component(query)

response = http.request(req)
unless response.code == '200'
  abort "SPARQL failed: #{response.code}\n#{response.body[0..400]}"
end

data    = JSON.parse(response.body)
results = data['results']['bindings']
puts "  #{results.size} subclass relationships found."

# Build lookup hash: specific -> canonical
# If a disease is a subclass of multiple targets (unlikely but possible),
# keep the most specific canonical (smallest MONDO number = most specific...
# actually we just take the first encountered; in practice this shouldn't occur
# for well-curated MONDO terms under 10 distinct disease roots).
lookup = {}
results.each do |row|
  specific  = row['specific']['value']
  canonical = row['canonical']['value']
  lookup[specific] ||= canonical
end

# Add identity entries for the 10 targets themselves
TARGET_DISEASES.each { |u| lookup[u] ||= u }

puts "  #{lookup.size} total entries in lookup (including identity for 10 targets)."

CSV.open(OUTPUT, 'w', col_sep: "\t") do |csv|
  csv << %w[specific_uri canonical_uri]
  lookup.sort_by { |s, _| s }.each { |s, c| csv << [s, c] }
end

puts "Written to #{OUTPUT}"

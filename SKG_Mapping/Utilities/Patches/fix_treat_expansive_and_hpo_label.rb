#!/usr/bin/env ruby
# fix_treat_expansive_and_hpo_label.rb
#
# Two targeted repairs:
# 1. Remove TREAT_EXPANSIVE source-relation triples from all_metadata.
#    These were written by the Radboud Drug-Phenotype notebook before the
#    TREAT_EXPANSIVE experimental relation was abandoned (2026-06-29).
#    The notebook fix is already in place; only Virtuoso still has stale data
#    because the Jun-23 .nq.large file was reloaded during the full purge.
#
# 2. Fix the bad rdfs:label for HP_0002140 in the one Radboud phenotype-gene
#    context where an OLS4 lookup failed and stored the error string as the
#    label. Correct label: "Ischemic stroke".
#
# Usage:
#   ruby fix_treat_expansive_and_hpo_label.rb
# Requires:
#   VIRTUOSO_USER, VIRTUOSO_PASS  (never use dba)

require 'net/http'
require 'uri'

VIRTUOSO_URL = 'http://57.128.119.57:8890/sparql'
USERNAME     = ENV['VIRTUOSO_USER']
PASSWORD     = ENV['VIRTUOSO_PASS']
abort 'Set ENV["VIRTUOSO_USER"] and ENV["VIRTUOSO_PASS"] — never use dba!' unless PASSWORD

def sparql_update(query, label)
  uri  = URI(VIRTUOSO_URL)
  http = Net::HTTP.new(uri.host, uri.port)
  req  = Net::HTTP::Post.new(uri)
  req.basic_auth(USERNAME, PASSWORD)
  req['Content-Type'] = 'application/sparql-update'
  req['Accept']       = '*/*'
  req.body = query
  resp = http.request(req)
  if resp.code == '200'
    puts "✓ #{label}"
  else
    puts "✗ #{label} — HTTP #{resp.code}"
    puts resp.body.to_s[0..300]
    exit 1
  end
end

def sparql_select(query)
  uri  = URI(VIRTUOSO_URL)
  http = Net::HTTP.new(uri.host, uri.port)
  req  = Net::HTTP::Post.new(uri)
  req.basic_auth(USERNAME, PASSWORD)
  req['Content-Type'] = 'application/x-www-form-urlencoded'
  req['Accept']       = 'application/sparql-results+json'
  req.body = 'query=' + URI.encode_www_form_component(query)
  require 'json'
  JSON.parse(http.request(req).body)
end

puts '=== Fix 1: Remove TREAT_EXPANSIVE from all_metadata ==='

# Verify first
before = sparql_select(<<~SPARQL)
  PREFIX simp: <urn:simpathic:>
  SELECT (COUNT(*) AS ?n) WHERE {
    GRAPH <urn:simpathic:context:all_metadata> { ?g simp:source-relation "TREAT_EXPANSIVE" }
  }
SPARQL
count_before = before['results']['bindings'][0]['n']['value'].to_i
puts "  Before: #{count_before} TREAT_EXPANSIVE triples"

if count_before > 0
  sparql_update(<<~SPARQL, 'DELETE TREAT_EXPANSIVE triples')
    PREFIX simp: <urn:simpathic:>
    WITH <urn:simpathic:context:all_metadata>
    DELETE { ?g simp:source-relation "TREAT_EXPANSIVE" }
    WHERE  { ?g simp:source-relation "TREAT_EXPANSIVE" }
  SPARQL
else
  puts '  Nothing to delete.'
end

after = sparql_select(<<~SPARQL)
  PREFIX simp: <urn:simpathic:>
  SELECT (COUNT(*) AS ?n) WHERE {
    GRAPH <urn:simpathic:context:all_metadata> { ?g simp:source-relation "TREAT_EXPANSIVE" }
  }
SPARQL
count_after = after['results']['bindings'][0]['n']['value'].to_i
puts "  After:  #{count_after} TREAT_EXPANSIVE triples"
abort '  ERROR: TREAT_EXPANSIVE triples still present!' if count_after > 0

puts
puts '=== Fix 2: Correct HP_0002140 label in rad_HP_0002140_ENSG00000068024 ==='

BAD_GRAPH  = 'urn:simpathic:context:rad_HP_0002140_ENSG00000068024'
HP_URI     = 'http://purl.obolibrary.org/obo/HP_0002140'
BAD_LABEL  = 'no HPO match found for HP_0002140'
GOOD_LABEL = 'Ischemic stroke'

sparql_update(<<~SPARQL, 'Delete bad HP_0002140 label')
  PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
  DELETE { GRAPH <#{BAD_GRAPH}> { <#{HP_URI}> rdfs:label "#{BAD_LABEL}" } }
  WHERE  { GRAPH <#{BAD_GRAPH}> { <#{HP_URI}> rdfs:label "#{BAD_LABEL}" } }
SPARQL

sparql_update(<<~SPARQL, 'Insert correct HP_0002140 label')
  PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
  INSERT { GRAPH <#{BAD_GRAPH}> { <#{HP_URI}> rdfs:label "#{GOOD_LABEL}" } }
  WHERE  { SELECT * WHERE { } LIMIT 1 }
SPARQL

# Verify
check = sparql_select(<<~SPARQL)
  PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
  SELECT ?lbl WHERE { GRAPH <#{BAD_GRAPH}> { <#{HP_URI}> rdfs:label ?lbl } }
SPARQL
labels = check['results']['bindings'].map { |b| b['lbl']['value'] }
if labels == [GOOD_LABEL]
  puts "  Verified: label is now \"#{GOOD_LABEL}\""
elsif labels.include?(GOOD_LABEL) && !labels.include?(BAD_LABEL)
  puts "  Verified: label is \"#{GOOD_LABEL}\" (plus #{labels.size - 1} other label(s))"
elsif labels.include?(BAD_LABEL)
  abort "  ERROR: bad label still present! Labels found: #{labels.inspect}"
else
  puts "  Labels now: #{labels.inspect}"
end

puts
puts 'All fixes applied. Re-run build_ml_set.rb to regenerate the ML dump.'

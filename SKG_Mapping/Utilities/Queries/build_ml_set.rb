#!/usr/bin/env ruby
# fetch_ers.rb
# Fragments the full entity-relation query by biolink type pairs,
# submits each to the Virtuoso SPARQL endpoint, and concatenates
# all results into a single CSV.

require 'sparql/client'
require 'csv'

ENDPOINT = 'http://57.128.119.57:8890/sparql'.freeze
OUTPUT   = 'all_pairs_both_orientations_split_evidence.csv.large'.freeze

BIOLINK = 'https://w3id.org/biolink/vocab/'.freeze

TYPES = %w[Gene Protein Disease Phenotype Drug].freeze

# All ordered pairs (both orientations, no self-pairs)
PAIRS = TYPES.permutation(2).to_a.freeze

def query_for(type1, type2)
  <<~SPARQL
    PREFIX simp:     <urn:simpathic:>
    PREFIX rdf:      <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
    PREFIX rdfs:     <http://www.w3.org/2000/01/rdf-schema#>
    PREFIX biolink:  <#{BIOLINK}>

    SELECT ?entity1 ?entity1_name (\"#{type1}\" AS ?entity1_type)
           ?entity2 ?entity2_name (\"#{type2}\" AS ?entity2_type)
           (GROUP_CONCAT(DISTINCT ?rel;    SEPARATOR=" | ") AS ?rels)
           (GROUP_CONCAT(DISTINCT ?source; SEPARATOR=" | ") AS ?sources)
           ?evidence
    WHERE {
      GRAPH ?graph {
        ?entity1 ?p      ?entity2 .
        ?entity1 a       biolink:#{type1} .
        ?entity2 a       biolink:#{type2} .
        ?entity1 rdfs:label ?entity1_name .
        ?entity2 rdfs:label ?entity2_name .
      }
      ?graph simp:source-relation ?rel .
      ?graph simp:skg-source      ?source .
      ?graph simp:evidence ?evidence .
    }
    GROUP BY ?entity1 ?entity1_name ?entity2 ?entity2_name ?evidence
    ORDER BY ?entity1_name ?entity2_name
  SPARQL
end

client = SPARQL::Client.new(ENDPOINT, read_timeout: 3600)

COLUMNS = %w[entity1 entity1_name entity1_type entity2 entity2_name entity2_type evidence rels sources].freeze

total_rows  = 0
header_done = false

CSV.open(OUTPUT, 'w') do |csv|
  PAIRS.each_with_index do |(type1, type2), idx|
    label = "#{type1} → #{type2}"
    print "[#{idx + 1}/#{PAIRS.size}] #{label} ... "
    $stdout.flush

    begin
      results = client.query(query_for(type1, type2))
      rows    = results.to_a

      unless header_done
        csv << COLUMNS
        header_done = true
      end

      rows.each do |row|
        csv << COLUMNS.map { |col| row[col.to_sym]&.to_s }
      end

      total_rows += rows.size
      puts "#{rows.size} rows"
    rescue StandardError => e
      warn "\n  ERROR on #{label}: #{e.message} — skipping"
      `echo "#{label}: #{e.message}" >> errors.log`
    end
  end
end

puts "\nDone — #{total_rows} total rows written to #{OUTPUT}"
puts "Run: wc -l #{OUTPUT}  (should be #{total_rows + 1} including header)"

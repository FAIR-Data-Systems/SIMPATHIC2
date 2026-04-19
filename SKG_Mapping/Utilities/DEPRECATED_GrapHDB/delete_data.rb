#!/usr/bin/env ruby
require 'sparql/client'

# Configuration
VIRTUOSO_URL = "http://57.128.119.57:8890/sparql-auth"  # adjust as needed
USERNAME     = ENV["VIRTUOSO_USER"]                            # or your admin user
PASSWORD     = ENV["VIRTUOSO_PASS"]                  # or use token

client = SPARQL::Client.new(VIRTUOSO_URL,
  method: :post,
  basic_auth: [USERNAME, PASSWORD],
  headers: { 'Accept' => 'application/sparql-results+json' }
)

source_value = "DEMOKRITOS"
prefixes = <<~PREFIX
  PREFIX simp: <urn:simpathic:>
  PREFIX rdf:  <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX

# Step 1: Gather all named graphs coming from this source
# Step 1: Gather all named graphs - safer handling
query_graphs = <<~SPARQL
  #{prefixes}
  SELECT DISTINCT ?g
  WHERE {
    GRAPH ?g { ?s ?p ?o }
    ?g simp:skg-source "#{source_value}" .
  }
SPARQL

puts "Executing query:\n#{query_graphs}"

begin
  solutions = client.select(query_graphs)
abort
  graphs = solutions.map { |row| row[:g] }.compact  # .compact removes any nil entries
rescue => e
  puts "Error executing SELECT: #{e.class} - #{e.message}"
  abort
end

if graphs.empty?
  puts "No graphs found for source: #{source_value} (returned #{solutions.size} solutions)"
  abort
end

puts "Found #{graphs.size} named graph(s) from source #{source_value}"
abort


# Step 2: Delete annotations for these graphs (safest first)
graphs.each do |g|
  delete_annotations = <<~SPARQL
    #{prefixes}
    DELETE WHERE {
      ?s ?p ?o .
      FILTER(?s = <#{g}>)
    }
  SPARQL

  client.update(delete_annotations)
  puts "Deleted annotations for graph: #{g}"
end

# Step 3: DROP the graphs themselves
graphs.each do |g|
  drop_query = "DROP GRAPH <#{g}>"
  client.update(drop_query)
  puts "Dropped graph: #{g}"
end

puts "Operation completed successfully for source: #{source_value}"

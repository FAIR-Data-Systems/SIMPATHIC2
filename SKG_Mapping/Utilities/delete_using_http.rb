require 'net/http'
require 'uri'
require 'json'
require 'logger'

# Configuration
source_value = "DEMOKRITOS"
VIRTUOSO_URL = "http://57.128.119.57:8890/sparql"  # adjust as needed
USERNAME     = ENV["VIRTUOSO_USER"]                            # or your admin user
PASSWORD     = ENV["VIRTUOSO_PASS"]                  # or use token
abort 'Set ENV["VIRTUOSO_USER"] ENV["VIRTUOSO_PASS"] AND DO NOT USE dba!!' unless PASSWORD

warn "UN: #{USERNAME} #{PASSWORD}"
# Enable full HTTP-level debugging
http_logger = Logger.new(STDOUT)
http_logger.level = Logger::DEBUG


# SELECT helper (only for queries that return results)
def sparql_select(query)
  uri = URI(VIRTUOSO_URL)
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri)
  request.basic_auth(USERNAME, PASSWORD)
  request['Content-Type'] = 'application/x-www-form-urlencoded'
  request['Accept'] = 'application/sparql-results+json'
  request.body = "query=" + URI.encode_www_form_component(query)
  http.request(request)
end

# UPDATE / DELETE / DROP helper
# UPDATE / DELETE / DROP helper - CORRECTED for Virtuoso
def sparql_update(query)
  uri = URI(VIRTUOSO_URL)
  http = Net::HTTP.new(uri.host, uri.port)

  request = Net::HTTP::Post.new(uri)
  request.basic_auth(USERNAME, PASSWORD)
  request['Content-Type'] = 'application/sparql-update'
  request['Accept'] = '*/*'

  # CRITICAL: raw query as body, NO "update=" prefix, NO encoding
  request.body = query

  response = http.request(request)

  # Debug output
  puts "\n=== UPDATE RESPONSE ==="
  puts "Status: #{response.code} #{response.message}"
  puts "Content-Type: #{response['content-type'] || 'none'}"
  puts "Body (first 400 chars):"
  puts response.body.to_s[0..400]
  puts "---"

  response
end

# Step 1: Gather graphs
prefixes = <<~PREFIX
  PREFIX simp: <urn:simpathic:>
  PREFIX rdf:  <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX

query_graphs = <<~SPARQL
  #{prefixes}
  SELECT DISTINCT ?g
  WHERE {
    GRAPH ?g { ?s ?p ?o }
    ?g simp:skg-source "#{source_value}" .
  }
SPARQL

response = sparql_select(query_graphs)
data = JSON.parse(response.body)
graphs = data["results"]["bindings"].map { |b| b["g"]["value"] }

puts "Found #{graphs.size} named graph(s) from source #{source_value}"

if response.code != "200"
  puts "SELECT FAILED: #{response.code} - #{response.body[0..300]}"
  abort
end

data = JSON.parse(response.body)
graphs = data["results"]["bindings"].map { |b| b["g"]["value"] }



# Step 2: Delete annotations for each graph
# === Step 2: Delete annotations (least destructive first) ===
puts "\n=== Starting annotation deletion (#{graphs.size} graphs) ==="

while false do 
graphs.each do |g|
delete_ann = <<~SPARQL
    #{prefixes}
    WITH <simp:context:all_metadata>
    DELETE { <#{g}> ?p ?o . }
    WHERE  { <#{g}> ?p ?o . }
  SPARQL

  resp = sparql_update(delete_ann)

  if resp.code == "200"
    puts "✓ Deleted annotations for: #{g}"
  else
    puts "✗ FAILED annotation delete for #{g} - #{resp.code}"
    puts "   Body: #{resp.body.to_s[0..300]}"
    puts "   Stopping for safety."
    abort
  end
end
end

# === Step 3: DROP the graphs ===
puts "\n=== Starting DROP of #{graphs.size} graphs ==="

graphs.each do |g|
  drop_q = "DROP SILENT GRAPH <#{g}>"

  resp = sparql_update(drop_q)

  if resp.code == "200"
    puts "✓ Dropped graph: #{g}"
  else
    puts "✗ FAILED DROP for #{g} - #{resp.code}"
    puts "   Body: #{resp.body.to_s[0..300]}"
    puts "   Stopping for safety."
    abort
  end
end

puts "\n=== OPERATION COMPLETED SUCCESSFULLY for source: #{source_value} ==="
puts "Total graphs processed: #{graphs.size}"

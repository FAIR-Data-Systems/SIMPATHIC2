require 'net/http'
require 'uri'
require 'json'
require 'logger'

# THIS CODE IS FOR DELETING GRAPHS FROM A VIRTUOSO TRIPLE STORE VIA HTTP SPARQL ENDPOINT
# USAGE: ruby delete_using_http.rb <source_value>
# Purges all data from graphs that have the specified simp:skg-source value, including graph-level annotations in simp:context:all_metadata.

# Configuration
source_value = ARGV[0] || abort('Usage: ruby delete_using_http.rb <source_value>')
VIRTUOSO_URL = 'http://57.128.119.57:8890/sparql' # adjust as needed
USERNAME     = ENV['VIRTUOSO_USER'] # or your admin user
PASSWORD     = ENV['VIRTUOSO_PASS'] # or use token
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
  request.body = 'query=' + URI.encode_www_form_component(query)
  http.request(request)
end

# UPDATE / DELETE / DROP helper - CORRECTED for Virtuoso
# Retries on 503 up to MAX_RETRIES times with exponential backoff.
MAX_RETRIES = 5
RETRY_BASE_DELAY = 10 # seconds

def sparql_update(query)
  uri = URI(VIRTUOSO_URL)
  response = nil

  (1..MAX_RETRIES + 1).each do |attempt|
    begin
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Post.new(uri)
      request.basic_auth(USERNAME, PASSWORD)
      request['Content-Type'] = 'application/sparql-update'
      request['Accept'] = '*/*'

      # CRITICAL: raw query as body, NO "update=" prefix, NO encoding
      request.body = query

      response = http.request(request)
    rescue Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET => e
      if attempt <= MAX_RETRIES
        delay = RETRY_BASE_DELAY * (2**(attempt - 1))
        puts "  Network error: #{e.class} — retrying in #{delay}s (attempt #{attempt}/#{MAX_RETRIES})..."
        sleep delay
        next
      end
      raise
    end

    # Debug output
    puts "\n=== UPDATE RESPONSE ==="
    puts "Status: #{response.code} #{response.message}"
    puts "Content-Type: #{response['content-type'] || 'none'}"
    puts 'Body (first 400 chars):'
    puts response.body.to_s[0..400]
    puts '---'

    if response.code == '503' && attempt <= MAX_RETRIES
      delay = RETRY_BASE_DELAY * (2**(attempt - 1))
      puts "  503 received (attempt #{attempt}/#{MAX_RETRIES}). Retrying in #{delay}s..."
      sleep delay
      next
    end

    break
  end

  response
end

# === Step 1: Gather graphs
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
if response.code != '200'
  puts "SELECT FAILED: #{response.code} - #{response.body[0..300]}"
  abort
end
data = JSON.parse(response.body)
graphs = data['results']['bindings'].map { |b| b['g']['value'] }
puts "Found #{graphs.size} named graph(s) from source #{source_value}"

# ===  Step 2: Delete grap-level annotations, to ensure no dangling references remain before dropping the graphs ===
puts "\n=== Starting annotation deletion (#{graphs.size} graphs) ==="

failed_annotations = []
graphs.each do |g|
  delete_ann = <<~SPARQL
    #{prefixes}
    WITH <simp:context:all_metadata>
    DELETE { <#{g}> ?p ?o . }
    WHERE  { <#{g}> ?p ?o . }
  SPARQL

  resp = sparql_update(delete_ann)

  if resp.code == '200'
    puts "✓ Deleted annotations for: #{g}"
  else
    puts "✗ FAILED annotation delete for #{g} - #{resp.code} (logged, continuing)"
    puts "   Body: #{resp.body.to_s[0..300]}"
    failed_annotations << { graph: g, code: resp.code }
  end
end

# === Step 3: DELETE all triples from each graph (avoids DROP permission requirement) ===
puts "\n=== Starting content deletion of #{graphs.size} graphs ==="

failed_drops = []
graphs.each do |g|
  drop_q = <<~SPARQL
    DELETE { GRAPH <#{g}> { ?s ?p ?o } }
    WHERE  { GRAPH <#{g}> { ?s ?p ?o } }
  SPARQL

  resp = sparql_update(drop_q)

  if resp.code == '200'
    puts "✓ Cleared graph: #{g}"
  else
    puts "✗ FAILED clear for #{g} - #{resp.code} (logged, continuing)"
    puts "   Body: #{resp.body.to_s[0..300]}"
    failed_drops << { graph: g, code: resp.code }
  end
end

puts "\n=== OPERATION COMPLETED for source: #{source_value} ==="
puts "Total graphs processed: #{graphs.size}"

unless failed_annotations.empty?
  puts "\n⚠ #{failed_annotations.size} annotation deletion(s) FAILED:"
  failed_annotations.each { |f| puts "  #{f[:code]}  #{f[:graph]}" }
end

unless failed_drops.empty?
  puts "\n⚠ #{failed_drops.size} graph DROP(s) FAILED:"
  failed_drops.each { |f| puts "  #{f[:code]}  #{f[:graph]}" }
end

if failed_annotations.empty? && failed_drops.empty?
  puts 'All operations succeeded.'
else
  puts "\nRe-run the script with the same source_value to retry the failures above."
end

# === Step 4: Verify — re-run the original SELECT to confirm nothing remains ===
puts "\n=== Verification: checking for remaining graphs ==="
verify_response = sparql_select(query_graphs)
if verify_response.code == '200'
  remaining = JSON.parse(verify_response.body)['results']['bindings'].map { |b| b['g']['value'] }
  if remaining.empty?
    puts "✓ Confirmed: 0 graphs remain for source '#{source_value}'"
  else
    puts "⚠ #{remaining.size} graph(s) STILL EXIST after deletion:"
    remaining.each { |g| puts "  #{g}" }
    exit 1
  end
else
  puts "Verification SELECT failed: #{verify_response.code}"
  exit 1
end

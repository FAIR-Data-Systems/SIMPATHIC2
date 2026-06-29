require 'net/http'
require 'uri'
require 'json'

# Selectively deletes all Biovista drug-related named graphs from Virtuoso,
# plus their annotations in urn:simpathic:context:all_metadata.
#
# "Drug graphs" are identified as Biovista graphs that contain at least one
# entity typed as biolink:Drug. This covers Drug-Disease, Drug-Gene, and
# Drug-Phenotype graphs while leaving Disease-Gene, Disease-Phenotype, and
# Gene-Phenotype graphs intact.
#
# Usage:
#   ruby delete_bv_drug_graphs.rb
# Requires env vars:
#   VIRTUOSO_USER, VIRTUOSO_PASS  (never use dba)

VIRTUOSO_URL = 'http://57.128.119.57:8890/sparql'
USERNAME     = ENV['VIRTUOSO_USER']
PASSWORD     = ENV['VIRTUOSO_PASS']
abort 'Set ENV["VIRTUOSO_USER"] and ENV["VIRTUOSO_PASS"] — AND DO NOT USE dba!!' unless PASSWORD

MAX_RETRIES      = 5
RETRY_BASE_DELAY = 10

def sparql_select(query)
  uri  = URI(VIRTUOSO_URL)
  http = Net::HTTP.new(uri.host, uri.port)
  req  = Net::HTTP::Post.new(uri)
  req.basic_auth(USERNAME, PASSWORD)
  req['Content-Type'] = 'application/x-www-form-urlencoded'
  req['Accept']       = 'application/sparql-results+json'
  req.body = 'query=' + URI.encode_www_form_component(query)
  http.request(req)
end

def sparql_update(query)
  uri      = URI(VIRTUOSO_URL)
  response = nil

  (1..MAX_RETRIES + 1).each do |attempt|
    begin
      http = Net::HTTP.new(uri.host, uri.port)
      req  = Net::HTTP::Post.new(uri)
      req.basic_auth(USERNAME, PASSWORD)
      req['Content-Type'] = 'application/sparql-update'
      req['Accept']       = '*/*'
      req.body = query
      response = http.request(req)
    rescue Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET => e
      if attempt <= MAX_RETRIES
        delay = RETRY_BASE_DELAY * (2**(attempt - 1))
        puts "  Network error: #{e.class} — retrying in #{delay}s (attempt #{attempt}/#{MAX_RETRIES})..."
        sleep delay
        next
      end
      raise
    end

    if response.code == '503' && attempt <= MAX_RETRIES
      delay = RETRY_BASE_DELAY * (2**(attempt - 1))
      puts "  503 received (attempt #{attempt}/#{MAX_RETRIES}) — retrying in #{delay}s..."
      sleep delay
      next
    end
    break
  end
  response
end

# ── Step 1: Discover Biovista drug graphs ────────────────────────────────────
# A graph is a "drug graph" if it has skg-source "biovista" AND contains at
# least one entity typed as biolink:Drug.  Non-drug Biovista notebooks
# (Disease-Gene, Disease-Phenotype, Gene-Phenotype) never emit biolink:Drug
# triples, so they are safely excluded.

discover_query = <<~SPARQL
  PREFIX simp:     <urn:simpathic:>
  PREFIX biolink:  <https://w3id.org/biolink/vocab/>
  PREFIX rdf:      <http://www.w3.org/1999/02/22-rdf-syntax-ns#>

  SELECT DISTINCT ?g WHERE {
    ?g simp:skg-source "Biovista" .
    GRAPH ?g {
      ?entity rdf:type biolink:Drug .
    }
  }
SPARQL

puts '=== Step 1: Discovering Biovista drug graphs ==='
resp = sparql_select(discover_query)
abort "Discovery SELECT failed: #{resp.code}\n#{resp.body[0..400]}" unless resp.code == '200'

graphs = JSON.parse(resp.body)['results']['bindings'].map { |b| b['g']['value'] }
puts "Found #{graphs.size} Biovista drug graph(s)."
if graphs.empty?
  puts 'Nothing to delete.'
  exit 0
end

# ── Step 2: Delete annotations from all_metadata ─────────────────────────────
puts "\n=== Step 2: Deleting metadata annotations (#{graphs.size} graphs) ==="

failed_annotations = []
graphs.each_with_index do |g, idx|
  print "[#{idx + 1}/#{graphs.size}] Annotation: #{g[0..80]}... "
  $stdout.flush

  ann_q = <<~SPARQL
    WITH <urn:simpathic:context:all_metadata>
    DELETE { <#{g}> ?p ?o }
    WHERE  { <#{g}> ?p ?o }
  SPARQL

  r = sparql_update(ann_q)
  if r.code == '200'
    puts '✓'
  else
    puts "✗ (#{r.code})"
    failed_annotations << { graph: g, code: r.code, body: r.body.to_s[0..200] }
  end
end

# ── Step 3: Delete graph content ─────────────────────────────────────────────
puts "\n=== Step 3: Deleting graph content (#{graphs.size} graphs) ==="

failed_drops = []
graphs.each_with_index do |g, idx|
  print "[#{idx + 1}/#{graphs.size}] Content:    #{g[0..80]}... "
  $stdout.flush

  drop_q = <<~SPARQL
    DELETE { GRAPH <#{g}> { ?s ?p ?o } }
    WHERE  { GRAPH <#{g}> { ?s ?p ?o } }
  SPARQL

  r = sparql_update(drop_q)
  if r.code == '200'
    puts '✓'
  else
    puts "✗ (#{r.code})"
    failed_drops << { graph: g, code: r.code, body: r.body.to_s[0..200] }
  end
end

# ── Step 4: Verify ───────────────────────────────────────────────────────────
puts "\n=== Step 4: Verification ==="
verify_resp = sparql_select(discover_query)
if verify_resp.code == '200'
  remaining = JSON.parse(verify_resp.body)['results']['bindings'].map { |b| b['g']['value'] }
  if remaining.empty?
    puts '✓ Confirmed: 0 Biovista drug graphs remain.'
  else
    puts "⚠  #{remaining.size} graph(s) still exist after deletion:"
    remaining.each { |g| puts "  #{g}" }
    exit 1
  end
else
  puts "Verification SELECT failed: #{verify_resp.code}"
  exit 1
end

# ── Summary ──────────────────────────────────────────────────────────────────
puts "\n=== Summary ==="
puts "Graphs processed: #{graphs.size}"

unless failed_annotations.empty?
  puts "\n⚠  #{failed_annotations.size} annotation deletion(s) FAILED:"
  failed_annotations.each { |f| puts "  #{f[:code]}  #{f[:graph]}" }
end

unless failed_drops.empty?
  puts "\n⚠  #{failed_drops.size} content deletion(s) FAILED:"
  failed_drops.each { |f| puts "  #{f[:code]}  #{f[:graph]}" }
end

if failed_annotations.empty? && failed_drops.empty?
  puts 'All operations succeeded. Safe to upload new drug graphs.'
else
  puts "\nRe-run this script to retry the failures listed above."
  exit 1
end

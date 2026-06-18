require 'net/http'
require 'uri'
require 'json'

# Purge all partner data from Virtuoso.
#
# Deletes every named graph that is annotated in simp:context:all_metadata
# (i.e. every graph we uploaded), then clears simp:context:all_metadata itself.
# The simp:context:all_metadata graph is left in existence but empty — it will
# be repopulated when graphs are re-uploaded.
#
# DO NOT use the dba account. Virtuoso blocks SPARQL UPDATE from dba via the
# HTTP /sparql endpoint. Use a named user that has been granted SPARQL_UPDATE
# privilege in the Virtuoso conductor.
#
# Usage:
#   export VIRTUOSO_USER=<your-user>
#   export VIRTUOSO_PASS=<your-password>
#   ruby purge_all_graphs.rb

VIRTUOSO_URL     = 'http://57.128.119.57:8890/sparql'
USERNAME         = ENV['VIRTUOSO_USER']
PASSWORD         = ENV['VIRTUOSO_PASS']
ANNOTATION_GRAPH = 'urn:simpathic:context:all_metadata'

abort 'Set ENV["VIRTUOSO_USER"] and ENV["VIRTUOSO_PASS"] — AND DO NOT USE dba!!' \
  unless USERNAME && PASSWORD

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def sparql_select(query)
  uri = URI(VIRTUOSO_URL)
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri)
  request.basic_auth(USERNAME, PASSWORD)
  request['Content-Type'] = 'application/x-www-form-urlencoded'
  request['Accept']       = 'application/sparql-results+json'
  request.body = 'query=' + URI.encode_www_form_component(query)
  http.request(request)
end

def sparql_update(query)
  uri = URI(VIRTUOSO_URL)
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri)
  request.basic_auth(USERNAME, PASSWORD)
  request['Content-Type'] = 'application/sparql-update'
  request['Accept']       = '*/*'
  # CRITICAL for Virtuoso: raw query as body, no "update=" prefix, no encoding
  request.body = query
  response = http.request(request)
  puts "  Status: #{response.code} #{response.message}"
  puts "  Body: #{response.body.to_s[0..300]}" unless response.code == '200'
  response
end

def ok!(response, label)
  return if response.code == '200'

  puts "✗ FAILED: #{label}"
  puts "  Body: #{response.body.to_s[0..400]}"
  abort 'Stopping for safety.'
end

# ---------------------------------------------------------------------------
# Step 1: Discover all data graphs via simp:context:all_metadata
# ---------------------------------------------------------------------------

puts "=== Step 1: Querying #{ANNOTATION_GRAPH} for all data graphs ==="

discover_query = <<~SPARQL
      SELECT DISTINCT ?g
    WHERE {
      GRAPH ?g  { ?s ?p ?o }
  FILTER(CONTAINS(STR(?g), "simpathic"))
    }
    ORDER BY ?g
SPARQL

response = sparql_select(discover_query)
ok!(response, 'discover graphs SELECT')

data = JSON.parse(response.body)
graphs = data['results']['bindings'].map { |b| b['g']['value'] }

puts "Found #{graphs.size} data graph(s):"
graphs.each { |g| puts "  #{g}" }

if graphs.empty?
  puts 'Nothing to delete. Exiting.'
  exit 0
end

# ---------------------------------------------------------------------------
# Step 2: Clear simp:context:all_metadata in one shot
# ---------------------------------------------------------------------------

puts "\n=== Step 2: Clearing annotation graph <#{ANNOTATION_GRAPH}> ==="

clear_annotations = "CLEAR GRAPH <#{ANNOTATION_GRAPH}>"
resp = sparql_update(clear_annotations)
ok!(resp, "CLEAR <#{ANNOTATION_GRAPH}>")
puts '✓ Annotation graph cleared'

# ---------------------------------------------------------------------------
# Step 3: CLEAR all data graphs in parallel threads
#
# Virtuoso silently accepts chained SPARQL Update (;-separated) but does not
# execute them. One statement per request is required. We parallelise to
# compensate for the per-request overhead.
# ---------------------------------------------------------------------------

NUM_THREADS = 16

puts "\n=== Step 3: Clearing #{graphs.size} data graph(s) with #{NUM_THREADS} threads ==="

queue     = Queue.new
graphs.each { |g| queue << g }

mutex     = Mutex.new
completed = 0
failed    = []

workers = NUM_THREADS.times.map do
  Thread.new do
    loop do
      g = begin; queue.pop(true); rescue ThreadError; break; end

      uri     = URI(VIRTUOSO_URL)
      http    = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Post.new(uri)
      request.basic_auth(USERNAME, PASSWORD)
      request['Content-Type'] = 'application/sparql-update'
      request['Accept']       = '*/*'
      request.body            = "CLEAR GRAPH <#{g}>"
      resp                    = http.request(request)

      mutex.synchronize do
        completed += 1
        if resp.code == '200'
          print "\r  #{completed}/#{graphs.size} cleared..." if (completed % 100).zero?
        else
          failed << { graph: g, code: resp.code, body: resp.body.to_s[0..200] }
        end
      end
    end
  end
end

workers.each(&:join)
puts "\r  #{completed}/#{graphs.size} cleared.   "

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

puts "\n=== PURGE COMPLETE ==="
if failed.empty?
  puts "All #{graphs.size} graph(s) cleared successfully."
else
  puts "FAILED (#{failed.size}):"
  failed.each { |f| puts "  #{f[:code]} — #{f[:graph]}\n    #{f[:body]}" }
  exit 1
end

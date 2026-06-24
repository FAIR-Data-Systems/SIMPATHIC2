require 'net/http'
require 'uri'
require 'json'

# Purge all partner data from Virtuoso.
#
# Deletes every named graph that is annotated in simp:context:all_metadata
# (i.e. every graph we uploaded), then clears simp:context:all_metadata itself.
# Uses DELETE { GRAPH ... } WHERE { ... } rather than CLEAR/DROP because the
# SPARQL user account has write privilege but not DROP privilege on Virtuoso.
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
NUM_THREADS      = 16
MAX_RETRIES      = 5
RETRY_BASE_DELAY = 10 # seconds

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

def sparql_update_with_retry(query, label = '')
  (1..MAX_RETRIES + 1).each do |attempt|
    begin
      uri = URI(VIRTUOSO_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Post.new(uri)
      request.basic_auth(USERNAME, PASSWORD)
      request['Content-Type'] = 'application/sparql-update'
      request['Accept']       = '*/*'
      request.body = query
      response = http.request(request)

      if response.code == '503' && attempt <= MAX_RETRIES
        delay = RETRY_BASE_DELAY * (2**(attempt - 1))
        warn "  503 on #{label} (attempt #{attempt}/#{MAX_RETRIES}), retrying in #{delay}s..."
        sleep delay
        next
      end

      return response
    rescue Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET => e
      raise if attempt > MAX_RETRIES
      delay = RETRY_BASE_DELAY * (2**(attempt - 1))
      warn "  #{e.class} on #{label}, retrying in #{delay}s (attempt #{attempt}/#{MAX_RETRIES})..."
      sleep delay
    end
  end
end

def ok!(response, label)
  return if response.code == '200'
  puts "✗ FAILED: #{label} — #{response.code}"
  puts "  Body: #{response.body.to_s[0..400]}"
  abort 'Stopping for safety.'
end

# ---------------------------------------------------------------------------
# Step 1: Discover all data graphs (exclude the annotation graph itself)
# ---------------------------------------------------------------------------

puts "=== Step 1: Querying for all SKG data graphs ==="

discover_query = <<~SPARQL
  SELECT DISTINCT ?g
  WHERE {
    GRAPH ?g { ?s ?p ?o }
    FILTER(CONTAINS(STR(?g), "simpathic"))
    FILTER(?g != <#{ANNOTATION_GRAPH}>)
  }
  ORDER BY ?g
SPARQL

response = sparql_select(discover_query)
ok!(response, 'discover graphs SELECT')

data = JSON.parse(response.body)
graphs = data['results']['bindings'].map { |b| b['g']['value'] }

puts "Found #{graphs.size} data graph(s)."

# ---------------------------------------------------------------------------
# Step 2: Clear simp:context:all_metadata in one shot
# ---------------------------------------------------------------------------

puts "\n=== Step 2: Clearing annotation graph <#{ANNOTATION_GRAPH}> ==="

clear_annotations = <<~SPARQL
  WITH <#{ANNOTATION_GRAPH}>
  DELETE { ?s ?p ?o }
  WHERE  { ?s ?p ?o }
SPARQL

resp = sparql_update_with_retry(clear_annotations, 'clear annotation graph')
ok!(resp, "clear <#{ANNOTATION_GRAPH}>")
puts '✓ Annotation graph cleared'

exit 0 if graphs.empty?

# ---------------------------------------------------------------------------
# Step 3: DELETE all triples from each data graph using parallel threads.
#
# Uses DELETE { GRAPH <g> { ?s ?p ?o } } WHERE { ... } rather than CLEAR/DROP
# because our Virtuoso user has write but not DROP privilege.
# Virtuoso requires one SPARQL Update statement per HTTP request.
# ---------------------------------------------------------------------------

puts "\n=== Step 3: Deleting content of #{graphs.size} data graph(s) with #{NUM_THREADS} threads ==="

queue     = Queue.new
graphs.each { |g| queue << g }

mutex     = Mutex.new
completed = 0
failed    = []

workers = NUM_THREADS.times.map do
  Thread.new do
    loop do
      g = begin; queue.pop(true); rescue ThreadError; break; end

      delete_q = "DELETE { GRAPH <#{g}> { ?s ?p ?o } } WHERE { GRAPH <#{g}> { ?s ?p ?o } }"
      resp = sparql_update_with_retry(delete_q, g)

      mutex.synchronize do
        completed += 1
        if resp.code == '200'
          print "\r  #{completed}/#{graphs.size} cleared..." if (completed % 10).zero? || completed == graphs.size
        else
          failed << { graph: g, code: resp.code, body: resp.body.to_s[0..200] }
        end
      end
    end
  end
end

workers.each(&:join)
puts "\r  #{completed}/#{graphs.size} processed.   "

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

puts "\n=== PURGE COMPLETE ==="
if failed.empty?
  puts "All #{graphs.size} graph(s) cleared successfully."
else
  puts "✗ FAILED (#{failed.size} graph(s)):"
  failed.each { |f| puts "  #{f[:code]} — #{f[:graph]}\n    #{f[:body]}" }
  exit 1
end

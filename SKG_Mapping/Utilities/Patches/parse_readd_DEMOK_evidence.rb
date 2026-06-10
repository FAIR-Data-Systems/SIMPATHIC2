require 'sparql/client'
require 'rdf'
require 'tempfile'
require 'sparql/client'
require 'rdf'

ENDPOINT    = 'http://57.128.119.57:8890/sparql'
UPDATE_EP   = 'http://57.128.119.57:8890/sparql-auth'
SIMP        = RDF::Vocabulary.new('urn:simpathic:')
PUBMED_BASE = 'https://pubmed.ncbi.nlm.nih.gov/'
# VT_USER     = 'skg_loader'
# VT_PASS     = 'skg_loader'
VT_USER     = 'dba'
VT_PASS     = 'dba'

DRY_RUN = false

read_client = SPARQL::Client.new(ENDPOINT)

def sparql_update(sparql)
  tmp = Tempfile.new(['sparql_update', '.sparql'])
  tmp.write(sparql)
  tmp.flush

  cmd = [
    'curl', '-s', '-f',
    '-X', 'POST',
    UPDATE_EP,
    '--anyauth', # ← let curl negotiate auth type automatically
    '--user', "#{VT_USER}:#{VT_PASS}",
    '--data-urlencode', "update@#{tmp.path}"
  ]

  output = IO.popen(cmd, err: %i[child out]) { |io| io.read }
  raise "curl SPARQL UPDATE failed (exit #{$?.exitstatus}):\n#{output}" unless $?.exitstatus == 0

  output
ensure
  tmp.close
  tmp.unlink
end

def verify_literal(graph, literal, read_client)
  q = <<~SPARQL
    PREFIX simp: <urn:simpathic:>
    SELECT ?rel
    WHERE {
      GRAPH simp:context:all_metadata {
        <#{graph}> simp:evidence ?rel .
        FILTER(ISLITERAL(?rel))
      }
    }
  SPARQL
  results = read_client.query(q)
  puts '  DB literals for this graph:'
  results.each { |r| puts "    #{r[:rel].to_s.inspect}" }
  puts '  Our literal:'.ljust(25)
  puts "    #{literal.inspect}"
end

# --- 1. Fetch all graph/literal pairs where evidence is a string literal
audit_query = <<~SPARQL
  PREFIX simp: <urn:simpathic:>

  SELECT ?graph ?rel
  WHERE {
    GRAPH simp:context:all_metadata {
      ?graph simp:skg-source "DEMOKRITOS" .
      ?graph simp:evidence ?rel .
    }
    FILTER(ISLITERAL(?rel))
    FILTER(STRSTARTS(STR(?rel), "["))
  }
  ORDER BY ?graph
SPARQL

results = read_client.query(audit_query)
rows = results.to_a
puts "Found #{rows.count} string-literal evidence values to migrate\n\n"

rows.each_with_index do |row, i|
  graph   = row[:graph]
  literal = row[:rel].to_s

  # --- 2. Parse PMIDs
  pmids = literal
          .gsub(/[\[\]"\s]/, '')
          .split(',')
          .map { |tok| tok.split('_').first }
          .select { |id| id =~ /\A\d+\z/ }
          .uniq

  if pmids.empty?
    puts "[#{i + 1}/#{rows.count}] SKIPPED (no PMIDs parsed): #{literal}"
    next
  end

  pubmed_uris = pmids.map { |id| RDF::URI("#{PUBMED_BASE}#{id}") }

  puts "[#{i + 1}/#{rows.count}] Graph: #{graph}"
  puts "  Literal : #{literal}"
  puts "  → URIs  : #{pubmed_uris.map(&:to_s).join(', ')}"

  # --- 3. INSERT new PubMed URI triples into the metadata graph
  insert_triples = pubmed_uris.map do |uri|
    "<#{graph}> <#{SIMP.evidence}> <#{uri}> ."
  end.join("\n    ")

  insert_sparql = <<~SPARQL
    PREFIX simp: <urn:simpathic:>

    INSERT DATA {
      GRAPH <urn:simpathic:context:all_metadata> {
        #{insert_triples}
      }
    }
  SPARQL

  # --- 4. DELETE the string literal from the metadata graph
  escaped_literal = literal.gsub('\\', '\\\\').gsub('"', '\\"')

  delete_sparql = <<~SPARQL
    PREFIX simp: <urn:simpathic:>

    DELETE {
      GRAPH <urn:simpathic:context:all_metadata> {
        <#{graph}> simp:evidence ?rel .
      }
    }
    WHERE {
      GRAPH <urn:simpathic:context:all_metadata> {
        <#{graph}> simp:evidence ?rel .
        FILTER(ISLITERAL(?rel))
        FILTER(STRSTARTS(STR(?rel), "["))
      }
    }
  SPARQL

  begin
    sparql_update(insert_sparql)
    puts "  ✓ Inserted #{pubmed_uris.size} PubMed URI(s)"
    verify_literal(graph, literal, read_client)
    sparql_update(delete_sparql)
    puts '  ✓ Deleted string literal'
  rescue StandardError => e
    puts "  ✗ ERROR on graph #{graph}: #{e.message}"
    puts "    Literal was: #{literal}"
  end
end

puts "\nMIGRATION COMPLETE"

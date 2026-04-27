# frozen_string_literal: true

# nmdo-search: Semantic search over the Neuromuscular Disease Ontology
#
# Architecture:
#   - This Ruby/Sinatra app owns all business logic: OWL parsing, index building,
#     cosine similarity search, and the REST API.
#   - It delegates *only* the embedding computation to a small Python/FastEmbed
#     sidecar (http://embedder:5001), so you never need to touch Python.
#
# Endpoints:
#   GET  /health          → service status + index stats
#   GET  /search?q=...    → top-N semantically similar ontology terms
#   POST /reindex         → re-fetch the OWL and rebuild the index

require 'sinatra'
require 'net/http'
require 'json'
require 'nokogiri'
require 'logger'

# ── Configuration ─────────────────────────────────────────────────────────────

OWL_URL       = ENV.fetch('OWL_URL', 'https://raw.githubusercontent.com/NeuromuscularDisease/neuromuscular-disease-ontology/refs/heads/main/nmdo.owl')
EMBEDDER_URL  = ENV.fetch('EMBEDDER_URL', 'http://embedder:5001')
OLS4_BASE_URL = ENV.fetch('OLS4_BASE_URL', 'https://simpathic.services/ols4')
TOP_K         = ENV.fetch('TOP_K', '10').to_i
INDEX_FILE    = ENV.fetch('INDEX_FILE', '/data/index.json')

# ── Logger ────────────────────────────────────────────────────────────────────

LOGGER = Logger.new($stdout)
LOGGER.level = Logger::INFO

# ── OWL Parser ────────────────────────────────────────────────────────────────

module OwlParser
  OBO_NS       = 'http://purl.obolibrary.org/obo/'
  IAO_DEF      = 'http://purl.obolibrary.org/obo/IAO_0000115' # definition
  RDFS_LABEL   = 'http://www.w3.org/2000/01/rdf-schema#label'
  OBO_SYNONYM  = 'http://www.geneontology.org/formats/oboInOwl#hasExactSynonym'

  def self.parse(owl_xml)
    doc = Nokogiri::XML(owl_xml)
    doc.remove_namespaces!

    terms = []

    doc.xpath('//Class').each do |cls|
      iri = cls['about'] || cls['ID']
      next unless iri&.start_with?(OBO_NS) # only OBO namespace IRIs

      # rdfs:label — prefer English, fall back to any label
      labels = cls.xpath('label')
      label = labels.find { |l| l['lang'] == 'en' }&.text ||
              labels.first&.text
      next if label.nil? || label.strip.empty?

      # IAO:0000115 definition
      definition = cls.xpath('*').find { |n| n['resource'] == IAO_DEF }&.text ||
                   cls.xpath("*[local-name()='IAO_0000115']").first&.text

      # hasExactSynonym — useful for boosting search coverage
      synonyms = cls.xpath("*[local-name()='hasExactSynonym']").map(&:text)

      # Build the text we embed: label + definition (+ synonyms if present)
      # Richer text = better semantic matches
      parts = [label]
      parts << definition unless definition.nil? || definition.strip.empty?
      parts.concat(synonyms) unless synonyms.empty?
      embed_text = parts.join('. ')

      # Derive the URL-encoded IRI for OLS4 deep-linking
      # OLS4 double-encodes colons and slashes in the IRI path segment
      encoded_iri = URI.encode_www_form_component(
        URI.encode_www_form_component(iri)
      )

      # Infer which ontology prefix this term belongs to (MONDO, HP, ORDO, etc.)
      short_id = iri.sub(OBO_NS, '') # e.g. "MONDO_0010679"
      prefix   = short_id.split('_').first&.downcase # e.g. "mondo"

      next if definition&.downcase&.include?('obsolete') || label.downcase.include?('obsolete')

      terms << {
        iri: iri,
        short_id: short_id,
        prefix: prefix,
        label: label.strip,
        definition: definition&.strip,
        synonyms: synonyms,
        embed_text: embed_text,
        ols4_url: "#{OLS4_BASE_URL}/ontologies/#{prefix}/classes/#{encoded_iri}"
      }
    end

    LOGGER.info "Parsed #{terms.size} OBO-namespace classes from OWL"
    terms
  end
end

# ── Embedder Client ───────────────────────────────────────────────────────────

module EmbedderClient
  def self.embed(texts)
    uri  = URI("#{EMBEDDER_URL}/embed")
    body = { texts: texts }.to_json

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 10
    http.read_timeout = 120 # batch indexing can take a moment on CPU

    req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
    req.body = body

    resp = http.request(req)
    raise "Embedder error #{resp.code}: #{resp.body}" unless resp.code == '200'

    JSON.parse(resp.body)['embeddings']
  end

  def self.healthy?
    uri  = URI("#{EMBEDDER_URL}/health")
    resp = Net::HTTP.get_response(uri)
    resp.code == '200'
  rescue StandardError
    false
  end
end

# ── Vector Maths ──────────────────────────────────────────────────────────────

module VectorMath
  def self.cosine_similarity(a, b)
    dot = a.zip(b).sum { |x, y| x * y }
    norm_a = Math.sqrt(a.sum { |x| x * x })
    norm_b = Math.sqrt(b.sum { |x| x * x })
    return 0.0 if norm_a.zero? || norm_b.zero?

    dot / (norm_a * norm_b)
  end
end

# ── Index ─────────────────────────────────────────────────────────────────────

class TermIndex
  attr_reader :built_at, :term_count

  def initialize
    @terms      = []     # Array of term hashes (metadata)
    @embeddings = []     # Parallel array of embedding vectors
    @built_at   = nil
    @term_count = 0
    @mutex      = Mutex.new
  end

  def build!
    LOGGER.info "Fetching OWL from #{OWL_URL} ..."
    owl_xml = Net::HTTP.get(URI(OWL_URL))

    LOGGER.info 'Parsing OWL ...'
    terms = OwlParser.parse(owl_xml)

    LOGGER.info "Requesting embeddings for #{terms.size} terms ..."
    # Batch in chunks of 64 to be friendly to the CPU embedder
    all_embeddings = []
    terms.each_slice(64).with_index do |slice, i|
      LOGGER.info "  Embedding batch #{i + 1} / #{(terms.size / 64.0).ceil} ..."
      vecs = EmbedderClient.embed(slice.map { |t| t[:embed_text] })
      all_embeddings.concat(vecs)
    end

    @mutex.synchronize do
      @terms      = terms
      @embeddings = all_embeddings
      @built_at   = Time.now.utc.iso8601
      @term_count = terms.size
    end

    persist!
    LOGGER.info "Index built: #{@term_count} terms at #{@built_at}"
    self
  end

  def search(query, top_k: TOP_K)
    raise 'Index is empty — call /reindex first' if @embeddings.empty?

    query_vec = EmbedderClient.embed([query]).first

    scored = @mutex.synchronize do
      @terms.zip(@embeddings).map do |term, vec|
        score = VectorMath.cosine_similarity(query_vec, vec)
        { score: score, term: term }
      end
    end

    scored
      .sort_by { |r| -r[:score] }
      .first(top_k)
      .map do |r|
        {
          score: r[:score].round(4),
          iri: r[:term][:iri],
          short_id: r[:term][:short_id],
          prefix: r[:term][:prefix],
          label: r[:term][:label],
          definition: r[:term][:definition],
          synonyms: r[:term][:synonyms],
          ols4_url: r[:term][:ols4_url]
        }
      end
  end

  def ready?
    !@embeddings.empty?
  end

  # ── Persistence (optional but speeds up restarts dramatically) ────────────

  def persist!
    return unless INDEX_FILE && !INDEX_FILE.empty?

    FileUtils.mkdir_p(File.dirname(INDEX_FILE))
    File.write(INDEX_FILE, JSON.generate({
                                           built_at: @built_at,
                                           terms: @terms,
                                           embeddings: @embeddings
                                         }))
    LOGGER.info "Index persisted to #{INDEX_FILE}"
  rescue StandardError => e
    LOGGER.warn "Could not persist index: #{e.message}"
  end

  def load_from_disk!
    return false unless INDEX_FILE && File.exist?(INDEX_FILE)

    LOGGER.info "Loading index from #{INDEX_FILE} ..."
    data = JSON.parse(File.read(INDEX_FILE), symbolize_names: false)

    @mutex.synchronize do
      @terms      = data['terms'].map { |t| t.transform_keys(&:to_sym) }
      @embeddings = data['embeddings']
      @built_at   = data['built_at']
      @term_count = @terms.size
    end
    LOGGER.info "Loaded #{@term_count} terms from disk (built #{@built_at})"
    true
  rescue StandardError => e
    LOGGER.warn "Could not load index from disk: #{e.message}"
    false
  end
end

# ── Singleton index ───────────────────────────────────────────────────────────

INDEX = TermIndex.new

# ── Startup: try disk first, then build from scratch ─────────────────────────

Thread.new do
  # Wait for embedder to be ready (it may still be loading the model)
  LOGGER.info 'Waiting for embedder service ...'
  30.times do
    break if EmbedderClient.healthy?

    sleep 2
  end

  unless EmbedderClient.healthy?
    LOGGER.error 'Embedder did not become healthy — index will not be built automatically'
    next
  end

  unless INDEX.load_from_disk!
    LOGGER.info 'No persisted index found — building from scratch ...'
    INDEX.build!
  end
end

# ── Sinatra configuration ─────────────────────────────────────────────────────

set :bind,          '0.0.0.0'
set :port,          4567
set :show_exceptions, false
set :protection, host_authorization: {
  permitted_hosts: [
    'simpathic.services',
    'www.simpathic.services',
    '127.0.0.1',
    'localhost'
  ]
}

before do
  content_type 'application/json'
end

error do |e|
  status 500
  JSON.generate({ error: e.message })
end

# ── Routes ─────────────────────────────────────────────────────────────────────

# GET /health
get '/llm_search/health' do
  JSON.generate({
                  status: INDEX.ready? ? 'ready' : 'building',
                  term_count: INDEX.term_count,
                  built_at: INDEX.built_at,
                  embedder_online: EmbedderClient.healthy?
                })
end

# GET /search?q=myopathy&top_k=5
get '/llm_search/search' do
  q = params['q']&.strip
  halt 400, JSON.generate({ error: "Missing query parameter 'q'" }) if q.nil? || q.empty?
  halt 503, JSON.generate({ error: 'Index not ready yet — please retry shortly' }) unless INDEX.ready?

  top_k = (params['top_k'] || TOP_K).to_i.clamp(1, 50)
  results = INDEX.search(q, top_k: top_k)

  JSON.generate({
                  query: q,
                  top_k: top_k,
                  results: results
                })
end

# POST /reindex  — re-fetch OWL and rebuild (useful after ontology updates)
post '/llm_search/reindex' do
  Thread.new { INDEX.build! }
  status 202
  JSON.generate({ message: 'Reindex started in background. Poll /health to check progress.' })
end

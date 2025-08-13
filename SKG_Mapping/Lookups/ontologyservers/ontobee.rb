require 'json'
require 'linkeddata'

class Ontobee
  attr_accessor :uri, :ontobeeurl

  def initialize(uri:)
    @uri = uri
    # @synonym_urls = [uri]
    warn "#{@uri} isn't an Ontobee OBO URI, don't expect this to work!" unless @uri =~ /obolibrary\.org/
    @ontobeeurl = "https://ontobee.org/ontology/GO?iri=#{uri}"
  end

  def lookup_title
    title = nil
    if (graph = resolve_url_to_rdf(url: @ontobeeurl, accept: 'application/rdf+xml'))
      # warn "Ontobee graph size:  #{graph.size}"
      title = find_title_in_graph(graph: graph) if graph.size.positive?
    end
    title
  end

  def find_title_in_graph(graph:)
    title = nil
    # QUERY5 = "select ?title where {|||SUBJECT||| <http://www.w3.org/2000/01/rdf-schema#label> ?title .}"

    query = QUERY5.gsub('|||SUBJECT|||', "<#{@uri}>") # label query - use the original URI, not the ontobeeurl
    # warn "query:  #{query}"
    query = SPARQL.parse(query)
    graph.query(query) do |result|
      # warn "found title #{result[:title]}"
      title = result[:title] if result[:title]
    end
    unless title
      @uri.gsub!('https', 'http') # F'ing W3C!!  They screwed up the entire semantic web!
      query = QUERY5.gsub('|||SUBJECT|||', "<#{@uri}>") # label query
      # warn "query:  #{query}"
      query = SPARQL.parse(query)
      graph.query(query) do |result|
        # warn "found title #{result[:title]}"
        title = result[:title] if result[:title]
      end
    end
    title.to_s
  end
end

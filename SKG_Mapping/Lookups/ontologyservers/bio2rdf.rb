require "json"
require "linkeddata"

class Bio2RDF
  attr_accessor :uri

  def initialize(uri:)
    @uri = uri
    warn "#{@uri} isn't an Bio2RDF URI, don't expect this to work!" unless (@uri =~ %r{bio2rdf\.org})
  end

  def lookup_title
    title = nil
    if (graph = resolve_url_to_rdf(url: @uri, accept: "application/rdf+xml")) 
      title = find_title_in_graph(graph: graph) if graph.size > 0   
    end
    title
  end

  def find_title_in_graph(graph:)
    title = nil
    query = QUERY1.gsub("|||SUBJECT|||", "<#{uri}>")  # dcterms:title query
    query = SPARQL.parse(query)
    graph.query(query) do |result|
      warn "found title #{result[:title]}"
      title = result[:title] if result[:title]
    end
    title.to_s
  end
end

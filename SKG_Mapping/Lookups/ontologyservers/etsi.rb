require "json"
require "linkeddata"

class Etsi
  attr_accessor :uri

  def initialize(uri:)
    @uri = uri
    warn "#{@uri} isn't an ETSI  URI, don't expect this to work!" unless (@uri =~ %r{etsi\.org})
  end

  def lookup_title
    title = nil
    if (graph = resolve_url_to_rdf(url: @uri, accept: "text/turtle")) 
      title = find_title_in_graph(graph: graph) if graph.size > 0   
    end
    title
  end

  def find_title_in_graph(graph:)
    title = nil
    query = QUERY5.gsub("|||SUBJECT|||", "<#{uri}>")
    query = SPARQL.parse(query)
    graph.query(query) do |result|
      warn "found title #{result[:title]}"
      title = result[:title] if result[:title]
    end
    title.to_s
  end
end

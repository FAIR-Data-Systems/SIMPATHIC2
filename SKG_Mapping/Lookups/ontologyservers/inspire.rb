require "json"
require "linkeddata"

class Inspire
  attr_accessor :uri

  #inspire requires the addition of a suffix to get the rdf
  # https://inspire.ec.europa.eu/theme/ad  -->  http://inspire.ec.europa.eu/theme/ad/ad.en.rdf

  def initialize(uri:)
    warn "starting URI #{uri}"
    term = uri.match(%r{.*/(\S+?)$})[1] # e.g.  "ad"
    inspirerdf = "#{uri}/#{term}.en.rdf"  # returns rdfxml
    warn "INSPIRE #{inspirerdf}"
    @uri = inspirerdf
    warn "This isn't an inspire URI, don't expect this to work!" unless @uri =~ %r{/inspire\.io/}

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

require "json"
require "linkeddata"

class WFO
  attr_accessor :uri
  # wfo has content-negotiation on a particular style of identifier... make sure it is that style first

  def initialize(uri:)
    warn "starting URI #{uri}"
    if uri.match(%r{//list\.worldfloraonline})
      @uri = uri
    elsif term = uri.match(%r{worldfloraonline.org/taxon/(.*)})[1] # e.g.  "wfo-0000729203"
      @uri = "https://list.worldfloraonline.org/#{term}"
    else
      @uri = nil
    end
    warn "WFO #{@uri}"
    warn "This isn't an WFO URI, don't expect this to work!" unless @uri 

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
    query = QUERY6.gsub("|||SUBJECT|||", "<#{uri}>")  # wfo:fullName query
    query = SPARQL.parse(query)
    graph.query(query) do |result|
      warn "found title #{result[:title]}"
      title = result[:title] if result[:title]
    end
    title.to_s
  end
end


# @prefix wfo: <https://list.worldfloraonline.org/terms/> .
# @prefix dc: <http://purl.org/dc/terms/> .
# @prefix og: <http://ogp.me/ns#> .

# <https://list.worldfloraonline.org/wfo-0000615907-2024-06>
#   a wfo:TaxonConcept ;
#   wfo:classification <https://list.worldfloraonline.org/2024-06> ;
#   dc:replaces <https://list.worldfloraonline.org/wfo-0000615907-2023-12> ;
#   wfo:hasName <https://list.worldfloraonline.org/wfo-0000615907> ;
#   dc:references <http://www.theplantlist.org/tpl1.1/record/kew-2732230> .

# <https://list.worldfloraonline.org/wfo-0000615907>
#   a wfo:TaxonName ;
#   wfo:rank wfo:species ;
#   wfo:fullName "Comandra elliptica Raf." ;
#   wfo:authorship "Raf." ;
#   dc:creator "Raf." ;
#   wfo:genusName "Comandra" ;
#   wfo:publicationCitation "New Fl. 2: 33 (1837)" ;
#   wfo:isSynonymOf <https://list.worldfloraonline.org/wfo-0000615918-2018-07>, <https://list.worldfloraonline.org/wfo-0000615918-2019-03>, <https://list.worldfloraonline.org/wfo-0000615918-2019-05>, <https://list.worldfloraonline.org/wfo-0000615918-2021-12>, <https://list.worldfloraonline.org/wfo-0000615918-2022-06>, <https://list.worldfloraonline.org/wfo-0000615918-2022-12>, <https://list.worldfloraonline.org/wfo-0000615918-2023-06>, <https://list.worldfloraonline.org/wfo-0000615918-2023-12>, <https://list.worldfloraonline.org/wfo-0000615918-2024-06> ;
#   wfo:currentPreferredUsage <https://list.worldfloraonline.org/wfo-0000615918-2024-06> ;
#   dc:references <http://www.wikidata.org/entity/Q364857>, <https://www.ipni.org/n/780102-1>, <http://www.theplantlist.org/tpl1.1/record/kew-2732230>, <http://www.theplantlist.org/tpl/record/kew-2732230> .

# <http://www.wikidata.org/entity/Q364857>
#   dc:title "Constantine Samuel Rafinesque (1783-1840)" ;
#   dc:type "person" ;
#   dc:description "Based on occurrence of standard abbreviation 'Raf.' in the authors string." ;
#   og:image <http://commons.wikimedia.org/wiki/Special:FilePath/Rafinesque%20Constantine%20Samuel%201783-1840.png> .

# <https://www.ipni.org/n/780102-1>
#   dc:title "IPNI record: 780102-1" ;
#   dc:type "database" .

# <http://www.theplantlist.org/tpl1.1/record/kew-2732230>
#   dc:title "The Plant List v1.1 record kew-2732230" ;
#   dc:type "database" ;
#   dc:description "Based on the initial data import" .

# <http://www.theplantlist.org/tpl/record/kew-2732230>
#   dc:title "The Plant List version 1.0, record: kew-2732230" ;
#   dc:type "database" .

require "json"
require "linkeddata"

PARAMS = "?apikey=24e04058-54e0-11e0-9d7b-005056aa3316&format=json"

# http://data.bioontology.org/ontologies/SNOMEDCT/classes/http%3A%2F%2Fpurl.bioontology.org%2Fontology%2FSNOMEDCT%2F410607006
class NCBO
  attr_accessor :url

  def initialize(uri:)
    @uri = uri
    warn "#{@uri} isn't an NCBO  URI, don't expect this to work!" unless @uri =~ /bioontology\.org/

    root = "http://data.bioontology.org/ontologies/XXXXX/classes/"
    encoded = URI.encode_www_form_component uri
    begin
      ontologyid = uri.match(%r{/ontology/([^/]+)/})[1]  # match the ontology identifier
    rescue StandardError => e
      warn e.inspect
    end
    warn "ontology #{ontologyid}"
    if ontologyid =="LNC"  # stupidly change the abbreviation!
      @url = root.gsub("XXXXX", "LOINC") + encoded + PARAMS
    else
      @url = root.gsub("XXXXX", ontologyid) + encoded + PARAMS
    end
  end

  def lookup_title
    title = nil
    fullURL = "#{url}?#{PARAMS}" # add API key and json directive
    if (json = resolve_url_to_json(url: fullURL, accept: "application/json"))
      title = find_title_in_json(json: json)
    end
    title
  end

  def find_title_in_json(json:)
    return "" unless json
    json["prefLabel"]
  end
end

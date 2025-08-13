require "json"
require "linkeddata"

PARAMS = "?apikey=74027bd8-6be0-4329-be22-aa3717f97243&format=json"

# http://data.bioontology.org/ontologies/EDAM/classes/operation_3441?apikey=74027bd8-6be0-4329-be22-aa3717f97243&format=json

class EDAM
  attr_accessor :uri, :url

  def initialize(uri:)
    @uri = uri
    # http://edamontology.org/format_3790
    warn "#{@uri} isn't an EDAM URI, don't expect this to work!" unless @uri =~ /edamontology\.org/

    @uri = @uri.gsub(%r{https?://edamontology.org/}, "")

    @url = "http://data.bioontology.org/ontologies/EDAM/classes/" + @uri + PARAMS
  end

  def lookup_title
    title = nil
    if (json = resolve_url_to_json(url: @url, accept: "application/json"))
      title = find_title_in_json(json: json)
    end
    title
  end

  def find_title_in_json(json:)
    return "" unless json
    json["prefLabel"]
  end
end

require "json"
require "linkeddata"

class DOID
  attr_accessor :uri

  def initialize(uri:)
    @uri = uri
  end

  def lookup_title
    title = nil
    if (json = resolve_url_to_json(url: @uri, accept: "application/json"))
      title = find_title_in_json(json: json)
    end
    title
  end

  def find_title_in_json(json:)
    return "" unless json
    json["name"]
  end
end

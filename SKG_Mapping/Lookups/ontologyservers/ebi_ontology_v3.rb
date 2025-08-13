class EBIv3Term
  attr_accessor :uri, :url

  def initialize(uri:)
    @uri = uri
    root = "https://www.ebi.ac.uk/ols4/api/ontologies/XXXXX/YYYYY/"

    encoded = URI.encode_www_form_component uri

    url = root.gsub("XXXXX", "edam").gsub("YYYYY", "terms") + encoded if uri =~ /edamontology/
    @url = url
  end

  def lookup_title
    title = nil
    if (json = resolve_url_to_json(url: @url))
      title = find_title_in_json(json: json)
    end
    title
  end

  def find_title_in_json(json:)  # structure of this JSON is different
    return "" unless json
    json["_embedded"]["terms"][0]["label"]
  end
end

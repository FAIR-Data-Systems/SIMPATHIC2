class EBITerm
  attr_accessor :uri, :url

  def initialize(uri:)
    @uri = uri
    root = "https://www.ebi.ac.uk/ols4/api/ontologies/XXXXX/YYYYY/"

    encoded = URI.encode_www_form_component uri
    encoded = URI.encode_www_form_component encoded

    # this is so stupid... sometimes an ontology term is resolved using "terms" and sometimes using "properties"
    if uri =~ /NCIT_/
      url = root.gsub("XXXXX", "ncit") + encoded
    elsif uri =~ /HP_/   # this is the only one used right now
      url = root.gsub("XXXXX", "hp").gsub("YYYYY", "terms") + encoded
    elsif uri =~ /CHEMINF/   # this is the only one used right now
      url = root.gsub("XXXXX", "cheminf").gsub("YYYYY", "properties") + encoded
    elsif uri =~ /GO_/
      url = root.gsub("XXXXX", "go") + encoded
    elsif uri =~ /SIO_/
      url = root.gsub("XXXXX", "sio").gsub("YYYYY", "terms") + encoded
    elsif uri =~ /UBERON_/  # this works with version 4 API
      url = root.gsub("XXXXX", "uberon").gsub("YYYYY", "terms") + encoded
    elsif uri =~ /ORDO/  # this also works with the version 4 API with double-encoding 
      url = root.gsub("XXXXX", "ordo").gsub("YYYYY", "terms") + encoded
    elsif uri =~ /edamontology/  # this also works with the version 4 API with double-encoding 
      url = root.gsub("XXXXX", "edam").gsub("YYYYY", "terms") + encoded
    elsif uri =~ /DUO_/  # this also works with the version 4 API with double-encoding 
      url = root.gsub("XXXXX", "duo").gsub("YYYYY", "terms") + encoded
    elsif uri =~ /CMO_/
      url = root.gsub("XXXXX", "cmo") + encoded
    elsif uri =~ /EFO_/
      url = root.gsub("XXXXX", "efo").gsub("YYYYY", "terms") + encoded
    elsif uri =~ /MONDO_/
      url = root.gsub("XXXXX", "mondo").gsub("YYYYY", "terms") + encoded
    end
    warn "final URL is #{url}"
    @url = url

  end

  def lookup_title
    title = ""
    if (json = resolve_url_to_json(url: @url))
      title = find_title_in_json(json: json)
    end
    title
  end

  def find_title_in_json(json:)
    return "" unless json
    json["label"] || ""
  end
end

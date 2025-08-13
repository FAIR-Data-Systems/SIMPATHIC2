require 'json'
require 'rest-client'
require 'csv'

class NCBO
  attr_accessor :uri, :url

  PARAMS = "apikey=#{ENV['APIKEY']}&format=json".freeze

  def initialize()
  end

  def lookup_title_by_uri(term_uri:, ontology:)
    warn "#{term_uri} isn't an NCBO  URI, don't expect this to work!" unless term_uri =~ /bioontology\.org/
    root = "http://data.bioontology.org/ontologies/#{ontology}/classes/"
    encoded = URI.encode_www_form_component term_uri
    url = root + encoded
    warn "final URL is #{url}"

    fullurl = "#{url}?#{PARAMS}" # add API key and json directive
    json = RestClient.get(fullurl)
    _find_title_in_json(json: json)
  end

  def search_by_term(term:, ontology:, exact: true)
    # https://data.bioontology.org/search?q=MYOTONIC%20DYSTROPHY%20TYPE%201;ontologies=ORDO;require_exact_match=true
    term = URI.encode_www_form_component term
    options = "ontologies=#{ontology};require_exact_match=#{exact.to_s}"
    url_prefix = "https://data.bioontology.org/search"
    url = "#{url_prefix}?q=#{term};#{options};#{PARAMS}"
    warn "final URL #{url}"
    json = RestClient.get(url)
    _find_termid_in_json(json: json)
  end


  def get_synonyms_for_term(term:, ontology:, exact: true)
    # https://data.bioontology.org/search?q=MYOTONIC%20DYSTROPHY%20TYPE%201;ontologies=ORDO;require_exact_match=true
    term = URI.encode_www_form_component term
    options = "ontologies=#{ontology};require_exact_match=#{exact.to_s}"
    url_prefix = "https://data.bioontology.org/search"
    url = "#{url_prefix}?q=#{term};#{options};#{PARAMS}"
    warn "final URL #{url}"
    json = RestClient.get(url)
    _find_synonyms_in_json(json: json)
  end

  def _find_title_in_json(json:)
    j = JSON.parse(json)
    # warn j["prefLabel"]
    j['prefLabel']
  end

  def _find_synonyms_in_json(json:)
    j = JSON.parse(json)
    if j["totalCount"].to_i == 0
      warn "found no synonyms! returning empty list"
      return []
    end
    labels = [j["collection"][0]['prefLabel']]
    labels.concat j["collection"][0]['synonym']
    warn "found synonyms #{labels.inspect}"
    labels
  end

  def _find_termid_in_json(json:)
    j = JSON.parse(json)
    if j["totalCount"].to_i == 0
      warn "found no match! returning nil"
      return nil
    end
    id = j["collection"][0]["@id"]
    warn "found id #{id}"
    id
  end



end
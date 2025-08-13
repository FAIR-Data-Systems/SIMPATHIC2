require "json"
require "linkeddata"

class BioRegistry
  attr_accessor :uri, :synonym_urls

  def initialize(uri:)
    @uri = uri
    @synonym_urls = []
    warn "starting URI #{uri}"
    term = uri.match(%r{.*/(\S+?)$})[1] # edam:data_1153
    bioreg = "https://bioregistry.io/api/reference/#{term}"
    warn "BIOREG #{bioreg}"

    warn "This isn't an bioregistry.io URI, don't expect this to work!" unless @uri =~ %r{/bioregistry\.io/}
    begin
      response = RestClient.get(bioreg)
    # headers: {accept: "text/turtle, application/ld+json, application/rdf+xml"}
    rescue StandardError
      warn "#{uri} didn't resolve #{response}"
    end
    # return nil unless response
    json = JSON.parse(response.body)
    @synonym_urls = json["providers"].map do |providerid, providerurl|
      providerurl unless %w[bioregistry miriam].include? providerid
    end
    @synonym_urls.compact!
    @synonym_urls.reject!(&:empty?)
    warn "bioreg synonyms found: #{@synonym_urls}"
  end
end

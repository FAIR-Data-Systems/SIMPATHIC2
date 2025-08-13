require "json"
require "linkeddata"


class IDsOrg
  attr_accessor :uri, :synonym_urls

  def initialize(uri:)
    @uri = uri
    @synonym_urls = []
    warn "This isn't an Identifiers.org URI, don't expect this to work!" unless @uri =~ %r{/identifiers\.org/}
    # from http://identifiers.org/orphanet:156152
    # to
    # <https://resolver.api.identifiers.org/orphanet:156152
    @uri = @uri.gsub("/identifiers.org/", "/resolver.api.identifiers.org/")

    begin
      r = RestClient.get(@uri)
    # headers: {accept: "text/turtle, application/ld+json, application/rdf+xml"}
    rescue StandardError
      warn "#{uri} didn't resolve #{r}"
    end

    return unless r&.body

    json = JSON.parse(r.body)
    @synonym_urls = json["payload"]["resolvedResources"].map { |r| r["compactIdentifierResolvedUrl"] }
    @synonym_urls.compact!
    @synonym_urls.reject!(&:empty?)
    warn "bioreg synonyms found: #{@synonym_urls}"
  end
end

require "json"
require "linkeddata"


class SchemaOrg
  attr_accessor :uri, :term

  def initialize(uri:)
    @uri = uri
    @synonym_urls = []
    warn "This isn't an schema.org URI, don't expect this to work!" unless @uri =~ %r{/schema\.org/}

    begin
      a = JSON::LD::API.loadRemoteDocument(@uri)
    rescue StandardError
      warn "#{@uri} didn't resolve "
    end

    return unless a.document

    @term = a.document["rdfs:label"]

  end
end

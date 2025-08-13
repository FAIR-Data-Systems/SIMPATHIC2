class REACTOME
  attr_accessor :uri, :reaction

  def initialize(uri:)  # comes in as either uri or just the molecular id
    @uri = uri
    unless uri =~ /^http/
      @uri = "http://identifiers.org/reactome/#{uri}"
      @reaction = uri
    else
      @uri = uri
      @reaction = @uri.match(/.*\/(\w+)$/)[1]
    end
  end

  def lookup_title
    title = ""
    json = RestClient.get("https://reactome.org/ContentService/data/query/#{reaction}")
    begin
      parsed = JSON.parse(json)
    rescue StandardError => e
      warn e.inspect
      return title  # give up
    end
    parsed["displayName"]
  end

end

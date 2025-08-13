
LABELQUERY = "PREFIX chembl: <http://rdf.ebi.ac.uk/terms/chembl#>
PREFIX dcterms: <http://purl.org/dc/terms/>
select distinct ?label ?type WHERE{ 
  <http://rdf.ebi.ac.uk/resource/chembl/molecule/|||MOLECULE|||> <http://www.w3.org/2004/02/skos/core#prefLabel> ?label ;
     a ?type
}"


class CHEMBL
  attr_accessor :uri, :molecule

  def initialize(uri:)  # comes in as either uri or just the molecular id
    @uri = uri
    unless uri =~ /^http/
      @uri = "http://rdf.ebi.ac.uk/resource/chembl/molecule/#{uri}"
      @molecule = uri
    else
      @uri = uri
      @molecule = @uri.match(/.*\/(\w+)$/)[1]
    end
  end

  def lookup_title
    title = ""
    sparql = SPARQL::Client.new("https://chemblmirror.rdf.bigcat-bioinformatics.org/sparql")

    retry_attempts = 1
    begin
      result = sparql.query(LABELQUERY.gsub("|||MOLECULE|||", @molecule),
      read_timeout: 300, # 5 minutes
      open_timeout: 60   # 1 minute
      )
    rescue StandardError => e
      warn e.inspect
      retry_attempts += 1
      if retry_attempts < 10
        retry
      else
        puts "Timeout error"
        abort
      end
    end

    result.each do |res|  # first to get the recommended label
      title = res[:label].to_s
    end
    title
  end

  def lookup_title_and_type
    title = ""
    thistype = ""
    sparql = SPARQL::Client.new("https://chemblmirror.rdf.bigcat-bioinformatics.org/sparql")

    retry_attempts = 1
    begin
      result = sparql.query(LABELQUERY.gsub("|||MOLECULE|||", @molecule),
      read_timeout: 300, # 5 minutes
      open_timeout: 60   # 1 minute
      )
    rescue StandardError => e
      warn e.inspect
      retry_attempts += 1
      if retry_attempts < 10
        retry
      else
        puts "Timeout error"
        abort
      end
    end

    result.each do |res|  # first to get the recommended label
      title = res[:label].to_s
      thistype = res[:type].to_s
    end
    [title, thistype]
  end

end

require_relative '../Lookups/metadata_functions'
require 'csv'

# lookup = NCBO.new
f = File.open('./SKG_Mapping/radboud/diseaseID-mappings.csv', 'w')
e = File.open('./SKG_Mapping/radboud/diseaseID-errors.txt', 'w')
f.sync = true # Ensure immediate writes
e.sync = true # Ensure immediate writes
f.write "radboudid,guid,label\n"

seen = {}
CSV.foreach('./SKG_Mapping/radboud/rawdata/disease-gene.csv', headers: true) do |row|
  next if row.size < 3

  source = row[0]
  ontology = source.match(/([^_]+)_/)[1]
  next if seen[ontology]
  seen[ontology]= 1

  if ontology == "EFO"
    url = "http://www.ebi.ac.uk/efo/#{source}"
  elsif ontology == "OTAR"
    url = "http://www.ebi.ac.uk/efo/#{source}"
  elsif ontology == "DOID"
    url = "https://api.disease-ontology.org/v1/terms/#{source}"
  elsif ontology == "Orphanet"
    url = "http://www.orpha.net/ORDO/#{source}"
  else
    url = "http://purl.obolibrary.org/obo/#{source}"
  end

  title = ontology_annotations(uri: url)
  # lookup.lookup_title_by_uri(term_uri: url, ontology: ontology)
  if title
    warn "#{source}, #{url}, #{title}"
    f.write CSV.generate_line([source, url, title])
  else
    warn "No match for #{source}, #{url}"
    e.write "No match for #{source}, #{url}"
  end
end

f.close
e.close
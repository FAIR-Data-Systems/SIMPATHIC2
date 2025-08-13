require 'json'
require 'rest-client'
require './obo.rb'
require 'csv'

abort "\n\nusage:  ruby lookup.rb ONTOLOGY inputfile.csv COLNUMBER > output.csv\n\n" unless ARGV[0] && ARGV[1] && ARGV[2]
abort "\n\nusage:  You must set your OBO API key in the APIKEY environment variable\n\n" unless ENV['APIKEY']

ONTOLOGY = ARGV[0]
CSVFILE = ARGV[1]
COLUMN = ARGV[2].to_i
@seen = {}
File.readlines(CSVFILE, chomp: true).each do |line|
#CSV.foreach(CSVFILE) do |row|
  row = line.split("\t")
  next unless row[COLUMN + 1] == "Disease"
  value = row[COLUMN]
  value.strip!
  next if @seen[value]
  warn "looking for #{value}"
  if value.empty?
    warn "no value found in the column"
    next
  end
  n = NCBO.new()
  uri = n.search_by_term(term: value, ontology: ONTOLOGY, exact: true)
  unless uri  # backup plan
    synonyms = n.get_synonyms_for_term(term: value, ontology: "MESH", exact: true) # returns list
    synonyms.each do |syn|
      uri = n.search_by_term(term: syn, ontology: ONTOLOGY, exact: true)
      break if uri
    end
  end
  unless uri  # give up
    puts "No URI found for #{value}"
  else
    puts "#{uri},#{value}"
  end
  @seen[value] = 1
end

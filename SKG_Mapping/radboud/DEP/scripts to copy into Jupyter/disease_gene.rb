require_relative '../Lookups/uniprot'
require 'csv'

# warn `pwd`
# abort
u = UNIPROT.new
f = File.open('./SKG_Mapping/radboud/ENSG-UP-mappings.csv', 'w')
e = File.open('./SKG_Mapping/radboud/ENSG-UP-errors.txt', 'w')
f.sync = true # Ensure immediate writes
e.sync = true # Ensure immediate writes
f.write "source,ensembl,uniprot,taxon,prefname\n"
batch = []
sources = []

CSV.foreach('./SKG_Mapping/radboud/rawdata/disease-gene.csv', headers: true) do |row|
  next if row.size < 3

  source = row[0]
  target = row[2] || ''

  # Collect source and target for the batch
  batch << target
  sources << source

  # Process batch when it reaches 100 or at the end
  if batch.size >= 100
    # Search for all targets in the batch
    results = u.search_by_ensgene(ensg: batch)

    # Process each result with corresponding source and tar    
    results.each_with_index do |result, i|
      ensgene, protein, tax, recommended_full = result || [nil, nil, nil, nil]
      unless protein
        warn "Failed to fetch data for #{batch[i]}"
        e.write "Failed to fetch data for #{batch[i]}"
        next
      end

      warn "#{sources[i]}, #{ensgene}, #{protein}"
      f.write CSV.generate_line([sources[i], batch[i], ensgene, protein, tax, recommended_full])
    end

    # Clear batch and sources for the next set
    batch.clear
    sources.clear
  end
end

# Process any remaining rows in the batch
unless batch.empty?
  results = u.search_by_ensgene(ensg: batch)
  results.each_with_index do |result, i|
    ensgene, protein, tax, recommended_full = result || [nil, nil, nil, nil]
    unless protein
      warn "Failed to fetch data for #{batch[i]}"
      next
    end

    warn "#{sources[i]}, #{protein}"
    f.write CSV.generate_line([sources[i], batch[i], ensgene, protein, tax, recommended_full])
  end
end
f.close

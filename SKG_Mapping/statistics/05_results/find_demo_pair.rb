require 'set'
path = 'SEPT_all_pairs_both_orientations_split_evidence.csv.large'
pair_sources = Hash.new { |h,k| h[k] = Set.new }
pair_names = {}
count = 0
File.foreach(path, encoding: 'utf-8').with_index do |line, i|
  next if i == 0
  cols = line.chomp("\n").split("\t", -1)
  e1, n1, t1, e2, n2, t2, rels, sources, = cols
  next unless (t1 == 'Drug' && t2 == 'Disease') || (t1 == 'Disease' && t2 == 'Drug')
  drug_uri, drug_name, disease_uri, disease_name = t1 == 'Drug' ? [e1,n1,e2,n2] : [e2,n2,e1,n1]
  key = [drug_uri, disease_uri]
  sources.to_s.split('|').each { |s| pair_sources[key] << s.strip }
  pair_names[key] = [drug_name, disease_name]
end

candidates = pair_sources.select { |k, v| v.include?('Demokritos') && v.include?('Biovista') }
puts "Found #{candidates.size} Drug-Disease pairs with both Demokritos and Biovista evidence"
candidates.first(20).each do |k, v|
  puts "#{pair_names[k].join(' <-> ')}  sources=#{v.to_a}"
end

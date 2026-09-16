#!/usr/bin/env ruby
# For each partner, extracts the distinct entity IDs referenced in
# entity-mapping-stage error files vs. relation-graphing-stage error files,
# and reports how many graphing-stage IDs are/aren't explained by a known
# mapping-stage failure. Read-only against SKG_Mapping.
#
# IMPORTANT: entity-mapping error file formats vary per file (not just per
# partner) -- a generic "last whitespace token" heuristic silently produces
# wrong IDs on lines with trailing parentheticals (Biovista:
# "No PubChem CID found for D013482 (Superoxide Dismutase)") or embedded
# names after the ID (Demokritos: "failed compound name to cid lookup for
# XREF C0000477 Dalfampridine-containing product"). Each file format below
# is handled explicitly and was spot-checked against real lines.
require 'json'
require 'set'

root = ARGV[0] or abort "usage: compare_mapping_vs_graphing_errors.rb <SKG_Mapping root>"

def read(root, rel)
  File.readlines(File.join(root, rel), encoding: 'utf-8')
rescue Errno::ENOENT
  []
end

# --- Entity-mapping-stage extractors (format-specific) ---

def ids_radboud_diseases_errors(lines)
  # "found no mondo for EFO_0000174" / "found no mondo label for MONDO_..." / "found no results for ..."
  lines.map { |l| l.strip.split(' ').last }.compact
end

def ids_radboud_drugs_biologics_errors(lines)
  # "failed again for CHEMBL2108222"
  lines.map { |l| l.strip.split(' ').last }.compact
end

def ids_demokritos_gene_errors(lines)
  # "error getting C0002085"
  lines.map { |l| l.strip.split(' ').last }.compact
end

def ids_demokritos_phenotype_errors(lines)
  # "not_found\tUMLS:C0422837\tName"
  lines.filter_map { |l| l.split("\t")[1]&.sub(/^UMLS:/, '') }
end

def ids_demokritos_drug_errors(lines)
  # "failed compound name to cid lookup for XREF C0000477 Dalfampridine-containing product"
  # "failed UMLS to cid lookup for C5544328"
  lines.filter_map do |l|
    if (m = l.match(/XREF\s+(\S+)/))
      m[1]
    elsif (m = l.match(/for\s+(\S+)\s*$/))
      m[1]
    end
  end
end

def ids_demokritos_unmapped_diseases(lines)
  # CSV with header: "demokritos_umls,prefname,mondo"
  lines.drop(1).filter_map { |l| l.split(',').first&.strip }
end

def ids_biovista_drugs_errors(lines)
  # "No PubChem CID found for D013482 (Superoxide Dismutase)"
  # "4901d7c1b4e2aef6913d880bfc91240e ERROR mesh_fetch_failed"
  lines.filter_map do |l|
    if (m = l.match(/for\s+(\S+)\s*\(/))
      m[1]
    elsif (m = l.match(/^(\S+)\s+ERROR/))
      m[1]
    end
  end
end

def ids_biovista_drugs_biologics_errors(lines)
  # "No SID found for D013482 (Superoxide Dismutase)"
  lines.filter_map { |l| (m = l.match(/for\s+(\S+)\s*\(/)) && m[1] }
end

# --- Graphing-stage extractor (uniform across partners, both formats) ---

def ids_graphing_errors(lines)
  lines.filter_map do |l|
    l = l.chomp
    next unless l.include?('lookup failed')
    if l.include?("\t")
      parts = l.split("\t")
      (parts[1] || '').sub(/^UMLS:/, '')
    else
      l.split(' ').last
    end
  end.reject(&:empty?)
end

mapping_ids = {
  'Radboud' => (ids_radboud_diseases_errors(read(root, 'radboud/maps/diseases-errors.txt')) +
                ids_radboud_drugs_biologics_errors(read(root, 'radboud/maps/drugs-biologics-errors.txt'))),
  'Demokritos' => (ids_demokritos_gene_errors(read(root, 'demokritos/maps/2026-gene-errors.txt')) +
                   ids_demokritos_phenotype_errors(read(root, 'demokritos/maps/2026-phenotype-mapping-errors.txt')) +
                   ids_demokritos_drug_errors(read(root, 'demokritos/maps/2026-drug-mapping-errors.txt')) +
                   ids_demokritos_unmapped_diseases(read(root, 'demokritos/maps/2026-unmapped-diseases.csv'))),
  'Biovista' => (ids_biovista_drugs_errors(read(root, 'biovista/maps/2026-biovista-drugs-errors')) +
                 ids_biovista_drugs_biologics_errors(read(root, 'biovista/maps/2026-biovista-drugs-biologics-errors')))
}

graphing_files = {
  'Radboud' => Dir.glob(File.join(root, 'radboud/graph/*errors*.txt')),
  'Demokritos' => Dir.glob(File.join(root, 'demokritos/graph/*errors*.txt')),
  'Biovista' => Dir.glob(File.join(root, 'biovista/graph/*errors*.txt'))
}

results = {}
%w[Radboud Demokritos Biovista].each do |partner|
  mapping_set = Set.new(mapping_ids[partner])
  graphing_lines = graphing_files[partner].flat_map { |f| File.readlines(f, encoding: 'utf-8') }
  graphing_all = ids_graphing_errors(graphing_lines)
  graphing_set = Set.new(graphing_all)
  explained = graphing_set & mapping_set
  unexplained = graphing_set - mapping_set

  results[partner] = {
    mapping_distinct_failed_ids: mapping_set.size,
    graphing_distinct_failed_ids: graphing_set.size,
    graphing_explained_by_mapping_failure: explained.size,
    graphing_unexplained_never_attempted: unexplained.size,
    graphing_total_error_lines: graphing_all.size,
    sample_unexplained_ids: unexplained.to_a.first(10)
  }
end

puts JSON.pretty_generate(results)

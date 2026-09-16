#!/usr/bin/env ruby
# True count of "missing triples": for each partner's graphing notebook
# (== one output .nq.large graph), replicate its exact candidate-row filter
# and its exact success/failure lookup logic (read from notebook source,
# not assumed), then missing = candidate_rows - successful_rows. Summed per
# partner across all its graphing notebooks. Read-only.
require 'csv'
require 'set'
require 'json'

root = ARGV[0] or abort "usage: count_missing_triples.rb <SKG_Mapping root>"

def load_set(path, key)
  s = Set.new
  CSV.foreach(path, headers: true) { |row| s << row[key] if row[key] }
  s
end

def load_tsv_set(path, key)
  s = Set.new
  CSV.foreach(path, headers: true, col_sep: "\t") { |row| s << row[key] if row[key] }
  s
end

results = {}

# ============================== DEMOKRITOS ==============================
dk = File.join(root, 'demokritos')
d_disease = load_set(File.join(dk, 'maps/2026-demokritos-disease-mondo.map'), 'demokritos_umls')
d_gene    = load_set(File.join(dk, 'maps/2026-gene-mappings.map'), 'source')
d_drug    = load_set(File.join(dk, 'maps/2026-drug-mappings.map'), 'demokritosid')
d_pheno   = load_tsv_set(File.join(dk, 'maps/cui_hpo_lookup.tsv'), 'CUI')

dk_type_sets = { 'Disease' => d_disease, 'Gene' => d_gene, 'Drug' => d_drug, 'Phenotype' => d_pheno }

dk_files = %w[
  Disease-Drug Disease-Gene Disease-Phenotype
  Drug-Disease Drug-Gene Drug-Phenotype
  Gene-Disease Gene-Drug Gene-Phenotype
  Phenotype-Disease Phenotype-Drug Phenotype-Gene
]

dk_candidates = 0
dk_missing = 0
dk_per_file = {}
dk_files.each do |pair|
  t1, t2 = pair.split('-')
  path = File.join(dk, "raw-data/#{pair} triples.tsv")
  next unless File.exist?(path)
  set1, set2 = dk_type_sets[t1], dk_type_sets[t2]
  cand = 0
  miss = 0
  CSV.foreach(path, headers: true, col_sep: "\t", quote_char: "\x00", liberal_parsing: true) do |row|
    id1 = row[0] && row[1] # header: Type1, Type1_id, RELATION, PROVENANCE, Type2, Type2_id
    # use positional access since header names vary (Disease/Disease1/Gene1 etc.)
    id1 = row[1]
    id2 = row[5]
    cand += 1
    miss += 1 unless (set1.include?(id1) && set2.include?(id2))
  end
  dk_candidates += cand
  dk_missing += miss
  dk_per_file[pair] = { candidates: cand, missing: miss }
end
results['Demokritos'] = { candidate_triples: dk_candidates, missing_triples: dk_missing, per_file: dk_per_file }

# ============================== RADBOUD ==============================
rb = File.join(root, 'radboud')
r_disease = load_set(File.join(rb, 'maps/diseases.map'), 'source')
r_drug    = load_set(File.join(rb, 'maps/drugs.map'), 'chembl')
r_gene    = load_set(File.join(rb, 'maps/genes.map'), 'sourceid')

rb_per_notebook = {}

# 1. Disease-Gene: rawdata/disease-gene.csv, ALL rows (source=disease, target=gene)
cand = 0; miss = 0
CSV.foreach(File.join(rb, 'rawdata/disease-gene.csv'), headers: true) do |row|
  cand += 1
  miss += 1 unless (r_disease.include?(row['source']) && r_gene.include?(row['target']))
end
rb_per_notebook['Disease-Gene'] = { candidates: cand, missing: miss }

# 2. Drug-Disease: rawdata/drug-disease.csv, ALL rows (source=drug, target=disease)
# NOTE: rows where target is HP_-prefixed are really phenotypes (handled separately
# by Drug-Phenotype below) but this notebook does NOT filter them out, so they
# genuinely appear as failed "disease" lookups in the real pipeline -- replicated faithfully.
cand = 0; miss = 0
CSV.foreach(File.join(rb, 'rawdata/drug-disease.csv'), headers: true) do |row|
  cand += 1
  miss += 1 unless (r_drug.include?(row['source']) && r_disease.include?(row['target']))
end
rb_per_notebook['Drug-Disease'] = { candidates: cand, missing: miss }

# 3. Drug-Gene: rawdata/drug-gene.csv, ALL rows
cand = 0; miss = 0
CSV.foreach(File.join(rb, 'rawdata/drug-gene.csv'), headers: true) do |row|
  cand += 1
  miss += 1 unless (r_drug.include?(row['source']) && r_gene.include?(row['target']))
end
rb_per_notebook['Drug-Gene'] = { candidates: cand, missing: miss }

# 4. Drug-Phenotype: rawdata/drug-disease.csv, filtered to target =~ /HP_/. Only drug checked
# (phenotype side is used as-is, no lookup/failure possible per notebook source).
cand = 0; miss = 0
CSV.foreach(File.join(rb, 'rawdata/drug-disease.csv'), headers: true) do |row|
  next unless row['target'] =~ /HP_/
  cand += 1
  miss += 1 unless r_drug.include?(row['source'])
end
rb_per_notebook['Drug-Phenotype'] = { candidates: cand, missing: miss }

# 5. Phenotype-Gene: rawdata/disease-gene.csv, filtered to source =~ /HP_/. Only gene checked.
cand = 0; miss = 0
CSV.foreach(File.join(rb, 'rawdata/disease-gene.csv'), headers: true) do |row|
  next unless row['source'] =~ /HP_/
  cand += 1
  miss += 1 unless r_gene.include?(row['target'])
end
rb_per_notebook['Phenotype-Gene'] = { candidates: cand, missing: miss }

results['Radboud'] = {
  candidate_triples: rb_per_notebook.values.sum { |v| v[:candidates] },
  missing_triples: rb_per_notebook.values.sum { |v| v[:missing] },
  per_file: rb_per_notebook
}

# ============================== BIOVISTA ==============================
bv = File.join(root, 'biovista')
source_path = File.join(bv, 'raw_data/bv-kg-20260617.large')

b_disease = load_set(File.join(bv, 'maps/2026-biovista-disease-mondo.map'), 'biovista_umls')
b_drug_suffixes = Set.new
CSV.foreach(File.join(bv, 'maps/2026-biovista-drugs.map'), headers: true) do |row|
  if row['biovista_meshid'] =~ %r{/([^/]+)$}
    b_drug_suffixes << Regexp.last_match(1)
  end
end
b_gene = load_set(File.join(bv, 'maps/2025-biovista-genes.map'), 'bv_geneid')

bv_per_notebook = Hash.new { |h, k| h[k] = { candidates: 0, missing: 0 } }

CSV.foreach(source_path, headers: true, col_sep: "\t", quote_char: '"', liberal_parsing: true) do |row|
  t1, t2 = row['type_1'], row['type_2']
  id1, id2 = row['id_1'], row['id_2']

  # --- Disease-Gene ---
  if (t1 == 'Gene' || t2 == 'Gene') && (t1 == 'Disease' || t2 == 'Disease')
    gene_id, disease_id = t1 == 'Gene' ? [id1, id2] : [id2, id1]
    unless gene_id =~ /[A-Z]/ # MeSH-lettered gene IDs excluded by the notebook
      disease_id = 'C2931891' if disease_id == 'C0023264' # notebook's harmonization hack
      bv_per_notebook['Disease-Gene'][:candidates] += 1
      ok = b_gene.include?(gene_id) && b_disease.include?(disease_id)
      bv_per_notebook['Disease-Gene'][:missing] += 1 unless ok
    end
  end

  # --- Drug-Disease ---
  if (%w[Drug Compound].include?(t1) || %w[Drug Compound].include?(t2)) && (t1 == 'Disease' || t2 == 'Disease')
    drug_id, disease_id = %w[Drug Compound].include?(t1) ? [id1, id2] : [id2, id1]
    bv_per_notebook['Drug-Disease'][:candidates] += 1
    ok = b_drug_suffixes.include?(drug_id) && b_disease.include?(disease_id)
    bv_per_notebook['Drug-Disease'][:missing] += 1 unless ok
  end

  # --- Drug-Gene ---
  if (%w[Drug Compound].include?(t1) || %w[Drug Compound].include?(t2)) && (t1 == 'Gene' || t2 == 'Gene')
    drug_id, gene_id = %w[Drug Compound].include?(t1) ? [id1, id2] : [id2, id1]
    unless gene_id =~ /[A-Z]/
      bv_per_notebook['Drug-Gene'][:candidates] += 1
      ok = b_drug_suffixes.include?(drug_id) && b_gene.include?(gene_id)
      bv_per_notebook['Drug-Gene'][:missing] += 1 unless ok
    end
  end

  # --- Drug-Phenotype (phenotype side always "succeeds" if HP-shaped) ---
  if (%w[Drug Compound].include?(t1) && t2 == 'Human Phenotype') || (t1 == 'Human Phenotype' && %w[Drug Compound].include?(t2))
    drug_id, pheno_id = %w[Drug Compound].include?(t1) ? [id1, id2] : [id2, id1]
    if pheno_id =~ /\d+/
      bv_per_notebook['Drug-Phenotype'][:candidates] += 1
      bv_per_notebook['Drug-Phenotype'][:missing] += 1 unless b_drug_suffixes.include?(drug_id)
    end
  end

  # --- Gene-Phenotype ---
  if (t1 == 'Gene' && t2 == 'Human Phenotype') || (t1 == 'Human Phenotype' && t2 == 'Gene')
    gene_id, pheno_id = t1 == 'Gene' ? [id1, id2] : [id2, id1]
    unless gene_id =~ /[A-Z]/
      if pheno_id =~ /HP:\d+/
        bv_per_notebook['Gene-Phenotype'][:candidates] += 1
        bv_per_notebook['Gene-Phenotype'][:missing] += 1 unless b_gene.include?(gene_id)
      end
    end
  end

  # --- Disease-Phenotype ---
  if (t1 == 'Disease' && t2 == 'Human Phenotype') || (t1 == 'Human Phenotype' && t2 == 'Disease')
    disease_id, pheno_id = t1 == 'Disease' ? [id1, id2] : [id2, id1]
    disease_id = 'C2931891' if disease_id == 'C0023264'
    if pheno_id =~ /\d+/
      bv_per_notebook['Disease-Phenotype'][:candidates] += 1
      bv_per_notebook['Disease-Phenotype'][:missing] += 1 unless b_disease.include?(disease_id)
    end
  end
end

results['Biovista'] = {
  candidate_triples: bv_per_notebook.values.sum { |v| v[:candidates] },
  missing_triples: bv_per_notebook.values.sum { |v| v[:missing] },
  per_file: bv_per_notebook
}

puts JSON.pretty_generate(results)

#!/usr/bin/env ruby
# Computes entity-mapping-stage coverage/failure rates per partner/entity-type,
# using ONLY pairs where the success (.map) file and failure (-errors) file are
# verified to reflect the same input population — confirmed either by matching
# mtimes, or by a documented row-count-preserving label-only patch in
# CHANGES.md. Pairs without that verification are marked not_verified rather
# than guessed. See README.md "Coverage / failure rates" section for the
# reasoning behind each entry.
require 'json'

root = ARGV[0] or abort "usage: compute_coverage_rates.rb <SKG_Mapping root>"

def rows(path)
  File.foreach(path).count - 1 # minus header
end
def err_lines(path)
  File.foreach(path).count
end

entries = []

# --- Radboud ---
entries << { partner: 'Radboud', entity_type: 'disease',
  success_file: 'radboud/maps/diseases.map', error_files: ['radboud/maps/diseases-errors.txt'],
  verified: true, note: 'mtimes match (same run)' }
entries << { partner: 'Radboud', entity_type: 'drug',
  success_file: 'radboud/maps/drugs.map', error_files: ['radboud/maps/drugs-biologics-errors.txt'],
  verified: true,
  note: 'two-stage lookup: drugs-errors.txt (308) = first-pass CID-lookup failures; ' \
        'drugs-biologics-errors.txt (66) = still-failed after biologics-fallback retry, ' \
        'i.e. the true final failure count. 308-66=242 were recovered by the fallback and ARE in drugs.map.' }
entries << { partner: 'Radboud', entity_type: 'gene',
  success_file: 'radboud/maps/genes.map', error_files: [],
  verified: false, note: 'no current (non-deprecated) error log exists for this stage' }

# --- Demokritos ---
entries << { partner: 'Demokritos', entity_type: 'disease',
  success_file: 'demokritos/maps/2026-demokritos-disease-mondo.map',
  error_files: ['demokritos/maps/2026-unmapped-diseases.csv'],
  error_files_have_header: true,
  verified: false,
  note: 'success file mtime (2026-06-15) is ~2 months after error file mtime (2026-04-17) ' \
        'with no documented patch explaining the gap (unlike the gene-map patch below) — ' \
        'cannot confirm both reflect the same input run. Numbers given for reference only.' }
entries << { partner: 'Demokritos', entity_type: 'drug',
  success_file: 'demokritos/maps/2026-drug-mappings.map', error_files: ['demokritos/maps/2026-drug-mapping-errors.txt'],
  verified: true,
  note: 'mtimes match to the second (same run). CHANGES.md flags this map as using stale ' \
        'BioPortal prefLabel and "Needs re-run" for label quality — does not affect this row count.' }
entries << { partner: 'Demokritos', entity_type: 'gene',
  success_file: 'demokritos/maps/2026-gene-mappings.map', error_files: ['demokritos/maps/2026-gene-errors.txt'],
  verified: true,
  note: 'mtimes differ (map is 2 months newer) but CHANGES.md documents a one-time label-only ' \
        'backfill patch (cell 7a99c64b) that rewrote recommended_full for existing rows without ' \
        'changing which rows succeeded/failed — so the original error file remains valid.' }
entries << { partner: 'Demokritos', entity_type: 'phenotype',
  success_file: 'demokritos/maps/cui_hpo_lookup.tsv', error_files: ['demokritos/maps/2026-phenotype-mapping-errors.txt'],
  verified: true, note: 'mtimes match to the second (same run)' }

# --- Biovista ---
entries << { partner: 'Biovista', entity_type: 'disease',
  success_file: 'biovista/maps/2026-biovista-disease-mondo.map', error_files: [],
  verified: false,
  note: 'no error log exists for this stage; the 10 core target diseases are supplied ' \
        'directly as MONDO/xref IDs rather than looked up, so a near-zero failure rate is ' \
        'expected by construction, not measured' }
entries << { partner: 'Biovista', entity_type: 'drug',
  success_file: 'biovista/maps/2026-biovista-drugs.map', error_files: ['biovista/maps/2026-biovista-drugs-biologics-errors'],
  verified: true,
  note: 'two-stage lookup like Radboud drugs: drugs-errors (72) = first-pass PubChem-CID failures; ' \
        'drugs-biologics-errors (53) = still-failed after SID/biologics fallback retry, the true final ' \
        'failure count. 72-53=19 recovered by the fallback.' }
entries << { partner: 'Biovista', entity_type: 'gene',
  success_file: 'biovista/maps/2025-biovista-genes.map', error_files: [],
  verified: false, note: 'no error log exists for this stage; map file is 2025-dated' }
entries << { partner: 'Biovista', entity_type: 'phenotype',
  success_file: 'biovista/maps/2025-biovista-phenotypes.map', error_files: [],
  verified: false, note: 'no error log exists for this stage; map file is 2025-dated' }

results = entries.map do |e|
  s = rows(File.join(root, e[:success_file]))
  err = e[:error_files].sum { |f| err_lines(File.join(root, f)) }
  err -= 1 if e[:error_files_have_header] # e.g. demokritos unmapped-diseases.csv has a CSV header row
  total = s + err
  e.merge(
    success_rows: s,
    failure_rows: err,
    total_attempted: total,
    failure_rate_pct: total > 0 ? (err.to_f / total * 100).round(2) : nil
  )
end

puts JSON.pretty_generate(results)

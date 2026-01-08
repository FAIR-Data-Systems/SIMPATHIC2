require 'csv'
require 'securerandom'
require 'net/http'
require 'uri'
require 'json'

# Simple in-memory cache for MONDO lookups
MONDO_CACHE = {}

def get_mondo_code(disease_str)
  # Basic normalisation and heuristics for the sample data
  normalized = disease_str.strip
                    .gsub(/\s*isogenic.*/i, '')              # remove "isogenic" and anything after
                    .gsub(/^\s*LS\s*/i, 'Leigh Syndrome')    # expand common "LS" abbreviation
                    .gsub(/MT-ATP6/i, 'Leigh syndrome')      # map gene-based entry to disease
                    .gsub(/[\.,;]$/, '')                     # strip trailing punctuation
                    .strip

  return MONDO_CACHE[normalized] if MONDO_CACHE.key?(normalized)

  # Query OLS4 API (current as of 2026)
  query = URI.encode_www_form_component(normalized)
  url = "https://www.ebi.ac.uk/ols4/api/search?q=#{query}&ontology=mondo&rows=5"
  uri = URI(url)

  begin
    response = Net::HTTP.get_response(uri)
    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      docs = data['response']['docs']
      if docs.any?
        # Prefer exact label match, otherwise take the top result
        best = docs.find { |d| d['label'].downcase == normalized.downcase } || docs[0]
        obo_id = best['obo_id'] # e.g. "MONDO:0009723"
        if obo_id && obo_id.start_with?('MONDO:')
          code = obo_id.sub('MONDO:', '')
          MONDO_CACHE[normalized] = code
          puts "Mapped '#{disease_str}' → MONDO:#{code} (#{best['label']})"
          return code
        end
      end
    end
  rescue => e
    puts "Error querying OLS for '#{disease_str}': #{e.message}"
  end

  # Fallback for unmapped terms
  puts "No MONDO mapping found for '#{disease_str}' – using placeholder MONDO:0000000"
  '0000000' # placeholder – review logs for manual fixes
end

# ----------------------------- Script starts here -----------------------------

input_file = ARGV[0] || 'cell_lines.csv'
output_file = ARGV[1] || 'simpathic_cell_lines.ttl'

File.open(output_file, 'w') do |f|
  f.puts <<~PREFIX
    @prefix sio: <http://semanticscience.org/resource/> .
    @prefix mondo: <http://purl.obolibrary.org/obo/MONDO_> .
    @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
    @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
    @prefix local: <urn:local:simpathic:celllinemodel:> .
    @prefix simpathicmetadata: <https://fdp.simpathic.eu/dataset/> .

  PREFIX

  skipped_header = false

  CSV.foreach(input_file, col_sep: ',') do |row|
    # Skip the header row (first row only)
    if !skipped_header
      skipped_header = true
      next
    end

    # Skip empty/incomplete rows
    next if row.compact.empty?

    disease_str   = row[0].to_s.strip
    local_id_str  = row[1].to_s.strip
    hpscreg_raw   = row[2].to_s.strip

    # Clean hPSCreg ID (remove trailing punctuation like '.' if present)
    hpscreg_id    = hpscreg_raw.gsub(/[.\s]+$/, '')

    next if disease_str.empty? || hpscreg_id.empty?

    mondo_code = get_mondo_code(disease_str)

    # Generate unique GUIDs for this entry
    cellline_uuid      = SecureRandom.uuid
    disease_ref_uuid   = SecureRandom.uuid
    localid_uuid       = SecureRandom.uuid
    deriv_proc_uuid    = SecureRandom.uuid
    patient_uuid       = SecureRandom.uuid
    disease_attr_uuid  = SecureRandom.uuid

    # Local resource names
    cellline      = "local:CellLine_#{cellline_uuid}"
    disease_ref   = "local:DiseaseRef_#{disease_ref_uuid}"
    localid       = "local:LocalID_#{localid_uuid}"
    deriv_proc    = "local:DerivationProcess_#{deriv_proc_uuid}"
    patient       = "local:Patient_#{patient_uuid}"
    disease_attr  = "local:DiseaseAttribute_#{disease_attr_uuid}"

    hpscreg_url   = "https://hpscreg.eu/cell-line/#{hpscreg_id}"

    cellline_label = "#{disease_str} cell line#{local_id_str.empty? ? '' : " (#{local_id_str})"}".strip

    f.puts <<~TRIPLES

      #{cellline} a sio:SIO_010054 ;
        rdfs:label "#{cellline_label}" ;
        sio:SIO_000671 #{localid} ;
        sio:SIO_000232 #{deriv_proc} ;
        sio:SIO_000210 #{disease_ref} .

      #{disease_ref} a mondo:#{mondo_code} ;
        rdfs:label "#{disease_str}" .

      #{localid} a sio:SIO_000114 ;
        sio:SIO_000300 "#{local_id_str}"^^xsd:string ;
        sio:SIO_000672 #{cellline} .

      <#{hpscreg_url}> a sio:SIO_000756 ;
        rdfs:label "hPSCreg record for #{hpscreg_id}" ;
        sio:SIO_000628 #{cellline} ;
        sio:SIO_000557 simpathicmetadata:_datasetid_ .

      #{deriv_proc} a sio:SIO_000006 ;
        rdfs:label "Derivation process for #{cellline_uuid}" ;
        sio:SIO_000230 #{patient} ;
        sio:SIO_000229 #{cellline} .

      #{patient} a sio:SIO_010006 ;
        rdfs:label "Source patient for #{cellline_uuid}" ;
        sio:SIO_000008 #{disease_attr} .

      #{disease_attr} a sio:SIO_010299 ;
        rdfs:label "#{disease_str}" ;
        sio:SIO_000628 #{disease_ref} .

    TRIPLES

    f.puts "\n" # blank line between entries for readability
  end
end

puts "Generated #{output_file} from #{input_file}"
puts "Header row skipped automatically."
puts "Unmapped diseases will use MONDO:0000000 as placeholder – review logs for manual fixes."
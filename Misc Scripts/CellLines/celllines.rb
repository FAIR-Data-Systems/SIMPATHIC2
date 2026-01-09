require 'csv'
require 'securerandom'
require 'net/http'
require 'uri'
require 'json'

# Simple in-memory cache for MONDO lookups
MONDO_CACHE = {}

require 'net/http'
require 'json'
require 'rest-client'
require 'json'

require 'rest-client'
require 'json'
require 'uri'

def get_orphanet_from_mondo(mondo_id)
  base_iri = "http://purl.obolibrary.org/obo/MONDO_#{mondo_id}"
  # First encode
  first_encoded = URI.encode_www_form_component(base_iri)
  # Second encode (double-encode)
  double_encoded = URI.encode_www_form_component(first_encoded)
  
  url = "https://www.ebi.ac.uk/ols4/api/ontologies/mondo/terms/#{double_encoded}"

  begin
    response = RestClient.get(url, { accept: :json })
    data = JSON.parse(response.body)

    orphanet_codes = []

    # Try common fields where xrefs appear
    (data.dig('annotation', 'database_cross_reference') || []).each do |xref|
      orphanet_codes << xref.split(':').last if xref&.start_with?('Orphanet:')
    end

    (data.dig('obo_xref') || []).each do |xref|
      orphanet_codes << xref['id'] if xref['database'] == 'Orphanet'
    end

    # Also check if xrefs are flat strings sometimes
    (data['xrefs'] || []).each do |xref|
      orphanet_codes << xref.split(':').last if xref.start_with?('Orphanet:')
    end

    orphanet_codes.uniq!
    first_code = orphanet_codes.first
    puts "Found Orphanet code(s) for MONDO:#{mondo_id}: #{orphanet_codes.join(', ')}"
    first_code
  rescue RestClient::ExceptionWithResponse => e
    puts "Error fetching MONDO term (code #{e.response&.code}): #{e.response&.body || e.message}"
    nil
  rescue => e
    puts "Unexpected error: #{e.message}"
    nil
  end
end


# # Usage example
# mondo_code = '0009723'  # From your earlier mapping
# orphanet = get_orphanet_from_mondo(mondo_code)
# puts "Orphanet code for MONDO:#{mondo_code}: #{orphanet}"  # e.g., "506"

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
  url = "https://www.ebi.ac.uk/ols4/api/search?q=#{query}&ontology=mondo&rows=1"   # first match only... let's try that!
  uri = URI(url)
  warn "CALLING #{url}"

  begin
    response = Net::HTTP.get_response(uri)
    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      docs = data['response']['docs']
      warn "\n\n", docs
      if docs.any?
        # Prefer exact label match, otherwise take the top result
        best = docs.find { |d| d['label'].downcase == normalized.downcase } || docs[0]
        obo_id = best['obo_id'] # e.g. "MONDO:0009723"
        if obo_id && obo_id.start_with?('MONDO:')
          code = obo_id.sub('MONDO:', '')
          MONDO_CACHE[normalized] = [code, best['label']]
          puts "Mapped '#{disease_str}' → MONDO:#{code} (#{best['label']})"
          return [code, best['label']]
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

keywords = Hash.new
themes = Hash.new

File.open(output_file, 'w') do |f|
  f.puts <<~PREFIX
    @prefix sio: <http://semanticscience.org/resource/> .
    @prefix mondo: <http://purl.obolibrary.org/obo/MONDO_> .
    @prefix orpha: <http://www.orpha.net/ORDO/Orphanet_> .
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

    mondo_code, mondo_label = get_mondo_code(disease_str) # numeric only!
    orpha_code = get_orphanet_from_mondo(mondo_code)  # numeric only!
    warn "ORPHA #{orpha_code}"
    # abort
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

    datasetid = "9225eb84-e5ff-4a86-8e37-13f882f18f56"

    cellline_label = "#{disease_str} cell line#{local_id_str.empty? ? '' : " (#{local_id_str})"}".strip

    f.puts <<~TRIPLES

      #{cellline} a sio:SIO_010054 ;
        rdfs:label "#{cellline_label}" ;
        sio:SIO_000671 #{localid} ;
        sio:SIO_000232 #{deriv_proc} ;
        sio:SIO_000210 #{disease_ref} .

      #{disease_ref} a mondo:#{mondo_code} ;
        rdfs:label "#{disease_str}" ;
        rdfs:label "#{mondo_label}" .

      #{disease_ref} a orpha:#{orpha_code} .

      #{localid} a sio:SIO_000114 ;
        sio:SIO_000300 "#{local_id_str}"^^xsd:string ;
        sio:SIO_000672 #{cellline} .

      <#{hpscreg_url}> a sio:SIO_000756 ;
        rdfs:label "hPSCreg record for #{hpscreg_id}" ;
        sio:SIO_000628 #{cellline} ;
        sio:SIO_000557 simpathicmetadata:#{datasetid} .

      #{deriv_proc} a sio:SIO_000006 ;
        rdfs:label "Derivation process for #{cellline_uuid}" ;
        sio:SIO_000230 #{patient} ;
        sio:SIO_000229 #{cellline} .

      #{patient} a sio:SIO_010006 ;
        rdfs:label "Source patient for #{cellline_uuid}" ;
        sio:SIO_000008 #{disease_attr} .

      #{disease_attr} a sio:SIO_010299 ;
        rdfs:label "#{mondo_label}" ;
        sio:SIO_000628 #{disease_ref} .

    TRIPLES

    f.puts "\n" # blank line between entries for readability

    # keywords['"#{cellline_label}"'] = 1
    keywords["\"#{disease_str}\",\"#{mondo_label}\""] = 1
    themes["<http://purl.obolibrary.org/obo/MONDO_#{mondo_code}>"] = 1
    themes["<#{hpscreg_url}>"] = 1
    themes["<http://www.orpha.net/ORDO/Orphanet_#{orpha_code}>"] = 1

  end
end

File.open("./keywords_frag.ttl", "w") do |kw|
  kw.puts keywords.keys.join(",\n")
end

File.open("./themes_frag.ttl", "w") do |ont|
  ont.puts themes.keys.join(",\n")
end

puts "Generated #{output_file} from #{input_file}"
puts "Header row skipped automatically."
puts "Unmapped diseases will use MONDO:0000000 as placeholder – review logs for manual fixes."
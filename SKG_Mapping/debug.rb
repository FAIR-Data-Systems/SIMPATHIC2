require 'linkeddata'
require 'rdf/nquads'
require 'csv'

graphing_errors = File.open('./graph/2026-disease-gene-errors.txt', 'w')

# Define namespaces
SIMPATHIC = RDF::Vocabulary.new('urn:simpathic:')
RDFS = RDF::Vocabulary.new('http://www.w3.org/2000/01/rdf-schema#')

# Read input files
disease_mappings = CSV.read('./maps/2026-demokritos-disease-mondo.map', headers: true)
gene_mappings = CSV.read('./maps/2026-gene-mappings.map', headers: true)
failures = {}

# refresh graph file
f = File.open('./graph/2026-disease-gene.nq.large', 'w')
f.close

# recordcount = 0
foreach ['./raw-data/Gene-Disease triples.tsv', './raw-data/Disease-Gene triples.tsv'] do |sourcefile|
  CSV.foreach(sourcefile, col_sep: "\t", quote_char: '"', liberal_parsing: true, headers: true) do |row|
    # Gene	Gene_id	RELATION	PROVENANCE	Disease	Disease_id
    # ZIC1 gene	C1421581	ASSOCIATED_WITH		Craniosynostosis	C0010278
    disease_id = row['Disease_id']
    gene_id = row['Gene_id']
    # sourcegenelabel = row['Gene']
    # sourcediseaselabel = row['Disease']
    # score = 1
    evidence = row['PROVENANCE']
    source_relation = row['RELATION']

    warn "searching for #{disease_id}"
    abort # check the files are being read properly

    disease = disease_mappings.find { |d| d['demokritos_umls'] == disease_id }
    gene = gene_mappings.find { |d| d['source'] == gene_id }

    unless disease
      next if failures[disease_id]

      failures[disease_id] = 1
      warn "disease lookup failed #{disease_id}"
      graphing_errors.write "disease lookup failed #{disease_id}\n"
      next
    end
    unless gene
      next if failures[gene_id]

      failures[gene_id] = 1
      warn "gene lookup failed #{gene_id}"
      graphing_errors.write "gene lookup failed #{gene_id}\n"
      next
    end

    # demokritos_umls,prefname,mondo
    # C0000774,gastrin secretion abnormality,http://purl.obolibrary.org/obo/MONDO_0001770
    mondo_uri = RDF::URI.new(disease['mondo'])
    mondo_type = RDF::URI.new('https://bioportal.bioontology.org/ontologies/MONDO')
    mondo_core_type = RDF::URI.new('https://w3id.org/biolink/vocab/Disease')
    mondo_label = RDF::Literal.new('MONDO Term')
    #   orphanet = RDF::URI.new(disease['orpha'])
    disease_label = RDF::Literal.new(disease['prefname'])
    original_disease = RDF::Literal.new(disease_id)

    #   source,label,geneid,protein,recommended_full,taxon
    #   C1421313,UCP1,http://purl.uniprot.org/geneid/7350,http://purl.uniprot.org/uniprot/P25874,uncoupling protein 1,http://purl.uniprot.org/taxonomy/9606
    gene_uri = RDF::URI.new(gene['geneid'])
    gene_type = RDF::URI.new('http://edamontology.org/data_2610')
    _gene_label = RDF::Literal.new(gene['label'])
    gene_core_type = RDF::URI.new('https://w3id.org/biolink/vocab/Gene')
    human_gene_label = RDF::Literal.new(gene['recommended_full'])

    protein_uri = RDF::URI.new(gene['protein'])
    protein_type = RDF::URI.new('http://edamontology.org/data_2291')
    _protein_label = RDF::Literal.new(gene['protein'])
    protein_core_type = RDF::URI.new('https://w3id.org/biolink/vocab/Protein')
    human_protein_label = RDF::Literal.new(gene['recommended_full'])

    taxon = RDF::URI.new(gene['taxon'])

    # Create context URI
    context_uri = RDF::URI.new("urn:simpathic:context:#{disease_id}_#{gene_id}")
    general_context = RDF::URI.new('urn:simpathic:context:all_metadata')

    # Create RDF repository (need to do this each time, since there are hundreds of thousands of lines, and the graph gets too big for memory)
    graph = RDF::Repository.new

    # Add quads to graph using RDF::Statement
    graph << RDF::Statement.new(mondo_uri, SIMPATHIC['associated-with'], gene_uri, graph_name: context_uri)
    graph << RDF::Statement.new(gene_uri, SIMPATHIC['associated-with'], mondo_uri, graph_name: context_uri)

    graph << RDF::Statement.new(mondo_uri, RDFS.label, disease_label, graph_name: context_uri)
    graph << RDF::Statement.new(mondo_uri, RDF.type, mondo_type, graph_name: context_uri)
    graph << RDF::Statement.new(mondo_uri, RDF.type, mondo_core_type, graph_name: context_uri)
    graph << RDF::Statement.new(mondo_type, RDFS.label, mondo_label, graph_name: context_uri)
    #   graph << RDF::Statement.new(mondo_uri, SIMPATHIC['orphanet'], orphanet, graph_name: context_uri)
    graph << RDF::Statement.new(mondo_uri, SIMPATHIC['original-id'], original_disease, graph_name: context_uri)

    graph << RDF::Statement.new(gene_uri,  RDFS.label,       human_gene_label, graph_name: context_uri)
    graph << RDF::Statement.new(gene_uri,  RDF.type,         gene_type, graph_name: context_uri)
    graph << RDF::Statement.new(gene_uri,  RDF.type,         gene_core_type, graph_name: context_uri)
    graph << RDF::Statement.new(gene_type, RDFS.label,       RDF::Literal.new('NCBI Gene'),
                                graph_name: context_uri)
    graph << RDF::Statement.new(gene_core_type, RDFS.label,  RDF::Literal.new('Gene'), graph_name: context_uri)
    graph << RDF::Statement.new(gene_uri,  SIMPATHIC['original-id'], RDF::Literal.new("#{gene_id}"),
                                graph_name: context_uri)
    graph << RDF::Statement.new(gene_uri,  SIMPATHIC['in-taxon'], taxon, graph_name: context_uri)

    graph << RDF::Statement.new(mondo_uri, SIMPATHIC['associated-with'], protein_uri, graph_name: context_uri)
    graph << RDF::Statement.new(protein_uri, SIMPATHIC['associated-with'], mondo_uri, graph_name: context_uri)

    graph << RDF::Statement.new(protein_uri,  RDFS.label,       human_protein_label, graph_name: context_uri)
    graph << RDF::Statement.new(protein_uri,  RDF.type,         protein_type, graph_name: context_uri)
    graph << RDF::Statement.new(protein_uri,  RDF.type,         protein_core_type, graph_name: context_uri)
    graph << RDF::Statement.new(protein_type, RDFS.label,       RDF::Literal.new('UniProt'),
                                graph_name: context_uri)
    graph << RDF::Statement.new(protein_core_type, RDFS.label,  RDF::Literal.new('Protein'),
                                graph_name: context_uri)
    graph << RDF::Statement.new(protein_uri,  SIMPATHIC['original-id'], RDF::Literal.new("#{gene_id}"),
                                graph_name: context_uri)
    graph << RDF::Statement.new(protein_uri,  SIMPATHIC['in-taxon'], taxon, graph_name: context_uri)

    graph << RDF::Statement.new(context_uri, SIMPATHIC['skg-source'], RDF::Literal.new('Demokritos'),
                                graph_name: general_context)
    # evidence = row['PROVENANCE']
    # source_relation = row['RELATION']
    graph << RDF::Statement.new(context_uri, SIMPATHIC['evidence'], RDF::URI.new(evidence))
    graph << RDF::Statement.new(context_uri, SIMPATHIC['source-relation'],
                                RDF::URI.new(source_relation))
    #   graph << RDF::Statement.new(context_uri, SIMPATHIC['score'], RDF::Literal.new(score))

    #   warn "graph #{context_uri} built"
    # Write RDF to file in N-Quads format
    File.open('./graph/2026-disease-gene.nq.large', 'a') do |f|
      RDF::Writer.for(:nquads).new(f) do |writer|
        warn 'writing triples'
        writer << graph
      end
    end
    #   warn "end graph writing"
  end
end

warn 'completed graph building'
graphing_errors.close

puts 'RDF quads written'

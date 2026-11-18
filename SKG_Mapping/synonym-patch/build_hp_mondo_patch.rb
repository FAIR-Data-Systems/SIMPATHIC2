# Build Claude's best-guess HP -> MONDO consolidation candidates, in the partners'
# synonym patch-file format, for expert review. NOTHING IS APPLIED TO THE DATA.
#
# Background (TODO item 2, 2026-11-18): some concepts exist in the SKG both as a MONDO
# Disease node and as an HP Phenotype node (e.g. glaucoma: MONDO_0005041 from
# Demokritos, HP_0000501 from Biovista). Radboud also lists HP terms in its Disease
# column, and its graphing notebooks turned those into HP Phenotype nodes. Live
# store check: every Disease node is MONDO, every Phenotype node is HP, and no URI
# is typed as both.
#
# Tiers (both nodes must already exist in the SKG):
#   A  MONDO itself cross-references the HP term (oboInOwl:hasDbXref HP:..., almost all
#      annotated MONDO:otherHierarchy = "the phenotype-side counterpart of this disease")
#   B  HP label exactly matches the MONDO label or a MONDO exact synonym (case/punctuation-normalised)
#   C  word-overlap near-matches, each judged by hand (Claude); only accepted pairs are listed
# Some A/B pairs are downgraded by hand (FLAGS below) where the match is broader/narrower.
#
# SCOPE: only HP terms Radboud uses as DISEASES go in the patch file (see SCOPE below);
# everything else is written to a separate information-only file.
#
# Inputs: TSV exports from Virtuoso (see README.md in this folder for the queries):
#   hp_nodes.tsv, mondo_nodes.tsv, mondo_names.tsv, mondo_hp_xrefs.tsv
# Usage:  ruby build_hp_mondo_patch.rb INPUT_DIR OUTPUT.tsv
require 'set'

in_dir, out_path = ARGV
abort 'usage: ruby build_hp_mondo_patch.rb INPUT_DIR OUTPUT.tsv' unless in_dir && out_path
OBO = 'http://purl.obolibrary.org/obo/'

uq = ->(s) { s.to_s.strip.sub(/\A<(.*)>\z/, '\1').sub(/\A"(.*)"(\^\^.*|@.*)?\z/m, '\1') }
rows = ->(f) { File.readlines(File.join(in_dir, f), chomp: true).drop(1).map { |l| l.split("\t").map(&uq) } }
norm = ->(s) { s.downcase.gsub(/[^a-z0-9 ]/, ' ').squeeze(' ').strip }

hp = Hash.new { |h, k| h[k] = { labels: [], srcs: Set.new } }
rows.('hp_nodes.tsv').each { |u, l, s| hp[u][:labels] |= [l]; hp[u][:srcs] << s }
mondo = Hash.new { |h, k| h[k] = { labels: [], srcs: Set.new } }
rows.('mondo_nodes.tsv').each { |u, l, s| mondo[u][:labels] |= [l]; mondo[u][:srcs] << s }
by_name = Hash.new { |h, k| h[k] = Set.new }
rows.('mondo_names.tsv').each { |u, n| by_name[norm.(n)] << u if mondo.key?(u) }
mondo.each { |u, d| d[:labels].each { |n| by_name[norm.(n)] << u } }
xref = Hash.new { |h, k| h[k] = {} }
rows.('mondo_hp_xrefs.tsv').each { |m, x, src| xref["#{OBO}#{x.sub('HP:', 'HP_')}"][m] = src.to_s }

# Hand review of A/B matches that are broader/narrower than they look: [confidence, caution]
FLAGS = {
  'HP_0003348' => ['LOW',    'Hyperalaninemia (alanine) vs hyper-beta-alaninemia (beta-alanine): different metabolites despite the MONDO synonym'],
  'HP_0000107' => ['MEDIUM', 'a single renal cyst is narrower than cystic kidney disease'],
  'HP_0000155' => ['MEDIUM', 'oral ulcer is broader than aphthous stomatitis'],
  'HP_0000639' => ['MEDIUM', 'nystagmus (any) is broader than congenital nystagmus'],
  'HP_0100704' => ['MEDIUM', 'cerebral visual impairment is broader than cortical blindness'],
  'HP_0003643' => ['MEDIUM', 'HP sulfite oxidase deficiency also covers molybdenum cofactor deficiency; MONDO term is the isolated form'],
  'HP_0012120' => ['MEDIUM', 'methylmalonic aciduria is the urinary finding; methylmalonic acidemia the disease (MONDO lists them as synonyms)'],
}.freeze

# Tier C: near-matches accepted on hand review (all others rejected): HP => [MONDO, confidence, reason]
TIER_C = {
  'HP_0012452' => ['MONDO_0005391', 'HIGH',   'restless legs = restless legs syndrome'],
  'HP_0003774' => ['MONDO_0004375', 'HIGH',   'same concept, word order differs'],
  'HP_0002093' => ['MONDO_0021113', 'HIGH',   'MONDO term is "respiratory insufficiency/failure"'],
  'HP_0006536' => ['MONDO_0002267', 'MEDIUM', 'MONDO synonym "respiratory airway obstruction" matches, but the label used in the SKG is "obstructive lung disease", which is narrower than airway obstruction'],
  'HP_0008209' => ['MONDO_0001119', 'MEDIUM', 'premature ovarian insufficiency = premature ovarian failure, but the label used in the SKG is "premature menopause" (also see MONDO_0005387 primary ovarian insufficiency, which may itself be a duplicate)'],
  'HP_0000863' => ['MONDO_0007450', 'HIGH',   'central diabetes insipidus = neurohypophyseal diabetes insipidus'],
  'HP_0011924' => ['MONDO_0015448', 'HIGH',   'decreased complex III activity is the defining finding of complex III deficiency'],
  'HP_0002928' => ['MONDO_0019169', 'HIGH',   'decreased PDC activity is the defining finding of PDC deficiency'],
  'HP_0030050' => ['MONDO_0021107', 'HIGH',   'HP term is obsolete (narcolepsy moved to the disease hierarchy)'],
  'HP_0002086' => ['MONDO_0005087', 'MEDIUM', 'grouping classes: HP "abnormality of" vs MONDO "disorder"'],
  'HP_0001626' => ['MONDO_0004995', 'MEDIUM', 'grouping classes: HP "abnormality of" vs MONDO "disease"'],
  'HP_0001928' => ['MONDO_0001531', 'MEDIUM', 'grouping classes: HP "abnormality of" vs MONDO "disorder"'],
  'HP_0100022' => ['MONDO_0005395', 'MEDIUM', 'grouping classes: abnormality of movement vs movement disorder'],
  'HP_0012332' => ['MONDO_0001292', 'MEDIUM', 'grouping classes: abnormal autonomic physiology vs autonomic nervous system disorder'],
  'HP_0003287' => ['MONDO_0044970', 'MEDIUM', 'grouping classes: abnormal mitochondrial metabolism vs mitochondrial disease'],
  'HP_0012432' => ['MONDO_0005404', 'MEDIUM', 'symptom (chronic fatigue) vs syndrome (chronic fatigue syndrome)'],
  'HP_0011107' => ['MONDO_0004845', 'MEDIUM', 'recurrent aphthous stomatitis is essentially the disease'],
  'HP_0000857' => ['MONDO_0016391', 'MEDIUM', 'neonatal insulin-dependent DM vs neonatal diabetes mellitus'],
  'HP_0012450' => ['MONDO_0002203', 'MEDIUM', 'chronic constipation vs constipation disorder'],
  'HP_0003756' => ['MONDO_0005336', 'MEDIUM', 'MONDO myopathy = skeletal muscle disease'],
  'HP_0003477' => ['MONDO_0004183', 'MEDIUM', 'axonal neuropathy is peripheral by definition'],
  'HP_0001321' => ['MONDO_0008939', 'MEDIUM', 'MONDO term is the congenital form'],
  'HP_0008207' => ['MONDO_0015129', 'MEDIUM', 'primary adrenal insufficiency = Addison disease; MONDO term says chronic'],
  'HP_0001601' => ['MONDO_0007878', 'MEDIUM', 'laryngomalacia is almost always congenital'],
  'HP_0001250' => ['MONDO_0005027', 'LOW',    'a seizure (event) is not epilepsy (disorder); listed because it affects many edges and needs a policy decision'],
}.freeze

pairs = []
hp.each_key do |h|
  hid = h.delete_prefix(OBO)
  hits = {}
  xref[h].each { |m, src| hits[m] = ['A', "MONDO cross-references #{hid} (#{src.empty? ? 'unannotated xref' : src})"] if mondo.key?(m) }
  hp[h][:labels].each { |l| by_name[norm.(l)].each { |m| hits[m] ||= ['B', 'HP label exactly matches the MONDO label or a MONDO exact synonym'] } }
  if (c = TIER_C[hid])
    m = "#{OBO}#{c[0]}"
    abort "tier C target #{c[0]} not in SKG" unless mondo.key?(m)
    hits[m] ||= ['C', "near-match accepted on hand review: #{c[2]}"]
  end
  hits.each do |m, (tier, evidence)|
    conf, caution = if tier == 'C' then [TIER_C[hid][1], nil]
                    elsif FLAGS[hid] then FLAGS[hid]
                    else ['HIGH', nil]
                    end
    pairs << { m: m, h: h, hid: hid, tier: tier, conf: conf, evidence: evidence, caution: caution }
  end
end

# SCOPE (Mark, 2026-11-18): the patch applies ONLY where an HP term is used as a DISEASE,
# i.e. Radboud's Disease column. Other partners' HP terms are genuine phenotypes and must
# stay. Because HP URIs are shared between partners, a row must not be applied as a global
# URI merge; it applies only to Radboud's graphs (urn:simpathic:context:rad_*).
# Pairs whose HP term is NOT used by Radboud go to a separate information-only file.
order = { 'HIGH' => 0, 'MEDIUM' => 1, 'LOW' => 2 }
pairs.sort_by! { |p| [order[p[:conf]], p[:tier], p[:hid]] }
radboud, others = pairs.partition { |p| hp[p[:h]][:srcs].include?('Radboud') }

write = lambda do |path, list, scoped|
  File.open(path, 'w') do |f|
    f.puts %w[canonical_url synonym_url type names note].join("\t")
    list.each do |p|
      names = (mondo[p[:m]][:labels] + hp[p[:h]][:labels]).uniq.join('|')
      shared = hp[p[:h]][:srcs].to_a.sort - ['Radboud']
      scope = if scoped
                ' SCOPE: Radboud only. Radboud uses this HP term in its Disease column; apply only to Radboud graphs (rad_*).' +
                  (shared.empty? ? '' : " #{shared.join('+')} also use #{p[:hid]} as a genuine phenotype: keep that.")
              else
                ' NOT FOR PATCHING: no partner uses this HP term as a disease (Biovista/Demokritos phenotype vs MONDO disease). For information/discussion only.'
              end
      note = "Claude suggestion 2026-11-18, confidence #{p[:conf]} (tier #{p[:tier]}): #{p[:evidence]}." \
             "#{p[:caution] ? " CAUTION: #{p[:caution]}." : ''}" \
             " MONDO node from #{mondo[p[:m]][:srcs].to_a.sort.join('+')}; HP node from #{hp[p[:h]][:srcs].to_a.sort.join('+')}.#{scope}"
      f.puts [p[:m], p[:h], 'Disease', names, note].join("\t")
    end
  end
end
write.(out_path, radboud, true)
info_path = out_path.sub(/\.tsv\z/, '') + '_NOT-FOR-PATCH_other-partners.tsv'
write.(info_path, others, false)

puts "#{radboud.size} Radboud-scoped patch rows written to #{out_path}"
puts "  by confidence: #{radboud.map { |p| p[:conf] }.tally}   by tier: #{radboud.map { |p| p[:tier] }.tally}"
puts "  of which the HP URI is ALSO used as a phenotype by another partner: #{radboud.count { |p| hp[p[:h]][:srcs].size > 1 }}"
puts "#{others.size} information-only rows written to #{info_path}"
puts "  HP nodes with >1 candidate: #{pairs.group_by { |p| p[:h] }.count { |_, v| v.size > 1 }}"
radboud_hp = hp.count { |_, d| d[:srcs].include?('Radboud') }
puts "Radboud HP-as-disease nodes in SKG: #{radboud_hp}; with a MONDO candidate already in the SKG: #{radboud.map { |p| p[:h] }.uniq.size}"

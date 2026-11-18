# Patch the on-disk Demokritos .nq.large files so that the graph-less
# simp:evidence / simp:source-relation triples carry the metadata graph
# <urn:simpathic:context:all_metadata>, exactly as a re-run of the (now patched)
# graphing notebooks would produce. This avoids re-running the slow notebooks.
#
# Why (found 2026-11-18): three Demokritos graphing notebooks wrote these two
# statements without `graph_name:`, so the files contain plain triples and
# Virtuoso's bulk loader put them in its default graph <urn:dummy>. The
# notebooks are fixed by patch_demokritos_graphless_metadata.py; the live
# database by Fix_URN_Dummy_Graph.*.
#
# - Backs up each original to graph/deprecated/<name>.BEFORE-graphfix-<date>.nq.large
#   (.nq.large files are git-ignored, so the backup is the only copy).
# - Only rewrites lines of the form  <urn:simpathic:context:...> <simp:evidence|simp:source-relation> OBJ .
# - Aborts without writing if any line is neither a recognised quad nor one of those triples.
#
# Usage (from SKG_Mapping/):  ruby Utilities/Patches/patch_demokritos_graphless_nquads.rb [--dry-run]

require 'fileutils'
require 'date'

GRAPH_DIR = File.expand_path('../../demokritos/graph', __dir__)
FILES = %w[
  2026-disease-gene.nq.large
  2026-demokritos_drug-disease.nq.large
  2026-demokritos_drug-gene.nq.large
]
META = '<urn:simpathic:context:all_metadata>'
TERM = %q{(?:<[^>]*>|_:\S+|"(?:[^"\\\\]|\\\\.)*"(?:\^\^<[^>]*>|@[A-Za-z0-9-]+)?)}
QUAD = /\A#{TERM} <[^>]*> #{TERM} <[^>]*> \.\s*\z/
GRAPHLESS = /\A(<urn:simpathic:context:[^>]*> <urn:simpathic:(?:evidence|source-relation)> #{TERM}) \.\s*\z/

abort <<~MSG unless ARGV.include?('--dry-run')
  ALREADY APPLIED 2026-11-18. The corrected files are in demokritos/graph/NOV-20261118/.
  The files in demokritos/graph/ are the September originals the partners used, restored
  on purpose as a provenance record. They must NOT be modified in place (Mark, 2026-11-18).
  Only --dry-run is allowed.
MSG
dry_run = ARGV.include?('--dry-run')
stamp = Date.today.strftime('%Y%m%d')

FILES.each do |name|
  path = File.join(GRAPH_DIR, name)
  out_lines = []
  fixed = quads = blank = 0
  bad = []
  File.foreach(path) do |line|
    if line.strip.empty?
      blank += 1
      out_lines << line
    elsif (m = GRAPHLESS.match(line))
      fixed += 1
      out_lines << "#{m[1]} #{META} .\n"
    elsif QUAD.match?(line)
      quads += 1
      out_lines << line
    else
      bad << line
    end
  end

  puts "#{name}: #{quads} quads unchanged, #{fixed} graph-less triples fixed, #{bad.size} unrecognised"
  unless bad.empty?
    bad.first(3).each { |l| puts "    UNRECOGNISED: #{l[0, 160]}" }
    abort "Aborting: #{name} has unrecognised lines; nothing written for this or later files."
  end
  next if dry_run || fixed.zero?

  backup = File.join(GRAPH_DIR, 'deprecated', name.sub(/\.nq\.large\z/, ".BEFORE-graphfix-#{stamp}.nq.large"))
  abort "Backup #{backup} already exists; refusing to overwrite it." if File.exist?(backup)
  FileUtils.cp(path, backup, preserve: true)
  tmp = "#{path}.tmp"
  File.write(tmp, out_lines.join)
  File.rename(tmp, path)
  puts "    backup: #{backup}"
end
puts(dry_run ? 'DRY RUN - no files written' : 'done')

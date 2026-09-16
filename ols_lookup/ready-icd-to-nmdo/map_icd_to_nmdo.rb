#!/usr/bin/env ruby
# map_icd_to_nmdo.rb — map REaDY's ICD-11 (English) and MKN-10/ICD-10 (Czech)
# neuromuscular-block codes to NMDO terms via nmdo-search.
#
# Input:  mockdata/icd11_scoped.tsv, mockdata/mkn10_scoped.tsv
#         (produced by extract_icd_catalogs.py)
# Output: mockdata/mapped_icd11.csv, mockdata/mapped_mkn10.csv
#         mockdata/mapping_stats.json
#
# For each code's label, we query nmdo-search for the top-5 candidates and
# prefer an exact (normalized) label/synonym match over the raw top score —
# same rerank rule the spreadsheet-2-CARE transformer uses (a same-ontology
# exact match at rank 2/3 beats an over/under-specified relative at rank 1).
# A candidate only counts as a hit if its score clears SCORE_THRESHOLD.
#
# Czech labels are queried as-is: nmdo-search embeds free text, and NMDO's
# underlying terms are English, so a Czech query is a genuine test of whether
# the embedder generalises cross-lingually — not an assumption that it will.

require "net/http"
require "uri"
require "json"
require "csv"
require "set"

SEARCH_URL = ENV.fetch("NMDO_SEARCH_URL", "https://simpathic.services/llm_search/search")
SCORE_THRESHOLD = 0.50   # matches profile_columns.py's SCORE_THRESHOLD convention
TOP_K = 5

HERE = File.dirname(File.expand_path(__FILE__))
MOCKDATA = File.join(HERE, "mockdata")

def search(query, k: TOP_K)
  return [] if query.nil? || query.strip.empty?
  uri = URI(SEARCH_URL)
  uri.query = URI.encode_www_form(q: query, top_k: k)
  begin
    res = Net::HTTP.get_response(uri)
    return [] unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)["results"] || []
  rescue StandardError => e
    warn "  search error for #{query.inspect}: #{e.message}"
    []
  end
end

def normalize_label(s)
  s.to_s.strip.downcase.gsub(/[^a-z0-9 ]+/, " ").gsub(/\s+/, " ").strip
end

# Prefer an exact label/synonym match among candidates that clear the score
# threshold, over the raw top-scoring candidate. Returns [hit_or_nil, reranked?]
def pick_exact_match(query, candidates)
  cands = candidates.select { |c| c && !c["_error"] && (c["score"] || 0) >= SCORE_THRESHOLD }
  return [nil, false] if cands.empty?
  top = cands.first
  nq = normalize_label(query)
  is_exact = ->(c) {
    return true if normalize_label(c["label"]) == nq
    (c["synonyms"] || []).any? { |s| normalize_label(s) == nq }
  }
  return [top, false] if is_exact.call(top)
  cands[1..].each { |c| return [c, true] if is_exact.call(c) }
  [top, false]
end

def load_tsv(path)
  rows = []
  CSV.foreach(path, col_sep: "\t", headers: true) { |r| rows << r.to_h }
  rows
end

def map_catalog(name, rows, label_key: "label")
  puts "== #{name}: #{rows.size} codes =="
  cache = {}
  stats = Hash.new(0)
  out = []
  rows.each_with_index do |row, i|
    label = row[label_key]
    cands = (cache[label] ||= search(label))
    hit, reranked = pick_exact_match(label, cands)
    stats[:reranked_exact_match] += 1 if reranked
    if hit
      stats[:mapped] += 1
      out << row.merge(
        "nmdo_iri" => hit["iri"], "nmdo_prefix" => hit["prefix"],
        "nmdo_label" => hit["label"], "score" => hit["score"],
        "reranked" => reranked
      )
    else
      stats[:unmapped] += 1
      best = cands.first
      out << row.merge(
        "nmdo_iri" => "", "nmdo_prefix" => "", "nmdo_label" => "",
        "score" => (best && best["score"]) || "", "reranked" => false
      )
    end
    print "\r  #{i + 1}/#{rows.size} (#{stats[:mapped]} mapped, #{stats[:unmapped]} unmapped)"
    $stdout.flush
  end
  puts
  [out, stats]
end

icd11_rows = load_tsv(File.join(MOCKDATA, "icd11_scoped.tsv"))
mkn10_rows = load_tsv(File.join(MOCKDATA, "mkn10_scoped.tsv"))

icd11_out, icd11_stats = map_catalog("ICD-11 (English)", icd11_rows)
mkn10_out, mkn10_stats = map_catalog("MKN-10 / ICD-10 (Czech)", mkn10_rows)

def write_csv(path, rows)
  return if rows.empty?
  CSV.open(path, "w") do |csv|
    csv << rows.first.keys
    rows.each { |r| csv << r.values }
  end
end

write_csv(File.join(MOCKDATA, "mapped_icd11.csv"), icd11_out)
write_csv(File.join(MOCKDATA, "mapped_mkn10.csv"), mkn10_out)

prefix_breakdown = ->(rows) {
  Hash.new(0).tap { |h| rows.each { |r| h[r["nmdo_prefix"]] += 1 if r["nmdo_prefix"] && !r["nmdo_prefix"].empty? } }
}

summary = {
  icd11: {
    total: icd11_rows.size,
    mapped: icd11_stats[:mapped],
    unmapped: icd11_stats[:unmapped],
    reranked_exact_match: icd11_stats[:reranked_exact_match],
    hit_rate: (icd11_stats[:mapped].to_f / icd11_rows.size).round(3),
    prefix_breakdown: prefix_breakdown.call(icd11_out),
  },
  mkn10: {
    total: mkn10_rows.size,
    mapped: mkn10_stats[:mapped],
    unmapped: mkn10_stats[:unmapped],
    reranked_exact_match: mkn10_stats[:reranked_exact_match],
    hit_rate: (mkn10_stats[:mapped].to_f / mkn10_rows.size).round(3),
    prefix_breakdown: prefix_breakdown.call(mkn10_out),
  },
}

File.write(File.join(MOCKDATA, "mapping_stats.json"), JSON.pretty_generate(summary))
puts JSON.pretty_generate(summary)

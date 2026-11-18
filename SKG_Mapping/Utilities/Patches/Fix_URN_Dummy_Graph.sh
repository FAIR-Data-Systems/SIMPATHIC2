#!/usr/bin/env bash
# Move graph-less Demokritos metadata out of <urn:dummy> into all_metadata,
# then empty <urn:dummy>. See the two .sparql files for the full rationale.
#
# Run from this directory (Utilities/Patches/), with credentials set first
# (never dba):   export VIRTUOSO_USER=...  VIRTUOSO_PASS=...
#                bash Fix_URN_Dummy_Graph.sh
#
# Writes go to /sparql-auth (HTTP Digest); checks use the anonymous /sparql.
# Stops before step 2 if step 1 did not fully copy the metadata.
set -euo pipefail
: "${VIRTUOSO_USER:?set VIRTUOSO_USER}" "${VIRTUOSO_PASS:?set VIRTUOSO_PASS}"

HOST="http://57.128.119.57:8890"
q() {  # read-only count query -> prints the single number
  curl -sf -m 600 -G "$HOST/sparql" --data-urlencode "query=$1" \
       -H 'Accept: text/tab-separated-values' | tail -1
}
update() {
  curl -sf -m 600 -X POST "$HOST/sparql-auth" --digest \
       --user "${VIRTUOSO_USER}:${VIRTUOSO_PASS}" \
       --data-urlencode "update@$1"
  echo
}

PREFIXED='FILTER(STRSTARTS(STR(?s),"urn:simpathic:context:dem_") || STRSTARTS(STR(?s),"urn:simpathic:context:bv_") || STRSTARTS(STR(?s),"urn:simpathic:context:rad_"))'
NOT_COPIED="SELECT (COUNT(*) AS ?n) WHERE { GRAPH <urn:dummy> { ?s ?p ?o } $PREFIXED FILTER NOT EXISTS { GRAPH <urn:simpathic:context:all_metadata> { ?s ?p ?o } } }"
DUMMY='SELECT (COUNT(*) AS ?n) WHERE { GRAPH <urn:dummy> { ?s ?p ?o } }'
META='SELECT (COUNT(*) AS ?n) WHERE { GRAPH <urn:simpathic:context:all_metadata> { ?s ?p ?o } }'

echo "BEFORE: urn:dummy=$(q "$DUMMY")  all_metadata=$(q "$META")  not-yet-copied=$(q "$NOT_COPIED")"
echo "        (expected on 2026-11-18: 23500 / 1148121 / 3908)"

echo "== STEP 1: copy provider-prefixed metadata into all_metadata"
update Fix_URN_Dummy_Graph_1_copy.sparql
left=$(q "$NOT_COPIED")
echo "after step 1: not-yet-copied=$left  all_metadata=$(q "$META")"
if [ "$left" != "0" ]; then
  echo "ABORT: $left triples were not copied; step 2 NOT run. <urn:dummy> is untouched." >&2
  exit 1
fi

echo "== STEP 2: remove context metadata from urn:dummy"
update Fix_URN_Dummy_Graph_2_clear.sparql
echo "AFTER:  urn:dummy=$(q "$DUMMY")  all_metadata=$(q "$META")"
echo "        (expected: 0 / 1152029)"

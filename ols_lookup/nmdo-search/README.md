# nmdo-search

Semantic search over the **Neuromuscular Disease Ontology** (NMDO), returning
ranked OBO-namespace terms with deep-links into your OLS4 instance.

## How it works

```
User query
    │
    ▼
Ruby/Sinatra app  ──POST /embed──►  Python/transformers sidecar
    │                                (SapBERT-UMLS-2020AB-all-lang-from-XLMR,
    │                                 CPU-only, multilingual)
    │  ◄── embedding vector ──────────────────────────────────────
    │
    ▼
Cosine similarity against in-memory index
    │
    ▼
Ranked results JSON  (with ols4_url deep-links)
```

- **Ruby app** owns: OWL parsing, index management, cosine search, REST API.
- **Python sidecar** owns: nothing except embedding vectors. You never need to
  touch Python for any business logic change.
- The embedder is **not exposed** to the internet — only the Ruby app can reach it.
- The index is **persisted** to a Docker volume so restarts are instant. On
  startup the Ruby app also probes the embedder's current output dimension
  and discards a persisted index that doesn't match (e.g. left over from a
  prior embedding model) rather than silently comparing incompatible
  vectors — see `TermIndex#load_from_disk!`.

## Requirements

- Docker + Docker Compose (v2)
- ~1.1 GB disk for the embedding model (downloaded once at build time)
- ~1.8-2 GB RAM at runtime (model + index for ~4,000 terms) — measured on a
  2-core/CPU-only dev VM; budget 2-3 GB free for comfortable headroom.
- No GPU required.

## Quick start

```bash
git clone <this-repo>
cd nmdo-search

# Build and start (first build downloads the embedding model — ~2 min)
docker compose up --build -d

# Watch logs
docker compose logs -f

# The service is ready when you see:
#   Index built: N terms at ...
```

## API

### `GET /llm_search/health`

Returns service status.

```json
{
  "status": "ready",
  "term_count": 1847,
  "built_at": "2026-04-27T10:30:00Z",
  "embedder_online": true
}
```

`status` will be `"building"` while the index is being constructed on first startup.

---

### `GET /llm_search/search?q=<query>&top_k=<n>`

Returns semantically similar ontology terms.

| Parameter | Required | Default | Notes |
|-----------|----------|---------|-------|
| `q`       | ✅       | —       | Free-text query |
| `top_k`   | ❌       | 10      | Max 50 |

**Example:**

```
GET /llm_search/search?q=difficulty+walking&top_k=5
```

```json
{
  "query": "difficulty walking",
  "top_k": 5,
  "results": [
    {
      "score": 0.8921,
      "iri": "http://purl.obolibrary.org/obo/HP_0002355",
      "short_id": "HP_0002355",
      "prefix": "hp",
      "label": "Difficulty walking",
      "definition": "Reduced ability to walk due to neurological, muscular, or skeletal conditions.",
      "synonyms": ["Gait disturbance", "Walking difficulty"],
      "ols4_url": "https://simpathic.services/ols/ontologies/hp/classes/http%253A%252F%252Fpurl.obolibrary.org%252Fobo%252FHP_0002355"
    },
    ...
  ]
}
```

The `ols4_url` field takes the user directly to that term's page in your OLS4 instance.

---

### `POST /llm_search/reindex`

Triggers a background re-fetch of the OWL file and rebuilds the index. Useful
after your ontology is updated upstream. Returns `202 Accepted` immediately.

```bash
curl -X POST http://localhost:4567/llm_search/reindex
```

The old index remains live during the rebuild. Poll `/llm_search/health` to confirm completion.

## Configuration

All settings are environment variables in `docker-compose.yml`:

| Variable       | Default | Description |
|----------------|---------|-------------|
| `OWL_URL`      | NMDO GitHub raw URL | URL to fetch the OWL file from |
| `EMBEDDER_URL` | `http://embedder:5001` | Internal URL of the Python sidecar |
| `OLS4_BASE_URL`| `https://simpathic.services/ols4` | Base URL of your OLS4 instance |
| `TOP_K`        | `10` | Default number of results |
| `INDEX_FILE`   | `/data/index.json` | Where to persist the built index |

## Exposing via nginx/Caddy

The search service listens on container port **4567**, mapped to host port
**11000** (see `docker-compose.yml`). If you want to serve it at
`https://simpathic.services/nmdo-search/`, add a reverse proxy block:

**Caddy example:**
```
simpathic.services {
    handle /nmdo-search/* {
        uri strip_prefix /nmdo-search
        reverse_proxy localhost:11000
    }
    # ... your existing OLS4 proxy block
}
```

**nginx example:**
```nginx
location /nmdo-search/ {
    proxy_pass http://localhost:11000/;
    proxy_set_header Host $host;
}
```

## Rebuilding after an ontology update

```bash
curl -X POST https://simpathic.services/nmdo-search/llm_search/reindex
# Then poll:
curl https://simpathic.services/nmdo-search/llm_search/health
```

## Extending the service

All Ruby logic lives in `ruby-app/app.rb`. Key areas to modify:

- **`OwlParser`** — change which annotations are extracted (e.g. add `hasRelatedSynonym`)
- **`TermIndex#search`** — add score boosting (e.g. boost exact label matches)
- **New endpoints** — add routes at the bottom of `app.rb`

The Python sidecar (`embedder/app.py`) should rarely need changes. If you want
a different embedding model, change `MODEL_NAME` there and in the Dockerfile's
pre-download line, then rebuild: `docker compose build embedder`. After
switching models, either delete the `index_data` volume or just restart the
`search` service — `TermIndex#load_from_disk!` detects the dimension change
and rebuilds automatically (see "How it works" above), so this is safe to
skip if you forget.

## Swapping the embedding model

The model `cambridgeltl/SapBERT-UMLS-2020AB-all-lang-from-XLMR` was chosen
(2026-09) for:
- Trained via metric learning directly on UMLS synonym pairs — its training
  objective (cluster different surface forms of the same concept) is the same
  task as this project's term matching, unlike a general-purpose sentence
  embedder.
- Cross-lingual: built on XLM-R-base, so non-English queries (Spanish, French,
  ...) can match NMDO's English-labelled terms — needed for pan-European
  partner data. Measured: minimal quality loss on Spanish, mostly good on
  French with one known miss ("pied tombant" / French for "foot drop" lands
  on the wrong concept at low confidence — a real gap, not solved by this
  model alone).
- 768-dimensional vectors, ~1.1 GB download, no GPU required.

**Not available via `fastembed`** (checked 2026-09 against its 30 curated
ONNX models — no match), so the sidecar loads it via plain `transformers`
instead. Two things to know if you touch `embedder/app.py` or `Dockerfile`:
- Load the tokenizer with `use_fast=False` and keep `transformers` pinned to
  `4.46.3` — `transformers>=5`'s fast-tokenizer conversion path has a bug
  reading this model's sentencepiece file (misroutes it through a tiktoken
  parser and fails). `sentencepiece` and `tiktoken` are both required deps.
- Pool with the `[CLS]` token, L2-normalized — **not** mean-pooling — per
  SapBERT's own usage docs. Using the wrong pooling will silently produce
  low-quality embeddings rather than an error.

The previous model, `sentence-transformers/all-MiniLM-L6-v2` (80 MB,
fastembed/ONNX, 384-dim, English-only), is still a reasonable choice if
you need a smaller/faster footprint and don't need multilingual queries or
UMLS-tuned concept matching.

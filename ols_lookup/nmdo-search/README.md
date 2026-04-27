# nmdo-search

Semantic search over the **Neuromuscular Disease Ontology** (NMDO), returning
ranked OBO-namespace terms with deep-links into your OLS4 instance.

## How it works

```
User query
    │
    ▼
Ruby/Sinatra app  ──POST /embed──►  Python/FastEmbed sidecar
    │                                (all-MiniLM-L6-v2, ONNX, CPU-only)
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
- The index is **persisted** to a Docker volume so restarts are instant.

## Requirements

- Docker + Docker Compose (v2)
- ~300 MB disk for the embedding model (downloaded once at build time)
- ~500 MB RAM at runtime (model + index for ~2,000 terms)

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

### `GET /health`

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

### `GET /search?q=<query>&top_k=<n>`

Returns semantically similar ontology terms.

| Parameter | Required | Default | Notes |
|-----------|----------|---------|-------|
| `q`       | ✅       | —       | Free-text query |
| `top_k`   | ❌       | 10      | Max 50 |

**Example:**

```
GET /search?q=difficulty+walking&top_k=5
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
      "ols4_url": "https://simpathic.services/ols4/ontologies/hp/classes/http%253A%252F%252Fpurl.obolibrary.org%252Fobo%252FHP_0002355"
    },
    ...
  ]
}
```

The `ols4_url` field takes the user directly to that term's page in your OLS4 instance.

---

### `POST /reindex`

Triggers a background re-fetch of the OWL file and rebuilds the index. Useful
after your ontology is updated upstream. Returns `202 Accepted` immediately.

```bash
curl -X POST http://localhost:4567/reindex
```

The old index remains live during the rebuild. Poll `/health` to confirm completion.

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

The search service runs on port **4567**. If you want to serve it at
`https://simpathic.services/nmdo-search/`, add a reverse proxy block:

**Caddy example:**
```
simpathic.services {
    handle /nmdo-search/* {
        uri strip_prefix /nmdo-search
        reverse_proxy localhost:4567
    }
    # ... your existing OLS4 proxy block
}
```

**nginx example:**
```nginx
location /nmdo-search/ {
    proxy_pass http://localhost:4567/;
    proxy_set_header Host $host;
}
```

## Rebuilding after an ontology update

```bash
curl -X POST https://simpathic.services/nmdo-search/reindex
# Then poll:
curl https://simpathic.services/nmdo-search/health
```

## Extending the service

All Ruby logic lives in `ruby-app/app.rb`. Key areas to modify:

- **`OwlParser`** — change which annotations are extracted (e.g. add `hasRelatedSynonym`)
- **`TermIndex#search`** — add score boosting (e.g. boost exact label matches)
- **New endpoints** — add routes at the bottom of `app.rb`

The Python sidecar (`embedder/app.py`) should rarely need changes. If you want
a different embedding model, change `MODEL_NAME` there and in the Dockerfile's
pre-download line, then rebuild: `docker compose build embedder`.

## Swapping the embedding model

The model `sentence-transformers/all-MiniLM-L6-v2` was chosen for:
- 80 MB size — fast Docker build, minimal RAM
- ONNX-backed via `fastembed` — no GPU needed, fast on CPU
- 384-dimensional vectors — excellent for short biomedical labels + definitions

If you want higher quality at slightly more CPU cost, change `MODEL_NAME` in
`embedder/app.py` and the Dockerfile to `"BAAI/bge-small-en-v1.5"` (~130 MB).

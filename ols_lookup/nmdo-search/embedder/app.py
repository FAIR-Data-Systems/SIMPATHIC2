"""
Embedding sidecar for nmdo-search.
Uses transformers (CPU) to serve a single /embed endpoint.
Called internally by the Ruby Sinatra app - not exposed to the internet.

MODEL NOTE: this model is not in fastembed's curated ONNX model list (checked
2026-09 against fastembed 0.8.0's 30 supported models - no match), so it's
loaded directly via transformers rather than fastembed. transformers>=5's
fast-tokenizer conversion path also has a bug reading this model's
sentencepiece file (misroutes it through a tiktoken parser, raising
"tiktoken is required" / a bpe-parse error) - pin transformers==4.46.3 and
load with use_fast=False to avoid it. Representation is the [CLS] token,
L2-normalized, per cambridgeltl's own SapBERT usage docs - NOT mean-pooling.
"""

import torch
from transformers import AutoTokenizer, AutoModel
from flask import Flask, request, jsonify

# Multilingual SapBERT: UMLS-synonym-trained (concept normalization objective,
# the same task as this project's term matching), cross-lingual via XLM-R-base
# so non-English queries (Spanish, French, ...) can match NMDO's English terms.
MODEL_NAME = "cambridgeltl/SapBERT-UMLS-2020AB-all-lang-from-XLMR"
MAX_LENGTH = 128  # generous enough for label + definition + synonyms text

app = Flask(__name__)

print(f"Loading embedding model: {MODEL_NAME} ...")
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME, use_fast=False)
model = AutoModel.from_pretrained(MODEL_NAME)
model.eval()
print("Model ready.")


@torch.no_grad()
def embed_texts(texts):
    enc = tokenizer(texts, padding=True, truncation=True, max_length=MAX_LENGTH,
                     return_tensors="pt")
    out = model(**enc)
    cls = out.last_hidden_state[:, 0, :]  # [CLS] token representation
    cls = torch.nn.functional.normalize(cls, p=2, dim=1)
    return cls.numpy()


@app.route("/health")
def health():
    return jsonify({"status": "ok", "model": MODEL_NAME})


@app.route("/embed", methods=["POST"])
def embed():
    """
    POST /embed
    Body: { "texts": ["text one", "text two", ...] }
    Returns: { "embeddings": [[0.1, 0.2, ...], ...] }
    """
    data = request.get_json(force=True)
    texts = data.get("texts", [])
    if not texts:
        return jsonify({"error": "No texts provided"}), 400

    embeddings = embed_texts(texts)
    return jsonify({"embeddings": embeddings.tolist()})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, debug=False)

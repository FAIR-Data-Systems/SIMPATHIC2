"""
Minimal embedding sidecar for nmdo-search.
Uses fastembed (ONNX-backed, CPU-friendly) to serve a single /embed endpoint.
Called internally by the Ruby Sinatra app - not exposed to the internet.
"""

from fastembed import TextEmbedding
from flask import Flask, request, jsonify
import numpy as np

app = Flask(__name__)

# all-MiniLM-L6-v2: 80MB, 384-dim, very fast on CPU, great for short biomedical labels+defs
MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
print(f"Loading embedding model: {MODEL_NAME} ...")
model = TextEmbedding(MODEL_NAME)
print("Model ready.")


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

    embeddings = list(model.embed(texts))
    # Convert numpy arrays to plain Python lists for JSON serialisation
    return jsonify({"embeddings": [e.tolist() for e in embeddings]})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, debug=False)

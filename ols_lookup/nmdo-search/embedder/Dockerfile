FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu
RUN pip install --no-cache-dir -r requirements.txt

# Pre-download the model at build time so startup is instant.
# use_fast=False: see app.py's MODEL NOTE for why (transformers>=5's fast-
# tokenizer conversion path can't read this model's sentencepiece file).
RUN python -c "from transformers import AutoTokenizer, AutoModel; \
    m='cambridgeltl/SapBERT-UMLS-2020AB-all-lang-from-XLMR'; \
    AutoTokenizer.from_pretrained(m, use_fast=False); \
    AutoModel.from_pretrained(m)"

COPY app.py .
EXPOSE 5001
CMD ["python", "app.py"]

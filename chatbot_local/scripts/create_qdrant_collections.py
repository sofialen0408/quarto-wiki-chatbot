import os
from dotenv import load_dotenv
from tqdm import tqdm
from sentence_transformers import SentenceTransformer
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct

from constants import client, collection_name
from helpers import get_chunks_fixed_size_with_overlap, stable_int_id
from qmd_extraction import load_qmd_files

load_dotenv()

QDRANT_URL = os.getenv("QDRANT_URL")
QDRANT_API_KEY = os.getenv("QDRANT_API_KEY")  # optional
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL")

if not QDRANT_URL:
    raise RuntimeError("QDRANT_URL is not set in .env")
if not EMBEDDING_MODEL:
    raise RuntimeError("EMBEDDING_MODEL is not set in .env")

#Set chunking parameters
CHUNK_SIZE = 300
CHUNK_OVERLAP = 0.1

# Build docs
quarto_docs = []
for data in load_qmd_files():
    path = data["path"]
    doc_title = path.split("/")[-1]
    chunks = get_chunks_fixed_size_with_overlap(data["content"], CHUNK_SIZE, CHUNK_OVERLAP)

    for i, chunk in enumerate(chunks):
        quarto_docs.append({
            "title": f"{doc_title} - Chunk {i+1}",
            "content": chunk,
            "source": path,
            "chunk": i + 1,
        })

print(f"Built {len(quarto_docs)} chunks")

# Embedder
embedding_model = SentenceTransformer(f"sentence-transformers/{EMBEDDING_MODEL}")
dim = embedding_model.get_sentence_embedding_dimension()

# Create collection if missing
existing = {c.name for c in client.get_collections().collections}
if collection_name not in existing:
    print(f"== Creating Collection {collection_name} ==")
    client.create_collection(
        collection_name=collection_name,
        vectors_config=VectorParams(size=dim, distance=Distance.COSINE),
    )
else:
    print(f"== Collection {collection_name} Already Exists ==")

# Stream embed + upsert
UPSERT_BATCH = 128
ENCODE_BATCH = 64

points = []
for start in tqdm(range(0, len(quarto_docs), ENCODE_BATCH), desc="Embedding & Upserting"):
    batch_docs = quarto_docs[start:start + ENCODE_BATCH]
    batch_texts = [d["content"] for d in batch_docs]

    batch_vecs = embedding_model.encode(
        batch_texts,
        normalize_embeddings=True,
        batch_size=ENCODE_BATCH,
    )

    for doc, vec in zip(batch_docs, batch_vecs):
        pid = stable_int_id(f'{doc["source"]}::{doc["chunk"]}')
        points.append(
            PointStruct(
                id=pid,
                vector=vec.tolist(),
                payload={
                    "title": doc["title"],
                    "content": doc["content"],
                    "source": doc["source"],
                    "chunk": doc["chunk"],
                    "embedding_model": EMBEDDING_MODEL,
                },
            )
        )

    if len(points) >= UPSERT_BATCH:
        client.upsert(collection_name=collection_name, points=points)
        points = []

if points:
    client.upsert(collection_name=collection_name, points=points)

print("✅ Completed embedding and upserting to Qdrant")
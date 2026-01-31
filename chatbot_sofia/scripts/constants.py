# Constants.py
import re
from ollama import Client
from qdrant_client import QdrantClient
from dotenv import load_dotenv
import os

load_dotenv()  # reads .env automatically

# Environment variables
OLLAMA_URL = os.getenv("OLLAMA_URL")
QDRANT_URL = os.getenv("QDRANT_URL")
QDRANT_API_KEY = os.getenv("QDRANT_API_KEY")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL")

# Ollama client connection
ollama_client = Client(OLLAMA_URL)

# Set up Qdrant connection & collection name
client = QdrantClient(url=QDRANT_URL, api_key=QDRANT_API_KEY)

model_safe = re.sub(r"[^\w]+", "_", EMBEDDING_MODEL)
collection_name = f"QUARTO_Embedding_{model_safe}"

# Readiness + list collections
try:
    collections = client.get_collections()
    print("✅ Successfully connected to Qdrant!")
    print("Collections:", [c.name for c in collections.collections])
except Exception as e:
    raise Exception(f"❌ Failed to connect to Qdrant: {e}")
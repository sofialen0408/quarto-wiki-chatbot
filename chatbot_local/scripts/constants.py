# Constants.py
import re
from ollama import Client
from qdrant_client import QdrantClient
from dotenv import load_dotenv
import os
from openai import OpenAI

load_dotenv()  # reads .env automatically

# Environment variables
OLLAMA_URL = os.getenv("OLLAMA_URL")

QDRANT_URL = os.getenv("QDRANT_URL")
QDRANT_API_KEY = os.getenv("QDRANT_API_KEY")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_BASE_URL = os.getenv("OPENAI_BASE_URL")
MODEL_ID = os.getenv("MODEL_ID")

if OLLAMA_URL:
    # Ollama client connection
    llm_client = Client(OLLAMA_URL)
    client_type = "ollama"
    print("✅ Ollama Client Connected")
else:
    # OpenAI client connection
    REGION = "us-east-1"
    llm_client = OpenAI(api_key=OPENAI_API_KEY, base_url=OPENAI_BASE_URL)
    client_type = "openai"
    print("✅ OpenAI Client Connected")

# Set up Qdrant connection & collection name
db_client = QdrantClient(url=QDRANT_URL, api_key=QDRANT_API_KEY)

model_safe = re.sub(r"[^\w]+", "_", EMBEDDING_MODEL)
collection_name = f"QUARTO_Embedding_{model_safe}"

# Readiness + list collections
try:
    collections = db_client.get_collections()
    print("✅ Successfully connected to Qdrant!")
    print("Collections:", [c.name for c in collections.collections])
except Exception as e:
    raise Exception(f"❌ Failed to connect to Qdrant: {e}")
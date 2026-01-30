# Constants.py
import re
from ollama import Client
from qdrant_client import QdrantClient
from dotenv import load_dotenv
import os

load_dotenv()  # reads .env automatically

OLLAMA_URL = os.getenv("OLLAMA_URL")
QDRANT_URL = os.getenv("QDRANT_URL")
#QDRANT_API_KEY = os.getenv("QDRANT_API_KEY")

## MODEL INFO ##
llms = [
    'llama3.2:3b-instruct-q4_K_M',
    'llama3.3:70b-instruct-q4_K_M',
    'llama3.2-vision:11b-instruct-q4_K_M'
]

embedding_models = [
    'mxbai-embed-large:latest'
]

# Ollama client connection
ollama_client = Client(OLLAMA_URL)

# Set up Qdrant connection
client = QdrantClient(url=QDRANT_URL) #api_key=qdrant_api_key)

# Readiness + list collections
try:
    collections = client.get_collections()
    print("✅ Successfully connected to Qdrant!")
    print("Collections:", [c.name for c in collections.collections])
except Exception as e:
    raise Exception(f"❌ Failed to connect to Qdrant: {e}")
# finally:
#     client.close()

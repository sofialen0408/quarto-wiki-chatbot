# Constants.py
# Storing variables and datasets
import re
from ollama import Client
import weaviate

## MODEL INFO ##
llms = [
    'llama3.2:3b-instruct-q4_K_M', 
    'llama3.3:70b-instruct-q4_K_M', 
    'llama3.2-vision:11b-instruct-q4_K_M'
]

embedding_models = [
    'mxbai-embed-large:latest'
]

formatted_embedding_models = [re.sub(r'[^\w\s]', '_', embed) for embed in embedding_models]

## DEFINE WEAVIATE SERVER ATTRIBUTES ##
# hostname = "172.18.0.2" # Docker IPAddress attribute
# port = 8080 # Default for Weaviate, listed in Verba deployment
hostname = "131.110.210.165" # Server IP
port = 80 # Normal HTTP port

## DEFINE OLLAMA ATTRIBUTES ##
ollama_url = "http://131.110.210.167:443"
ollama_client = Client(ollama_url)

# Set up Weaviate connections
client = weaviate.connect_to_local(
    host=hostname,
    port=port,
    grpc_port=50051,
    )

if client.is_ready():
    print("✅ Successfully connected to Weaviate!")
else:
    raise Exception("❌ Failed to connect to Weaviate!")

collections = client.collections.list_all()

client.close()
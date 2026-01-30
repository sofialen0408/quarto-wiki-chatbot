import weaviate
import weaviate.classes.config as wvcc
import os
import re
from tqdm import tqdm
import pandas as pd
from typing import List
import glob

# Read in local dependencies
from constants import client, hostname, port, embedding_models, ollama_client, ollama_url
from helpers import get_chunks_fixed_size_with_overlap,word_splitter
from qmd_extraction import get_qmd_files_from_github, get_repo_tree

# Define Quarto documents folder
CHUNK_SIZE = 300  # Number of characters per chunk (adjustable)
CHUNK_OVERLAP = 0.1

quarto_docs = []
for path, content in get_qmd_files_from_github():
            doc_title = path.split("/")[-1]
            print(doc_title)
            # Split content into chunks
            chunks = get_chunks_fixed_size_with_overlap(content, CHUNK_SIZE, CHUNK_OVERLAP)
            for i, chunk in enumerate(chunks):
                quarto_docs.append({
                    "title": f"{doc_title} - Chunk {i+1}",
                    "content": chunk,
                    "source": path  # Keep track of the original file
                })


# Instantiate Weaviate client
print("Initiating Weaviate client...")
client = weaviate.connect_to_local(
    host=hostname,
    port=port,
    grpc_port=50051,
)

# Iterate through embedding models
for embedding_model in embedding_models:
    embedding_model_formatted = re.sub(r'[^\w\s]', '_', embedding_model)
    chunking_method = "custom_overlap_automated"  # Clarify chunking - manual
    collection_name = f"QUARTO_Embedding_{embedding_model_formatted}_Chunking_{chunking_method}"

    # Check if the collection already exists
    collections = client.collections.list_all()
    if collection_name in collections:
        print(f"== Collection {collection_name} Already Exists ==")
        

    # Create a new collection
    else:
        print(f"== Creating Collection {collection_name} ==")
        client.collections.create(
            collection_name,
            vectorizer_config=[
                wvcc.Configure.NamedVectors.text2vec_ollama(
                    name="title_vector",
                    source_properties=["title"],
                    api_endpoint=ollama_url,
                    model=embedding_model,
                ),
                wvcc.Configure.NamedVectors.text2vec_ollama(
                    name="content_vector",
                    source_properties=["content"],  # ✅ Embedding full document chunks
                    api_endpoint=ollama_url,
                    model=embedding_model,
                ),
            ],
        )

    # Retrieve collection
    collection = client.collections.get(collection_name)

    # Load Quarto document chunks into Weaviate
    print(" ... loading Quarto document chunks ...")
    with collection.batch.dynamic() as batch:
        for doc in tqdm(quarto_docs, desc="Uploading chunks"):
            weaviate_obj = {
                "title": doc["title"],
                "content": doc["content"],
                "source": doc["source"],  # Keep track of the original file
            }

            batch.add_object(properties=weaviate_obj)

    print(" == Loading Complete == ")
    print("== Failed Objects ==")
    failed_objs = collection.batch.failed_objects
    print(f"    Total Failed Objects: {failed_objs}")

client.close()
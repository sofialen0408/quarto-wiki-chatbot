import scripts.helpers as h
import scripts.constants as c
from weaviate.classes.query import MetadataQuery

# Connect to Weaviate Client
client = c.client
client.connect()

# replace with target collection name 
COLLECTION_NAME = "QUARTO_Embedding_mxbai_embed_large_latest_Chunking_custom" 

# Chatbot Query Function
def query_weaviate(text_input: str, COLLECTION_NAME: str = COLLECTION_NAME):
    """
    This function performs the hybrid query to Weaviate and returns relevant documents.
    """
    collection = client.collections.get(COLLECTION_NAME)

    # Hybrid Querying
    response = collection.query.hybrid(
            query=text_input,
            limit=3,
            alpha=0.5,
            return_metadata=MetadataQuery(score=True, explain_score=True),
            target_vector="content_vector"  # chunk content stored in "content_vector"
        )

    # Filter relevant documents by score
    relative_score = 0.85  # replace with desired threshold
    max_score = response.objects[0].metadata.score

    returned_docs = ""
    returned_chunks = ""
    
    for o in response.objects:

        # Return document title and chunk content
        returned_document = o.properties["source"]
        returned_chunk = o.properties["content"]  

        # Filter relevant documents by score
        if o.metadata.score >= relative_score * max_score:
            returned_docs = returned_document + "; \n\n" + returned_docs
            returned_chunks = returned_chunk + "\n\n" + returned_chunks
        
    # Format the prompt
    combined_prompt = h.create_prompt(text_input, returned_chunks, returned_docs)

    # Generate the LLM response
    response = h.llm_generate(prompt=combined_prompt, client=c.ollama_client, model='llama3.3:70b-instruct-q4_K_M')
    return(response)



# Close Connection Function
def close_client():
    """
    This function closes the Weaviate client connection.
    """
    client.close()
# helpers.py 
# Helper functions
from ollama import Client
from typing import List
import re

def llm_generate(prompt, client, model):

    response = client.generate(
        model=model,
        prompt=prompt,
        # system="Keep responses brief"
    )

    return response['response']

def create_prompt(question, retrieved_chunk, document):
    ''' Helper function to assemble system prompt, the user question, retrieved relevant chunk(s), and the document of origin into a prompt to send to the LLM '''

    system_prompt = '''You a chatbot for Retrieval Augmented Generation (RAG).
    You will receive a user query and context pieces that have a semantic similarity to that query. 
    Please answer these user queries only with the provided context. 
    If the provided document contains only a YAML header, ignore.
    Mention documents you used from the context if you use them and cite at the end of each response to reduce hallucination. 
    If the provided documentation does not provide enough information, say so. 
    Sometimes documents will be uncessary, so if the user asks questions about you as a chatbot specifially, answer them naturally. 
    If the answer requires code examples encapsulate them with ```programming-language-name ```.'''

    combined_prompt = f'''

    {system_prompt}

    User Question: {question}

    Relevant Context:{retrieved_chunk}

    Context Document Source: {document}
    '''

    return combined_prompt

def llm_chat(prompt, model_url, model_name):
    ''' Helper function to feed the combined prompt to LLM of choice '''

    client = Client(
    host=model_url,
    )
    response = client.chat(model=model_name, messages=[
    {
        'role': 'user',
        'content': prompt,
    }
    ], stream=False, keep_alive=False)
    return response

def retrieve_collection_name(collections, chunk_method, embedding_model):
    ''' Retrieve the exact Weaviate collection name if it matches the chunk method and the embedding model '''

    # Large chunks respond to collections that contain "complete_question", small to custom
    chunk_criteria = "complete_question" if chunk_method == "Large" else "custom"

    # Filter the collections that have these criteria in their name
    filtered_collections = [schema for schema in collections if (chunk_criteria in schema and embedding_model in schema)]

    collection = filtered_collections[0] if len(filtered_collections) > 0 else "None"
    return collection


# Split the text into units (words, in this case)
def word_splitter(source_text: str) -> List[str]:
    source_text = re.sub("\s+", " ", source_text)  # Replace multiple whitespces
    return re.split("\s", source_text)  # Split by single whitespace


# Iterate through text and join the split words with respect to chunk size and overlap fraction
def get_chunks_fixed_size_with_overlap(text: str, chunk_size: int, overlap_fraction: float) -> List[str]:
    text_words = word_splitter(text)
    overlap_int = int(chunk_size * overlap_fraction)
    chunks = []
    for i in range(0, len(text_words), chunk_size):
        chunk_words = text_words[max(i - overlap_int, 0): i + chunk_size]
        chunk = " ".join(chunk_words)
        chunks.append(chunk)
    return chunks
 
# def clean_string(text):
#     ''' clean document names so we can assess similarity to expected document tag'''
#     text = text.replace(r".docx", "")
#     text = text.replace(r" HR VAContentDev-", "")
#     # Remove Draft
#     text = re.sub(r'-Draft\d+', '', text) # Matches '-Draft #'
#     text = re.sub(r' Draft \d+', '', text) # Matches ' Draft #'
#     text = re.sub(r'-Draft \d+', '', text) # Matches '-Draft#'
#     # Remove Dates 
#     text = re.sub(r'^\d{4}-\d{2}-\d{2}', '', text) # Matches 'YYYY-MM-DD '
#     text = re.sub(r'^\d{4}-\d{2}-\d{1}', '', text) # Matches 'YYYY-MM-D'
#     return text

# def calculate_similarity(str1, str2):
#     ''' calculate similarity for the time being to see how close filename is to flagged tag'''

#     # Clean strings
#     str1 = clean_string(str1)
#     str2 = clean_string(str2)

#     # Convert strings into TF-IDF feature vectors
#     vectorizer = TfidfVectorizer()
#     tfidf_matrix = vectorizer.fit_transform([str1, str2])

#     # Calculate cosine similarity
#     similarity = cosine_similarity(tfidf_matrix[0], tfidf_matrix[1])
#     return similarity


# list_response = client.list()

# # Extract the "model" attribute from each item in the list response
# model_names = [model.model for model in list_response.models]

# # Print the list of model names
# print(model_names)


# def llm_query(query, temp=0, seed=42, k=0, p=1.0):    
#     base_url = "http://131.110.210.167:443/"
#     model_name = "llama3.2-vision:11b-instruct-q4_K_M" #"llama2"    
#     try:
#         response = requests.post(
#             f"{base_url}/api/generate",            
#             json={"model": model_name, "prompt": query, "stream": False, "temperature": temp, "seed": seed, "top_k": k, "top_p": p}      
#             )        
#         response.raise_for_status()
#     except requests.exceptions.RequestException as e:        
#         print("Error querying Ollama:", e)    
#         return response
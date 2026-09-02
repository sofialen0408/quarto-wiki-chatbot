# helpers.py
# Helper functions
from ollama import Client
from typing import List
import re
import hashlib
import os
from urllib.parse import quote
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()

MODEL_ID = os.getenv("MODEL_ID")

def llm_generate(prompt, client, model, client_type="openai"):
    if client_type == "openai":
        completion = client.chat.completions.create(
            model=MODEL_ID,
            messages=[{"role": "user", "content": prompt}],
        )
        response = completion.choices[0].message.content
        return response
    elif client_type == "ollama":
        response = client.generate(
            model=model,
            prompt=prompt,
            # system="Keep responses brief"
        )['response']
        return response
    else:
        raise Exception("Client Type Does Not Exist")


def format_sources_for_prompt(sources):
    ''' Render the retrieved sources as a Markdown link list the LLM can copy
    verbatim into its answer. `sources` is a list of {"label", "path"} dicts
    (path = site-relative URL from the Qdrant payload). '''
    if not sources:
        return "(no sources)"
    return "\n".join(f"- [{s['label']}]({s['path']})" for s in sources)


def create_prompt(question, retrieved_chunk, sources):
    ''' Assemble the system prompt, user question, retrieved chunk(s) and the
    list of source links into a single prompt string for the LLM. '''

    source_links = format_sources_for_prompt(sources)

    system_prompt = '''You a chatbot for Retrieval Augmented Generation (RAG).
    You will receive a user query and context pieces that have a semantic similarity to that query.
    Please answer these user queries only with the provided context.
    If the provided document contains only a YAML header, ignore.
    Cite sources INLINE, right after the specific statement they support: put the matching Markdown link from the "Sources" list in parentheses at the end of that sentence or clause, before its punctuation. Example: "Data governance defines who within an organization has authority over data assets ([Data Process and Roles](site/data-products-use-cases/data-product-management-&-governance/data-process-and-roles.html))."
    Only the links in the "Sources" list are valid citations - they point to the knowledge base pages. Any URLs that appear inside the context text are just references within a page; do not use them as your citation. Every answer that uses the context must include at least one "Sources" citation.
    Copy each link EXACTLY as it appears in the "Sources" list - do not change the link text or the target, and do not invent links (never write a link whose target is a plain word like "(GraphGPT)").
    If several consecutive sentences rely on the same source, cite it once after the last of them.
    Do NOT collect citations into a "Sources", "References" or "Citations" section at the end - every citation must sit next to the claim it supports.
    You may use Markdown formatting: fenced code blocks with a language (```r ... ```), inline code, bullet lists, and bold.
    If the provided documentation does not provide enough information, say so.
    Sometimes documents will be uncessary, so if the user asks questions about you as a chatbot specifially, answer them naturally.
    If the answer requires code examples encapsulate them with ```programming-language-name ```.'''

    combined_prompt = f'''

    {system_prompt}

    User Question: {question}

    Relevant Context:{retrieved_chunk}

    Sources (cite by copying these Markdown links verbatim):
    {source_links}
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
    ''' Retrieve the exact Qdrant collection name if it matches the chunk method and the embedding model '''

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


def stable_int_id(s: str) -> int:
    # stable across runs/machines
    return int(hashlib.md5(s.encode("utf-8")).hexdigest()[:16], 16)


# RFC 3986 sub-delims + ":"/"@" are legal unencoded in a path segment; Quarto
# serves those folder names verbatim (e.g. ".../data-product-management-&-governance/..."),
# so encoding "&" as %26 gives a 404. Only characters that actually break URL
# parsing (space, "#", "?", "%") get percent-encoded.
_PATH_SAFE = "!$&'()*+,;=:@"


def qmd_source_to_relurl(source_path: str) -> str:
    """Map a repo-relative .qmd path (as stored in the Qdrant `source` payload)
    to the relative URL of its rendered page on the Quarto site.

    e.g. "site/technology-analytics-references/python/python.qmd"
      -> "site/technology-analytics-references/python/python.html"

    Folders with spaces become %20 (a raw space isn't a valid href and won't
    parse as a Markdown link), but "&" and other path-legal sub-delims are
    left as-is to match how Quarto serves the file. The site origin is
    prepended on the R/UI side.
    """
    if not source_path:
        return ""
    path = source_path.strip().lstrip("/")
    if path.endswith(".qmd"):
        path = path[:-4] + ".html"
    return "/".join(quote(seg, safe=_PATH_SAFE) for seg in path.split("/"))


def source_label(source_path: str) -> str:
    """Human-readable label for a cited source path. Uses the file stem, or the
    parent folder when the file is a section landing page (main/index)."""
    if not source_path:
        return ""
    parts = source_path.strip().lstrip("/").split("/")
    stem = parts[-1]
    if stem.endswith(".qmd"):
        stem = stem[:-4]
    if stem.lower() in ("main", "index") and len(parts) >= 2:
        stem = parts[-2]
    return re.sub(r"[-_]+", " ", stem).strip().title()
 
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
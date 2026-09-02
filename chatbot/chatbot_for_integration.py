import scripts.helpers as h
import scripts.constants as c
import pandas as pd
import duckdb
from datetime import datetime
from qdrant_client import models
from sentence_transformers import SentenceTransformer, util
import os
from dotenv import load_dotenv

load_dotenv()

EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL")
MODEL_ID = os.getenv("MODEL_ID")

# Retrieval score gate. After Qdrant returns the top-`limit` chunks, keep only
# those whose cosine score clears BOTH an absolute floor and a fraction of the
# best hit's score, so weakly-related chunks never become context or citations.
# The cosine scale depends on the embedding model, so both are tunable via .env.
RETRIEVAL_SCORE_MIN = float(os.getenv("RETRIEVAL_SCORE_MIN", "0.25"))
RETRIEVAL_SCORE_RATIO = float(os.getenv("RETRIEVAL_SCORE_RATIO", "0.6"))

DUCKDB_PATH = "feedback.duckdb"
TABLE_NAME = "feedback"

def initialize_feedback_db(filepath: str = DUCKDB_PATH):
    conn = duckdb.connect(filepath)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS feedback (
            query_history TEXT,
            response TEXT,
            avg_rating DOUBLE,
            num_ratings INTEGER,
            timestamp TIMESTAMP
        )
    """)
    conn.close()


def load_past_feedback_duckdb(filepath: str = DUCKDB_PATH, table_name: str = TABLE_NAME):
    if not os.path.exists(filepath):
        print("DuckDB database not found.")
        return pd.DataFrame(columns=["query_history", "response", "avg_rating", "num_ratings", "timestamp"])

    conn = duckdb.connect(filepath)
    try:
        df = conn.execute(f"SELECT * FROM {table_name}").fetchdf()
        print("connected!")
        return df
    except Exception as e:
        print(f"Error reading DuckDB: {e}")
        return pd.DataFrame(columns=["query_history", "response", "avg_rating", "num_ratings", "timestamp"])
    finally:
        conn.close()


def save_feedback_to_duckdb(base, query, response, rating, db_path: str = DUCKDB_PATH):
    """
    Save or update feedback in DuckDB, preserving query_history, avg_rating, and num_ratings logic.
    """
    try:
        dirpath = os.path.dirname(db_path)
        if dirpath:
            os.makedirs(dirpath, exist_ok=True)
        con = duckdb.connect(database=db_path)
        print("Connected to DuckDB!")

        # Create the table if not exists
        con.execute("""
        CREATE TABLE IF NOT EXISTS feedback (
            query_history TEXT,
            response TEXT,
            avg_rating DOUBLE,
            num_ratings INTEGER,
            timestamp TIMESTAMP
        )
        """)

        # Load existing data into DataFrame
        existing_df = con.execute("SELECT * FROM feedback").fetchdf()

        # Try to find matching row
        existing_entry = existing_df[existing_df["query_history"].str.contains(base, na=False)]
        matching_entry = existing_entry[existing_entry["response"] == response]

        if not matching_entry.empty:
            index = matching_entry.index[0]
            old_queries = existing_df.at[index, "query_history"]
            old_avg = existing_df.at[index, "avg_rating"]
            num_ratings = existing_df.at[index, "num_ratings"]

            # Prevent duplicate queries
            query_list = old_queries.split(" | ") if isinstance(old_queries, str) else []
            if query not in query_list:
                query_list.append(query)
            new_queries = " | ".join(query_list)

            # Compute new average rating
            new_avg = (old_avg * num_ratings + rating) / (num_ratings + 1)
            num_ratings += 1

            # Ensure native Python types
            new_avg = float(new_avg)
            num_ratings = int(num_ratings)

            # Update the entry in the table
            con.execute("""
                DELETE FROM feedback
                WHERE query_history = ? AND response = ?
            """, [old_queries, response])

            con.execute("""
                INSERT INTO feedback VALUES (?, ?, ?, ?, ?)
            """, [new_queries, response, new_avg, num_ratings, datetime.now()])
            print("Updated existing feedback entry.")

        else:
            # Create a new feedback entry
            new_feedback = {
                "query_history": query,
                "response": response,
                "avg_rating": float(rating),
                "num_ratings": int(1),
                "timestamp": datetime.now()
            }
            con.execute("""
                INSERT INTO feedback VALUES (?, ?, ?, ?, ?)
            """, list(new_feedback.values()))
            print("Created new feedback entry.")

        con.close()

    except Exception as e:
        print(f"Error saving feedback to DuckDB: {e}")

def find_similar_query(user_input, feedback_df, similarity_threshold=0.7):
    """
    Compare the user's input with past queries and return a past response
    if similarity is above a threshold.
    """

    if feedback_df is None or feedback_df.empty:
        return user_input, None, None  # No past queries to compare

    model = SentenceTransformer(f"sentence-transformers/{EMBEDDING_MODEL}")

    # Extract all past queries as a flat list
    past_queries = []
    query_to_response_map = {}

    for row_idx, row in feedback_df.iterrows():
        queries = row["query_history"].split(" | ")
        response = row["response"]
        avg_rating = row["avg_rating"]
        
        for query in queries:
            past_queries.append(query)

            if query not in query_to_response_map:
                query_to_response_map[query] = []
            
            query_to_response_map[query].append((response, avg_rating))

    print(f"Number of past queries: {len(past_queries)}")
    print(f"Past Queries: {past_queries}")
    print(f"query to response map: {query_to_response_map}")
    
    # Compute similarity scores
    input_embedding = model.encode(user_input, convert_to_tensor=True)
    past_embeddings = model.encode(past_queries, convert_to_tensor=True)
    
    similarities = util.pytorch_cos_sim(input_embedding, past_embeddings)[0]
    print(f"Similarity scores: {similarities.tolist()}")
    best_match_idx = similarities.argmax().item()

    # If similarity is high, return past response and feedback score
    # Store responses with their feedback scores if similarity is above threshold
    responses_with_ratings = []
    for idx, similarity in enumerate(similarities):
        if similarity >= similarity_threshold:
            query = past_queries[idx]
            responses_with_ratings.extend(query_to_response_map.get(query, []))
    
    # If there are valid responses, find the one with the highest feedback score
    if responses_with_ratings:
        # Sort by feedback score (descending order)
        best_response, best_rating = max(responses_with_ratings, key=lambda x: x[1])
        return past_queries[best_match_idx], best_response, best_rating
    
    return user_input, None, None

# Connect to Qdrant Client
client = c.db_client

# replace with target collection name 
COLLECTION_NAME = c.collection_name

# Chatbot Query Function
def query_qdrant(text_input: str, COLLECTION_NAME: str = COLLECTION_NAME):
    """
    Perform query in Qdrant and return documents while considering past feedback.
    """
    initialize_feedback_db()
    feedback_df = load_past_feedback_duckdb()  # Load feedback history
    query, past_response, past_score = find_similar_query(text_input, feedback_df) # Find similar query to avoid calling LLM

    # If past response exists and feedback was HIGH, return it directly.
    # Cached responses don't retain their source list, so return no citations.
    if past_response and past_score >= 1.5:
        print("Returning past response")
        return query, past_response, []
    
    # If past response exists but feedback was LOW, adjust retrieval
    modify_retrieval = past_response is not None and past_score < 1
    limit = 5 if modify_retrieval else 3

    model_name = f"sentence-transformers/{EMBEDDING_MODEL}"

    result = client.query_points(
        collection_name=COLLECTION_NAME,
        query=models.Document(text=text_input, model=model_name), limit=limit
        ).points

    # Drop weakly-related chunks: keep only those at/above both the absolute
    # floor and a fraction of the top hit's score. An off-topic question whose
    # best hit is still below the floor yields no context -> the LLM answers
    # "not enough information" instead of citing an irrelevant page.
    if result:
        top_score = result[0].score or 0.0
        cutoff = max(RETRIEVAL_SCORE_MIN, RETRIEVAL_SCORE_RATIO * top_score)
        kept = [o for o in result if (o.score or 0.0) >= cutoff]
        print(f"Retrieval: top={top_score:.3f} cutoff={cutoff:.3f} "
              f"kept {len(kept)}/{len(result)}")
        result = kept

    # Each chunk's payload already carries the rendered page's URL + title
    # (baked in at ingestion by create_qdrant_collections.py), so retrieval
    # just consolidates a unique, ready-to-link source list -- no path
    # cleaning here or on the R side.
    returned_chunks = []
    sources = []
    seen_urls = set()

    for o in result:
        payload = o.payload or {}
        chunk = payload.get("content", "")
        if chunk:
            returned_chunks.append(chunk)

        url = payload.get("url", "")
        if url and url not in seen_urls:
            seen_urls.add(url)
            sources.append({
                "label": payload.get("page_title") or url,
                "path": url,
            })

    chunks_text = "\n\n---\n\n".join(returned_chunks)

    combined_prompt = h.create_prompt(text_input, chunks_text, sources)

    response = h.llm_generate(
            prompt=combined_prompt,
            client=c.llm_client,
            model=MODEL_ID,
            client_type=c.client_type
            )

    return(query, response, sources)

# if __name__ == "__main__":
#     user_input = "How can I use data products to improve decision-making in my organization?"
#     user_input, response = query_qdrant(user_input)
#     print("User Input:", user_input)
#     print("Final Response:", response)


    # return response
    # returned_docs = ""
    # returned_chunks = ""

    # print(f"This is how many objects were pulled: {len(result)}")
    
    # for o in result:
    #     print(f"Source: {o.payload['source']}, Score: {o.score}")
    #     # Return document title and chunk content
    #     returned_document = o.payload['source']
    #     returned_chunk = o.payload['content']

    #     # # Filter relevant documents by score
    #     # if o.metadata.score >= relative_score * max_score:
    #     #     returned_docs = returned_document + "; \n\n" + returned_docs
    #     #     returned_chunks = returned_chunk + "\n\n" + returned_chunks
    
    # #Format the prompt
    # combined_prompt = h.create_prompt(text_input, returned_chunks, returned_docs)

    # # Generate the LLM response
    # response = h.llm_generate(prompt=combined_prompt, client=c.ollama_client, model='llama3.3:70b-instruct-q4_K_M')
    # return(query, response)
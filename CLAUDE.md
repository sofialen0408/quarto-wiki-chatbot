# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Quarto-based knowledge base website (PA Knowledge Base) with an integrated RAG (Retrieval Augmented Generation) chatbot. The chatbot uses vector search over `.qmd` documentation files to provide contextual answers, and learns from user feedback over time.

The Weaviate → Qdrant migration is complete in code — no `.py` file references Weaviate anymore; only the unused `weaviate-client` dependency lingers in `chatbot/pyproject.toml`. Recent feature branches (`3-correct-chatbot-window`, `4-correct-sending-chats`) are UI/behaviour fixes to the Shiny chatbot.

**Two READMEs are stale**: `README.md` and `chatbot/README.md` still tell you to work under a `chatbot_local/` folder and copy `chatbot_local/.env` — that folder was renamed to `chatbot/` (commit "single chatbot folder"). Trust the `Makefile` and this file for paths, not the READMEs.

## Architecture

### Components

1. **Quarto Website** (`site/` folder)
   - Documentation stored as `.qmd` files, organized under `site/data-products-use-cases/`, `site/technology-analytics-references/`, and `site/quarto_llm/`
   - Site navigation/config lives in `_quarto.yml` at the repo root — indentation matters, and every new `.qmd` file must be registered here or it won't appear on the site
   - Rendered output goes to `output/` (configured via `output-dir` in `_quarto.yml`, NOT Quarto's default `_site/`)

2. **Chatbot Backend** (`chatbot/` — Python, managed with Poetry)
   - **Vector database**: Qdrant, run via Docker Compose (`docker-compose.yml` at repo root)
   - **Embeddings**: sentence-transformers models (configurable via `.env`, e.g. `all-MiniLM-L6-v2`)
   - **LLM**: auto-detected client — Ollama if `OLLAMA_URL` is set, otherwise an OpenAI-compatible client (works with AWS Bedrock, Azure, etc.) — see `chatbot/scripts/constants.py`
   - **Feedback system**: DuckDB (`chatbot/feedback.duckdb`) stores user ratings and query history
   - **Smart caching**: returns cached responses for similar past queries with high ratings instead of re-querying the LLM

3. **Chatbot UI**
   - R Shiny app (`chatbot/app.R`), served on port 5075
   - Embedded into the Quarto site via iframe (`chatbot-toggle.html`)
   - **Session persistence**: `chatbot-toggle.html` mints a `sid` UUID in `sessionStorage` and appends it as `?sid=` on the iframe URL. `app.R` keys an in-memory environment `CHAT_STORE` by that `sid`; the `chatHistory` `reactiveVal` loads from / writes back to `CHAT_STORE[[sid]]` on every change, and a session-end handler deletes the entry. History survives Quarto page navigation in the same browser tab, but not an app restart.
   - **Inline feedback**: each bot reply in `output$chatMessages` renders 👍/😐/👎 buttons that fire a single `Shiny.setInputValue('rate', {idx, value})`. `observeEvent(input$rate)` stamps the rating onto the message in `chatHistory()` and calls `py$save_feedback_to_duckdb(...)`. Rating is optional — it does not gate asking the next question.

### Data Flow

1. **Indexing**: `.qmd` files in `site/` → chunked → embedded → upserted into Qdrant (`chatbot/scripts/create_qdrant_collections.py`)
2. **Query**: user question → check `feedback.duckdb` for a similar past query → if a high-rated match exists, return it directly; otherwise query Qdrant for relevant chunks and generate an LLM response (`chatbot/chatbot_for_integration.py:query_qdrant`)
3. **Feedback**: user rates a response → stored/aggregated in DuckDB → influences retrieval parameters for future similar queries

## Development Commands

Almost everything is driven through the root `Makefile`, which wraps R/renv, Poetry, and Docker Compose. Run these from the repo root.

```bash
make setup        # One-time: renv::restore(), poetry install (in chatbot/), validate chatbot/.env
make qdrant-up     # Start the Qdrant container and wait for it to be healthy
make qdrant-down   # Stop the Qdrant container
make ingest        # qdrant-up, then run create_qdrant_collections.py to (re)build the vector collection
make run           # qdrant-up, then launch the Shiny chatbot app at http://127.0.0.1:5075
make clean         # Stop Qdrant; leaves R/Poetry environments intact
```

`env-check` (run automatically by `setup`) copies `chatbot/.env.example` to `chatbot/.env` on first run and validates that `QDRANT_URL`, `QDRANT_API_KEY`, `EMBEDDING_MODEL`, `MODEL_ID`, and one of (`OLLAMA_URL`) or (`OPENAI_API_KEY` + `OPENAI_BASE_URL`) are set.

**Quarto site preview** (not wrapped by the Makefile):
- RStudio: Build → Render Website
- Positron: open `index.qmd`, press `Ctrl/Cmd+Shift+K`
- Terminal: `quarto preview` (run `make run` first if you also want the chatbot iframe live)

**Testing the LLM connection directly**:
```bash
cd chatbot && poetry run python scripts/test_bedrock.py   # AWS Bedrock specifically
```

Note: `pyproject.toml` lives in `chatbot/` and is shared by `chatbot/` and `chatbot/scripts/` — there is no separate `pyproject.toml` under `scripts/`. **Always run from `chatbot/`, never from `chatbot/scripts/`.** The two Python entry points use different import styles, each depending on that CWD:
- `chatbot_for_integration.py` (loaded by `app.R` via `source_python`) uses `import scripts.constants as c` — needs CWD `chatbot/`.
- `scripts/*.py` use bare `import constants` / `import helpers`, which only resolve when run as `python scripts/<x>.py` from `chatbot/` (Python puts `scripts/` on `sys.path[0]`).

## Key Implementation Details

### Chunking Strategy (`chatbot/scripts/create_qdrant_collections.py`)

- Chunk size: 300 words, 10% overlap (`get_chunks_fixed_size_with_overlap` in `chatbot/scripts/helpers.py`)
- Qdrant point IDs are stable hashes of `{source_path}::{chunk_number}` (`stable_int_id`), so re-running ingestion upserts in place rather than duplicating points
- Collection name is derived from the embedding model: `QUARTO_Embedding_{EMBEDDING_MODEL, sanitized}` — changing `EMBEDDING_MODEL` in `.env` and re-ingesting creates a new collection rather than overwriting the old one

### Feedback-Driven Query Optimization

`chatbot/chatbot_for_integration.py`:
- `find_similar_query` embeds the incoming question and compares it (cosine similarity, threshold 0.7) against all past queries in `feedback.duckdb`, then picks the **best-rated** response among matches
- If that response has `avg_rating >= 1.5`, it is returned immediately with no LLM call
- If it has `avg_rating < 1`, retrieval is widened: `limit` goes from 3 to 5 documents before querying Qdrant (still a fresh LLM call)
- `save_feedback_to_duckdb(base, query, response, rating)` — `rating` is `2` (helpful) / `1` (okay) / `0` (not helpful). Matches an existing row by **substring match of `base` against `query_history` AND exact `response` text**, then recomputes a running `avg_rating` over `num_ratings`; otherwise inserts a new row. DB file is `chatbot/feedback.duckdb` (`DUCKDB_PATH`), gitignored via `chatbot/.gitignore`.

### Feedback Gotchas

- `save_feedback_to_duckdb` wraps its whole body in `try/except Exception: print(...)` and never re-raises, so a failed write is **invisible to the R side** — the UI still shows "thanks for the feedback".
- Its row match uses pandas `.str.contains(base)` with the default `regex=True`. Once the table has rows, a question containing regex metacharacters can throw internally (swallowed by the `except`) and the rating is silently dropped. The fix is `regex=False`.

### LLM Client Abstraction

`chatbot/scripts/constants.py` picks the LLM client at import time: `OLLAMA_URL` set → Ollama client; otherwise → OpenAI-compatible client (works with AWS Bedrock/Azure). It also opens the Qdrant connection and fails fast (raises) if Qdrant is unreachable — so `make qdrant-up` (or a running Docker Compose stack) must precede anything that imports this module.

## File Structure

```
Makefile                            # setup / qdrant-up / qdrant-down / ingest / run / clean
docker-compose.yml                  # Qdrant service definition
_quarto.yml                         # Quarto site config + nav (root-level, indentation-sensitive)
chatbot-toggle.html                 # Chatbot iframe embed for the Quarto site
chatbot/
├── app.R                           # Shiny UI/server
├── chatbot_for_integration.py      # Main chatbot query + feedback logic
├── feedback.duckdb                 # User ratings / query history (not source-controlled content)
├── pyproject.toml                  # Shared Poetry env for chatbot/ and chatbot/scripts/
├── .env                            # Local config (not tracked; copy from .env.example)
└── scripts/
    ├── constants.py                # LLM + Qdrant client setup, collection naming
    ├── helpers.py                  # Prompt creation, chunking utilities
    ├── qmd_extraction.py           # Load .qmd files from site/ (local) or via GitHub API
    ├── create_qdrant_collections.py  # Build/rebuild the Qdrant vector index
    └── test_bedrock.py             # Standalone AWS Bedrock connectivity check

site/                                # Quarto content (.qmd files), rendered to output/
```

## Common Tasks

### Adding New Documentation

1. Create the `.qmd` file under the appropriate `site/` subfolder, matching the title/author/date YAML frontmatter used by other pages in that section
2. Register it in `_quarto.yml` navigation (root level) — indentation matters
3. Rebuild the Qdrant collection: `make ingest`
4. Preview the site to verify navigation and content

### Switching Embedding Models

1. Update `EMBEDDING_MODEL` in `chatbot/.env`
2. `make ingest` — this creates a new collection named `QUARTO_Embedding_{new_model_name}` (the old collection is left in place)

### Debugging Retrieval

- `create_qdrant_collections.py` logs chunk counts as it builds/upserts
- `chatbot/feedback.duckdb` holds cached query/response/rating history
- `find_similar_query` prints similarity scores to the console on each query

## Branch Strategy

- `main`: production-ready code; merging `development` → `main` triggers the GitHub Actions auto-publish
- `development`: integration branch contributors branch from and merge back into (per `README.md`)
- Feature branches: named `<issue#>-<slug>` (e.g. `3-correct-chatbot-window`)

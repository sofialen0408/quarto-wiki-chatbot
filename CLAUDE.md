# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Quarto-based knowledge base website with an integrated RAG (Retrieval Augmented Generation) chatbot. The chatbot uses vector search over .qmd documentation files to provide contextual answers.

**Current Branch**: `qdrant-migration` - Migration from Weaviate to Qdrant for vector storage.

## Architecture

### Components

1. **Quarto Website** (`site/` folder)
   - Documentation stored as `.qmd` files
   - Rendered to HTML in `output/` directory
   - Configuration in `_quarto.yml`
   - FontAwesome extension for icons

2. **Chatbot Backend** (`chatbot_local/` - current implementation)
   - **Vector Database**: Qdrant for embeddings storage
   - **Embeddings**: sentence-transformers models (configurable via `.env`)
   - **LLM**: Supports Ollama or OpenAI-compatible APIs (including AWS Bedrock)
   - **Feedback System**: DuckDB for storing user ratings and query history
   - **Smart Caching**: Returns cached responses for similar queries with high ratings

3. **Chatbot UI** 
   - R Shiny app (`chatbot_local/app.R`)
   - Embedded in Quarto site via iframe (`chatbot-toggle.html`)
   - Session persistence across page navigation using `sessionStorage`

4. **Legacy Implementation** (`chatbot/`)
   - Uses Weaviate instead of Qdrant
   - Being phased out in favor of `chatbot_local/`

### Data Flow

1. **Indexing**: `.qmd` files → chunked → embedded → stored in Qdrant
2. **Query**: User question → check feedback DB for similar queries → if not cached, query Qdrant → retrieve relevant chunks → generate LLM response
3. **Feedback**: User rates response → stored in DuckDB → influences future similar queries

## Development Commands

### Environment Setup

**Quarto Website**:
```bash
# In R terminal
source("renv/activate.R")
# Follow prompts to create lockfile
```

**Chatbot (Python)**:
```bash
cd chatbot_local
poetry install
```

**Environment Variables**:
Create `.env` file in `chatbot_local/` based on `.env.example`:
- `QDRANT_URL` - Qdrant database URL
- `QDRANT_API_KEY` - Qdrant API key
- `EMBEDDING_MODEL` - e.g., "all-MiniLM-L6-v2"
- `MODEL_ID` - LLM model identifier
- `PAT` - GitHub Personal Access Token
- `GITHUB_API`, `ORG`, `REPO` - For GitHub integration
- Either `OLLAMA_URL` OR (`OPENAI_API_KEY` + `OPENAI_BASE_URL`)

### Running the Application

**Preview Quarto Website**:
```bash
# In RStudio: Build → Render Website
# OR in Positron: Ctrl+Shift+K on index.qmd
```

**Run Chatbot App**:
```bash
cd chatbot_local
poetry run R -e "shiny::runApp('$(pwd)')"
# Opens at http://127.0.0.1:5075
```

### Data Preparation

**Create/Update Qdrant Collection**:
```bash
cd chatbot_local/scripts
poetry run python create_qdrant_collections.py
```

This script:
- Loads all `.qmd` files from `site/`
- Chunks text (300 words, 10% overlap)
- Generates embeddings
- Upserts to Qdrant collection named `QUARTO_Embedding_{EMBEDDING_MODEL}`

## Key Implementation Details

### Chunking Strategy

- **Chunk Size**: 300 words
- **Overlap**: 10% (configurable in `create_qdrant_collections.py`)
- Chunks maintain context across boundaries

### Feedback-Driven Query Optimization

The chatbot learns from user feedback (`chatbot_for_integration.py:find_similar_query`):

1. **High-rated cached responses** (avg_rating ≥ 1.5): Returned immediately without LLM call
2. **Low-rated responses** (avg_rating < 1): Adjusts retrieval parameters:
   - Increases limit from 3 to 5 documents
   - Adjusts alpha parameter (semantic vs keyword balance)

### Session Persistence

Chat history is preserved across page navigation:
- Session ID stored in `sessionStorage` (browser)
- Managed by R Shiny's reactive environment (`CHAT_STORE`)
- Cleaned up on session end

### LLM Client Abstraction

`constants.py` auto-detects LLM provider:
- If `OLLAMA_URL` set → use Ollama client
- Otherwise → use OpenAI-compatible client (supports AWS Bedrock, Azure, etc.)

## File Structure

```
chatbot_local/
├── app.R                           # Shiny UI/server
├── chatbot_for_integration.py      # Main chatbot logic
├── .env                           # Local config (not tracked)
└── scripts/
    ├── constants.py               # Client connections & config
    ├── helpers.py                 # Prompt creation, chunking utilities
    ├── qmd_extraction.py          # Load .qmd files from site/
    └── create_qdrant_collections.py  # Build vector index

site/                              # Quarto content (.qmd files)
chatbot-toggle.html                # Chatbot iframe integration
_quarto.yml                        # Quarto site config
```

## Common Tasks

### Adding New Documentation

1. Create `.qmd` file in appropriate `site/` subfolder
2. Add to `_quarto.yml` navigation structure (indentation matters!)
3. Rebuild Qdrant collection: `cd chatbot_local/scripts && poetry run python create_qdrant_collections.py`
4. Preview site to verify navigation

### Switching Embedding Models

1. Update `EMBEDDING_MODEL` in `.env`
2. Recreate collection: `poetry run python create_qdrant_collections.py`
3. New collection name will be `QUARTO_Embedding_{new_model_name}`

### Debugging Retrieval

- Check vector search results: `scripts/create_qdrant_collections.py` logs chunk count
- Examine feedback DB: `feedback.duckdb` in `chatbot_local/`
- Review similarity scores: printed to console when `find_similar_query` runs

### Testing LLM Connection

```bash
cd chatbot_local/scripts
poetry run python test_bedrock.py  # For AWS Bedrock specifically
```

## Branch Strategy

- `main`: Production-ready code
- `development`: Active development (README references this branch)
- `qdrant-migration`: Current work (Weaviate → Qdrant transition)

Merges: `development` → `main` triggers GitHub Actions for auto-publishing

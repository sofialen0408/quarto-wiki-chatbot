.PHONY: setup env-check qdrant-up qdrant-down ingest run clean

# --- One-time / per-clone setup -------------------------------------------
# pyproject.toml lives in chatbot_local/ and is shared by chatbot_local + scripts.
setup: env-check
	@echo ">> Restoring R environment (renv)..."
	R -e "source('renv/activate.R'); renv::restore()"
	@echo ">> Installing Python deps (poetry, shared env)..."
	cd chatbot_local && poetry install
	@echo ">> Setup complete."

env-check:
	@if [ ! -f chatbot_local/.env ]; then \
		echo "No .env found in chatbot_local/ — copying from chatbot_local/.env.example."; \
		cp chatbot_local/.env.example chatbot_local/.env; \
		echo "Edit chatbot_local/.env before continuing (QDRANT_URL, EMBEDDING_MODEL, MODEL_ID, etc)."; \
		exit 1; \
	fi
	@set -a; . ./chatbot_local/.env; set +a; \
	missing=""; \
	for var in QDRANT_URL QDRANT_API_KEY EMBEDDING_MODEL MODEL_ID; do \
		eval val=\$$$$var; \
		if [ -z "$$val" ]; then missing="$$missing $$var"; fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo "Missing required values in chatbot_local/.env:$$missing"; \
		exit 1; \
	fi; \
	if [ -n "$$OLLAMA_URL" ]; then \
		: ; \
	elif [ -n "$$OPENAI_API_KEY" ] && [ -n "$$OPENAI_BASE_URL" ]; then \
		: ; \
	else \
		echo "Set either OLLAMA_URL, or both OPENAI_API_KEY and OPENAI_BASE_URL, in chatbot_local/.env"; \
		exit 1; \
	fi

# --- Vector DB --------------------------------------------------------------
qdrant-up:
	docker compose --env-file chatbot_local/.env up -d qdrant
	@echo ">> Waiting for Qdrant to be healthy..."
	@until docker inspect --format='{{.State.Health.Status}}' quarto-wiki-qdrant 2>/dev/null | grep -q healthy; do sleep 1; done
	@echo ">> Qdrant is up at http://localhost:6333"

qdrant-down:
	docker compose --env-file chatbot_local/.env down

# --- Ingestion ---------------------------------------------------------------
# Run via the shared env in chatbot_local/ using a relative path to the script,
# since scripts/ has no pyproject.toml of its own.
ingest: qdrant-up
	cd chatbot_local && poetry run python scripts/create_qdrant_collections.py

# --- App ----------------------------------------------------------------------
run: qdrant-up
	cd chatbot_local && poetry run R -e "shiny::runApp('.', port=5075)"

clean: qdrant-down
	@echo ">> Stopped Qdrant. R/Poetry envs left intact."

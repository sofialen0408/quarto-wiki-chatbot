"""Build the 20-question RAGAS test set (question, answer, reference_text).

Each question is grounded in exactly one chunk that currently lives in the
Qdrant collection. `reference_text` is the chunk's `content` payload copied
verbatim from Qdrant, so it matches what the retriever would actually return.

Run from the `chatbot/` folder (so `.env` is picked up):

    poetry run python experiments/build_ragas_testset.py

Writes `experiments/ragas_testset.csv`.
"""

import csv
import os
import urllib.request
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENV_PATH = HERE.parent / ".env"
OUT_PATH = HERE / "ragas_testset.csv"


def load_env(path: Path) -> dict:
    env = {}
    if path.exists():
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            env[key.strip()] = val.strip().strip('"').strip("'")
    return env


ENV = load_env(ENV_PATH)
QDRANT_URL = os.environ.get("QDRANT_URL", ENV.get("QDRANT_URL", "http://localhost:6333"))
QDRANT_API_KEY = os.environ.get("QDRANT_API_KEY", ENV.get("QDRANT_API_KEY", ""))
EMBEDDING_MODEL = os.environ.get(
    "EMBEDDING_MODEL", ENV.get("EMBEDDING_MODEL", "all-MiniLM-L6-v2")
)
# Collection naming mirrors create_qdrant_collections.py: QUARTO_Embedding_{model, sanitized}
COLLECTION = "QUARTO_Embedding_" + "".join(
    c if c.isalnum() else "_" for c in EMBEDDING_MODEL
)


def fetch_chunks_by_id() -> dict:
    """Return {str(point_id): content} for every point in the collection."""
    url = f"{QDRANT_URL}/collections/{COLLECTION}/points/scroll"
    body = json.dumps(
        {"limit": 1000, "with_payload": True, "with_vector": False}
    ).encode()
    req = urllib.request.Request(
        url, data=body, headers={"Content-Type": "application/json", "api-key": QDRANT_API_KEY}
    )
    with urllib.request.urlopen(req) as resp:
        data = json.load(resp)
    return {str(p["id"]): p["payload"]["content"] for p in data["result"]["points"]}


# (question, ground-truth answer, Qdrant point id the question is grounded in)
ROWS = [
    ("What is the recommended best-practice way to create and share reusable functions and variables in R?",
     "Creating R packages and uploading them to GitHub, then sourcing them from there. Simply sourcing loose R scripts from GitHub is easy but hard to manage across projects, so packaging (using devtools and usethis, per Hadley Wickham's \"R Packages\" book) is the best-practice approach.",
     "1300542709777459"),

    ("Which R command creates a new package at a chosen location, and which command creates the first .R file inside it?",
     "Run create_package(PATH) to create the package at the given location, then use_r(FILENAME) to create the first .R file that will hold your functions.",
     "3028566453149301963"),

    ("What is clustering, and is it a supervised or unsupervised method?",
     "Clustering is a method of analysis that groups individual observations into \"clusters\" that are as close to each other as possible but as dissimilar from other clusters as possible. It is unsupervised: it does not make predictions about new data, it helps you understand the existing structure of your dataset.",
     "67053934899966892"),

    ("What does the GraphGPT tool do?",
     "GraphGPT converts unstructured natural language into a knowledge graph.",
     "7609572588452585008"),

    ("Which Neo4j resource about building a context-aware chatbot is listed on the Knowledge Graph page?",
     "The Neo4j developer blog post \"Context-Aware Knowledge Graph Chatbot With GPT-4 and Neo4j\".",
     "12641818102040185954"),

    ("What common Windows setup mistake stops the 'python' and 'pip' commands from working, and how do you fix it?",
     "Python was not added to the PATH environment variables during installation (an easily missed optional checkbox on the Advanced Options page). Fix it by going to Add or Remove Programs, selecting your Python version, choosing Modify, ensuring pip is installed and that \"Add Python to environment variables\" is selected, then restarting your terminals.",
     "12674562173800552857"),

    ("How do you pip install a package when you are using pyenv for Windows?",
     "Use pyenv's exec command, for example: pyenv exec pip install pandas. Other commands such as virtualenv can be run the same way.",
     "13506471383234824939"),

    ("Why must every new .qmd file be added to _quarto.yml, and what detail is critical when editing that file?",
     "Any new .qmd file must be \"registered\" in _quarto.yml (the skeleton of the whole site body) or it will not appear on the website. Indentation matters, and the file must not be renamed from _quarto.yml.",
     "6251259776082378237"),

    ("If a page title is defined in both the YAML config and the .qmd file itself, which one wins?",
     "The YAML file's title takes precedence in the sidebar tab, but the .qmd file's title takes precedence as the title of the actual page when you click into it on the site.",
     "16294748915175786884"),

    ("Which presentation format does Quarto recommend, and what other output formats does it support?",
     "Quarto recommends revealjs (reveal.js HTML). It also supports pptx (PowerPoint) and beamer (LaTeX/PDF).",
     "8478394450325939985"),

    ("How do you update the renv environment for the Posit Connect server when working in Quarto?",
     "Download the necessary packages through your RStudio Console, then run renv::snapshot().",
     "1496412248354042808"),

    ("What Git commands do you use to create a new branch and then move into it?",
     "Run 'git branch new_feature_branch' to create the branch, then 'git checkout new_feature_branch' to step into it. ('git branch -a' shows all local and remote branches, with * marking the active one.)",
     "16578619939130199874"),

    ("How do you set up a shared Git commit message template for a repository?",
     "Create the template file with an editor (e.g. vim .gitmessage), then run 'git config --global commit.template .gitmessage' and commit without the -m flag so the template is used. Teammates adopt it by pulling the changes and running the same 'git config --global commit.template .gitmessage'.",
     "1648736690560350380"),

    ("How do you authenticate with NASA's GitHub (developer.nasa.gov) from RStudio Server?",
     "In the RStudio Terminal, generate SSH keys with 'ssh-keygen' in your home folder, show hidden files and open id_rsa.pub, copy its contents, and add it as an SSH key in your GitHub settings. Verify with 'ssh -T git@developer.nasa.gov', after which you can clone repositories over SSH.",
     "15160681666488521380"),

    ("Among the reviewed open source data catalog tools, which one is the author's overall pick?",
     "OpenDataDiscovery is the author's overall personal pick.",
     "6190207954455050430"),

    ("Who should you contact about catalogs and data governance, and who about People Analytics tools and methods?",
     "Email Sarah Hampton (sarah.hampton@nasa.gov) about catalogs and data governance, and David Meza (david.meza-1@nasa.gov), Branch Chief of People Analytics, about People Analytics tools and methods.",
     "12627743488688016588"),

    ("How is \"Data Governance\" defined in the Data Process and Roles documentation?",
     "Data Governance is the system for defining who within an organization has authority and control over data assets and how they will be used. It encompasses the people, processes, and technologies required to manage and protect data assets.",
     "6785769202127028950"),

    ("How does the People Analytics data process differ from pulling PDW data directly with BOBJ reports?",
     "The People Analytics team automates retrieval and transformation of Personnel Data Warehouse (PDW) data into curated, sustainable, AIML-ready content, forming a human capital datalake that feeds analytics and visualizations with little to no manual updates. Unlike pulling PDW data directly through BOBJ reports, this approach allows continuous updates while improving efficiency and accuracy in the dashboard.",
     "13612471835982989762"),

    ("What book by Hadley Wickham is recommended for getting started with R Shiny?",
     "\"Mastering Shiny\" by Hadley Wickham (mastering-shiny.org). The RStudio Shiny hands-on video tutorials are also recommended as a starting point.",
     "8737777563015519034"),

    ("Which quick-sketch tool is recommended for designing a web app or dashboard?",
     "Excalidraw (excalidraw.com), described as an awesome quick sketch tool recommended by Andy and endorsed by Madison/Katya. draw.io is also listed for wireframing.",
     "14567209698326504533"),
]

assert len(ROWS) == 20, f"expected 20 rows, got {len(ROWS)}"


def main() -> None:
    by_id = fetch_chunks_by_id()
    missing = [pid for _, _, pid in ROWS if pid not in by_id]
    if missing:
        raise SystemExit(
            f"Point id(s) not found in collection {COLLECTION!r}: {missing}. "
            "Re-run `make ingest` or update the ids in this script."
        )
    with OUT_PATH.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["question", "answer", "reference_texts"])
        for question, answer, pid in ROWS:
            w.writerow([question, answer, by_id[pid].strip()])
    print(f"wrote {OUT_PATH} ({len(ROWS)} questions)")


if __name__ == "__main__":
    main()

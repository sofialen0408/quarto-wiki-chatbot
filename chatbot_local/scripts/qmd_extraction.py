import os
import requests
import base64

# ==== CONFIGURATION ====
GITHUB_API = os.getenv("GITHUB_API")
ORG = os.getenv("ORG")
REPO = os.getenv("REPO")
PAT = os.getenv("PAT")

HEADERS = {
    "Authorization": f"token {PAT}",
    "Accept": "application/vnd.github.v3+json"
}

def get_repo_tree(branch):
    url = f"{GITHUB_API}/repos/{ORG}/{REPO}/git/trees/{branch}?recursive=1"
    resp = requests.get(url, headers=HEADERS)
    resp.raise_for_status()
    return resp.json()["tree"]


def get_qmd_files_from_github():
    branch = "development"  # Or "main" if that's your default branch
    print(f"Accessing branch: {branch}...")
    
    tree = get_repo_tree(branch)
    qmd_files = [
        item["path"]
        for item in tree
        if item["type"] == "blob" and item["path"].startswith("site/") and item["path"].endswith(".qmd")
    ]
    
    print(f"Found {len(qmd_files)} .qmd files.")
    
    result = []
    for path in qmd_files:
        print(path)
        file_url = f"{GITHUB_API}/repos/{ORG}/{REPO}/contents/{path}?ref={branch}"
        file_resp = requests.get(file_url, headers=HEADERS)
        if file_resp.status_code == 200:
            content = base64.b64decode(file_resp.json()["content"]).decode("utf-8")
            result.append((path, content))
        else:
            print(f"❌ Skipped {path} | Status: {file_resp.status_code} | URL: {file_url}")

    return result

from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent
SITE_DIR = PROJECT_ROOT / "site"

def load_qmd_files():
    files = []

    for path in SITE_DIR.rglob("*.qmd"):
        try:
            content = path.read_text(encoding="utf-8")
            files.append({
                "path": str(path.relative_to(PROJECT_ROOT)),
                "content": content
            })
        except Exception as e:
            print(f"Failed to read {path}: {e}")
    return files

if __name__ == "__main__":
    qmd_files = load_qmd_files()
    print(f"Loaded {len(qmd_files)} .qmd files from local site directory.")
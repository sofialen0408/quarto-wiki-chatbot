import os
import requests
import base64

# ==== CONFIGURATION ====
GITHUB_API = "https://developer.nasa.gov/api/v3"
ORG = "ochco"
REPO = "pa-knowledge-base"
PAT = "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" 

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
    branch = "development"
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
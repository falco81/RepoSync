#!/bin/bash
# CGI script – packages a repository as ZIP and streams it to the browser
# Usage: https://docs.example.com/cgi-bin/download-repo.cgi?repo=REPO_NAME

REPOS_DIR="/opt/github-mirror/repos"

# Read ?repo= parameter from query string
REPO_NAME=$(echo "$QUERY_STRING" | sed -n 's/.*repo=\([^&]*\).*/\1/p')

# Security check – only allow letters, numbers, hyphens and dots
if [[ ! "$REPO_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "Content-Type: text/plain"
  echo "Status: 400 Bad Request"
  echo ""
  echo "Invalid repository name."
  exit 1
fi

REPO_PATH="$REPOS_DIR/$REPO_NAME"

# Check repository exists
if [ ! -d "$REPO_PATH" ]; then
  echo "Content-Type: text/plain"
  echo "Status: 404 Not Found"
  echo ""
  echo "Repository '$REPO_NAME' not found."
  exit 1
fi

# Send headers for ZIP download
echo "Content-Type: application/zip"
echo "Content-Disposition: attachment; filename=\"${REPO_NAME}.zip\""
echo ""

# Stream ZIP directly to stdout – no temp file on disk
cd "$REPOS_DIR"
zip -r -q - "$REPO_NAME" --exclude "*/.git/*" --exclude "*/.git"

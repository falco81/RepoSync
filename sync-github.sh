#!/bin/bash
source /opt/github-mirror/venv/bin/activate

# ============================================================
# Configuration – edit these values before first run
# ============================================================
GITHUB_USER="your-username"             # your GitHub username
GITHUB_TOKEN="ghp_xxxxxxxxxxxx"         # your Personal Access Token
SITE_URL="https://docs.example.com"     # public URL of your server
# ============================================================

REPOS_DIR="/opt/github-mirror/repos"
MKDOCS_DIR="/opt/github-mirror/mkdocs"
WWW_DIR="/var/www/html/docs"
ARCHIVE_DIR="/opt/github-mirror/rawfiles"
LOG="/var/log/github-mirror/sync.log"
KEEP_DAYS=60                             # retain archives for 2 months

echo "==============================" >> "$LOG"
echo "START: $(date '+%Y-%m-%d %H:%M')" >> "$LOG"

mkdir -p "$REPOS_DIR" "$MKDOCS_DIR/docs" "$ARCHIVE_DIR"

# ---- 1. Fetch list of all repositories (paginated) ----
echo "Fetching repository list..." >> "$LOG"
PAGE=1
REPOS=""
while true; do
  BATCH=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/user/repos?per_page=100&type=all&page=$PAGE" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
if not data: exit()
for r in data: print(r['clone_url'])
")
  [ -z "$BATCH" ] && break
  REPOS="$REPOS $BATCH"
  ((PAGE++))
done

# ---- 2. Clone or pull + archive on change ----
TIMESTAMP=$(date '+%Y%m%d_%H%M')

for REPO_URL in $REPOS; do
  AUTH_URL=$(echo "$REPO_URL" | sed "s|https://|https://$GITHUB_TOKEN@|")
  REPO_NAME=$(basename "$REPO_URL" .git)
  REPO_PATH="$REPOS_DIR/$REPO_NAME"
  REPO_ARCHIVE_DIR="$ARCHIVE_DIR/$REPO_NAME"
  mkdir -p "$REPO_ARCHIVE_DIR"

  if [ -d "$REPO_PATH/.git" ]; then
    OLD_HASH=$(git -C "$REPO_PATH" rev-parse HEAD 2>/dev/null)
    echo "Pull: $REPO_NAME" >> "$LOG"
    git -C "$REPO_PATH" pull --quiet 2>> "$LOG"
    NEW_HASH=$(git -C "$REPO_PATH" rev-parse HEAD 2>/dev/null)

    if [ "$OLD_HASH" != "$NEW_HASH" ]; then
      echo "  Archiving changes: $REPO_NAME ($TIMESTAMP)" >> "$LOG"
      tar -czf "$REPO_ARCHIVE_DIR/${REPO_NAME}_${TIMESTAMP}.tar.gz" \
        -C "$REPOS_DIR" "$REPO_NAME" \
        --exclude='.git' 2>> "$LOG"
    else
      echo "  No changes: $REPO_NAME" >> "$LOG"
    fi
  else
    echo "Clone: $REPO_NAME" >> "$LOG"
    git clone --quiet "$AUTH_URL" "$REPO_PATH" 2>> "$LOG"
    echo "  Initial archive: $REPO_NAME ($TIMESTAMP)" >> "$LOG"
    tar -czf "$REPO_ARCHIVE_DIR/${REPO_NAME}_${TIMESTAMP}.tar.gz" \
      -C "$REPOS_DIR" "$REPO_NAME" \
      --exclude='.git' 2>> "$LOG"
  fi
done

# ---- 3. Delete archives older than KEEP_DAYS ----
echo "Cleaning old archives (>${KEEP_DAYS} days)..." >> "$LOG"
find "$ARCHIVE_DIR" -name "*.tar.gz" -mtime +$KEEP_DAYS -delete
TOTAL_FILES=$(find "$ARCHIVE_DIR" -name "*.tar.gz" | wc -l)
echo "  Remaining archives: $TOTAL_FILES" >> "$LOG"

# ---- 4. Clean old docs ----
find "$MKDOCS_DIR/docs" -mindepth 1 -maxdepth 1 \
  -not -name 'index.md' \
  -not -name 'archives.md' \
  -exec rm -rf {} +
mkdir -p "$MKDOCS_DIR/docs"

# ---- 5. Main index page ----
cat > "$MKDOCS_DIR/docs/index.md" << EOF
# GitHub Mirror – $GITHUB_USER

Local backup of all repositories from [github.com/$GITHUB_USER](https://github.com/$GITHUB_USER).

**Last updated:** $(date '+%Y-%m-%d %H:%M')

---

## Projects

EOF

# ---- 6. MkDocs configuration ----
# Navigation:
#   Top bar:  Home | Projects | Archives
#   Sidebar:  all repositories listed under Projects section
cat > "$MKDOCS_DIR/mkdocs.yml" << EOF
site_name: GitHub Mirror – $GITHUB_USER
site_description: Local backup of GitHub repositories
site_url: $SITE_URL

theme:
  name: material
  language: en
  palette:
    scheme: slate
    primary: indigo
    accent: indigo
  features:
    - navigation.tabs           # top-level sections become tabs
    - navigation.tabs.sticky    # tabs stay visible while scrolling
    - navigation.sections       # sidebar shows sections expanded
    - navigation.indexes        # section index pages
    - navigation.top            # back-to-top button
    - navigation.expand         # expand sidebar by default
    - search.highlight
    - search.suggest
    - content.code.copy

docs_dir: docs

nav:
  - Home: index.md
  - Projects:
EOF

# ---- 7. Archive overview page ----
ARCHIVE_INDEX="$MKDOCS_DIR/docs/archives.md"
cat > "$ARCHIVE_INDEX" << EOF
# 🗄️ Repository Archives

Snapshots of all repositories – retained for **2 months**.
A new archive is created **only when changes are detected**.

<a href="$SITE_URL/rawfiles/" target="_blank" style="background:#1976D2;color:white;padding:8px 16px;text-decoration:none;border-radius:5px;font-weight:bold;">📂 Open raw file browser</a>

**Last updated:** $(date '+%Y-%m-%d %H:%M')

---

EOF

for REPO_ARCHIVE_DIR in "$ARCHIVE_DIR"/*/; do
  REPO_NAME=$(basename "$REPO_ARCHIVE_DIR")
  ARCHIVE_COUNT=$(find "$REPO_ARCHIVE_DIR" -name "*.tar.gz" 2>/dev/null | wc -l)

  [ "$ARCHIVE_COUNT" -eq 0 ] && continue

  echo "## 📦 $REPO_NAME" >> "$ARCHIVE_INDEX"
  echo "" >> "$ARCHIVE_INDEX"
  echo "| File | Date | Size | Download |" >> "$ARCHIVE_INDEX"
  echo "|------|------|------|----------|" >> "$ARCHIVE_INDEX"

  find "$REPO_ARCHIVE_DIR" -name "*.tar.gz" | sort -r | while read -r ARCH; do
    ARCH_NAME=$(basename "$ARCH")
    ARCH_DATE=$(echo "$ARCH_NAME" | grep -oP '\d{8}_\d{4}' | \
      sed 's/\(....\)\(..\)\(..\)_\(..\)\(..\)/\3.\2.\1 \4:\5/')
    ARCH_SIZE=$(du -sh "$ARCH" | cut -f1)
    ARCH_URL="$SITE_URL/rawfiles/$REPO_NAME/$ARCH_NAME"
    echo "| $ARCH_NAME | $ARCH_DATE | $ARCH_SIZE | [⬇️ Download]($ARCH_URL) |" >> "$ARCHIVE_INDEX"
  done

  echo "" >> "$ARCHIVE_INDEX"
done

# ---- 8. Copy ALL repository files and generate project pages ----
echo "Processing repositories..." >> "$LOG"
for REPO_PATH in "$REPOS_DIR"/*/; do
  REPO_NAME=$(basename "$REPO_PATH")
  FILE_COUNT=$(find "$REPO_PATH" -not -path '*/.git/*' -type f 2>/dev/null | wc -l)

  [ "$FILE_COUNT" -eq 0 ] && continue

  echo "  → $REPO_NAME ($FILE_COUNT files)" >> "$LOG"

  DEST="$MKDOCS_DIR/docs/$REPO_NAME"
  mkdir -p "$DEST"

  rsync -a --exclude='.git/' "$REPO_PATH" "$DEST/"

  if [ -f "$DEST/README.md" ]; then
    cp "$DEST/README.md" "$DEST/index.md"
  else
    echo "# $REPO_NAME" > "$DEST/index.md"
  fi

  # ZIP download button
  cat >> "$DEST/index.md" << MDEOF

<div style="margin: 1em 0;">
<a href="$SITE_URL/cgi-bin/download-repo.cgi?repo=$REPO_NAME"
   style="background:#4CAF50;color:white;padding:10px 20px;text-decoration:none;border-radius:5px;font-weight:bold;">
  📦 Download entire project as ZIP
</a>
</div>

---

## 📁 Files

MDEOF

  find "$DEST" -not -path '*/.git/*' -not -name '*.md' -type f | sort | while read -r FILE; do
    REL="${FILE#$DEST/}"
    echo "- [📄 $REL]($REL)" >> "$DEST/index.md"
  done

  # Last 5 archive versions
  REPO_ARCHIVE_DIR="$ARCHIVE_DIR/$REPO_NAME"
  ARCHIVE_COUNT=$(find "$REPO_ARCHIVE_DIR" -name "*.tar.gz" 2>/dev/null | wc -l)

  if [ "$ARCHIVE_COUNT" -gt 0 ]; then
    cat >> "$DEST/index.md" << MDEOF

---

## 🗄️ Archive Versions

Available snapshots: **$ARCHIVE_COUNT** → [View all](../archives.md)

| File | Date | Size | Download |
|------|------|------|----------|
MDEOF

    find "$REPO_ARCHIVE_DIR" -name "*.tar.gz" | sort -r | head -5 | while read -r ARCH; do
      ARCH_NAME=$(basename "$ARCH")
      ARCH_DATE=$(echo "$ARCH_NAME" | grep -oP '\d{8}_\d{4}' | \
        sed 's/\(....\)\(..\)\(..\)_\(..\)\(..\)/\3.\2.\1 \4:\5/')
      ARCH_SIZE=$(du -sh "$ARCH" | cut -f1)
      ARCH_URL="$SITE_URL/rawfiles/$REPO_NAME/$ARCH_NAME"
      echo "| $ARCH_NAME | $ARCH_DATE | $ARCH_SIZE | [⬇️ Download]($ARCH_URL) |" >> "$DEST/index.md"
    done
    echo "" >> "$DEST/index.md"
  fi

  # Add to nav under Projects section (indented under "Projects:")
  echo "      - $REPO_NAME: $REPO_NAME/index.md" >> "$MKDOCS_DIR/mkdocs.yml"
  echo "- [$REPO_NAME]($REPO_NAME/index.md)" >> "$MKDOCS_DIR/docs/index.md"
done

# Close nav with Archives section
# NOTE: external URLs cannot be used in MkDocs nav - link is inside archives.md instead
# Using /rawfiles path to avoid any conflict with MkDocs generated output
cat >> "$MKDOCS_DIR/mkdocs.yml" << EOF
  - Archives: archives.md
EOF

# ---- 9. Build MkDocs ----
echo "Building MkDocs site..." >> "$LOG"
cd "$MKDOCS_DIR"
mkdocs build --quiet 2>> "$LOG"

# ---- 10. Deploy to Apache ----
echo "Deploying to Apache..." >> "$LOG"
rsync -a --delete --exclude="/rawfiles" "$MKDOCS_DIR/site/" "$WWW_DIR/"
chown -R apache:apache "$WWW_DIR"

# ---- 11. Summary ----
TOTAL_SIZE=$(du -sh "$ARCHIVE_DIR" 2>/dev/null | cut -f1)
TOTAL_FILES=$(find "$ARCHIVE_DIR" -name "*.tar.gz" | wc -l)
echo "Total archives: $TOTAL_FILES, Size: $TOTAL_SIZE" >> "$LOG"
echo "DONE: $(date '+%Y-%m-%d %H:%M')" >> "$LOG"
deactivate

# GitHub Mirror – Local Documentation Server

A self-hosted solution that automatically mirrors all your GitHub repositories to a local Apache web server with full Markdown rendering, file downloads, and versioned archives.

---

## Features

- 📄 Renders all Markdown files using MkDocs Material theme
- 📁 Browse and download all repository files directly from the web
- 📦 Download any repository as a ZIP archive on demand
- 🗄️ Versioned `.tar.gz` archives – created only when changes are detected
- 🔄 Automatic hourly sync via cron
- 🔒 HTTPS support with your own certificates
- 🧹 Archives automatically cleaned up after 2 months

---

## Requirements

- Alma Linux 8.x (or compatible RHEL-based distro)
- Apache HTTP Server with `mod_ssl`, `mod_headers`, `mod_rewrite`
- Python 3.11
- Git, rsync, zip
- GitHub Personal Access Token

---

## Directory Structure

```
/opt/github-mirror/
├── repos/          # cloned repositories (raw git)
├── mkdocs/         # MkDocs project (generated)
├── archive/        # versioned .tar.gz archives
└── venv/           # Python virtual environment

/var/www/html/docs/ # Apache DocumentRoot (MkDocs output)
/var/www/cgi-bin/   # CGI scripts
/var/log/github-mirror/sync.log
```

---

## Installation

### 1. System update and dependencies

```bash
dnf update -y
dnf install -y epel-release
dnf install -y httpd mod_ssl mod_headers git rsync zip python3.11
```

### 2. Firewall

```bash
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload
```

### 3. Enable Apache

```bash
systemctl enable httpd
systemctl start httpd
```

### 4. Python virtual environment and MkDocs

```bash
mkdir -p /opt/github-mirror/repos
mkdir -p /opt/github-mirror/mkdocs/docs
mkdir -p /opt/github-mirror/archive
mkdir -p /var/www/html/docs
mkdir -p /var/log/github-mirror

python3.11 -m venv /opt/github-mirror/venv
source /opt/github-mirror/venv/bin/activate
pip install --upgrade pip
pip install mkdocs mkdocs-material
mkdocs --version
deactivate
```

### 5. GitHub Personal Access Token

1. Go to **GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)**
2. Click **Generate new token (classic)**
3. Set a name (e.g. `github-mirror`) and expiration
4. Select scope: **`repo`** (reads both public and private repositories)
5. Copy the token – it is shown only once!

### 6. Deploy scripts

```bash
# Sync script
cp sync-github.sh /opt/github-mirror/sync-github.sh
chmod +x /opt/github-mirror/sync-github.sh

# Edit and fill in your values
nano /opt/github-mirror/sync-github.sh

# CGI download script
cp download-repo.cgi /var/www/cgi-bin/download-repo.cgi
chmod +x /var/www/cgi-bin/download-repo.cgi
```

### 7. SSL certificates

Place your certificate files in `/etc/httpd/certs/`:

```
/etc/httpd/certs/server.pem   # domain certificate
/etc/httpd/certs/server.key   # private key
/etc/httpd/certs/server.ca    # CA / chain certificate
```

```bash
mkdir -p /etc/httpd/certs
chmod 700 /etc/httpd/certs
```

### 8. Apache configuration

```bash
cp github-mirror.conf /etc/httpd/conf.d/github-mirror.conf

# Verify syntax
httpd -t

# Restart Apache
systemctl restart httpd
```

### 9. First run

```bash
/opt/github-mirror/sync-github.sh

# Watch the log
tail -f /var/log/github-mirror/sync.log
```

### 10. Cron – hourly sync

```bash
crontab -e
```

```cron
0 * * * * /opt/github-mirror/sync-github.sh
```

---

## Configuration

Edit `/opt/github-mirror/sync-github.sh` and set these variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `GITHUB_USER` | Your GitHub username | `your-username` |
| `GITHUB_TOKEN` | Personal Access Token | `ghp_xxxxxxxxxxxx` |
| `SITE_URL` | Public URL of your server | `https://docs.example.com` |
| `KEEP_DAYS` | How many days to retain archives | `60` |

---

## How It Works

```
GitHub API
    ↓  (every hour via cron)
sync-github.sh
    ├── git clone / git pull  →  /opt/github-mirror/repos/
    ├── on change: tar.gz     →  /opt/github-mirror/archive/
    └── MkDocs build          →  /var/www/html/docs/
                                        ↓
                                  Apache serves
                              https://docs.example.com/
```

### Archive logic

Archives are created **only when a change is detected**:

```bash
OLD_HASH=$(git rev-parse HEAD)
git pull
NEW_HASH=$(git rev-parse HEAD)

if [ "$OLD_HASH" != "$NEW_HASH" ]; then
    # create .tar.gz snapshot
fi
```

Archives older than `KEEP_DAYS` are automatically deleted on each run.

### ZIP on demand

Clicking **Download entire project as ZIP** on any project page calls:

```
https://docs.example.com/cgi-bin/download-repo.cgi?repo=REPO_NAME
```

The CGI script streams the ZIP directly to the browser with no temporary file on disk.

---

## Web Interface

| URL | Description |
|-----|-------------|
| `https://docs.example.com/` | Home – list of all projects |
| `https://docs.example.com/REPO_NAME/` | Project page with files and archive links |
| `https://docs.example.com/archives/` | MkDocs archive overview page |
| `https://docs.example.com/archive/` | Apache directory listing of raw `.tar.gz` files |
| `https://docs.example.com/cgi-bin/download-repo.cgi?repo=NAME` | Download repo as ZIP |

---

## Notes

- **SELinux**: if enabled, run `setsebool -P httpd_unified 1` and `restorecon -Rv /var/www/html/docs`
- **Private repos**: the `repo` token scope covers both public and private repositories
- **More than 100 repos**: the script handles GitHub pagination automatically
- The MkDocs archive page is named `/archives/` (not `/archive/`) to avoid conflicting with the Apache `Alias /archive` directive

---

## License

MIT

#!/usr/bin/env bash
# deploy.sh - Automated deployment of a Dockerized app to a remote Linux server
# Usage: ./deploy.sh      (interactive)
#        ./deploy.sh --cleanup  (remove deployed resources on remote)
set -o errexit
set -o nounset
set -o pipefail

# ---------------------
# Config / Globals
# ---------------------
TIMESTAMP="$(date +%F_%H%M%S)"
LOGFILE="deploy_${TIMESTAMP}.log"
# Masked logging helper
_mask() { printf '%s' "******"; }

# Exit codes
E_GENERAL=1
E_VALIDATION=2
E_SSH=3
E_DEPLOY=4

# Write message to console and log
log() {
  local msg="$1"
  printf '%s %s\n' "$(date +'%Y-%m-%dT%H:%M:%S')" "$msg" | tee -a "$LOGFILE"
}

# Fatal error helper
fatal() {
  log "ERROR: $1"
  exit "${2:-$E_GENERAL}"
}

# Trap for unexpected exit
on_error() {
  rc=$?
  log "Script terminated with exit code ${rc}."
  exit $rc
}
trap on_error ERR INT

# ---------------------
# Helpers
# ---------------------
ask() {
  # ask "Prompt" default
  local prompt="$1"; local default="${2:-}"
  if [ -n "$default" ]; then
    printf "%s [%s]: " "$prompt" "$default"
  else
    printf "%s: " "$prompt"
  fi
  read -r ans
  if [ -z "$ans" ]; then
    echo "$default"
  else
    echo "$ans"
  fi
}

prompt_sensitive() {
  # Read sensitive input silently
  local prompt="$1"
  printf "%s: " "$prompt"
  stty -echo
  read -r secret
  stty echo
  printf "\n"
  echo "$secret"
}

# Simple remote execution wrapper
remote_exec() {
  local remote_cmd="$1"
  ssh -o BatchMode=yes -o ConnectTimeout=10 -i "$SSH_KEY" "$SSH_USER@$REMOTE_IP" "$remote_cmd"
}

# Rsync wrapper
remote_sync() {
  local src="$1"; local dest="$2"
  rsync -az -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" --exclude '.git' "$src" "$SSH_USER@$REMOTE_IP:$dest" | tee -a "$LOGFILE"
}

# ---------------------
# Parse args
# ---------------------
CLEANUP_ONLY=0
if [ "${1:-}" = "--cleanup" ] || [ "${1:-}" = "-c" ]; then
  CLEANUP_ONLY=1
fi

# ---------------------
# Interactive prompts (if not cleanup-only)
# ---------------------
if [ "$CLEANUP_ONLY" -eq 0 ]; then
  log "Starting interactive deployment. Logfile: $LOGFILE"

  REPO_URL="$(ask "Git repository URL (HTTPS, e.g. https://github.com/user/repo.git)" )"
  if [ -z "$REPO_URL" ]; then fatal "Repository URL required." $E_VALIDATION; fi

  PAT="$(prompt_sensitive "Personal Access Token (PAT) for repo (will NOT be logged)")"
  if [ -z "$PAT" ]; then fatal "PAT required." $E_VALIDATION; fi

  BRANCH="$(ask "Branch name" "main")"

  SSH_USER="$(ask "Remote SSH username" "ubuntu")"
  REMOTE_IP="$(ask "Remote server IP or hostname")"
  if [ -z "$REMOTE_IP" ]; then fatal "Remote server address required." $E_VALIDATION; fi

  SSH_KEY="$(ask "SSH private key path (absolute or relative)" "$HOME/.ssh/id_rsa")"
  if [ ! -f "$SSH_KEY" ]; then fatal "SSH key not found at $SSH_KEY" $E_VALIDATION; fi

  # Port: container internal port (application port)
  CONTAINER_PORT="$(ask "Application container port (internal container port, e.g., 8000)" "8000")"
  HOST_PORT="$(ask "Host port to expose on remote server (HTTP port forwarded from Nginx will point to this) " "$CONTAINER_PORT")"

  # Local temp dir for clone
  LOCAL_TMP_DIR="$(mktemp -d -t deployrepo_XXXX)"
  log "Using local temp dir: $LOCAL_TMP_DIR"
else
  # For cleanup, still need connection details
  log "Cleanup mode: will remove deployed resources on remote."
  SSH_USER="$(ask "Remote SSH username" "ubuntu")"
  REMOTE_IP="$(ask "Remote server IP or hostname")"
  SSH_KEY="$(ask "SSH private key path (absolute or relative)" "$HOME/.ssh/id_rsa")"
  if [ ! -f "$SSH_KEY" ]; then fatal "SSH key not found at $SSH_KEY" $E_VALIDATION; fi
  # Project directory on remote (default)
  REMOTE_APP_DIR="$(ask "Remote app directory to cleanup" "/home/$SSH_USER/deploy_app")"
fi

# ---------------------
# Helper: mask PAT for logs
# ---------------------
masked_repo_for_clone() {
  # Insert masked PAT into URL for logging only
  # Accepts https://github.com/owner/repo.git format
  if printf "%s" "$REPO_URL" | grep -qE '^https://'; then
    # show URL without token (we won't print PAT)
    printf "%s" "$REPO_URL"
  else
    printf "%s" "$REPO_URL"
  fi
}

# ---------------------
# CLEANUP ACTION
# ---------------------
if [ "$CLEANUP_ONLY" -eq 1 ]; then
  log "Running cleanup on remote host $SSH_USER@$REMOTE_IP..."
  # Ask which project dir to remove
  REMOTE_APP_DIR="${REMOTE_APP_DIR:-/home/$SSH_USER/deploy_app}"
  CLEAN_CMD=$(cat <<EOF
set -e
echo "Stopping containers if exist..."
docker ps -q --filter "name=deployed_app" | xargs -r docker stop
docker ps -a -q --filter "name=deployed_app" | xargs -r docker rm
docker images -q deployed_app | xargs -r docker rmi -f || true
rm -f /etc/nginx/sites-enabled/deployed_app.conf /etc/nginx/sites-available/deployed_app.conf || true
nginx -t && systemctl reload nginx || true
rm -rf "$REMOTE_APP_DIR"
echo "Cleanup complete."
EOF
)
  remote_exec "$CLEAN_CMD" || fatal "Remote cleanup failed." $E_SSH
  log "Cleanup finished successfully."
  exit 0
fi

# ---------------------
# Clone repo (locally)
# ---------------------
log "Cloning repository..."
# Build clone URL with PAT but avoid storing PAT in logs
if printf "%s" "$REPO_URL" | grep -qE '^https://'; then
  # Insert token into URL for git clone
  # Escape @ in token if any
  safe_pat="$PAT"
  # Construct: https://$PAT@github.com/owner/repo.git
  clone_url="$(printf "%s" "$REPO_URL" | sed -E "s#https://##")"
  full_clone_url="https://${safe_pat}@${clone_url}"
else
  fatal "Only HTTPS repo URLs are supported for PAT authentication in this script." $E_VALIDATION
fi

log "Cloning (masked URL): $(masked_repo_for_clone)"
(
  cd "$LOCAL_TMP_DIR"
  if printf '%s' "$full_clone_url" | grep -q '.'; then
    # try shallow clone if small
    if git clone --branch "$BRANCH" --single-branch "$full_clone_url" . 2>>"$LOGFILE"; then
      log "Repository cloned (branch $BRANCH)."
    else
      log "Clone with branch failed, attempting full clone then checkout..."
      git clone "$full_clone_url" repo 2>>"$LOGFILE"
      cd repo
      git checkout "$BRANCH" 2>>"$LOGFILE" || fatal "Could not checkout branch $BRANCH" $E_DEPLOY
    fi
  fi
)

# Avoid leaving PAT credentials in git config: remove remote URL credentials
cd "$LOCAL_TMP_DIR"
# If .git exists and has origin URL with PAT, sanitize for safety
if [ -d .git ]; then
  git remote set-url origin "$(printf "%s" "$REPO_URL")" 2>>"$LOGFILE" || true
fi

# Detect project directory (if cloned into repo/ or directly)
PROJECT_DIR="$LOCAL_TMP_DIR"
if [ -d "$LOCAL_TMP_DIR/.git" ]; then
  PROJECT_DIR="$LOCAL_TMP_DIR"
else
  # fallback: find first directory with .git
  found="$(find "$LOCAL_TMP_DIR" -maxdepth 2 -type d -name .git | head -n1 || true)"
  if [ -n "$found" ]; then PROJECT_DIR="$(dirname "$found")"; fi
fi
log "Project directory: $PROJECT_DIR"

# Verify Dockerfile or docker-compose.yml
if [ -f "$PROJECT_DIR/Dockerfile" ]; then
  DEPLOY_MODE="dockerfile"
  log "Found Dockerfile."
elif [ -f "$PROJECT_DIR/docker-compose.yml" ] || [ -f "$PROJECT_DIR/docker-compose.yaml" ]; then
  DEPLOY_MODE="compose"
  log "Found docker-compose.yml."
else
  fatal "No Dockerfile or docker-compose.yml found in project root ($PROJECT_DIR)." $E_VALIDATION
fi

# ---------------------
# Confirm remote connectivity
# ---------------------
log "Testing SSH connectivity to $SSH_USER@$REMOTE_IP..."
ssh -o BatchMode=yes -o ConnectTimeout=8 -i "$SSH_KEY" "$SSH_USER@$REMOTE_IP" "echo SSH_OK" >>"$LOGFILE" 2>&1 || fatal "SSH connectivity failed. Check SSH key, user, and network." $E_SSH
log "SSH connectivity OK."

# ---------------------
# Prepare remote environment (install docker, docker-compose, nginx)
# ---------------------
log "Preparing remote environment (installing Docker, Docker Compose, Nginx if needed)..."
REMOTE_APP_DIR="/home/$SSH_USER/deploy_app"
PREP_CMD=$(cat <<'REMOTE_CMDS'
set -e
# Update and install prerequisites
if command -v docker >/dev/null 2>&1; then
  echo "docker: present"
else
  echo "Installing Docker..."
  # Ubuntu/Debian friendly install; adapt if not apt-based
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
  else
    echo "Non-apt system detected. Please install Docker manually."
    exit 1
  fi
fi

if command -v docker-compose >/dev/null 2>&1; then
  echo "docker-compose: present"
else
  echo "Installing docker-compose..."
  sudo apt-get update -y
  sudo apt-get install -y python3-pip
  sudo pip3 install docker-compose
fi

if command -v nginx >/dev/null 2>&1; then
  echo "nginx: present"
else
  echo "Installing nginx..."
  sudo apt-get update -y
  sudo apt-get install -y nginx
  sudo systemctl enable --now nginx
fi

# Add user to docker group if not root
if ! groups "$USER" | grep -q docker; then
  sudo usermod -aG docker "$USER" || true
fi

# Ensure docker service running
sudo systemctl enable --now docker || true

# Create app dir
mkdir -p "$REMOTE_APP_DIR"
REMOTE_CMDS
)

# Pass PREP_CMD to remote and execute
remote_exec "$PREP_CMD" || fatal "Remote preparation failed." $E_SSH
log "Remote environment prepared."

# ---------------------
# Transfer project files
# ---------------------
log "Transferring project files to remote: $REMOTE_APP_DIR"
remote_sync "$PROJECT_DIR/" "$REMOTE_APP_DIR/"

# ---------------------
# Remote deploy: stop & remove old containers, then deploy
# ---------------------
log "Starting remote deployment..."
DEPLOY_CMD=$(cat <<REMOTE_DEPLOY
set -e
cd "$REMOTE_APP_DIR" || exit 1
# Stop existing container
if docker ps -q --filter "name=deployed_app" | grep -q .; then
  docker stop deployed_app || true
  docker rm deployed_app || true
fi

# If compose exists, use it
if [ -f docker-compose.yml ] || [ -f docker-compose.yaml ]; then
  # bring down duplicates safely
  docker-compose down || true
  # Build and start
  docker-compose up -d --build
  # rename container? assume service named web or app; try to find a running container
  # If user has a service named differently, we'll proceed with what's running.
else
  # Build image and run container
  docker build -t deployed_app .
  # Remove old container if exists
  docker ps -a -q --filter "name=deployed_app" | xargs -r docker rm -f || true
  docker run -d --name deployed_app -p ${HOST_PORT}:${CONTAINER_PORT} deployed_app
fi

# Wait briefly then check container health / status
sleep 3
docker ps --filter "name=deployed_app" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Ensure app responds on localhost:HOST_PORT
if command -v curl >/dev/null 2>&1; then
  if curl -sS --fail "http://127.0.0.1:${HOST_PORT}" -m 5 >/dev/null 2>&1; then
    echo "APP_OK"
  else
    echo "WARNING: app did not respond on http://127.0.0.1:${HOST_PORT} (may be starting or require different path)"
  fi
fi
REMOTE_DEPLOY
)

# Replace placeholders in DEPLOY_CMD with actual numeric values by here-doc substitution
DEPLOY_CMD="${DEPLOY_CMD//\${HOST_PORT}/$HOST_PORT}"
DEPLOY_CMD="${DEPLOY_CMD//\${CONTAINER_PORT}/$CONTAINER_PORT}"

remote_exec "$DEPLOY_CMD" >>"$LOGFILE" 2>&1 || fatal "Remote deployment failed." $E_DEPLOY
log "Remote deployment step complete."

# ---------------------
# Configure Nginx reverse proxy
# ---------------------
log "Creating Nginx reverse proxy configuration..."
NGINX_CONF=$(cat <<NGINX
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:${HOST_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX
)

# Write nginx config remotely
tmpfile="/tmp/deployed_app_nginx_${TIMESTAMP}.conf"
printf "%s\n" "$NGINX_CONF" > "/tmp/local_nginx_${TIMESTAMP}.conf"
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "/tmp/local_nginx_${TIMESTAMP}.conf" "$SSH_USER@$REMOTE_IP:$tmpfile" >>"$LOGFILE" 2>&1 || fatal "Failed to upload Nginx config." $E_SSH
remote_exec "sudo mv $tmpfile /etc/nginx/sites-available/deployed_app.conf && sudo ln -sf /etc/nginx/sites-available/deployed_app.conf /etc/nginx/sites-enabled/deployed_app.conf && sudo nginx -t && sudo systemctl reload nginx" >>"$LOGFILE" 2>&1 || fatal "Failed to install/reload Nginx config." $E_SSH
rm -f "/tmp/local_nginx_${TIMESTAMP}.conf"

log "Nginx configured to reverse proxy to 127.0.0.1:${HOST_PORT}"

# ---------------------
# Validation steps
# ---------------------
log "Validating deployment from remote..."
VALIDATE_CMD=$(cat <<EOF
set -e
echo "Docker service status:"
sudo systemctl is-active docker || true
echo "Docker ps:"
docker ps --filter "name=deployed_app" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
# Try curling local app
if command -v curl >/dev/null 2>&1; then
  echo "curling local app..."
  curl -sS -I "http://127.0.0.1:${HOST_PORT}" | head -n 10 || true
fi
# Test nginx proxy locally
if command -v curl >/dev/null 2>&1; then
  echo "curling via nginx (localhost:80)..."
  curl -sS -I "http://127.0.0.1/" | head -n 10 || true
fi
EOF
)
remote_exec "$VALIDATE_CMD" >>"$LOGFILE" 2>&1 || log "Validation had warnings; check $LOGFILE"

# Also attempt to curl from local machine to remote IP (public)
log "Testing endpoint from control machine: http://$REMOTE_IP/ (may fail if firewall closed)"
if command -v curl >/dev/null 2>&1; then
  if curl -sS --fail "http://$REMOTE_IP/" -m 7 >/dev/null 2>&1; then
    log "Remote endpoint OK (HTTP 200)."
  else
    log "Warning: Could not get 200 from http://$REMOTE_IP/. It might be blocked by firewall or app path is different. Check $LOGFILE for remote output."
  fi
fi

# ---------------------
# Final status
# ---------------------
log "Deployment finished. Log file: $LOGFILE"
log "Remote app directory: $REMOTE_APP_DIR"
log "To cleanup: ./deploy.sh --cleanup"

exit 0

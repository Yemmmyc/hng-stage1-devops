#!/bin/bash
set -e

# ---------- Logging ----------
LOG_FILE="./deploy_$(date +%Y%m%d_%H%M%S).log"
log() { echo "[INFO] $(date +%Y-%m-%d\ %H:%M:%S) $*" | tee -a "$LOG_FILE"; }
fatal() { echo "[ERROR] $(date +%Y-%m-%d\ %H:%M:%S) $*" | tee -a "$LOG_FILE"; exit 1; }

# ---------- Last used settings file ----------
SETTINGS_FILE="./.deploy_settings"

# Load previous settings if available
if [[ -f "$SETTINGS_FILE" ]]; then
    source "$SETTINGS_FILE"
fi

# ---------- Handle Cleanup ----------
if [[ "$1" == "--cleanup" ]]; then
    log "Cleanup flag detected. Removing deployed resources..."
    docker stop deployed_app 2>/dev/null || true
    docker rm deployed_app 2>/dev/null || true
    docker rmi deployed_app:latest 2>/dev/null || true
    sudo rm -f /etc/nginx/sites-available/deployed_app.conf
    sudo rm -f /etc/nginx/sites-enabled/deployed_app.conf
    sudo nginx -t && sudo systemctl reload nginx || true
    log "Cleanup complete."
    exit 0
fi

# ---------- User Inputs ----------
read -p "Git repository URL [${LAST_REPO_URL:-https://github.com/Yemmmyc/hng-stage1-devops.git}]: " REPO_URL
REPO_URL=${REPO_URL:-${LAST_REPO_URL:-https://github.com/Yemmmyc/hng-stage1-devops.git}}

read -p "Branch name [${LAST_BRANCH:-main}]: " BRANCH
BRANCH=${BRANCH:-${LAST_BRANCH:-main}}

read -p "App container port [${LAST_CONTAINER_PORT:-8000}]: " CONTAINER_PORT
CONTAINER_PORT=${CONTAINER_PORT:-${LAST_CONTAINER_PORT:-8000}}

read -p "Host port to expose [${LAST_HOST_PORT:-80}]: " HOST_PORT
HOST_PORT=${HOST_PORT:-${LAST_HOST_PORT:-80}}

# Save settings for next run
cat > "$SETTINGS_FILE" <<EOL
LAST_REPO_URL=$REPO_URL
LAST_BRANCH=$BRANCH
LAST_CONTAINER_PORT=$CONTAINER_PORT
LAST_HOST_PORT=$HOST_PORT
EOL

log "Starting deployment..."

# ---------- Clone / Update Repository ----------
if [ -d "./app_repo" ]; then
    log "Repository exists. Pulling latest changes..."
    git -C ./app_repo fetch --all
    git -C ./app_repo reset --hard origin/$BRANCH
else
    log "Cloning repository..."
    git clone --branch "$BRANCH" "$REPO_URL" app_repo
fi

# ---------- Handle Host Port Conflicts ----------
if sudo lsof -i :"$HOST_PORT" >/dev/null 2>&1; then
    log "Port $HOST_PORT is in use. Using 8076 instead for local testing."
    HOST_PORT=8076
fi
log "Host port set to $HOST_PORT (container port $CONTAINER_PORT)"

# ---------- Build Docker Image ----------
log "Building Docker image..."
docker build -t deployed_app:latest ./app_repo

# ---------- Stop & Remove Old Container ----------
if docker ps -a --format '{{.Names}}' | grep -Eq "^deployed_app\$"; then
    log "Stopping old container..."
    docker stop deployed_app
    docker rm deployed_app
fi

# ---------- Remove Old Docker Image ----------
if docker images -q deployed_app:latest >/dev/null 2>&1; then
    log "Removing old Docker image..."
    docker rmi deployed_app:latest || true
fi

# ---------- Run New Container ----------
log "Running Docker container..."
docker run -d --name deployed_app -p $HOST_PORT:$CONTAINER_PORT deployed_app:latest

# ---------- Configure Nginx Reverse Proxy ----------
log "Configuring Nginx reverse proxy..."
NGINX_CONFIG=$(cat <<EOF
server {
    listen 80;

    location / {
        proxy_pass http://127.0.0.1:$CONTAINER_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
)

echo "$NGINX_CONFIG" | sudo tee /etc/nginx/sites-available/deployed_app.conf > /dev/null
sudo ln -sf /etc/nginx/sites-available/deployed_app.conf /etc/nginx/sites-enabled/
sudo nginx -t || fatal "Nginx configuration test failed"
sudo systemctl reload nginx || fatal "Failed to reload Nginx"
log "Nginx reverse proxy configured."

# ---------- Validate Deployment ----------
log "Validating deployment..."
if curl -s "http://127.0.0.1:$HOST_PORT" >/dev/null; then
    log "Deployment complete. Application running on port $HOST_PORT"
else
    fatal "App validation failed. Check container logs with 'docker logs deployed_app'"
fi

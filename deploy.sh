#!/bin/bash
set -euo pipefail

# ---------------------------- Config ----------------------------
APP_NAME="deployed_app"
CONTAINER_PORT=8000       # internal container port
HOST_PORT=80              # host port to expose
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/deploy_$(date +%Y%m%d_%H%M%S).log"
DOCKER_IMAGE="$APP_NAME:latest"

mkdir -p "$LOG_DIR"

# ---------------------------- Logging --------------------------
log() {
    echo "[INFO] $(date +'%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
}

fatal() {
    echo "[ERROR] $(date +'%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
    exit 1
}

# ---------------------------- Cleanup -------------------------
cleanup() {
    log "Stopping and removing old container if exists..."
    if docker ps -a --format '{{.Names}}' | grep -q "^$APP_NAME\$"; then
        docker stop "$APP_NAME" || true
        docker rm "$APP_NAME" || true
    fi
    log "Removing old Docker image if exists..."
    docker rmi -f "$DOCKER_IMAGE" || true
}

if [[ "${1:-}" == "--cleanup" ]]; then
    cleanup
    log "Cleanup completed."
    exit 0
fi

# ---------------------------- Docker Build & Deploy ------------
log "Building Docker image..."
docker build -t "$DOCKER_IMAGE" .

log "Running Docker container..."
cleanup  # ensure no conflicts
docker run -d --name "$APP_NAME" -p "$HOST_PORT:$CONTAINER_PORT" "$DOCKER_IMAGE"

# ---------------------------- Nginx Config ---------------------
log "Configuring Nginx reverse proxy..."
NGINX_CONFIG=$(cat <<EOF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:$CONTAINER_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    # Optional SSL placeholder:
    # listen 443 ssl;
    # ssl_certificate /path/to/cert.crt;
    # ssl_certificate_key /path/to/cert.key;
}
EOF
)

echo "$NGINX_CONFIG" | sudo tee /etc/nginx/sites-available/$APP_NAME.conf > /dev/null
sudo ln -sf /etc/nginx/sites-available/$APP_NAME.conf /etc/nginx/sites-enabled/
sudo nginx -t || fatal "Nginx configuration test failed."
sudo systemctl reload nginx

# ---------------------------- Validation -----------------------
log "Validating deployment..."
if ! docker ps --format '{{.Names}}' | grep -q "^$APP_NAME\$"; then
    fatal "Docker container is not running!"
fi

if ! curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$HOST_PORT" | grep -q "200"; then
    fatal "Nginx is not proxying correctly!"
fi

log "Deployment successful. App running on http://127.0.0.1:$HOST_PORT"

# ---------------------------- Exit -----------------------------
exit 0

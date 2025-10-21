#!/bin/bash
# -------------------------
# Automated Deployment Script - HNG Stage 1
# -------------------------
set -e
trap 'echo "[ERROR] Deployment failed at line $LINENO"; exit 1' ERR

LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"
echo "[INFO] Deployment started at $(date)" | tee -a "$LOG_FILE"

# -------------------------
# Collect user inputs
# -------------------------
read -p "Git repository URL [https://github.com/Yemmmyc/hng-stage1-devops.git]: " GIT_REPO
GIT_REPO=${GIT_REPO:-https://github.com/Yemmmyc/hng-stage1-devops.git}

read -p "GitHub Personal Access Token (PAT): " GIT_PAT

read -p "Branch name [main]: " GIT_BRANCH
GIT_BRANCH=${GIT_BRANCH:-main}

read -p "SSH Username [ubuntu]: " SSH_USER
SSH_USER=${SSH_USER:-ubuntu}

read -p "Server IP [localhost]: " SERVER_IP
SERVER_IP=${SERVER_IP:-localhost}

read -p "SSH Key Path [/home/$USER/.ssh/id_rsa]: " SSH_KEY
SSH_KEY=${SSH_KEY:-/home/$USER/.ssh/id_rsa}

read -p "Container port [8000]: " CONTAINER_PORT
CONTAINER_PORT=${CONTAINER_PORT:-8000}

read -p "Host port [80]: " HOST_PORT
HOST_PORT=${HOST_PORT:-80}

CONTAINER_NAME="landing_page"
IMAGE_NAME="landing_page_image"

# -------------------------
# Clone or update repo
# -------------------------
REPO_NAME=$(basename "$GIT_REPO" .git)
if [ -d "$REPO_NAME" ]; then
    echo "[INFO] Repository exists. Pulling latest changes..." | tee -a "$LOG_FILE"
    cd "$REPO_NAME"
    git pull origin "$GIT_BRANCH"
    git checkout "$GIT_BRANCH"
else
    echo "[INFO] Cloning repository..." | tee -a "$LOG_FILE"
    git clone -b "$GIT_BRANCH" "https://$GIT_PAT@${GIT_REPO#https://}"
    cd "$REPO_NAME"
fi

# -------------------------
# SSH connectivity (skip for localhost)
# -------------------------
if [[ "$SERVER_IP" != "localhost" && "$SERVER_IP" != "127.0.0.1" ]]; then
    echo "[INFO] Testing SSH connectivity to $SSH_USER@$SERVER_IP..." | tee -a "$LOG_FILE"
    ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$SERVER_IP" "echo SSH connection successful" | tee -a "$LOG_FILE"
else
    echo "[INFO] Running locally. Skipping SSH." | tee -a "$LOG_FILE"
fi

# -------------------------
# Server preparation (only if remote)
# -------------------------
if [[ "$SERVER_IP" != "localhost" && "$SERVER_IP" != "127.0.0.1" ]]; then
    echo "[INFO] Preparing remote server..." | tee -a "$LOG_FILE"
    ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash <<'REMOTE'
        sudo apt update -y
        sudo apt install -y docker.io docker-compose nginx
        sudo systemctl enable --now docker
        sudo systemctl enable --now nginx
        sudo usermod -aG docker $USER
REMOTE
else
    echo "[INFO] Installing Docker/Nginx locally if missing..." | tee -a "$LOG_FILE"
    sudo apt update -y
    sudo apt install -y docker.io docker-compose nginx
    sudo systemctl enable --now docker
    sudo systemctl enable --now nginx
    sudo usermod -aG docker $USER
fi

# -------------------------
# Stop/remove old container/image
# -------------------------
echo "[INFO] Stopping and removing old container..." | tee -a "$LOG_FILE"
docker rm -f $CONTAINER_NAME 2>/dev/null || true
echo "[INFO] Removing old Docker image..." | tee -a "$LOG_FILE"
docker rmi $IMAGE_NAME 2>/dev/null || true

# -------------------------
# Build Docker image
# -------------------------
echo "[INFO] Building Docker image..." | tee -a "$LOG_FILE"
docker build -t $IMAGE_NAME . | tee -a "$LOG_FILE"

# -------------------------
# Check port availability
# -------------------------
if lsof -i :$HOST_PORT >/dev/null; then
    echo "[INFO] Port $HOST_PORT in use, using 8076 instead" | tee -a "$LOG_FILE"
    HOST_PORT=8076
fi

# -------------------------
# Run Docker container
# -------------------------
echo "[INFO] Running Docker container..." | tee -a "$LOG_FILE"
docker run -d --name $CONTAINER_NAME -p $HOST_PORT:$CONTAINER_PORT $IMAGE_NAME | tee -a "$LOG_FILE"

# -------------------------
# Configure Nginx as reverse proxy
# -------------------------
NGINX_CONF="/etc/nginx/sites-available/$CONTAINER_NAME"
sudo bash -c "cat > $NGINX_CONF" <<EOF
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://127.0.0.1:$HOST_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
echo "[INFO] Nginx configured as reverse proxy to container port $CONTAINER_PORT" | tee -a "$LOG_FILE"

# -------------------------
# Health checks
# -------------------------
sleep 5
if curl -s "http://127.0.0.1:$HOST_PORT" >/dev/null; then
    echo "[INFO] Docker container is running and reachable" | tee -a "$LOG_FILE"
else
    echo "[ERROR] Container is not reachable!" | tee -a "$LOG_FILE"
    exit 1
fi

if curl -s http://127.0.0.1 >/dev/null; then
    echo "[INFO] Nginx is proxying correctly" | tee -a "$LOG_FILE"
else
    echo "[ERROR] Nginx proxy failed!" | tee -a "$LOG_FILE"
    exit 1
fi

# -------------------------
# Optional cleanup flag
# -------------------------
if [[ $1 == "--cleanup" ]]; then
    echo "[INFO] Cleanup requested. Removing container, image, and Nginx config..." | tee -a "$LOG_FILE"
    docker rm -f $CONTAINER_NAME || true
    docker rmi $IMAGE_NAME || true
    sudo rm -f $NGINX_CONF
    sudo systemctl reload nginx
fi

echo "[INFO] Deployment completed successfully! Visit: http://127.0.0.1:$HOST_PORT/" | tee -a "$LOG_FILE"
echo "[INFO] Logs saved to $LOG_FILE"

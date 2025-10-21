#!/bin/bash

# ===============================
# HNG Stage 1 Task - deploy.sh
# Automated Dockerized App Deployment Script
# Author: Yemisi
# ===============================

set -euo pipefail

# ---------- Helpers ----------
timestamp() { date +"%Y-%m-%dT%H:%M:%S"; }
log() { echo "$(timestamp) $1"; }
fatal() { echo "$(timestamp) ERROR: $1" >&2; exit 1; }
ask() {
  local prompt="$1"
  local default="$2"
  read -r -p "$prompt [$default]: " input
  echo "${input:-$default}"
}
ask_secret() {
  local prompt="$1"
  read -s -p "$prompt: " input
  echo
  echo "$input"
}

# ---------- Defaults ----------
DEFAULT_REPO="https://github.com/Yemmmyc/hng-stage1-devops.git"
DEFAULT_BRANCH="main"
DEFAULT_SSH_USER="banji"
DEFAULT_REMOTE_IP="127.0.0.1"
DEFAULT_SSH_KEY="/home/banji/.ssh/id_rsa"
DEFAULT_CONTAINER_PORT="8000"
DEFAULT_HOST_PORT="80"
LOG_FILE="deploy_$(date +%Y-%m-%d_%H%M%S).log"

# ---------- Start ----------
log "Starting interactive deployment..."
REPO_URL=$(ask "Git repository URL" "$DEFAULT_REPO")
PAT=$(ask_secret "Personal Access Token (hidden)")
BRANCH=$(ask "Branch name" "$DEFAULT_BRANCH")
SSH_USER=$(ask "Remote SSH username" "$DEFAULT_SSH_USER")
REMOTE_IP=$(ask "Remote server IP" "$DEFAULT_REMOTE_IP")
SSH_KEY=$(ask "SSH key path" "$DEFAULT_SSH_KEY")
CONTAINER_PORT=$(ask "App container port" "$DEFAULT_CONTAINER_PORT")
HOST_PORT=$(ask "Host port to expose" "$DEFAULT_HOST_PORT")

# ---------- Clone or Pull Repo ----------
log "Cloning repository..."
PAT_CLEAN=$(echo -n "$PAT" | tr -d '\n\r' | xargs)
AUTH_REPO_URL="https://${PAT_CLEAN}@${REPO_URL#https://}"
REPO_NAME=$(basename "$REPO_URL" .git)

if [[ -d "$REPO_NAME/.git" ]]; then
  log "Repository exists. Pulling latest changes..."
  cd "$REPO_NAME" || fatal "Failed to enter repo directory"
  git pull || fatal "Git pull failed"
else
  git clone -b "$BRANCH" "$AUTH_REPO_URL" "$REPO_NAME" || fatal "Git clone failed"
  cd "$REPO_NAME" || fatal "Failed to enter cloned repo"
fi

log "Repository ready in $(pwd)"

# ---------- Validate Docker setup ----------
if [[ ! -f Dockerfile && ! -f docker-compose.yml ]]; then
  fatal "No Dockerfile or docker-compose.yml found in $(pwd). Please add one."
fi
log "Dockerfile/docker-compose.yml verified."

# ---------- Prepare Remote Environment ----------
log "Preparing remote environment on $REMOTE_IP..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$REMOTE_IP" bash <<'EOF' || fatal "Remote setup failed"
set -e
# Clean old unreachable sources
sudo rm -f /etc/apt/sources.list.d/hashicorp.list || true
sudo rm -f /etc/apt/sources.list.d/jumppad.list || true

echo "Updating system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y

# Install required packages
sudo apt-get install -y curl gnupg lsb-release software-properties-common nginx

# Docker
if ! command -v docker >/dev/null 2>&1; then
  echo "Installing Docker..."
  sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io
  sudo usermod -aG docker $USER
else
  echo "Docker already installed, skipping..."
fi

# Docker Compose
if ! command -v docker-compose >/dev/null 2>&1; then
  echo "Installing Docker Compose..."
  DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
  sudo curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
  docker-compose --version
else
  echo "Docker Compose already installed, skipping..."
fi

# Nginx
echo "Ensuring Nginx is running..."
sudo systemctl enable nginx --now
nginx -v
EOF
log "Remote environment prepared successfully."

# ---------- Deploy Dockerized Application ----------
log "Deploying Docker container..."
scp -i "$SSH_KEY" -r ./* "$SSH_USER@$REMOTE_IP:/home/$SSH_USER/deployed_app" || fatal "File transfer failed"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$REMOTE_IP" bash <<EOF || fatal "App deployment failed"
set -e
cd /home/$SSH_USER/deployed_app

# Remove old containers
if [[ -f docker-compose.yml ]]; then
  sudo docker-compose down || true
  sudo docker-compose up -d --build
elif [[ -f Dockerfile ]]; then
  sudo docker stop deployed_app || true
  sudo docker rm deployed_app || true
  sudo docker build -t deployed_app .
  sudo docker run -d -p $CONTAINER_PORT:$CONTAINER_PORT --name deployed_app deployed_app
fi
EOF
log "Dockerized app deployed successfully."

# ---------- Configure Nginx Reverse Proxy ----------
log "Configuring Nginx reverse proxy..."

ssh -i "$SSH_KEY" "$SSH_USER@$REMOTE_IP" bash <<'EOF_REMOTE'
set -e

# Variables passed from deploy.sh
CONTAINER_PORT='"$CONTAINER_PORT"'

# Create Nginx config
sudo tee /etc/nginx/sites-available/deployed_app.conf > /dev/null <<NGINX
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:$CONTAINER_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINX

# Enable site and reload Nginx
sudo ln -sf /etc/nginx/sites-available/deployed_app.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
EOF_REMOTE
log "Nginx reverse proxy configured."


# ---------- Validate Deployment ----------
log "Validating deployment..."
ssh -i "$SSH_KEY" "$SSH_USER@$REMOTE_IP" curl -I "http://127.0.0.1:$HOST_PORT" || fatal "App validation failed"
log "Deployment complete. Application running on port $HOST_PORT"

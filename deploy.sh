#!/bin/bash

# -------------------------
# Default Variables (can be overridden by user)
# -------------------------
DEFAULT_GIT_REPO="https://github.com/Yemmmyc/hng-stage1-devops.git"
DEFAULT_BRANCH="main"
DEFAULT_SSH_USER="banji"
DEFAULT_SERVER_IP="localhost"
DEFAULT_SSH_KEY="/home/banji/.ssh/id_rsa"
DEFAULT_CONTAINER_PORT=8000
DEFAULT_HOST_PORT=80
IMAGE_NAME="landing_page_image"
CONTAINER_NAME="landing_page"
LOG_FILE="deploy.log"

# -------------------------
# Prompt for values with defaults
# -------------------------
read -p "Git repository URL [$DEFAULT_GIT_REPO]: " GIT_REPO
GIT_REPO=${GIT_REPO:-$DEFAULT_GIT_REPO}

read -p "GitHub Personal Access Token (PAT): " GIT_PAT

read -p "Branch name [$DEFAULT_BRANCH]: " BRANCH
BRANCH=${BRANCH:-$DEFAULT_BRANCH}

read -p "SSH Username [$DEFAULT_SSH_USER]: " SSH_USER
SSH_USER=${SSH_USER:-$DEFAULT_SSH_USER}

read -p "Server IP [$DEFAULT_SERVER_IP]: " SERVER_IP
SERVER_IP=${SERVER_IP:-$DEFAULT_SERVER_IP}

read -p "SSH Key Path [$DEFAULT_SSH_KEY]: " SSH_KEY
SSH_KEY=${SSH_KEY:-$DEFAULT_SSH_KEY}

read -p "Container port [$DEFAULT_CONTAINER_PORT]: " CONTAINER_PORT
CONTAINER_PORT=${CONTAINER_PORT:-$DEFAULT_CONTAINER_PORT}

read -p "Host port [$DEFAULT_HOST_PORT]: " HOST_PORT
HOST_PORT=${HOST_PORT:-$DEFAULT_HOST_PORT}

# -------------------------
# Stop and remove old container/image
# -------------------------
echo "[INFO] Stopping and removing old container..." | tee -a "$LOG_FILE"
docker rm -f $CONTAINER_NAME 2>/dev/null | tee -a "$LOG_FILE"

echo "[INFO] Removing old Docker image..." | tee -a "$LOG_FILE"
docker rmi $IMAGE_NAME 2>/dev/null | tee -a "$LOG_FILE"

# -------------------------
# Build Docker image (Nginx)
# -------------------------
echo "[INFO] Building Docker image..." | tee -a "$LOG_FILE"
docker build -t $IMAGE_NAME . | tee -a "$LOG_FILE"

# -------------------------
# Check if port is available
# -------------------------
if lsof -i :$HOST_PORT >/dev/null; then
    echo "[INFO] Port $HOST_PORT is in use, using 8076 instead" | tee -a "$LOG_FILE"
    HOST_PORT=8076
fi

# -------------------------
# Run the container
# -------------------------
echo "[INFO] Running Docker container..." | tee -a "$LOG_FILE"
docker run -d --name $CONTAINER_NAME -p $HOST_PORT:80 $IMAGE_NAME | tee -a "$LOG_FILE"

# -------------------------
# Deployment complete
# -------------------------
echo "[INFO] Deployment successful! Visit: http://127.0.0.1:$HOST_PORT/" | tee -a "$LOG_FILE"
echo "[INFO] Logs saved to $LOG_FILE"

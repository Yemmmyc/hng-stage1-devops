#!/bin/bash
set -e

# ---------- Helper functions ----------
log() {
    echo -e "[INFO] $1"
}

fatal() {
    echo -e "[ERROR] $1"
    exit 1
}

# ---------- User Inputs ----------
read -p "Git repository URL [https://github.com/Yemmmyc/hng-stage1-devops.git]: " GIT_REPO
GIT_REPO=${GIT_REPO:-https://github.com/Yemmmyc/hng-stage1-devops.git}

read -s -p "Personal Access Token (hidden): " GIT_TOKEN
echo

read -p "Branch name [main]: " GIT_BRANCH
GIT_BRANCH=${GIT_BRANCH:-main}

read -p "Remote SSH username [banji]: " SSH_USER
SSH_USER=${SSH_USER:-banji}

read -p "Remote server IP [127.0.0.1]: " REMOTE_IP
REMOTE_IP=${REMOTE_IP:-127.0.0.1}

read -p "SSH key path [/home/banji/.ssh/id_rsa]: " SSH_KEY
SSH_KEY=${SSH_KEY:-/home/banji/.ssh/id_rsa}

read -p "App container port [8000]: " CONTAINER_PORT
CONTAINER_PORT=${CONTAINER_PORT:-8000}

read -p "Host port to expose [80]: " HOST_PORT
HOST_PORT=${HOST_PORT:-80}

# ---------- Prepare Repository ----------
log "Cloning repository..."
if [ ! -d "./hng-stage1-devops" ]; then
    git clone -b "$GIT_BRANCH" "https://$GIT_TOKEN@${GIT_REPO#https://}" ./hng-stage1-devops || fatal "Git clone failed"
else
    cd hng-stage1-devops
    git pull origin "$GIT_BRANCH" || fatal "Git pull failed"
    cd ..
fi

log "Repository ready."

# ---------- Build Docker Image ----------
log "Building Docker container..."
cd ./hng-stage1-devops || fatal "Cannot enter repo folder"
docker build -t deployed_app . || fatal "Docker build failed"
cd ..

log "Dockerized app deployed successfully."

# ---------- Configure Nginx Reverse Proxy ----------
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
}
EOF
)

ssh -i "$SSH_KEY" "$SSH_USER@$REMOTE_IP" bash <<EOF || fatal "Nginx config failed"
set -e
echo "$NGINX_CONFIG" | sudo tee /etc/nginx/sites-available/deployed_app.conf > /dev/null
sudo ln -sf /etc/nginx/sites-available/deployed_app.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
EOF

log "Nginx reverse proxy configured."

# ---------- Validate Deployment ----------
log "Validating deployment..."
ssh -i "$SSH_KEY" "$SSH_USER@$REMOTE_IP" curl -I "http://127.0.0.1:$HOST_PORT" || fatal "App validation failed"

log "Deployment complete. Application running on port $HOST_PORT"

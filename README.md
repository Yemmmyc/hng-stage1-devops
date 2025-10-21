HNG DevOps Stage 1 — Automated Deployment Bash Script
Project Overview

This project demonstrates a robust, production-grade Bash script to automate the setup, deployment, and configuration of a Dockerized Node.js application on a remote EC2 Linux server. It includes logging, error handling, SSH connectivity, Docker & Nginx installation, reverse proxy configuration, and full idempotency.

Features

Automated deployment: One script handles cloning, Docker build/run, Nginx configuration, and validation.

SSH-ready: Script connects to remote EC2 server using provided credentials.

Logging & error handling: Timestamped logs and set -e/trap ensure failures are captured.

Idempotent & cleanup-friendly: Stops/removes old containers, handles port conflicts, and includes optional --cleanup flag.

Health checks: Validates Docker container, service, and Nginx proxy.

User-friendly prompts: Accepts default values for quick deployment; PAT can be pasted when prompted.

Deployment Steps
1. Prerequisites

EC2 instance running Ubuntu

Private key (.pem) for SSH access

GitHub Personal Access Token (PAT)

Docker installed (optional; script installs if missing)

2. Script Usage
# Make script executable
chmod +x deploy.sh

# Run deployment
./deploy.sh


You will be prompted for:

Git repository URL (default: https://github.com/Yemmmyc/hng-stage1-devops.git)

GitHub PAT

Branch name (default: main)

SSH Username (default: ubuntu)

Server IP (EC2 instance)

SSH Key Path (default: /home/ubuntu/.ssh/Automation.pem)

Container port (default: 8000)

Host port (default: 80)

Press Enter to accept default values.

Optional flag for cleanup:

./deploy.sh --cleanup

3. Logs

All actions are logged to:

deploy.log — general logging

deploy_YYYYMMDD_HHMMSS.log — timestamped logs per run

Helps with troubleshooting and auditing.

4. Troubleshooting

Port conflicts: Script automatically switches if default port is in use.

Docker permissions: Ensure user is in docker group.

SSH issues: Ensure correct .pem permissions:

chmod 400 /path/to/Automation.pem


Network issues pulling Docker images: Confirm internet access on EC2.

Manual cleanup commands:

docker rm -f landing_page
docker rmi landing_page_image

5. Author

Name: Oluwayemisi Okunrounmu
Email: yemmmyc@hotmail.com

GitHub: https://github.com/Yemmmyc/hng-stage1-devops

✅ Final Checklist for Stage 1 Submission

 Repository cloned successfully

 README.md exists with content

 deploy.sh exists and is executable

 Bash script has proper shebang (#!/bin/bash)

 Error handling implemented (set -e and trap)

 Logging implemented (general + timestamped logs)

 User input prompts with defaults

 Git clone/pull implemented, branch switching included

 SSH connectivity tested, commands executed remotely

 EC2 server prepared: packages updated, Docker & Nginx installed, Docker group configured

 Docker container build/run included

 Nginx configured as reverse proxy to container port

 Health checks: Docker container & service verified, Nginx proxy verified

 Script idempotent & safe to re-run

 Optional --cleanup flag included for removing all deployed resources

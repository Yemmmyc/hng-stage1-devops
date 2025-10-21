# 🎯 HNG DevOps Intern Stage 1 - Automated Deployment Bash Script

![GitHub last commit](https://img.shields.io/github/last-commit/Yemmmyc/hng-stage1-devops)
![GitHub repo size](https://img.shields.io/github/repo-size/Yemmmyc/hng-stage1-devops)
![GitHub issues](https://img.shields.io/github/issues/Yemmmyc/hng-stage1-devops)
![GitHub license](https://img.shields.io/github/license/Yemmmyc/hng-stage1-devops)
![Docker](https://img.shields.io/badge/Docker-Installed-blue)
![Bash](https://img.shields.io/badge/Bash-Deployment-orange)

Automated deployment of a Dockerized application on a remote Linux server using a single Bash script (`deploy.sh`).  

---

## 🛠️ Features

- Prompts for Git repo, PAT, branch, SSH credentials, container and host ports  
- Clones/pulls repository automatically  
- Builds and runs Docker containers  
- Configures Nginx as a reverse proxy  
- Optional cleanup and health checks for full idempotency  
- Logging and error handling  
- Handles port conflicts and existing containers  

---

## ⚡ Quick Setup

1. **Clone the repository**
```bash
git clone https://github.com/Yemmmyc/hng-stage1-devops.git
cd hng-stage1-devops
chmod +x deploy.sh
Create .gitignore
Ignore all logs except deploy.log:

gitignore
Copy code
*.log
!deploy.log
Run the deployment script

bash
Copy code
./deploy.sh
When prompted, press Enter for default values or paste your PAT when requested.

📂 Logs
All actions are logged to deploy.log

Timestamped logs (deploy_YYYYMMDD_HHMMSS.log) are created for each run

Helps in troubleshooting and auditing deployments

⚠️ Troubleshooting
Port conflicts: Script auto-switches if a port is in use

Network issues: Ensure internet and Docker Hub access

Container conflicts: Remove old containers manually:

bash
Copy code
docker rm -f landing_page
docker rmi landing_page_image
📄 Author
Oluwayemisi Okunrounmu
Email: yemmmyc@hotmail.com
GitHub: https://github.com/Yemmmyc/hng-stage1-devops

✅ Final Checklist for Stage 1 Submission
 deploy.sh exists, executable, proper shebang

 Error handling included (set -e + trap)

 Logging to deploy.log and timestamped logs

 User input prompts for all required parameters

 Git clone/pull and branch switching implemented

 SSH connectivity and remote commands

 Docker & Nginx installed and configured on EC2

 Docker deployment and container health checks

 Nginx reverse proxy setup

 Idempotency and optional --cleanup flag

 .gitignore excludes unnecessary logs, keeps deploy.log

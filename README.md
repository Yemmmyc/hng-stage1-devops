# 🎯 HNG13 DevOps Intern – Stage 1  
**Automated Deployment Bash Script (deploy.sh)**  

[![Built with Bash](https://img.shields.io/badge/Built%20with-Bash-121011?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Dockerized](https://img.shields.io/badge/Containerized%20with-Docker-blue?logo=docker)](https://www.docker.com/)
[![Deployed on AWS EC2](https://img.shields.io/badge/Deployed%20on-AWS%20EC2-orange?logo=amazon-aws)](https://aws.amazon.com/ec2/)
[![GitHub Repo Size](https://img.shields.io/github/repo-size/Yemmmyc/hng-stage1-devops?color=blue)](https://github.com/Yemmmyc/hng-stage1-devops)
[![License](https://img.shields.io/github/license/Yemmmyc/hng-stage1-devops)](https://github.com/Yemmmyc/hng-stage1-devops/blob/main/LICENSE)
[![Status](https://img.shields.io/badge/Status-Working%20✅-success)](https://github.com/Yemmmyc/hng-stage1-devops)

---

## 🌍 Overview  

This project automates the deployment of a **Dockerized NGINX web application** onto a remote Linux (AWS EC2) server using a **single Bash script (`deploy.sh`)**.  
It simplifies CI/CD operations by handling **repository pulls, container builds, NGINX setup, error recovery**, and **optional cleanup** automatically.

---

## 🛠️ Features  

✅ Prompts for Git repo, Personal Access Token (PAT), branch, SSH credentials, and port mapping  
✅ Auto-clones or updates the repository  
✅ Builds and runs Docker containers  
✅ Configures NGINX as a reverse proxy  
✅ Includes cleanup flag (`--cleanup`) for full idempotency  
✅ Health checks and port-conflict resolution  
✅ Error handling with `set -e` and `trap`  
✅ Centralized and timestamped logging  

---

## ⚡ Quick Setup  

### 1️⃣ Clone the Repository  
```bash
git clone https://github.com/Yemmmyc/hng-stage1-devops.git
cd hng-stage1-devops
chmod +x deploy.sh

2️⃣ Create a .gitignore
Ignore all logs except deploy.log:

bash
Copy code
*.log
!deploy.log

3️⃣ Run the Deployment Script
bash
Copy code
./deploy.sh
Press Enter for default values, or paste your GitHub PAT when prompted.

📂 Logs
🧾 All deployment activities are logged to deploy.log
🕓 Each run also generates timestamped logs (deploy_YYYYMMDD_HHMMSS.log)
🔍 Useful for troubleshooting and auditing automated runs

⚠️ Troubleshooting
Issue	Fix
Port 80 already in use	Stop conflicting service → sudo fuser -k 80/tcp
Network issues	Ensure Internet and Docker Hub access
Container conflicts	Remove old containers → docker rm -f landing_page
Stale image	Rebuild image → docker rmi landing_page_image
NGINX not serving custom page	Verify /var/www/html/index.html exists and permissions are correct

🧹 Optional Cleanup
Use the cleanup flag to stop and remove existing containers before redeployment:

bash
Copy code
./deploy.sh --cleanup
This ensures full idempotency, avoiding stale containers or port conflicts.

✅ Final Checklist for Stage 1 Submission

Requirement	    Status
deploy.sh exists, executable, proper shebang	✅
Error handling (set -e + trap)	✅
Logging to deploy.log and timestamped logs	✅
User prompts for Git and SSH details	✅
Git clone/pull + branch switching	✅
SSH connectivity & remote commands	✅
Docker & NGINX installation and config	✅
Container deployment + health checks	✅
NGINX reverse proxy setup	✅
Idempotent with --cleanup flag	✅
.gitignore excludes logs but keeps deploy.log	✅

🧑‍💻 Author
👩‍💻 Name: Oluwayemisi Okunrounmu
💬 Slack: @yemmmyc
📧 Email: yemmmyc@hotmail.com
🌐 GitHub: https://github.com/Yemmmyc/hng-stage1-devops
☁️ Platform: AWS EC2 (Ubuntu 22.04 LTS)

✅ Status: Successfully Deployed and Verified on AWS EC2 🎉

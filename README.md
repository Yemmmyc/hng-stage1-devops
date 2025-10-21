# HNG Stage 1 DevOps - Automated Deployment Script

## 🎯 Project Overview
This project is an **automated Bash deployment script** for a Dockerized application. It simulates a real-world DevOps workflow by deploying a Node.js application behind Nginx with a colorful landing page. The script handles:

- Docker image building
- Container deployment
- Port management
- Logging
- Idempotent redeployment

---

## ⚙️ Prerequisites
Before running the script, ensure you have:

- **Docker** installed on your system
- **Git** installed
- **Bash shell**
- **GitHub Personal Access Token (PAT)** for private repo access
- **SSH access** if deploying on a remote server

---

## 🚀 Deployment Instructions

1. Clone the repository:

```bash
git clone https://github.com/Yemmmyc/hng-stage1-devops.git
cd hng-stage1-devops
Make the deployment script executable:

bash
Copy code
chmod +x deploy.sh
Run the deployment script:

bash
Copy code
./deploy.sh
The script will prompt you to paste your GitHub PAT. Press Enter for all other prompts as default values are pre-configured.

Once deployed, access the app via your browser at:

cpp
Copy code
http://127.0.0.1:8080/
📄 Script Features
Stops and removes old containers and images

Builds a new Docker image using Nginx

Copies the landing page to the container

Checks if the host port is available and switches automatically if needed

Deploys the container safely

Logs all actions to deploy.log with timestamps

Idempotent — safe to re-run multiple times

🎨 Landing Page
The landing page is colorful, responsive, and shows deployment success:

🎉 Message: App deployed successfully

🔗 Link: Directs users to the application

Background gradients and styled text for visual appeal

Example:


📂 Logs
All actions are logged to deploy.log

Timestamped logs (deploy_YYYYMMDD_HHMMSS.log) are created for each run

Helps in troubleshooting and auditing deployments

⚠️ Troubleshooting
Port conflicts: If port 8080 is in use, the script automatically switches to 8076

Network issues pulling Docker images: Ensure internet connectivity and Docker Hub access

Container conflicts: Remove old containers manually using:

bash
Copy code
docker rm -f landing_page
docker rmi landing_page_image
📝 Author
Name: Yemisi Okunroumu
Email: yemmmyc@hotmail.com

GitHub: https://github.com/Yemmmyc/hng-stage1-devops

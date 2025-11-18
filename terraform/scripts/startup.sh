#!/bin/bash
set -e

# Log everything
exec > >(tee -a /var/log/startup.log)
exec 2>&1

echo "=== Starting deployment at $(date) ==="

# Update system
apt-get update
apt-get upgrade -y

# Install Docker
echo "Installing Docker..."
apt-get install -y ca-certificates curl gnupg lsb-release
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start Docker
systemctl enable docker
systemctl start docker

# Install Node.js 20
echo "Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Install Ollama
echo "Installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh

# Start Ollama service
systemctl enable ollama
systemctl start ollama

# Wait for Ollama to be ready
echo "Waiting for Ollama to start..."
sleep 10

# Pull Ollama model
echo "Pulling Ollama model..."
HOME=/root ollama pull ${OLLAMA_MODEL}

# Create app directory
mkdir -p /opt/agent-app
cd /opt/agent-app

# Pull Docker image
echo "Pulling Docker image..."
docker pull ${DOCKER_IMAGE}

# Create systemd service for Inngest Dev Server
cat > /etc/systemd/system/inngest-dev.service <<EOF
[Unit]
Description=Inngest Dev Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/agent-app
Environment="INNGEST_DEV=1"
ExecStart=/usr/bin/npx inngest-cli@latest dev -u http://localhost:3000/api/inngest
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create systemd service for the app container
cat > /etc/systemd/system/agent-app.service <<EOF
[Unit]
Description=Agent App Container
After=docker.service ollama.service
Requires=docker.service ollama.service

[Service]
Type=simple
User=root
ExecStartPre=-/usr/bin/docker stop agent-app
ExecStartPre=-/usr/bin/docker rm agent-app
ExecStart=/usr/bin/docker run --rm --name agent-app \\
  --network=host \\
  -e INNGEST_APP_ID=${INNGEST_APP_ID} \\
  -e INNGEST_DEV=1 \\
  -e INNGEST_DEV_SERVER_URL=http://localhost:8288 \\
  -e AGENT_RESULT_TOKEN=${AGENT_RESULT_TOKEN} \\
  -e OLLAMA_BASE_URL=http://localhost:11434/v1 \\
  ${DOCKER_IMAGE}
ExecStop=/usr/bin/docker stop agent-app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start services
echo "Starting services..."
systemctl daemon-reload
systemctl enable inngest-dev
systemctl enable agent-app
systemctl start inngest-dev
sleep 5
systemctl start agent-app

# Configure UFW firewall
echo "Configuring firewall..."
ufw --force enable
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw allow 5000/tcp  # Flask app
ufw allow 8288/tcp  # Inngest Dev UI
ufw allow 3000/tcp  # Agent service
ufw allow 11434/tcp # Ollama API

echo "=== Deployment completed at $(date) ==="
echo "=== Services status ==="
systemctl status ollama --no-pager
systemctl status inngest-dev --no-pager
systemctl status agent-app --no-pager

echo "=== Access URLs ==="
echo "Frontend: http://$(curl -s ifconfig.me):5000"
echo "Inngest Dev UI: http://$(curl -s ifconfig.me):8288"
echo "Ollama API: http://$(curl -s ifconfig.me):11434"

#!/usr/bin/env bash
# role-app-server.sh — provisions the application server.
# Runs the backend as a Docker container (replaces the old systemd placeholder).
# Only the web servers (never the load balancer, never the outside world)
# are allowed to reach it.
set -euo pipefail
source /vagrant/scripts/docker-install.sh

echo "==> Provisioning app-server..."

# Remove the old placeholder systemd service if it exists from a previous run
systemctl stop placeholder-app.service 2>/dev/null || true
systemctl disable placeholder-app.service 2>/dev/null || true
rm -f /etc/systemd/system/placeholder-app.service
systemctl daemon-reload

# Copy the backend application code onto this VM
mkdir -p /opt/app/backend
cp -r /vagrant/app/backend/* /opt/app/backend/

# Build the Docker image from the copied code
cd /opt/app/backend
docker build -t backend-app .

# Stop and remove any previous container run (idempotency)
docker stop backend-app 2>/dev/null || true
docker rm backend-app 2>/dev/null || true

# Run the backend container, publishing port 3000 to the host
docker run -d \
  --name backend-app \
  --hostname app-server \
  --restart unless-stopped \
  -p 3000:3000 \
  backend-app
# Give uvicorn a moment to finish starting before provisioning continues
sleep 3

echo "==> Restricting port 3000 to the web tier subnet only"
ufw allow from 192.168.56.0/24 to any port 3000 proto tcp

echo "==> Backend container running on port 3000."


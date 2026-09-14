#!/usr/bin/env bash
# role-web-server.sh — provisions a web server running the frontend container.
# Only the load balancer is allowed to reach port 80 here — nobody else,
# and definitely not the outside world.
set -euo pipefail
source /vagrant/scripts/docker-install.sh

echo "==> Provisioning web-server..."

# Remove the old nginx placeholder if it exists from a previous run
systemctl stop nginx 2>/dev/null || true
systemctl disable nginx 2>/dev/null || true

# Copy the frontend application code onto this VM
mkdir -p /opt/app/frontend
cp -r /vagrant/app/frontend/* /opt/app/frontend/

# Build the Docker image from the copied code
cd /opt/app/frontend
docker build -t frontend-app .

# Stop and remove any previous container run (idempotency)
docker stop frontend-app 2>/dev/null || true
docker rm frontend-app 2>/dev/null || true

# Run the frontend container, passing the backend's URL as an env var
docker run -d \
  --name frontend-app \
  --hostname "$(hostname)" \
  --restart unless-stopped \
  -e BACKEND_URL=http://192.168.56.13:3000 \
  -p 80:80 \
  frontend-app

# Give uvicorn a moment to finish starting before provisioning continues
sleep 3

echo "==> Restricting port 80 to the load balancer only"
ufw allow from 192.168.56.10 to any port 80 proto tcp

echo "==> Frontend container running on port 80."


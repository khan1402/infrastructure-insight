#!/usr/bin/env bash
# docker-install.sh — installs Docker Engine on a Debian/Ubuntu VM.
# Shared by role-app-server.sh and role-web-server.sh.

set -euo pipefail

echo "==> Installing Docker..."

# Skip if Docker is already installed (makes this script safe to re-run)
if command -v docker &> /dev/null; then
    echo "Docker already installed, skipping."
    exit 0
fi

# Install prerequisites for adding Docker's repository
apt-get update
apt-get install -y ca-certificates curl gnupg

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Let the devops user run docker without sudo
usermod -aG docker devops

# Ensure Docker starts on boot and is running now
systemctl enable docker
systemctl start docker

echo "==> Docker installed successfully."


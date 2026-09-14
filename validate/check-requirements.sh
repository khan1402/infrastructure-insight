#!/usr/bin/env bash
# check-requirements.sh
#
# Run this ON your host machine (needs ssh access to devops@ each VM) to
# sanity-check the environment against the grading rubric before a review.
#
# Usage: ./validate/check-requirements.sh
#
# This does NOT replace explaining things live to a reviewer - it's here so
# you catch regressions before they do.

set -uo pipefail

KEY="$HOME/.ssh/devops_key"
HOSTS=("load-balancer:192.168.56.10" "web-server-1:192.168.56.11" "web-server-2:192.168.56.12" "app-server:192.168.56.13")

PASS=0
FAIL=0

check() {
  local desc="$1"
  local result="$2"
  if [ "$result" -eq 0 ]; then
    echo "  [PASS] $desc"
    PASS=$((PASS + 1))
  else
    echo "  [FAIL] $desc"
    FAIL=$((FAIL + 1))
  fi
}

ssh_cmd() {
  local ip="$1"; shift
  ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$KEY" "devops@${ip}" "$@"
}

for entry in "${HOSTS[@]}"; do
  name="${entry%%:*}"
  ip="${entry##*:}"
  echo ""
  echo "=== ${name} (${ip}) ==="

  # devops user exists
  ssh_cmd "$ip" "grep -q devops /etc/passwd" &>/dev/null
  check "devops user exists" $?

  # devops in sudo group
  ssh_cmd "$ip" "groups devops | grep -q sudo" &>/dev/null
  check "devops is in sudo group" $?

  # key-based login works (this whole script running implies it does, but
  # double check no password was needed by checking BatchMode succeeded)
  ssh_cmd "$ip" "true" &>/dev/null
  check "SSH key login works without a password" $?

  # root login disabled
  ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@${ip}" "true" &>/dev/null
  root_result=$?
  check "root SSH login is refused" $([ $root_result -ne 0 ] && echo 0 || echo 1)

  # UFW active
  ssh_cmd "$ip" "sudo ufw status | grep -q 'Status: active'" &>/dev/null
  check "UFW is active" $?

  # umask
  umask_val=$(ssh_cmd "$ip" "umask" 2>/dev/null)
  if [[ "$umask_val" == "0027" || "$umask_val" == "027" ]]; then
    check "umask is set to 027" 0
  else
    check "umask is set to 027 (got: ${umask_val:-none})" 1
  fi

  # auto-updates configured
  ssh_cmd "$ip" "grep -q 'Unattended-Upgrade \"1\"' /etc/apt/apt.conf.d/20auto-upgrades" &>/dev/null
  check "unattended-upgrades configured" $?

  # hostname resolution
  ssh_cmd "$ip" "getent hosts load-balancer" &>/dev/null
  check "hostname resolution works (/etc/hosts)" $?

  # --- Group 1-4 additions below ---

  if [[ "$name" == "app-server" ]]; then
    ssh_cmd "$ip" "command -v docker" &>/dev/null
    check "Docker is installed" $?

    ssh_cmd "$ip" "docker ps --filter name=backend-app --filter status=running -q | grep -q ." &>/dev/null
    check "backend-app container is running" $?

    ssh_cmd "$ip" "curl -sf http://localhost:3000/metrics | grep -q hostname" &>/dev/null
    check "/metrics endpoint returns real data" $?
  fi

  if [[ "$name" == "web-server-1" || "$name" == "web-server-2" ]]; then
    ssh_cmd "$ip" "command -v docker" &>/dev/null
    check "Docker is installed" $?

    ssh_cmd "$ip" "docker ps --filter name=frontend-app --filter status=running -q | grep -q ." &>/dev/null
    check "frontend-app container is running" $?

    ssh_cmd "$ip" "curl -sf http://localhost:80 | grep -q 'Infrastructure Insight'" &>/dev/null
    check "frontend serves the expected page" $?
  fi

  if [[ "$name" == "load-balancer" ]]; then
    ssh_cmd "$ip" "command -v nginx" &>/dev/null
    check "nginx is installed" $?

    ssh_cmd "$ip" "sudo nginx -t" &>/dev/null
    check "nginx config is valid" $?
  fi
done

# --- Load balancing behavior check (run from host, not over SSH) ---
echo ""
echo "=== Load balancer distribution check ==="
responses=$(for i in $(seq 1 6); do curl -s http://192.168.56.10 | grep -oP '(?<=Responding web server: <strong>)[^<]+'; done)
unique_servers=$(echo "$responses" | sort -u | wc -l)
if [ "$unique_servers" -ge 2 ]; then
  check "traffic is distributed across both web servers" 0
else
  check "traffic is distributed across both web servers (only saw: $(echo "$responses" | sort -u | tr '\n' ' '))" 1
fi

# --- No unused ports check ---
echo ""
echo "=== Port exposure check (from host machine) ==="
# app-server:3000 should NOT be reachable from the load-balancer's IP range perspective on host directly - only from web tier
nc -z -w2 192.168.56.13 3000 &>/dev/null
check "app-server:3000 is NOT directly reachable from host (should only be reachable from web tier)" $([ $? -ne 0 ] && echo 0 || echo 1)

echo ""
echo "=================================="
echo " ${PASS} passed, ${FAIL} failed"
echo "=================================="

[ "$FAIL" -eq 0 ]


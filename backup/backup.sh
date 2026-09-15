#!/usr/bin/env bash
# backup.sh - pulls a fresh backup from every other VM over SSH.
# Run by cron as the devops user (see crontab.txt).
set -euo pipefail

SSH_KEY="/home/devops/.ssh/devops_key"
SSH_OPTS="-i ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
BACKUP_ROOT="/var/backups/infrastructure-insight"
DATE=$(date +%Y-%m-%d)
DEST="${BACKUP_ROOT}/${DATE}"

echo "==> Starting backup run: ${DATE}"
mkdir -p "${DEST}"

# Hosts to pull from, and what to pull from each.
# app data lives at /opt/app on app-server and both web servers.
HOSTS=("app-server" "web-server-1" "web-server-2" "load-balancer")

for host in "${HOSTS[@]}"; do
  echo "==> Backing up ${host}..."
  mkdir -p "${DEST}/${host}"

  # /etc - system configuration
  rsync -az -e "ssh ${SSH_OPTS}" \
    "devops@${host}:/etc/" "${DEST}/${host}/etc/" \
    --exclude='shadow' --exclude='gshadow' 2>&1 | tee -a "${DEST}/${host}-etc.log"

  # /home/devops - the devops user's home directory
  rsync -az -e "ssh ${SSH_OPTS}" \
    "devops@${host}:/home/devops/" "${DEST}/${host}/home-devops/" \
    2>&1 | tee -a "${DEST}/${host}-home.log"

  # Application data - only exists on app-server and the web servers
  if [[ "$host" != "load-balancer" ]]; then
    rsync -az -e "ssh ${SSH_OPTS}" \
      "devops@${host}:/opt/app/" "${DEST}/${host}/app-data/" \
      2>&1 | tee -a "${DEST}/${host}-app.log"
  fi
done

# Compress the whole day's backup into one archive
echo "==> Compressing backup..."
tar -czf "${BACKUP_ROOT}/${DATE}.tar.gz" -C "${BACKUP_ROOT}" "${DATE}"
rm -rf "${DEST}"

# Keep the last 4 weekly backups, delete anything older
echo "==> Pruning old backups (keeping last 4)..."
cd "${BACKUP_ROOT}"
ls -1t *.tar.gz 2>/dev/null | tail -n +5 | xargs -r rm --

echo "==> Backup complete: ${BACKUP_ROOT}/${DATE}.tar.gz"


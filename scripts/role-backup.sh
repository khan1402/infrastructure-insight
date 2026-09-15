#!/usr/bin/env bash
# role-backup.sh - provisions the backup VM.
# Pulls weekly backups from every other VM over SSH as the devops user.
set -euo pipefail

echo "==> Provisioning backup VM..."

# Install the devops private key that was copied in by the Vagrantfile's
# file provisioner - this lets this VM authenticate as devops on every
# other VM, since they all already trust the matching public key.
mkdir -p /home/devops/.ssh
cp /tmp/devops_key /home/devops/.ssh/devops_key
chown devops:devops /home/devops/.ssh/devops_key
chmod 600 /home/devops/.ssh/devops_key

# Deploy the backup/restore scripts
mkdir -p /opt/backup
cp /vagrant/backup/backup.sh /opt/backup/backup.sh
cp /vagrant/backup/restore.sh /opt/backup/restore.sh
chmod +x /opt/backup/backup.sh /opt/backup/restore.sh
chown -R devops:devops /opt/backup

# Set up the backup storage location
mkdir -p /var/backups/infrastructure-insight
chown devops:devops /var/backups/infrastructure-insight

# Install the weekly cron job
cp /vagrant/backup/crontab.txt /etc/cron.d/backup
chmod 644 /etc/cron.d/backup

# Log file for cron output
touch /var/log/backup.log
chown devops:devops /var/log/backup.log

echo "==> Backup VM ready. Manual run: sudo -u devops /opt/backup/backup.sh"


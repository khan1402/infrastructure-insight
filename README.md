# Infrastructure Insight

## 1. Project Overview

A 5-VM environment extending [Server Sorcery 101][https://github.com/khan1402/server-sorcery-101.git] with a real, containerized diagnostic application — proving the hardened infrastructure actually works by serving live server metrics through it.

- **load-balancer** — the only VM reachable from outside the lab network. Runs nginx as a reverse proxy, distributing traffic across both web servers using the `least_conn` algorithm with passive health checks.
- **web-server-1 / web-server-2** — identical, stateless frontend containers behind the load balancer. Each calls the backend's `/metrics` endpoint and renders a live diagnostic dashboard.
- **app-server** — hosts the backend container: a small FastAPI service that reads real system data (hostname, OS, CPU, memory) and serves it as JSON.
- **backup** — pulls weekly automated backups (application data, `/home`, `/etc`) from all four other VMs over SSH, and can restore any of the three data types on demand.

The environment keeps Project 1's **least exposure** principle throughout: every VM only accepts traffic it strictly needs, from exactly the hosts that need to send it — extended here to also cover Docker's own port publishing, which by default bypasses UFW's filtering entirely (see `docs/architecture.md`, "Docker/UFW Port Binding").

For the full network diagram, IP/resource table, and security measures, see [`docs/architecture.md`](docs/architecture.md). For the running build logs, see [`docs/notes_project-1.md`](docs/notes_project-1.md) and [`docs/notes_project-2.md`](docs/notes_project-2.md).

## 2. Repository Structure

```
infrastructure-insight/
├── Vagrantfile                  # VM topology: 5 nodes, IPs, resources, provisioning order
├── README.md                    # this file
├── .gitattributes                # forces LF line endings on .sh/.txt (Windows CRLF fix)
├── .gitignore
├── app/
│   ├── backend/
│   │   ├── metrics.py            # system data collection — no web-framework code
│   │   ├── main.py               # FastAPI app, exposes /metrics
│   │   ├── requirements.txt
│   │   ├── Dockerfile
│   │   └── .dockerignore
│   └── frontend/
│       ├── main.py               # FastAPI app, calls backend, renders dashboard
│       ├── requirements.txt
│       ├── Dockerfile
│       ├── .dockerignore
│       ├── templates/index.html  # Jinja2 dashboard template
│       └── static/css/style.css  # responsive dashboard styling
├── backup/
│   ├── backup.sh                 # pulls weekly backups from all 4 VMs over SSH
│   ├── restore.sh                # restores one data type to one host on demand
│   └── crontab.txt               # weekly schedule (Sunday 2 AM)
├── scripts/
│   ├── common.sh                 # baseline hardening, applied to every VM
│   ├── docker-install.sh         # shared Docker install, sourced by app/web roles
│   ├── role-app-server.sh        # builds + runs backend container
│   ├── role-web-server.sh        # builds + runs frontend container
│   ├── role-load-balancer.sh     # nginx reverse proxy + load-balancing config
│   ├── role-backup.sh            # deploys backup/restore scripts + cron job
│   ├── bonus-fail2ban.sh
│   ├── bonus-wireguard.sh
│   └── bonus-netdata.sh
├── validate/
│   └── check-requirements.sh     # 45 automated checks across all 5 VMs
└── docs/
    ├── architecture.md
    ├── notes_project-1.md
    └── notes_project-2.md
```

## 3. Setup & Installation

### Prerequisites
- [VirtualBox](https://www.virtualbox.org/wiki/Downloads)
- [Vagrant](https://developer.hashicorp.com/vagrant/downloads)
- An SSH key pair for the `devops` user:
  ```bash
  ssh-keygen -t ed25519 -f ~/.ssh/devops_key
  ```
  Creates `devops_key` (private) and `devops_key.pub` (public, installed on every VM automatically). Press Enter twice at the passphrase prompts. Neither file is in this repo — generate your own.

### Bring the environment up
```bash
git clone https://gitea.kood.tech/zeeshankhan/infrastructure-insight.git
cd infrastructure-insight
vagrant up
```

This provisions all 5 VMs in order, one at a time (parallel boot competes too hard for host resources on first boot — see `docs/notes_project-1.md`). Per VM:
1. Assigns its static IP, copies the `devops` public key
2. Runs `common.sh` — hardening, UFW, SSH lockdown, `rsync` install
3. Runs the role-specific script — installs Docker (app-server/web-servers), builds and runs the appropriate container, or configures nginx (load-balancer), or deploys backup tooling (backup)

**Save the sudo passwords shown during setup** — each VM gets a random local password for `devops`, printed once. See `docs/architecture.md` for why SSH key auth and `sudo` password are separate systems.

### Accessing the environment
```bash
ssh -i ~/.ssh/devops_key devops@192.168.56.10   # load-balancer
ssh -i ~/.ssh/devops_key devops@192.168.56.11   # web-server-1
ssh -i ~/.ssh/devops_key devops@192.168.56.12   # web-server-2
ssh -i ~/.ssh/devops_key devops@192.168.56.13   # app-server
ssh -i ~/.ssh/devops_key devops@192.168.56.14   # backup
```

The application, through the load balancer, from the host browser: **`http://localhost:8080`**

## 4. Usage Guide

**View the diagnostic dashboard** — open `http://localhost:8080` in a browser. Refresh to see the "Responding server" value alternate between `web-server-1` and `web-server-2`, proving the load balancer is distributing traffic live.

**Query the backend directly:**
```bash
curl http://192.168.56.13:3000/metrics
```

**Run a manual backup:**
```bash
ssh -i ~/.ssh/devops_key devops@192.168.56.14 "/opt/backup/backup.sh"
```

**Restore data** (three types: `app-data`, `etc`, `home-devops`):
```bash
ssh -i ~/.ssh/devops_key devops@192.168.56.14 \
  "/opt/backup/restore.sh <backup-date> <host> <data-type>"
# example:
ssh -i ~/.ssh/devops_key devops@192.168.56.14 \
  "/opt/backup/restore.sh 2026-09-18 web-server-1 app-data"
```
`etc` restores land in `/tmp/restored-etc/` for manual review rather than overwriting live system config directly — restoring straight into a running VM's `/etc` risks breaking SSH/sudo mid-restore.

## 5. Validating the Setup

```bash
bash validate/check-requirements.sh
```
Run from **Git Bash** (not WSL/PowerShell — different SSH key locations). 45 automated checks: user/SSH/sudo setup, UFW rules, umask, auto-updates, Docker installation, container status, `/metrics` and frontend responses (via each VM's own private IP, not `localhost` — see architecture doc), nginx status, load-balancing distribution, and the Docker/UFW port-exposure security check.

Manual checks matching the review rubric — see `docs/notes_project-2.md` for full command examples of `docker ps`, `docker logs`, `ufw status verbose`, `ping`/`telnet`/`traceroute` between VM pairs, `crontab -l` / `cat /etc/cron.d/backup`, and `curl -I`/`curl -v` header inspection.

## 6. Load Balancing Algorithm

`least_conn` (least connections), not nginx's default round-robin — chosen because the frontend must call the backend before responding, adding variable per-request latency; round-robin would keep sending new requests to a server that's still mid-request, while `least_conn` routes to whichever server currently has the fewest active connections. Paired with passive health checks (`max_fails=3 fail_timeout=10s`) — no extra monitoring tooling needed. Full config: `/etc/nginx/sites-available/load-balancer` on the load-balancer VM.

## 7. Bonus / Extra Functionality Implemented

Beyond the core requirements:
- **Docker/UFW port-binding security fix** — Docker's default port publishing (`0.0.0.0`) bypasses UFW's subnet filtering entirely for container ports. Fixed by binding each container to its VM's specific private IP instead (see `docs/architecture.md`).
- **Passive load-balancer health checking** — automatic failover if a web server starts failing, no extra tooling.
- **Full automated validation suite** — 45 checks across all 5 VMs in one command.
- **Complete restore tooling**, not just backup — all three data types, with a safety-conscious design for `/etc`.
- **Responsive, animated UI** — card-based dashboard, progress bars, dark theme, fade-in animation, mobile-responsive grid.
- **`.gitattributes` line-ending enforcement** — prevents Windows CRLF from silently breaking shell scripts.

Project 1's original bonus categories (Fail2Ban, WireGuard, Netdata) remain available via `ENABLE_BONUS=true vagrant up` — see the original `server-sorcery-101` README for details, carried forward unchanged in this repo's `scripts/bonus-*.sh`.

## 8. Challenges & Lessons Learned

See [`docs/notes_project-1.md`](docs/notes_project-1.md) and [`docs/notes_project-2.md`](docs/notes_project-2.md) for the full build logs. Headline items:

- **`docker-install.sh` sourced, not executed — `exit 0` killed the whole caller.** Since it's sourced by the role scripts rather than run as a subprocess, an early `exit 0` (idempotency check) terminated the *entire* calling script on any re-provision, not just itself. Fixed with `return 0`.
- **Docker bypasses UFW for published container ports.** Binding containers to `0.0.0.0` (the default) means Docker's own iptables rules accept traffic on any interface, regardless of UFW's subnet restrictions — a real, non-obvious security gap. Fixed by binding to each VM's specific private IP (`-p 192.168.56.13:3000:3000`) instead.
- **`/opt/app` unreadable by the backup process.** Backend/frontend code was copied as root with no explicit permissions for the non-root `devops` user that runs backups — `rsync` failed with `Permission denied` pulling `/opt/app`. Fixed with `chmod -R o+rX /opt/app` in both role scripts.
- **Restore failed with `chgrp`/`chmod` "Operation not permitted."** `rsync -a` preserves the original owner/group/permissions (often root) from the backup; restoring as non-root `devops` can't re-apply root ownership. Fixed with `--no-owner --no-group --no-perms` on all three restore paths.
- **Uvicorn startup race condition.** Containers reported "running" before the app inside had actually finished starting, causing early health checks to fail with connection resets. Fixed with a short `sleep 3` after `docker run`.
- **CRLF line endings silently broke shell scripts.** Windows/Git CRLF conversion caused `bash: $'\r': command not found` errors invisible to the eye in an editor. Fixed per-file with `sed -i 's/\r$//'`, then prevented repo-wide with `.gitattributes` (`*.sh` and `*.txt` forced to `eol=lf`).
- **VirtualBox host-only networking degraded after heavy VM churn.** Repeated destroy/rebuild/suspend/resume cycles in one session led to unreliable `vagrant ssh`/`vagrant provision` ("guest communication" errors) and eventual boot timeouts — not caused by any script bug. Resolved with a full host restart, then rebuilding one VM at a time rather than in parallel.
- **`vagrant reload` far less reliable than `destroy` + `up`** for VMs after heavy same-session churn — full rebuild was the consistently working fix throughout testing.
- **`crontab -l` shows nothing despite a working schedule** — the job lives in `/etc/cron.d/backup` (system-wide, provisioning-friendly) rather than a personal crontab (requires interactive `crontab -e`), which is the correct approach for a script-installed job but easy to misread as "not configured" if you don't know to check both.



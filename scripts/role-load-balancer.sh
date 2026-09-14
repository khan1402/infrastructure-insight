#!/usr/bin/env bash
# role-load-balancer.sh - nginx reverse proxy distributing traffic across the
# two web servers. This is the only VM in the whole environment that accepts
# connections from outside the lab subnet.
set -euo pipefail

echo "==> Installing nginx"
apt-get install -y nginx >/dev/null

cat <<'EOF' > /etc/nginx/sites-available/load-balancer
upstream backend_web_servers {
    # Algorithm: least_conn - routes each new request to whichever backend
    # currently has the fewest active connections, rather than blindly
    # alternating (plain round-robin). Better suited here since our backend
    # calls add variable latency per request - round-robin would send a new
    # request to a server that's still mid-request from before.
    least_conn;

    # max_fails=3 fail_timeout=10s: if a server fails 3 requests within
    # 10 seconds, nginx temporarily stops sending it traffic and retries
    # after the timeout - a passive health check with no extra tooling.
    server 192.168.56.11 max_fails=3 fail_timeout=10s;
    server 192.168.56.12 max_fails=3 fail_timeout=10s;
}

server {
    listen 80 default_server;
    server_name load-balancer;

    location / {
        proxy_pass http://backend_web_servers;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/load-balancer /etc/nginx/sites-enabled/load-balancer
nginx -t
systemctl restart nginx
systemctl enable nginx

echo "==> Opening HTTP to the outside world (this is the ONLY VM that does this)"
ufw allow 80/tcp

echo "==> role-load-balancer.sh complete"


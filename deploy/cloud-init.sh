#!/usr/bin/env bash
#
# First-boot setup for the battlebox.games droplet. Handed to DigitalOcean
# as user-data when the droplet is created, so it runs once, as root, on a
# clean Ubuntu 24.04.
#
# It sets up the box and NOTHING about the game: no image, no Caddyfile, no
# compose file. Those arrive from CI on every deploy (see the workflow),
# which means the running configuration is always the committed one and
# there is no second copy of it here to drift out of date.
#
# Re-running it by hand is safe.

set -euxo pipefail

DEPLOY_USER=deploy
APP_DIR=/srv/battlebox

# ------------------------------------------------------------------
# Docker
# ------------------------------------------------------------------

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg ufw unattended-upgrades

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# shellcheck source=/dev/null
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y --no-install-recommends \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

# ------------------------------------------------------------------
# The deploy user
# ------------------------------------------------------------------
#
# CI logs in as this, not as root. It is in the docker group, which is
# root-equivalent on this box in practice — but it keeps the ssh key CI
# holds out of root's authorized_keys, so a leaked deploy key is one
# revocation rather than a rebuild.

id -u "$DEPLOY_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$DEPLOY_USER"
usermod -aG docker "$DEPLOY_USER"

install -d -o "$DEPLOY_USER" -g "$DEPLOY_USER" -m 0700 "/home/$DEPLOY_USER/.ssh"
install -d -o "$DEPLOY_USER" -g "$DEPLOY_USER" -m 0755 "$APP_DIR"

# DigitalOcean writes the keys registered with the droplet into root's
# authorized_keys. Give the deploy user the same set: the CI key is one of
# them, and it is what CI needs to log in.
if [ -f /root/.ssh/authorized_keys ]; then
  install -o "$DEPLOY_USER" -g "$DEPLOY_USER" -m 0600 \
    /root/.ssh/authorized_keys "/home/$DEPLOY_USER/.ssh/authorized_keys"
fi

# ------------------------------------------------------------------
# Firewall
# ------------------------------------------------------------------
#
# 80 is not optional even though the site is https-only: Caddy renews its
# certificate over HTTP-01 on that port, and Cloudflare proxies it through.
# Close it and the certificate expires 60 days later, quietly, on a day
# nobody is deploying.

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# ------------------------------------------------------------------
# Keep it patched
# ------------------------------------------------------------------

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
systemctl enable --now unattended-upgrades

# Docker keeps every image it has ever pulled, and each of ours carries a
# 60 MB browser build plus four native clients. deploy.sh prunes on every
# release, but a box that has not shipped in a while should tidy anyway.
cat > /etc/cron.weekly/docker-prune <<'EOF'
#!/bin/sh
docker image prune -af --filter "until=336h" >/dev/null 2>&1 || true
EOF
chmod +x /etc/cron.weekly/docker-prune

echo "battlebox droplet ready — waiting for a deploy to populate $APP_DIR"

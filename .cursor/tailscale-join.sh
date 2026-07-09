#!/usr/bin/env bash
# Join Adam's Tailscale network from a Cursor cloud agent VM (userspace mode).
set -euo pipefail

if [ -z "${TAILSCALE_AUTHKEY:-}" ] || [ -z "${TAILSCALE_SSH_KEY:-}" ]; then
  echo "TAILSCALE_SECRETS_MISSING"
  exit 0
fi

if ! command -v tailscaled >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

mkdir -p /tmp/ts-state "$HOME/.ssh"
printf "%s\n" "$TAILSCALE_SSH_KEY" > "$HOME/.ssh/id_ed25519"
chmod 600 "$HOME/.ssh/id_ed25519"

cat > "$HOME/.ssh/config" <<'SSHCFG'
Host studio
  HostName 100.102.153.54
  User blairstudio
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new

Host mbp
  HostName 100.111.154.126
  User adamblair
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new

Host mbp2
  HostName 100.88.144.50
  User adamblair
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
SSHCFG
chmod 600 "$HOME/.ssh/config"

pkill -f "tailscaled.*userspace" 2>/dev/null || true
tailscaled --tun=userspace-networking \
  --socks5-server=localhost:1055 \
  --outbound-http-proxy-listen=localhost:1054 \
  --state=/tmp/ts-state/tailscaled.state \
  --statedir=/tmp/ts-state \
  >/tmp/tailscaled.log 2>&1 &
sleep 2

HOST="cursor-cloud-$(hostname | tr -cd a-zA-Z0-9 | cut -c1-10)"
tailscale up --authkey="$TAILSCALE_AUTHKEY" --hostname="$HOST" --accept-routes

export ALL_PROXY=socks5h://localhost:1055/
export HTTP_PROXY=http://localhost:1054/
export HTTPS_PROXY=http://localhost:1054/

echo "TAILSCALE_JOINED as $HOST"
tailscale status | head -15


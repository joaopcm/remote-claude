#!/usr/bin/env bash
set -euo pipefail
RC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

read -rp "VPS Tailscale MagicDNS name (e.g. myvps.tailXXXX.ts.net): " VPS_DNS
read -rp "VPS username: " VPS_USER

command -v brew >/dev/null 2>&1 || { echo "install homebrew first"; exit 1; }
brew list mosh >/dev/null 2>&1 || brew install mosh
command -v tailscale >/dev/null 2>&1 || brew install --cask tailscale-app

mkdir -p "$HOME/.config/remote-claude" "$HOME/.local/bin" "$HOME/.ssh"
cat > "$HOME/.config/remote-claude/config" <<EOF
VPS_HOST=vps
EOF
ln -sf "$RC_ROOT/mac/bin/rc" "$HOME/.local/bin/rc"

if ! grep -qE '^Host vps$' "$HOME/.ssh/config" 2>/dev/null; then
  cat >> "$HOME/.ssh/config" <<EOF

Host vps
  HostName $VPS_DNS
  User $VPS_USER
EOF
fi

cat <<'EOF'
done. next:
  1. open Tailscale.app, sign in to the same tailnet
  2. ssh vps          # should just work (Tailscale SSH)
  3. rc ls            # talk to the VPS
EOF

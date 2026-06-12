#!/usr/bin/env bash
set -euo pipefail

RC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log() { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

log "apt packages"
sudo apt-get update -y
sudo apt-get install -y git tmux mosh fish fzf jq curl ca-certificates locales

log "locales (mosh needs UTF-8)"
sudo sed -i -E 's/^# *(en_US.UTF-8|pt_BR.UTF-8)/\1/' /etc/locale.gen
sudo locale-gen

if ! have tailscale; then
  log "tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
fi

if ! have gh; then
  log "github cli"
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -y && sudo apt-get install -y gh
fi

if ! have doppler; then
  log "doppler"
  curl -Ls --tlsv1.2 --proto "=https" --retry 3 https://cli.doppler.com/install.sh | sudo sh
fi

if [ ! -d "$HOME/.volta" ]; then
  log "volta"
  curl -fsSL https://get.volta.sh | bash -s -- --skip-setup
fi
export VOLTA_HOME="$HOME/.volta" VOLTA_FEATURE_PNPM=1
export PATH="$VOLTA_HOME/bin:$PATH"
have node || volta install node
have pnpm || volta install pnpm

if ! have claude && [ ! -x "$HOME/.local/bin/claude" ]; then
  log "claude code"
  curl -fsSL https://claude.ai/install.sh | bash
fi

log "dirs, links, shell config"
mkdir -p "$HOME/repos" "$HOME/work" "$HOME/.local/bin" "$HOME/.config/fish/conf.d"
ln -sf "$RC_ROOT/vps/tmux.conf" "$HOME/.tmux.conf"
ln -sf "$RC_ROOT/bin/rc" "$HOME/.local/bin/rc"
cat > "$HOME/.config/fish/conf.d/remote-claude.fish" <<EOF
set -gx VOLTA_HOME \$HOME/.volta
set -gx VOLTA_FEATURE_PNPM 1
fish_add_path \$VOLTA_HOME/bin \$HOME/.local/bin $RC_ROOT/bin
EOF

FISH_BIN="$(command -v fish)"
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$FISH_BIN" ]; then
  log "default shell -> fish"
  sudo chsh -s "$FISH_BIN" "$USER"
fi

log "done. one-time auth steps:"
cat <<'EOF'
  1. sudo tailscale up --ssh        # join tailnet, enable Tailscale SSH
  2. gh auth login                  # git push/pull credentials
  3. claude                         # then /login
  4. doppler login
EOF

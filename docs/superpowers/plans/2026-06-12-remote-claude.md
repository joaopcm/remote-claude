# remote-claude Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A config repo that provisions a Linux VPS for remote Claude Code work from macOS — multi-session via tmux, git worktrees, per-repo setup hooks, Cursor remote IDE.

**Architecture:** Tailscale (private net, Tailscale SSH) + mosh + tmux on Ubuntu VPS. One bash CLI `rc` on the VPS manages bare clones (`~/repos/<repo>.git`) + worktrees (`~/work/<repo>/<branch>`) + tmux sessions running `claude`. Per-repo setup hooks live in this repo (`setup.d/<repo>.sh`) — never in the project repos. A thin mac companion `rc` proxies commands over SSH/mosh and opens Cursor via `vscode-remote://ssh-remote+vps<path>`.

**Tech Stack:** bash, tmux, mosh, Tailscale, fish (interactive shell), Volta (node+pnpm, `VOLTA_FEATURE_PNPM=1`), gh, Doppler CLI, fzf, bats-core (tests), shellcheck.

**Decisions made during brainstorming (user-approved):**
- Ubuntu/Debian VPS (already provisioned) · Tailscale · tmux · Cursor Remote-SSH · bare-repo+worktrees layout · hooks in this repo only · idempotent bootstrap script · `gh auth` no commit signing · mosh yes · fish on VPS · Volta (NOT mise)
- Commits: extremely concise messages, NO Claude credits / Co-Authored-By (user rule).

---

## File Structure

```
remote-claude/
├── README.md                      # quickstart both sides + one-time auth
├── bin/rc                         # VPS CLI: clone/new/attach/ls/path/rm
├── vps/
│   ├── bootstrap.sh               # idempotent provisioner
│   └── tmux.conf
├── mac/
│   ├── setup.sh                   # mac-side installer (brew, ssh config, symlink)
│   └── bin/rc                     # mac companion (ssh/mosh proxy + Cursor)
├── setup.d/
│   └── example.sh                 # documented hook template
├── tests/rc.bats                  # tests for rc pure helpers
└── docs/superpowers/
    ├── specs/2026-06-12-remote-claude-design.md
    └── plans/2026-06-12-remote-claude.md   # copy of this plan
```

---

### Task 1: Repo init + spec doc

**Files:**
- Create: `README.md` (skeleton), `docs/superpowers/specs/2026-06-12-remote-claude-design.md`, `docs/superpowers/plans/2026-06-12-remote-claude.md`, `.gitignore`

- [ ] **Step 1: Init repo**

```bash
cd /Users/jopcmelo/Developer/personal/remote-claude
git init -b main
printf 'codedb.snapshot\n' > .gitignore
```

- [ ] **Step 2: Write spec doc** at `docs/superpowers/specs/2026-06-12-remote-claude-design.md` — condense the Architecture + Decisions sections above plus the workflow narrative: `rc clone` once per repo → `rc new <repo> <branch>` per task (worktree + hook + tmux + claude) → attach from mac via mosh → `rc ide` opens Cursor remote → `rc rm` when merged.

- [ ] **Step 3: Copy this plan** into `docs/superpowers/plans/2026-06-12-remote-claude.md` (copy from `~/.claude/plans/this-is-a-brand-new-glimmering-nova.md`).

- [ ] **Step 4: README skeleton** — title, one-paragraph description, "WIP" sections: VPS setup, Mac setup, Daily workflow, Per-repo hooks.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "init: spec + plan"
```

---

### Task 2: `rc` helpers (TDD)

**Files:**
- Create: `bin/rc` (helpers only), `tests/rc.bats`

- [ ] **Step 1: Install test deps (dev machine)**

```bash
brew list bats-core >/dev/null 2>&1 || brew install bats-core
brew list shellcheck >/dev/null 2>&1 || brew install shellcheck
```

- [ ] **Step 2: Write failing tests** `tests/rc.bats`:

```bash
setup() { source "$BATS_TEST_DIRNAME/../bin/rc"; }

@test "session_name replaces dots and colons" {
  run session_name "my.repo" "feat:thing"
  [ "$output" = "my_repo/feat_thing" ]
}

@test "session_name passes through clean names" {
  run session_name "resend" "fix-bounce"
  [ "$output" = "resend/fix-bounce" ]
}

@test "repo_git_dir builds bare path" {
  REPOS_DIR=/tmp/r run repo_git_dir "dashboard"
  [ "$output" = "/tmp/r/dashboard.git" ]
}
```

- [ ] **Step 3: Run to verify fail** — `bats tests/rc.bats` → FAIL (no such file `bin/rc`).

- [ ] **Step 4: Implement helpers** — create `bin/rc` (chmod +x):

```bash
#!/usr/bin/env bash
set -euo pipefail

export VOLTA_HOME="${VOLTA_HOME:-$HOME/.volta}"
export VOLTA_FEATURE_PNPM=1
export PATH="$VOLTA_HOME/bin:$HOME/.local/bin:$PATH"

RC_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
REPOS_DIR="${REPOS_DIR:-$HOME/repos}"
WORK_DIR="${WORK_DIR:-$HOME/work}"

die() { printf 'rc: %s\n' "$*" >&2; exit 1; }

session_name() { printf '%s/%s' "$1" "$2" | tr '.:' '__'; }

repo_git_dir() { printf '%s/%s.git' "$REPOS_DIR" "$1"; }

default_branch() {
  git -C "$1" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's|^origin/||' || echo main
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
```

(`main` arrives in Task 3 — sourcing in tests never hits the guard.)

- [ ] **Step 5: Run to verify pass** — `bats tests/rc.bats` → 3 passing.

- [ ] **Step 6: Commit** — `git add -A && git commit -m "rc: helpers + tests"`

---

### Task 3: `rc` subcommands

**Files:**
- Modify: `bin/rc` (append below `default_branch`, above the source guard)

- [ ] **Step 1: Implement subcommands** — insert into `bin/rc`:

```bash
cmd_clone() {
  local slug="${1:?usage: rc clone <owner/repo>}"
  local repo="${slug##*/}"
  local dir; dir="$(repo_git_dir "$repo")"
  [ -d "$dir" ] && die "$dir already exists"
  gh repo clone "$slug" "$dir" -- --bare
  git -C "$dir" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  git -C "$dir" fetch origin --prune
  git -C "$dir" remote set-head origin --auto
  echo "cloned $slug -> $dir"
}

run_setup() {
  local repo="$1" branch="$2" wt="$3"
  local hook="$RC_ROOT/setup.d/$repo.sh"
  [ -f "$hook" ] || { echo "rc: no hook setup.d/$repo.sh, skipping"; return 0; }
  echo "rc: running setup.d/$repo.sh"
  (cd "$wt" && REPO="$repo" BRANCH="$branch" WORKTREE="$wt" bash "$hook") \
    || die "setup hook failed"
}

attach() {
  local session="$1"
  if [ -n "${TMUX:-}" ]; then tmux switch-client -t "=$session"
  else tmux attach -t "=$session"; fi
}

cmd_new() {
  local repo="${1:?usage: rc new <repo> <branch> [base]}"
  local branch="${2:?usage: rc new <repo> <branch> [base]}"
  local git_dir; git_dir="$(repo_git_dir "$repo")"
  [ -d "$git_dir" ] || die "no repo '$repo' — run: rc clone <owner>/$repo"
  local wt="$WORK_DIR/$repo/$branch"
  if [ ! -d "$wt" ]; then
    git -C "$git_dir" fetch origin --prune
    local base="${3:-origin/$(default_branch "$git_dir")}"
    mkdir -p "$(dirname "$wt")"
    if git -C "$git_dir" show-ref --verify --quiet "refs/heads/$branch"; then
      git -C "$git_dir" worktree add "$wt" "$branch"
    elif git -C "$git_dir" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      git -C "$git_dir" worktree add --track -b "$branch" "$wt" "origin/$branch"
    else
      git -C "$git_dir" worktree add -b "$branch" "$wt" "$base"
    fi
    run_setup "$repo" "$branch" "$wt"
  fi
  local session; session="$(session_name "$repo" "$branch")"
  if ! tmux has-session -t "=$session" 2>/dev/null; then
    tmux new-session -d -s "$session" -c "$wt"
    tmux send-keys -t "=$session" 'claude' Enter
  fi
  attach "$session"
}

cmd_attach() {
  local session="${1:-}"
  if [ -z "$session" ]; then
    session="$(tmux list-sessions -F '#S' 2>/dev/null | fzf --prompt='session> ')" \
      || die "no session selected"
  fi
  attach "$session"
}

cmd_ls() {
  echo "── sessions"
  tmux list-sessions -F '  #S' 2>/dev/null || echo "  (none)"
  echo "── worktrees"
  local gd
  for gd in "$REPOS_DIR"/*.git; do
    [ -d "$gd" ] || continue
    git -C "$gd" worktree list | grep -v ' (bare)' | sed 's/^/  /' || true
  done
}

cmd_path() {
  local repo="${1:?usage: rc path <repo> <branch>}" branch="${2:?usage: rc path <repo> <branch>}"
  echo "$WORK_DIR/$repo/$branch"
}

cmd_rm() {
  local repo="${1:?usage: rc rm <repo> <branch>}" branch="${2:?usage: rc rm <repo> <branch>}"
  local wt="$WORK_DIR/$repo/$branch"
  local git_dir; git_dir="$(repo_git_dir "$repo")"
  tmux kill-session -t "=$(session_name "$repo" "$branch")" 2>/dev/null || true
  if [ -d "$wt" ]; then
    git -C "$git_dir" worktree remove "$wt" \
      || die "worktree dirty — commit/stash, or: git -C $git_dir worktree remove --force $wt"
  fi
  local yn
  read -rp "delete local branch '$branch'? [y/N] " yn
  [[ "$yn" == [yY] ]] && git -C "$git_dir" branch -D "$branch"
  echo "removed $repo/$branch"
}

usage() {
  cat <<'EOF'
rc — remote claude code sessions
  rc clone <owner/repo>           bare-clone into ~/repos
  rc new <repo> <branch> [base]   worktree + setup hook + tmux session running claude
  rc attach [session]             attach (fzf picker if omitted)
  rc ls                           list sessions + worktrees
  rc path <repo> <branch>         print worktree path
  rc rm <repo> <branch>           kill session + remove worktree
EOF
}

main() {
  local cmd="${1:-attach}"
  shift || true
  case "$cmd" in
    clone)  cmd_clone "$@" ;;
    new)    cmd_new "$@" ;;
    attach) cmd_attach "$@" ;;
    ls)     cmd_ls "$@" ;;
    path)   cmd_path "$@" ;;
    rm)     cmd_rm "$@" ;;
    -h|--help|help) usage ;;
    *) usage; die "unknown command: $cmd" ;;
  esac
}
```

- [ ] **Step 2: Verify** — `bats tests/rc.bats` (still 3 pass) and `shellcheck bin/rc` (clean; `#S` tmux formats are inside single quotes so no SC warnings expected).

- [ ] **Step 3: Commit** — `git add bin/rc && git commit -m "rc: subcommands"`

---

### Task 4: VPS bootstrap + tmux.conf

**Files:**
- Create: `vps/bootstrap.sh` (chmod +x), `vps/tmux.conf`

- [ ] **Step 1: Write `vps/tmux.conf`**

```
set -g mouse on
set -g history-limit 100000
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:Tc"
set -g base-index 1
set -g renumber-windows on
set -s escape-time 0
set -g status-style bg=colour235,fg=colour245
set -g status-left "#[bold] #S "
set -g status-left-length 40
```

- [ ] **Step 2: Write `vps/bootstrap.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

RC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log() { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

log "apt packages"
sudo apt-get update -y
sudo apt-get install -y git tmux mosh fish fzf jq curl ca-certificates

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
```

- [ ] **Step 3: Verify** — `shellcheck vps/bootstrap.sh` → clean (add `# shellcheck disable=` only if a finding is a false positive, with the reason).

- [ ] **Step 4: Commit** — `git add vps && git commit -m "vps: bootstrap + tmux.conf"`

---

### Task 5: Setup hook template

**Files:**
- Create: `setup.d/example.sh`, `setup.d/.gitkeep` not needed (example.sh keeps the dir)

- [ ] **Step 1: Write `setup.d/example.sh`**

```bash
#!/usr/bin/env bash
# Worktree hook template. Copy to setup.d/<repo-name>.sh — runs after
# `rc new` creates a worktree, with cwd set to the worktree. Env:
#   $REPO      repo name              (dashboard)
#   $BRANCH    branch name            (feat-thing)
#   $WORKTREE  absolute worktree path (/home/you/work/dashboard/feat-thing)
set -euo pipefail

pnpm install

# doppler setup --project "$REPO" --config dev --no-interactive

# cp "$HOME/secrets/$REPO.env" .env.local
```

- [ ] **Step 2: Commit** — `git add setup.d && git commit -m "setup.d: hook template"`

---

### Task 6: Mac companion

**Files:**
- Create: `mac/bin/rc` (chmod +x), `mac/setup.sh` (chmod +x)

- [ ] **Step 1: Write `mac/bin/rc`**

```bash
#!/usr/bin/env bash
set -euo pipefail

CONFIG="${RC_CONFIG:-$HOME/.config/remote-claude/config}"
# shellcheck source=/dev/null
[ -f "$CONFIG" ] && source "$CONFIG"
VPS_HOST="${VPS_HOST:-vps}"
VPS_RC="${VPS_RC:-.local/bin/rc}"   # relative to remote \$HOME

interactive() {
  if command -v mosh >/dev/null 2>&1 && [ "${RC_NO_MOSH:-0}" != 1 ]; then
    exec mosh "$VPS_HOST" -- "$VPS_RC" "$@"
  fi
  exec ssh -t "$VPS_HOST" "$VPS_RC" "$@"
}

cmd_ide() {
  local repo="${1:?usage: rc ide <repo> <branch>}" branch="${2:?usage: rc ide <repo> <branch>}"
  local path; path="$(ssh "$VPS_HOST" "$VPS_RC" path "$repo" "$branch")"
  cursor --folder-uri "vscode-remote://ssh-remote+${VPS_HOST}${path}"
}

cmd="${1:-attach}"
case "$cmd" in
  ide)        shift; cmd_ide "$@" ;;
  ssh)        exec ssh -t "$VPS_HOST" ;;
  new|attach) interactive "$@" ;;
  *)          exec ssh -t "$VPS_HOST" "$VPS_RC" "$@" ;;
esac
```

(Note: when `$1` is empty, `interactive "$@"` sends zero args and VPS `rc` defaults to `attach` — fzf picker over mosh.)

- [ ] **Step 2: Write `mac/setup.sh`**

```bash
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
```

- [ ] **Step 3: Verify** — `shellcheck mac/bin/rc mac/setup.sh` → clean. Then dry-run locally: `RC_CONFIG=/dev/null bash mac/bin/rc help` → prints VPS usage via ssh (will fail without VPS — expected; just confirm it attempts `ssh vps`, e.g. error mentions `vps`).

- [ ] **Step 4: Commit** — `git add mac && git commit -m "mac: companion + setup"`

---

### Task 7: README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Write full README** covering:
  - What this is (one paragraph)
  - **VPS setup:** `git clone <this repo> ~/remote-claude && ~/remote-claude/vps/bootstrap.sh`, then the 4 one-time auth steps (tailscale up --ssh, gh auth login, claude /login, doppler login)
  - **Mac setup:** clone, run `mac/setup.sh`, sign into Tailscale.app
  - **Daily workflow** (exact commands):
    ```
    rc clone resend/dashboard        # once per repo
    rc new dashboard feat-bounce     # worktree + hook + tmux + claude, attaches
    rc ide dashboard feat-bounce     # Cursor on the remote worktree
    rc ls / rc attach / rc rm dashboard feat-bounce
    ```
  - **Per-repo hooks:** copy `setup.d/example.sh` → `setup.d/<repo>.sh`, document env vars
  - **Notes:** detach tmux `C-b d`; sessions survive disconnects; mosh handles roaming; Cursor needs Remote-SSH to host `vps`

- [ ] **Step 2: Commit** — `git add README.md && git commit -m "docs: readme"`

---

### Task 8: Publish to GitHub

- [ ] **Step 1:** `gh repo create jopcmelo/remote-claude --private --source . --push`
- [ ] **Step 2:** Verify — `gh repo view jopcmelo/remote-claude --json url` returns the URL.

---

### Task 9: Live verification (manual, with user — needs VPS access)

This task requires the user's VPS; run interactively, not via subagent.

- [ ] On VPS: `git clone https://github.com/jopcmelo/remote-claude ~/remote-claude && bash ~/remote-claude/vps/bootstrap.sh`, then re-run bootstrap once more → second run is a no-op (idempotency check).
- [ ] Complete the 4 auth steps on the VPS.
- [ ] On mac: run `mac/setup.sh`, sign into Tailscale, `ssh vps` works.
- [ ] `rc clone <owner/some-real-repo>`; add `setup.d/<repo>.sh` with `pnpm install`; `rc new <repo> test-rc` → worktree created, hook ran, lands inside tmux with claude running.
- [ ] Detach (`C-b d`), `rc ls` from mac shows session; `rc attach` picker reattaches; kill the terminal mid-session, reattach — session intact.
- [ ] `rc new <repo> second-branch` from inside tmux → switches client; two parallel claude sessions confirmed.
- [ ] `rc ide <repo> test-rc` → Cursor opens the remote worktree over SSH.
- [ ] `rc rm <repo> test-rc` → session gone, worktree removed.
- [ ] Fix anything that breaks; commit fixes (`fix: ...`); push.

---

## Verification (automated, run before Task 8)

```bash
shellcheck bin/rc vps/bootstrap.sh mac/bin/rc mac/setup.sh setup.d/example.sh
bats tests/rc.bats
```
Both clean/green.

---

## Unresolved questions

- GitHub repo: `jopcmelo/remote-claude`, private — ok?
- Claude Code install on VPS: native installer (`claude.ai/install.sh`) ok? (alt: volta/npm global)
- VPS username + MagicDNS name — needed only at Task 9.

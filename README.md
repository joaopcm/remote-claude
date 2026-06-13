# remote-claude

**Run Claude Code on an always-on Linux VPS and drive it from your Mac — multiple agents in parallel, each in its own git worktree, surviving laptop sleep, network drops, and roaming.**

```
mac (rc) ──mosh/ssh──▶ VPS ── tmux session per worktree, each running claude
                        ├── ~/repos/<repo>.git        bare clones
                        └── ~/work/<repo>/<branch>/   worktrees
```

## Why

Claude Code is great at long-running, autonomous work — but running it on a laptop has problems:

- **Close the lid and the agent dies.** Long tasks (big refactors, test-fixing loops, migrations) get killed by sleep, network changes, or a dead battery.
- **Parallel work collides.** Two agents in the same checkout step on each other's files, branches, and dev servers.
- **Your machine becomes the bottleneck.** Installs, builds, and test runs compete with everything else you're doing.

remote-claude moves the agents to a cheap always-on VPS and gives you a tiny CLI (`rc`) to manage them:

- **One tmux session + one git worktree per task.** `rc new dashboard feat-bounce` creates a worktree off the default branch, runs your per-repo setup hook (install deps, fetch secrets, write env files), starts tmux, and launches Claude Code in it. Run as many in parallel as the box can handle — they never touch each other's files.
- **Sessions are durable.** Detach, close your laptop, switch from wifi to LTE — mosh + tmux keep everything alive. Reattach from anywhere on your tailnet.
- **Steer from anywhere.** Sessions launch `claude --remote-control` by default, so you can also check in and steer agents from claude.ai/code or the Claude mobile app.
- **No public attack surface.** Everything rides a private [Tailscale](https://tailscale.com) network with Tailscale SSH — no open SSH port, no key juggling.
- **Edit remotely when you need to.** `rc ide dashboard feat-bounce` opens Cursor directly on the remote worktree over Remote-SSH.

## Use cases

- Kick off a long refactor before lunch, check on it from your phone, attach from your Mac later.
- Run 3–5 agents on different features of the same repo simultaneously, each isolated in its own worktree and branch.
- Keep a beefy build box doing installs/tests/builds while your laptop stays cool.
- Hand a flaky-test hunt or dependency upgrade to an agent and only reattach when it's done.

## How it works

- **Bare clones + worktrees.** Each repo is bare-cloned once into `~/repos/<repo>.git`. Every task gets a worktree at `~/work/<repo>/<branch>` — cheap to create, fully isolated, trivially removed when the branch merges.
- **tmux as the session layer.** Each worktree gets a tmux session named `<repo>/<branch>` running Claude Code. `rc` attaches, lists, and kills them.
- **mosh as the transport.** Interactive commands (`rc new`, `rc attach`) go over mosh, so sessions survive roaming and sleep. Non-interactive ones use plain SSH.
- **Setup hooks.** Repos need different worktree prep (pnpm install, Doppler, env files). Hooks live in this repo's `setup.d/` — never committed to your project repos.

## Requirements

- A Linux VPS (Debian/Ubuntu — bootstrap uses `apt`)
- A Mac with [Homebrew](https://brew.sh)
- A [Tailscale](https://tailscale.com) account (free tier is fine)
- A Claude subscription or API access for Claude Code

## VPS setup (once)

```sh
git clone https://github.com/joaopcm/remote-claude ~/remote-claude
bash ~/remote-claude/vps/bootstrap.sh
```

Idempotent — safe to re-run anytime. Installs: tmux, mosh, fish, fzf, Tailscale, gh, Doppler CLI, Volta (node + pnpm), Claude Code. Then the one-time auth steps:

```sh
sudo tailscale up --ssh    # join tailnet + enable Tailscale SSH (no public SSH needed)
gh auth login              # git push/pull credentials
claude                     # then /login
doppler login              # only if your repos use Doppler secrets
```

## Mac setup (once)

```sh
git clone https://github.com/joaopcm/remote-claude ~/remote-claude
bash ~/remote-claude/mac/setup.sh   # asks for MagicDNS name + VPS user
```

Installs mosh + Tailscale app, writes a `Host vps` SSH config entry, symlinks `rc` into `~/.local/bin`. Sign into Tailscale.app, then `ssh vps` should just work.

## Daily workflow (from the mac)

```sh
rc clone resend/dashboard        # once per repo — bare clone on the VPS
rc new dashboard feat-bounce     # worktree + setup hook + tmux + claude, attaches
rc                               # fzf session picker (same as: rc attach)
rc ls                            # sessions (● attached / ○ detached, last line) + worktrees
rc peek dashboard/feat-bounce    # glance at a session's output without attaching
rc ide dashboard feat-bounce     # open Cursor on the remote worktree
rc rm dashboard feat-bounce      # kill session + remove worktree when merged
rc prune                         # sweep worktrees whose remote branch was deleted
rc new dashboard feat-x origin/staging   # optional base ref
```

Detach with `C-b d`. Sessions survive disconnects, sleep, and network roaming (mosh); reattach from anywhere on the tailnet.

### Command reference

| command | what it does |
|---|---|
| `rc clone <owner/repo>` | bare-clone into `~/repos/<repo>.git` on the VPS |
| `rc new <repo> <branch> [base]` | create worktree (reusing local/remote branch if it exists), run setup hook, start tmux + claude, attach |
| `rc attach [session]` / `rc` | attach to a session (fzf picker if omitted) |
| `rc peek [session]` | print a session's recent output without attaching (fzf picker if omitted) |
| `rc ls` | list tmux sessions (● attached / ○ detached, with each session's last output line) and git worktrees |
| `rc ide <repo> <branch>` | open Cursor on the remote worktree (mac-side) |
| `rc rm <repo> <branch>` | kill session, remove worktree (and empty parent dirs), optionally delete branch |
| `rc prune [-n]` | remove every worktree whose remote branch is gone (deleted/merged on origin); `-n` previews without deleting |
| `rc sync` | mirror local `~/.claude` config to the VPS (mac-side) |
| `rc ssh` | plain interactive shell on the VPS |
| `rc path <repo> <branch>` | print worktree path (used internally by `rc ide`) |

`rc new` is safe to re-run: it reuses an existing worktree and session, so it doubles as "attach, creating if needed".

## Sync Claude config to the VPS

```sh
rc sync
```

Pushes your local `~/.claude` essentials to the VPS: `CLAUDE.md`, `RTK.md`, `rules/`, `skills/`, `hooks/`, `file-suggestion.sh`, `plugins/`, `~/.config/ccstatusline/`, and a Linux-safe `settings.json` (hook entries referencing `/Users/` or `codedb` are stripped, along with mac-only keys). Re-run anytime — it's a one-way mac → VPS mirror (`--delete` inside synced dirs).

## Per-repo hooks

Each repo can need different worktree setup (pnpm install, Doppler config, env files). Hooks live in this repo's `setup.d/` but are **git-ignored** (only `example.sh` is tracked) — they reach the VPS via `rc sync`, not git:

```sh
cp setup.d/example.sh setup.d/dashboard.sh   # name must match repo name
```

`rc new` runs the hook *inside the new tmux session*, as the first command before claude, with cwd set to the worktree and env:

| var | example |
|---|---|
| `$REPO` | `dashboard` |
| `$BRANCH` | `feat-bounce` |
| `$WORKTREE` | `/home/you/work/dashboard/feat-bounce` |

A typical hook:

```sh
#!/usr/bin/env bash
set -euo pipefail

pnpm install
doppler setup --project "$REPO" --config dev --no-interactive
cp "$HOME/secrets/$REPO.env" .env.local
```

Because the hook runs inside the session, its output (and any failure) stays on screen, and a long `pnpm install` survives a disconnect. If the hook fails, claude still launches afterward — you land in the worktree with the error visible rather than getting dropped out of mosh. No hook file means setup is skipped silently.

## Configuration

| where | var | default | meaning |
|---|---|---|---|
| mac (`~/.config/remote-claude/config`) | `VPS_HOST` | `vps` | SSH host alias for the VPS |
| mac | `VPS_RC` | `.local/bin/rc` | path to `rc` on the VPS, relative to remote `$HOME` |
| mac (env) | `RC_NO_MOSH=1` | — | force plain SSH for interactive commands |
| VPS (env) | `REPOS_DIR` | `~/repos` | where bare clones live |
| VPS (env) | `WORK_DIR` | `~/work` | where worktrees live |
| VPS (env) | `RC_CLAUDE_CMD` | `claude --remote-control` | command launched in each new session |

## Notes & troubleshooting

- **Remote control**: `claude --remote-control` lets you steer sessions from claude.ai/code or the mobile app. Requires claude.ai login on the VPS and Claude Code ≥ 2.1.51. Set `RC_CLAUDE_CMD=claude` on the VPS to opt out.
- **Cursor**: `rc ide` opens `vscode-remote://ssh-remote+vps<path>` — needs the Remote-SSH extension and the `Host vps` SSH entry (written by `mac/setup.sh`).
- **mosh garbled output / locale errors**: the bootstrap enables UTF-8 locales; re-run it if mosh complains.
- **Shift+Enter submits instead of adding a newline**: mosh can't carry the modern keyboard protocols (Kitty/CSI-u) that terminals use to signal Shift+Enter, so multi-line entry over mosh only works when your terminal emits a plain line feed for it — which some keyboard layouts (e.g. Brazilian ABNT) break. Use **`Ctrl+J`** or **`\` then Enter** for newlines; both are plain bytes that work over mosh on any layout. To keep Shift+Enter, bind it to send hex `0x0a` in your terminal (iTerm2: Settings → Profiles → Keys → add Shift+Return → "Send Hex Code" `0x0a`).
- **`rc rm` refuses on a dirty worktree**: commit/stash first, or force-remove with the `git worktree remove --force` command it prints.
- **Tidy up merged branches**: `rc prune` removes every worktree whose remote branch was deleted on origin (run `rc prune -n` first to preview). Dirty worktrees are skipped.
- **Not on Tailscale?** Nothing in `rc` is Tailscale-specific — any `Host vps` SSH config entry that reaches the box works. Tailscale just makes it safe and zero-config.

## Repo layout

```
bin/rc          VPS-side CLI (clone, new, attach, peek, ls, path, rm, prune)
mac/bin/rc      mac-side wrapper (ide, sync, ssh; proxies the rest over mosh/ssh)
mac/setup.sh    mac one-time setup
mac/completions/rc.fish  fish tab-completion for the mac CLI
vps/bootstrap.sh  VPS one-time provisioning (idempotent)
vps/tmux.conf   tmux config symlinked to ~/.tmux.conf
vps/completions/rc.fish  fish tab-completion when SSH'd into the VPS
setup.d/        per-repo worktree setup hooks
tests/rc.bats   bats tests for the VPS CLI
```

## Contributing

Issues and PRs welcome. The CLI is plain bash; tests use [bats](https://github.com/bats-core/bats-core):

```sh
bats tests/rc.bats
```

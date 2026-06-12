# remote-claude

Remote Claude Code on a Linux VPS, driven from macOS. Multiple parallel sessions (tmux), git worktrees per task, per-repo setup hooks, Cursor remote IDE — all over a private Tailscale network.

```
mac (rc) ──mosh/ssh──▶ VPS ── tmux session per worktree, each running claude
                        ├── ~/repos/<repo>.git        bare clones
                        └── ~/work/<repo>/<branch>/   worktrees
```

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
doppler login
```

## Mac setup (once)

```sh
git clone https://github.com/joaopcm/remote-claude ~/remote-claude
bash ~/remote-claude/mac/setup.sh   # asks for MagicDNS name + VPS user
```

Installs mosh + Tailscale app, writes `Host vps` SSH config, symlinks `rc` into `~/.local/bin`. Sign into Tailscale.app, then `ssh vps` should just work.

## Daily workflow (from the mac)

```sh
rc clone resend/dashboard        # once per repo — bare clone on the VPS
rc new dashboard feat-bounce     # worktree + setup hook + tmux + claude, attaches
rc                               # fzf session picker (same as: rc attach)
rc ls                            # sessions + worktrees overview
rc ide dashboard feat-bounce     # open Cursor on the remote worktree
rc rm dashboard feat-bounce      # kill session + remove worktree when merged
rc new dashboard feat-x origin/staging   # optional base ref
```

Detach with `C-b d`. Sessions survive disconnects, sleep, and network roaming (mosh); reattach from anywhere on the tailnet. Run as many parallel sessions as you like — one worktree + one claude each.

## Sync Claude config to the VPS

```sh
rc sync
```

Pushes your local `~/.claude` essentials to the VPS: `CLAUDE.md`, `RTK.md`, `rules/`, `skills/`, `hooks/`, `file-suggestion.sh`, `plugins/`, and a Linux-safe `settings.json` (hook entries referencing `/Users/`, `terminal-notifier`, or `codedb` are stripped, along with mac-only keys). Re-run anytime — it's a one-way mac → VPS mirror (`--delete` inside synced dirs).

## Per-repo hooks

Each repo can need different worktree setup (pnpm install, Doppler config, env files). Hooks live **in this repo only** — never committed to the project repos:

```sh
cp setup.d/example.sh setup.d/dashboard.sh   # name must match repo name
```

`rc new` runs the hook after creating the worktree, with cwd set to the worktree and env:

| var | example |
|---|---|
| `$REPO` | `dashboard` |
| `$BRANCH` | `feat-bounce` |
| `$WORKTREE` | `/home/you/work/dashboard/feat-bounce` |

## Notes

- Cursor opens remote folders via `vscode-remote://ssh-remote+vps<path>` — needs the Remote-SSH extension and the `Host vps` entry (written by `mac/setup.sh`).
- `RC_NO_MOSH=1 rc ...` forces plain SSH for interactive commands.
- VPS-side overrides: `REPOS_DIR`, `WORK_DIR`. Mac-side config: `~/.config/remote-claude/config`.

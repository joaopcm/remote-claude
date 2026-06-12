# remote-claude — Design

Provision a Linux VPS for remote Claude Code work from macOS: multiple parallel sessions, git worktrees, per-repo setup hooks, Cursor remote IDE.

## Architecture

- **Network:** Tailscale. VPS joins the tailnet with Tailscale SSH enabled (`tailscale up --ssh`) — no public SSH port, no key management. Mac reaches it as `vps` via SSH config pointing at the MagicDNS name.
- **Terminal:** mosh (roaming, local echo) + tmux (persistence). One tmux session per worktree, each running `claude`.
- **Repos:** bare clones in `~/repos/<repo>.git`, worktrees in `~/work/<repo>/<branch>`.
- **CLI:** `bin/rc` (bash) on the VPS — `clone`, `new`, `attach`, `ls`, `path`, `rm`.
- **Hooks:** `setup.d/<repo>.sh` in this repo (never committed to project repos). Run by `rc new` after worktree creation with `$REPO`, `$BRANCH`, `$WORKTREE`, cwd = worktree. Typical contents: `pnpm install`, `doppler setup`, copy env files.
- **Mac companion:** `mac/bin/rc` proxies commands over SSH (mosh for interactive `new`/`attach`); `rc ide <repo> <branch>` opens Cursor on the remote worktree via `vscode-remote://ssh-remote+vps<path>`.
- **Provisioning:** idempotent `vps/bootstrap.sh` — apt packages (git, tmux, mosh, fish, fzf, jq), Tailscale, gh, Doppler CLI, Volta (node + pnpm via `VOLTA_FEATURE_PNPM=1`), Claude Code, fish as default shell, config symlinks.

## Workflow

```
rc clone resend/dashboard        # once per repo (bare clone)
rc new dashboard feat-bounce     # worktree + hook + tmux + claude, attaches
rc ide dashboard feat-bounce     # Cursor on the remote worktree
rc ls / rc attach                # overview / fzf picker
rc rm dashboard feat-bounce      # when merged
```

## Decisions

- Ubuntu/Debian VPS (already provisioned)
- Tailscale over hardened SSH / Cloudflare Tunnel
- tmux over zellij
- Cursor Remote-SSH over sync/mount
- Bare repos + worktrees over normal clone + siblings
- Hooks in this config repo only
- Idempotent bash bootstrap over Ansible/Nix
- `gh auth` for git credentials, no commit signing (for now)
- mosh yes; fish as VPS interactive shell; Volta (not mise) for node/pnpm

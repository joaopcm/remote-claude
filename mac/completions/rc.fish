# rc completions for the mac wrapper. Repo/session names are fetched from the
# VPS over ssh (best-effort, short timeout) so tab-completion mirrors the box.
set -l rc_cmds clone new attach peek ls path rm ide sync ssh prune

function __rc_vps_host
  set -l cfg "$HOME/.config/remote-claude/config"
  if test -f $cfg
    set -l h (string match -rg '^VPS_HOST=(.*)' < $cfg)
    test -n "$h"; and echo $h[-1]; and return
  end
  echo vps
end

function __rc_ssh
  ssh -o BatchMode=yes -o ConnectTimeout=3 (__rc_vps_host) $argv 2>/dev/null
end

function __rc_repos
  __rc_ssh 'ls ~/repos 2>/dev/null' | string replace -r '\.git$' ''
end

function __rc_sessions
  __rc_ssh 'tmux list-sessions -F "#S" 2>/dev/null'
end

complete -c rc -f

complete -c rc -n "not __fish_seen_subcommand_from $rc_cmds" -a clone  -d 'bare-clone a repo'
complete -c rc -n "not __fish_seen_subcommand_from $rc_cmds" -a new    -d 'worktree + session'
complete -c rc -n "not __fish_seen_subcommand_from $rc_cmds" -a attach -d 'attach to a session'
complete -c rc -n "not __fish_seen_subcommand_from $rc_cmds" -a peek   -d 'peek at a session'
complete -c rc -n "not __fish_seen_subcommand_from $rc_cmds" -a ls     -d 'list sessions + worktrees'
complete -c rc -n "not __fish_seen_subcommand_from $rc_cmds" -a path   -d 'print worktree path'
complete -c rc -n "not __fish_seen_subcommand_from $rc_cmds" -a rm     -d 'remove session + worktree'
complete -c rc -n "not __fish_seen_subcommand_from $rc_cmds" -a ide    -d 'open worktree in Cursor'
complete -c rc -n "not __fish_seen_subcommand_from $rc_cmds" -a sync   -d 'sync hooks + config to VPS'
complete -c rc -n "not __fish_seen_subcommand_from $rc_cmds" -a ssh    -d 'ssh into the VPS'
complete -c rc -n "not __fish_seen_subcommand_from $rc_cmds" -a prune  -d 'prune gone worktrees'

complete -c rc -n "__fish_seen_subcommand_from new path rm ide; and test (count (commandline -opc)) -eq 2" -a '(__rc_repos)'
complete -c rc -n "__fish_seen_subcommand_from attach peek" -a '(__rc_sessions)'

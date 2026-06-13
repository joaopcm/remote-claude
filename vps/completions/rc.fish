# rc completions for use when SSH'd into the VPS. Reads repos/sessions locally.
set -l rc_cmds clone new attach peek ls path rm prune

function __rc_repos
  for d in $HOME/repos/*.git
    test -d $d; and string replace -r '\.git$' '' (basename $d)
  end
end

function __rc_sessions
  tmux list-sessions -F '#S' 2>/dev/null
end

complete -c rc -f

complete -c rc -n "not __fish_seen_subcommand_from $rc_cmds" -a clone  -d 'bare-clone a repo'
complete -c rc -n "not __fish_seen_subcommand_from $rc_cmds" -a new    -d 'worktree + session'
complete -c rc -n "not __fish_seen_subcommand_from $rc_cmds" -a attach -d 'attach to a session'
complete -c rc -n "not __fish_seen_subcommand_from $rc_cmds" -a peek   -d 'peek at a session'
complete -c rc -n "not __fish_seen_subcommand_from $rc_cmds" -a ls     -d 'list sessions + worktrees'
complete -c rc -n "not __fish_seen_subcommand_from $rc_cmds" -a path   -d 'print worktree path'
complete -c rc -n "not __fish_seen_subcommand_from $rc_cmds" -a rm     -d 'remove session + worktree'
complete -c rc -n "not __fish_seen_subcommand_from $rc_cmds" -a prune  -d 'prune gone worktrees'

complete -c rc -n "__fish_seen_subcommand_from new path rm; and test (count (commandline -opc)) -eq 2" -a '(__rc_repos)'
complete -c rc -n "__fish_seen_subcommand_from attach peek" -a '(__rc_sessions)'

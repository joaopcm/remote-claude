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

@test "launch_cmd is just claude when not fresh" {
  run launch_cmd "dashboard" "feat-x" "/w/dashboard/feat-x" 0
  [ "$output" = "claude --remote-control" ]
}

@test "launch_cmd runs the hook before claude on a fresh worktree" {
  RC_ROOT="$(mktemp -d)"; mkdir -p "$RC_ROOT/setup.d"; touch "$RC_ROOT/setup.d/dashboard.sh"
  run launch_cmd "dashboard" "feat/x" "/w/dashboard/feat/x" 1
  [ "$output" = "env REPO=dashboard BRANCH=feat/x WORKTREE=/w/dashboard/feat/x bash $RC_ROOT/setup.d/dashboard.sh; claude --remote-control" ]
}

@test "prune_empty_dirs removes empty parents up to WORK_DIR" {
  WORK_DIR="$(mktemp -d)"; mkdir -p "$WORK_DIR/repo/feat/branch"
  prune_empty_dirs "$WORK_DIR/repo/feat/branch"
  [ ! -d "$WORK_DIR/repo" ]
  [ -d "$WORK_DIR" ]
}

@test "prune_empty_dirs stops at a non-empty dir" {
  WORK_DIR="$(mktemp -d)"; mkdir -p "$WORK_DIR/repo/feat/branch"; touch "$WORK_DIR/repo/keep"
  prune_empty_dirs "$WORK_DIR/repo/feat/branch"
  [ -d "$WORK_DIR/repo" ]
  [ ! -d "$WORK_DIR/repo/feat" ]
}

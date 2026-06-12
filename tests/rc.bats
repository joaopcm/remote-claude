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

#!/usr/bin/env bash
# Worktree hook template. Copy to setup.d/<repo-name>.sh — runs after
# `rc new` creates a worktree, with cwd set to the worktree. Env:
#   $REPO      repo name              (dashboard)
#   $BRANCH    branch name            (feat-thing)
#   $WORKTREE  absolute worktree path (/home/you/work/dashboard/feat-thing)
set -euo pipefail

pnpm install

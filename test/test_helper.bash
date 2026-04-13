#!/usr/bin/env bash
# Shared setup for all bats test files.
#
# Key isolation strategy:
#   - Override HOME to a temp dir per test.
#   - proj.zsh hardcodes PROJ_DIR="$HOME/.proj", so HOME override redirects
#     all state to the temp dir without touching real ~/.proj.
#   - PATH prepends test/fixtures/bin so mock claude/fzf/etc. win over real.
#   - Each test runs in its own HOME; teardown removes it.
#
# Bridge pattern:
#   bats runs in bash. proj.zsh is zsh. We expose a bash function `proj`
#   that shells out to `zsh -c` with proj.zsh sourced. Positional args
#   pass through cleanly via `zsh -c 'script' name "$@"`.

# Resolve repo root once.
# BATS_TEST_DIRNAME is the directory containing the .bats file (test/unit/),
# so the repo root is two levels up.
PROJ_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
export PROJ_ROOT

# Force TMPDIR to /tmp so:
#   1. mktemp -d -t proj-test.XXXXXX lands in /tmp on both Linux and macOS
#      (macOS default TMPDIR is /var/folders/..., which makes CI artifact
#      globs miss the failed-test state on the macos-latest job).
#   2. Temp paths are predictable for teardown and log collection.
# Do this at file load time so every test in every file sees the same TMPDIR.
export TMPDIR=/tmp

# Load bats-support + bats-assert
load "$PROJ_ROOT/test/lib/bats-support/load"
load "$PROJ_ROOT/test/lib/bats-assert/load"

# Per-test setup: isolated HOME, clean env.
setup() {
  TEST_HOME=$(mktemp -d -t proj-test.XXXXXX)
  export TEST_HOME
  export HOME="$TEST_HOME"
  export PATH="$PROJ_ROOT/test/fixtures/bin:$PATH"

  # Disable any i18n surprises — force English for predictable assertions.
  export LANG="en_US.UTF-8"
  unset PROJ_LANG

  # Ensure a clean slate under the fake HOME.
  mkdir -p "$HOME"
}

teardown() {
  if [[ -n "$TEST_HOME" && -d "$TEST_HOME" && "$TEST_HOME" == /tmp/proj-test.* ]]; then
    rm -rf "$TEST_HOME"
  fi
}

# proj(): bash → zsh bridge. Sources proj.zsh fresh per call and dispatches.
# Why fresh per call: proj.zsh has top-level state (mkdir, schema check) that
# should reflect the current fake HOME. A new zsh subshell re-runs all of it.
proj() {
  zsh -c 'source "$1" && shift && proj "$@"' _proj_test "$PROJ_ROOT/proj.zsh" "$@"
}

# proj_yes(): like proj() but pipes "y" to stdin for commands that prompt
# for confirmation (e.g., `proj sync` first push, `proj rm` with close flow).
proj_yes() {
  echo "y" | zsh -c 'source "$1" && shift && proj "$@"' _proj_test "$PROJ_ROOT/proj.zsh" "$@"
}

# make_bare_repo(): create an empty bare git repo at $1 for sync tests.
# Returns a file:// URL usable as sync_repo.
make_bare_repo() {
  local path="$1"
  git init --bare --quiet "$path"
  echo "file://$path"
}

# set_sync_repo(): write sync_repo directly to the config file, bypassing
# `proj config sync-repo` which validates URL scheme (https / git@ only).
# Tests use file:// URLs for local bare repos — production validation is
# correct, we just need to skip it in the test harness.
set_sync_repo() {
  local url="$1"
  mkdir -p "$HOME/.proj"
  echo "sync_repo=$url" >> "$HOME/.proj/config"
}

# proj_data_dir(): absolute path to the current test's proj data dir.
proj_data_dir() {
  echo "$HOME/.proj/data"
}

# proj_field(): read a raw field file for a project.
# Usage: proj_field <name> <field>
proj_field() {
  local name="$1" field="$2"
  local dir
  dir="$(proj_data_dir)/$name"
  [[ -f "$dir/$field" ]] && cat "$dir/$field"
}

# machine_id(): the UUID generated on first run, needed for path.<mid> assertions.
machine_id() {
  cat "$HOME/.proj/machine-id" 2>/dev/null
}

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

# Route all test-created temp directories under a single parent so:
#   1. run.sh can purge the whole tree in one rm -rf at the start
#   2. CI artifact upload has one glob to match on failure
#   3. macOS $TMPDIR default (/var/folders/...) is bypassed uniformly
#   4. Ad-hoc mktemp calls inside tests (e.g. proj_sync.bats creates a
#      machine-B home with a different prefix) all land in the same tree
#
# Individual test HOMEs are still created via `mktemp -d -t` with unique
# prefixes — this just pins the parent directory.
export TMPDIR=/tmp/proj-tests
mkdir -p "$TMPDIR"

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
  # Preserve the temp home on failure so CI can upload it as a diagnostic
  # artifact and local devs can inspect it. bats sets BATS_TEST_COMPLETED=1
  # only when a test passes; any failure (assertion, timeout, crash) leaves
  # the variable unset. run.sh purges stale dirs at the start of each run.
  if [[ -z "${BATS_TEST_COMPLETED:-}" ]]; then
    return
  fi
  if [[ -n "$TEST_HOME" && -d "$TEST_HOME" && "$TEST_HOME" == /tmp/proj-tests/* ]]; then
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

# proj_after(): run setup code inside the same zsh subshell that sources
# proj.zsh, THEN dispatch `proj <args>`. Needed when a test must manipulate
# ~/.proj state (e.g., schema_version) AFTER the source-time auto-migrate
# runs but BEFORE the proj command executes.
#
# Usage: run proj_after 'echo "1" > "$HOME/.proj/schema_version"' doctor
proj_after() {
  local setup="$1"
  shift
  SETUP_CODE="$setup" zsh -c '
    source "$1"; shift
    eval "$SETUP_CODE"
    proj "$@"
  ' _proj_test "$PROJ_ROOT/proj.zsh" "$@"
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

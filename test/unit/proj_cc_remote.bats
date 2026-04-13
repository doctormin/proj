#!/usr/bin/env bats
# Tests for `proj cc <remote-name>` — running claude -c on a remote host
# over ssh -t. Uses a mock ssh binary in fixtures/bin that logs argv to
# $SSH_CALLS_LOG so tests can assert the exact command string proj emits.

load '../test_helper'

setup_cc() {
  setup
  export SSH_CALLS_LOG="$HOME/ssh-calls.log"
  : > "$SSH_CALLS_LOG"
}

_add_remote_project() {
  local name="$1" host="${2:-user@ai4s}" rpath="${3:-/srv/proj}"
  proj list >/dev/null  # trigger schema init
  mkdir -p "$HOME/.proj/data/$name"
  echo "remote" > "$HOME/.proj/data/$name/type"
  echo "active" > "$HOME/.proj/data/$name/status"
  echo "$host" > "$HOME/.proj/data/$name/host"
  echo "$rpath" > "$HOME/.proj/data/$name/remote_path"
  echo "2026-01-01 00:00" > "$HOME/.proj/data/$name/updated"
}

# ── happy paths ──────────────────────────────────────────────────────────

@test "proj cc <remote>: invokes ssh -t with the configured host" {
  setup_cc
  _add_remote_project srv-a user@ai4s /srv/proj
  run proj cc srv-a
  assert_success
  [ -s "$SSH_CALLS_LOG" ]
  local logged; logged="$(cat "$SSH_CALLS_LOG")"
  [[ "$logged" == *"-t"* ]]
  [[ "$logged" == *"user@ai4s"* ]]
}

@test "proj cc <remote>: cd's into remote_path and runs claude -c" {
  setup_cc
  _add_remote_project srv-a user@ai4s /srv/proj
  run proj cc srv-a
  assert_success
  local logged; logged="$(cat "$SSH_CALLS_LOG")"
  [[ "$logged" == *"cd /srv/proj"* ]]
  [[ "$logged" == *"claude -c"* ]]
}

@test "proj cc <remote>: default wrapper is bash -lc" {
  setup_cc
  _add_remote_project srv-a
  run proj cc srv-a
  assert_success
  [[ "$(cat "$SSH_CALLS_LOG")" == *"bash -lc"* ]]
}

@test "proj cc <remote>: PROJ_REMOTE_SHELL overrides the wrapper" {
  setup_cc
  _add_remote_project srv-a
  PROJ_REMOTE_SHELL="zsh -ic" run proj cc srv-a
  assert_success
  local logged; logged="$(cat "$SSH_CALLS_LOG")"
  [[ "$logged" == *"zsh -ic"* ]]
  [[ "$logged" != *"bash -lc"* ]]
}

@test "proj cc <remote>: uses exec so claude takes the foreground" {
  setup_cc
  _add_remote_project srv-a
  run proj cc srv-a
  assert_success
  [[ "$(cat "$SSH_CALLS_LOG")" == *"exec claude -c"* ]]
}

@test "proj cc <remote>: escapes remote_path containing spaces" {
  setup_cc
  _add_remote_project srv-a user@ai4s "/srv/my project"
  run proj cc srv-a
  assert_success
  local logged; logged="$(cat "$SSH_CALLS_LOG")"
  # printf %q would produce /srv/my\ project
  [[ "$logged" == *"my\\ project"* || "$logged" == *"'my project'"* ]]
}

@test "proj cc <remote>: bumps updated timestamp" {
  setup_cc
  _add_remote_project srv-a
  echo "2020-01-01 00:00" > "$HOME/.proj/data/srv-a/updated"
  run proj cc srv-a
  assert_success
  local after; after="$(proj_field srv-a updated)"
  [ "$after" != "2020-01-01 00:00" ]
}

@test "proj cc <remote>: prints connecting banner with host and path" {
  setup_cc
  _add_remote_project srv-a user@ai4s /srv/proj
  run proj cc srv-a
  assert_output --partial "user@ai4s"
  assert_output --partial "/srv/proj"
}

# ── error paths ──────────────────────────────────────────────────────────

@test "proj cc <remote>: missing host errors out" {
  setup_cc
  proj list >/dev/null
  mkdir -p "$HOME/.proj/data/srv-broken"
  echo "remote" > "$HOME/.proj/data/srv-broken/type"
  echo "active" > "$HOME/.proj/data/srv-broken/status"
  echo "/srv/proj" > "$HOME/.proj/data/srv-broken/remote_path"
  # no host file
  run proj cc srv-broken
  assert_failure
  assert_output --partial "no host"
  [ ! -s "$SSH_CALLS_LOG" ]
}

@test "proj cc <remote>: missing remote_path errors out" {
  setup_cc
  proj list >/dev/null
  mkdir -p "$HOME/.proj/data/srv-broken"
  echo "remote" > "$HOME/.proj/data/srv-broken/type"
  echo "active" > "$HOME/.proj/data/srv-broken/status"
  echo "user@host" > "$HOME/.proj/data/srv-broken/host"
  run proj cc srv-broken
  assert_failure
  [ ! -s "$SSH_CALLS_LOG" ]
}

@test "proj cc <remote>: ssh nonzero exit is propagated" {
  setup_cc
  _add_remote_project srv-a
  SSH_MOCK_EXIT=42 run proj cc srv-a
  assert_equal "$status" "42"
}

# ── local projects still take the local path ───────────────────────────

@test "proj cc <local>: does not invoke ssh" {
  setup_cc
  mkdir -p "$HOME/workspace/localp"
  proj add localp "$HOME/workspace/localp" >/dev/null
  run proj cc localp
  # Local path normally exits successfully via mock claude. We only
  # care that the ssh mock was NOT hit.
  [ ! -s "$SSH_CALLS_LOG" ]
}

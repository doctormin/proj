#!/usr/bin/env bats
# Tests for `proj code [name]` — open a project in the user's editor.
#
# Editor mocks live in test/fixtures/bin: code, cursor, subl, emacs.
# Each appends "<name> <args>" to $EDITOR_CALLS_LOG so tests can assert
# which editor was invoked with which path.

load '../test_helper'

setup_code() {
  setup
  export EDITOR_CALLS_LOG="$HOME/editor-calls.log"
  : > "$EDITOR_CALLS_LOG"
}

_add() {
  local name="$1"
  mkdir -p "$HOME/workspace/$name"
  proj add "$name" "$HOME/workspace/$name" >/dev/null
}

_add_remote() {
  local name="$1"
  proj list >/dev/null   # trigger schema init
  mkdir -p "$HOME/.proj/data/$name"
  echo "remote" > "$HOME/.proj/data/$name/type"
  echo "active" > "$HOME/.proj/data/$name/status"
  echo "user@host" > "$HOME/.proj/data/$name/host"
  echo "/srv/$name" > "$HOME/.proj/data/$name/remote_path"
  echo "2026-01-01 00:00" > "$HOME/.proj/data/$name/updated"
}

# ── happy paths ──────────────────────────────────────────────────────────

@test "proj code <name>: opens named project in default editor (code)" {
  setup_code
  _add foo
  run proj code foo
  assert_success
  [ -s "$EDITOR_CALLS_LOG" ]
  local logged; logged="$(cat "$EDITOR_CALLS_LOG")"
  [[ "$logged" == code* ]]
  [[ "$logged" == *"$HOME/workspace/foo"* ]]
}

@test "proj code (no arg): auto-detects project from cwd" {
  setup_code
  _add foo
  cd "$HOME/workspace/foo"
  run proj code
  assert_success
  [[ "$(cat "$EDITOR_CALLS_LOG")" == *"$HOME/workspace/foo"* ]]
}

@test "proj code (no arg): auto-detects from cwd subdirectory" {
  setup_code
  _add foo
  mkdir -p "$HOME/workspace/foo/src/lib"
  cd "$HOME/workspace/foo/src/lib"
  run proj code
  assert_success
  [[ "$(cat "$EDITOR_CALLS_LOG")" == *"$HOME/workspace/foo"* ]]
}

@test "proj code <name>: PROJ_EDITOR overrides default" {
  setup_code
  _add foo
  PROJ_EDITOR=emacs run proj code foo
  assert_success
  [[ "$(cat "$EDITOR_CALLS_LOG")" == emacs* ]]
  [[ "$(cat "$EDITOR_CALLS_LOG")" == *"$HOME/workspace/foo"* ]]
}

@test "proj code <name>: updates 'updated' timestamp" {
  setup_code
  _add foo
  echo "2020-01-01 00:00" > "$(proj_data_dir)/foo/updated"
  run proj code foo
  assert_success
  local after; after="$(proj_field foo updated)"
  [ "$after" != "2020-01-01 00:00" ]
}

# ── edge cases ───────────────────────────────────────────────────────────

@test "proj code <name>: error on nonexistent project" {
  setup_code
  run proj code ghost
  assert_failure
  assert_output --partial "ghost"
  [ ! -s "$EDITOR_CALLS_LOG" ]
}

@test "proj code (no arg): error when cwd matches no project" {
  setup_code
  _add foo
  cd "$HOME"   # not inside foo
  run proj code
  assert_failure
  assert_output --partial "No project matches"
  [ ! -s "$EDITOR_CALLS_LOG" ]
}

@test "proj code <name>: error on remote project with SSH hint" {
  setup_code
  _add_remote bar
  run proj code bar
  assert_failure
  assert_output --partial "Remote"
  assert_output --partial "proj go"
  [ ! -s "$EDITOR_CALLS_LOG" ]
}

@test "proj code <name>: error when path no longer exists" {
  setup_code
  _add foo
  rm -rf "$HOME/workspace/foo"
  run proj code foo
  assert_failure
  [ ! -s "$EDITOR_CALLS_LOG" ]
}

@test "proj code <name>: error when PROJ_EDITOR set to nonexistent command" {
  setup_code
  _add foo
  PROJ_EDITOR=no-such-editor-xyz run proj code foo
  assert_failure
  assert_output --partial "no-such-editor-xyz"
  [ ! -s "$EDITOR_CALLS_LOG" ]
}

# ── integration: dispatch, help, completion ─────────────────────────────

@test "proj help: includes 'code' subcommand" {
  setup_code
  run proj help
  assert_success
  assert_output --partial "proj code"
}

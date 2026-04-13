#!/usr/bin/env bats
# Tests for `proj export` and `proj import <file.json>` — JSON-based
# backup / migration. Covers dispatch routing, schema shape, round-trip
# fidelity, collision handling, and the zoxide keyword path.

load '../test_helper'

_add() {
  local name="$1"
  mkdir -p "$HOME/workspace/$name"
  proj add "$name" "$HOME/workspace/$name" >/dev/null
}

# ── proj export ─────────────────────────────────────────────────────────

@test "proj export: writes valid JSON with schema_version and projects array" {
  _add foo
  _add bar
  run proj export "$TEST_HOME/backup.json"
  assert_success
  assert_output --partial "Exported 2 projects"

  # Structural checks via jq.
  run jq -r '.schema_version' "$TEST_HOME/backup.json"
  assert_success
  assert_output "2"

  run jq -r '.projects | length' "$TEST_HOME/backup.json"
  assert_success
  assert_output "2"

  run jq -r '.projects[].name' "$TEST_HOME/backup.json"
  assert_success
  [[ "$output" == *"foo"* ]]
  [[ "$output" == *"bar"* ]]
}

@test "proj export: with no file writes JSON to stdout" {
  _add foo
  run proj export
  assert_success
  # Output must be parseable as JSON.
  echo "$output" | jq -e '.schema_version' >/dev/null
  echo "$output" | jq -e '.projects[0].name' >/dev/null
}

@test "proj export: preserves desc, status, path, tags per project" {
  _add foo
  proj status foo paused >/dev/null
  proj edit foo desc "a test project" >/dev/null
  proj tag foo work client-a >/dev/null

  proj export "$TEST_HOME/backup.json"
  run jq -r '.projects[] | select(.name=="foo") | .status' "$TEST_HOME/backup.json"
  assert_output "paused"

  run jq -r '.projects[] | select(.name=="foo") | .desc' "$TEST_HOME/backup.json"
  assert_output "a test project"

  run jq -r '.projects[] | select(.name=="foo") | .path' "$TEST_HOME/backup.json"
  assert_output "$HOME/workspace/foo"

  run jq -r '.projects[] | select(.name=="foo") | .tags | sort | join(",")' \
    "$TEST_HOME/backup.json"
  assert_output "client-a,work"
}

@test "proj export: empty project list still emits valid JSON with projects:[]" {
  run proj export "$TEST_HOME/backup.json"
  assert_success
  run jq -r '.projects | length' "$TEST_HOME/backup.json"
  assert_output "0"
}

# ── proj import <file.json> ─────────────────────────────────────────────

@test "proj import <file.json>: round-trips export → wipe → import" {
  _add foo
  _add bar
  proj status foo paused >/dev/null
  proj edit foo desc "foo desc" >/dev/null
  proj tag bar work >/dev/null

  proj export "$TEST_HOME/backup.json" >/dev/null

  # Wipe project data (but keep proj install state).
  rm -rf "$(proj_data_dir)"
  mkdir -p "$(proj_data_dir)"

  run proj import "$TEST_HOME/backup.json"
  assert_success
  assert_output --partial "imported"

  # Both projects restored
  [ -d "$(proj_data_dir)/foo" ]
  [ -d "$(proj_data_dir)/bar" ]
  assert_equal "$(proj_field foo status)" "paused"
  assert_equal "$(proj_field foo desc)" "foo desc"
  assert_equal "$(cat "$(proj_data_dir)/bar/tags")" "work"
}

@test "proj import <file.json>: collision skipped without --force" {
  _add foo
  proj export "$TEST_HOME/backup.json" >/dev/null
  # Mutate the local project so we can tell if import overwrote it.
  proj edit foo desc "local-value" >/dev/null

  run proj import "$TEST_HOME/backup.json"
  assert_success
  assert_output --partial "Skipping existing"
  # Local value preserved (import skipped).
  assert_equal "$(proj_field foo desc)" "local-value"
}

@test "proj import <file.json>: --force overwrites existing projects" {
  _add foo
  proj edit foo desc "exported" >/dev/null
  proj export "$TEST_HOME/backup.json" >/dev/null
  proj edit foo desc "local" >/dev/null

  run proj import "$TEST_HOME/backup.json" --force
  assert_success
  assert_output --partial "overwritten"
  assert_equal "$(proj_field foo desc)" "exported"
}

@test "proj import <file.json>: empty projects array imports 0 projects" {
  echo '{"schema_version":"2","projects":[]}' > "$TEST_HOME/empty.json"
  run proj import "$TEST_HOME/empty.json"
  assert_success
  assert_output --partial "0 imported"
}

@test "proj import <file.json>: malformed JSON is rejected cleanly" {
  echo "not valid json at all {" > "$TEST_HOME/bad.json"
  run proj import "$TEST_HOME/bad.json"
  assert_failure
  assert_output --partial "Not a valid proj export"
}

@test "proj import <file.json>: missing .projects key is rejected" {
  echo '{"schema_version":"2"}' > "$TEST_HOME/wrong.json"
  run proj import "$TEST_HOME/wrong.json"
  assert_failure
  assert_output --partial "Not a valid proj export"
}

@test "proj import <file.json>: invalid name inside JSON is skipped" {
  cat > "$TEST_HOME/mixed.json" <<'JSON'
{
  "schema_version": "2",
  "projects": [
    {"name": "good", "type": "local", "status": "active", "path": "/tmp", "desc":"", "progress":"", "todo":"", "updated":"2026-01-01 00:00", "host":"", "remote_path":"", "tags":[], "has_history":false},
    {"name": "../evil", "type": "local", "status": "active", "path": "/tmp", "desc":"", "progress":"", "todo":"", "updated":"2026-01-01 00:00", "host":"", "remote_path":"", "tags":[], "has_history":false}
  ]
}
JSON
  run proj import "$TEST_HOME/mixed.json"
  assert_success
  assert_output --partial "invalid name"
  [ -d "$(proj_data_dir)/good" ]
  [ ! -d "$(proj_data_dir)/../evil" ]
}

@test "proj import <file.json>: tags round-trip exactly" {
  _add foo
  proj tag foo alpha beta gamma >/dev/null
  proj export "$TEST_HOME/backup.json" >/dev/null
  rm -rf "$(proj_data_dir)/foo"

  run proj import "$TEST_HOME/backup.json"
  assert_success

  local tags; tags="$(cat "$(proj_data_dir)/foo/tags" | sort | tr '\n' ',' )"
  assert_equal "$tags" "alpha,beta,gamma,"
}

# ── import dispatch ─────────────────────────────────────────────────────

@test "proj import <dir>: still routes to directory-scan (backward compat)" {
  mkdir -p "$TEST_HOME/repos/sample"
  (cd "$TEST_HOME/repos/sample" && git init --quiet)
  run proj_yes import "$TEST_HOME/repos" --yes
  assert_success
  [ -d "$(proj_data_dir)/sample" ]
}

@test "proj import (no arg): still routes to directory-scan in cwd" {
  mkdir -p "$HOME/workspace/legacy"
  (cd "$HOME/workspace/legacy" && git init --quiet)
  cd "$HOME/workspace"
  run proj_yes import --yes
  assert_success
  [ -d "$(proj_data_dir)/legacy" ]
}

# ── proj export: integration with proj import ──────────────────────────

@test "proj export + proj import: preserves remote project fields" {
  proj list >/dev/null  # trigger schema init
  mkdir -p "$HOME/.proj/data/srv-1"
  echo "remote" > "$HOME/.proj/data/srv-1/type"
  echo "active" > "$HOME/.proj/data/srv-1/status"
  echo "user@ai4s" > "$HOME/.proj/data/srv-1/host"
  echo "/srv/proj" > "$HOME/.proj/data/srv-1/remote_path"
  echo "2026-01-01 00:00" > "$HOME/.proj/data/srv-1/updated"

  proj export "$TEST_HOME/backup.json"
  rm -rf "$(proj_data_dir)/srv-1"

  run proj import "$TEST_HOME/backup.json"
  assert_success
  assert_equal "$(proj_field srv-1 type)" "remote"
  assert_equal "$(proj_field srv-1 host)" "user@ai4s"
  assert_equal "$(proj_field srv-1 remote_path)" "/srv/proj"
}

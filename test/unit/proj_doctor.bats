#!/usr/bin/env bats
# Tests for `proj doctor` — environment/schema/sync/projects health check.

load '../test_helper'

_add() {
  local name="$1"
  mkdir -p "$HOME/workspace/$name"
  proj add "$name" "$HOME/workspace/$name" >/dev/null
}

_days_ago() {
  local n="$1"
  date -v-"${n}d" +"%Y-%m-%d %H:%M" 2>/dev/null \
    || date -d "$n days ago" +"%Y-%m-%d %H:%M"
}

@test "proj doctor: prints all four section headers" {
  run proj doctor
  assert_success
  assert_output --partial "Environment"
  assert_output --partial "Schema"
  assert_output --partial "Sync"
  assert_output --partial "Projects"
}

@test "proj doctor: prints summary line with counts" {
  run proj doctor
  assert_success
  # .* absorbs ANSI escape between "Summary:" and the count
  assert_output --regexp "Summary:.*[0-9]+ checks"
  assert_output --partial "passed"
  assert_output --partial "warnings"
  assert_output --partial "failed"
}

@test "proj doctor: clean install reports schema v2 as pass" {
  run proj doctor
  assert_success
  assert_output --partial "schema version"
  assert_output --partial "v2"
}

@test "proj doctor: no projects reports total=0 and no stale" {
  run proj doctor
  assert_success
  assert_output --partial "total"
  # 0 projects → 0 stale → pass
  assert_output --partial "stale (>90 days)"
}

@test "proj doctor: reports project counts by status" {
  _add alpha
  _add beta
  proj status beta paused >/dev/null

  run proj doctor
  assert_success
  assert_output --partial "active=1"
  assert_output --partial "paused=1"
}

@test "proj doctor: detects missing local path" {
  _add gone
  rm -rf "$HOME/workspace/gone"

  run proj doctor
  assert_success
  assert_output --regexp "missing local path[[:space:]]+1"
}

@test "proj doctor: remote projects are not counted as unlinked" {
  # Remote projects have no local path BY DESIGN. The unlinked health
  # signal should only fire for synced LOCAL projects that have no
  # path.<this-machine-id> file.
  run proj add-remote api user@server.example.com:/srv/api
  assert_success

  run proj doctor
  assert_success
  # "unlinked on this machine" should NOT appear — remote projects are
  # excluded from that check entirely.
  refute_output --partial "unlinked on this machine"
}

@test "proj doctor: synced local project without path.<mid> IS counted as unlinked" {
  # Simulate a project synced from another machine
  run proj --version
  mkdir -p "$(proj_data_dir)/foreign"
  echo "local"  > "$(proj_data_dir)/foreign/type"
  echo "active" > "$(proj_data_dir)/foreign/status"
  echo "2026-04-10 10:00" > "$(proj_data_dir)/foreign/updated"

  run proj doctor
  assert_success
  assert_output --partial "unlinked on this machine"
}

@test "proj doctor: detects stale projects (>90 days)" {
  _add oldie
  echo "$(_days_ago 100)" > "$(proj_data_dir)/oldie/updated"

  run proj doctor
  assert_success
  assert_output --regexp "stale \(>90 days\)[[:space:]]+1"
}

@test "proj doctor: fails when schema_version file missing" {
  # Use proj_after so the rm runs INSIDE the zsh subshell, after proj.zsh's
  # source-time auto-migrate has re-created schema_version.
  run proj_after 'rm -f "$HOME/.proj/schema_version"' doctor
  assert_failure
  assert_output --partial "schema version"
  assert_output --partial "missing"
  assert_output --regexp "[1-9][0-9]* failed"
}

@test "proj doctor: warns when schema_version is v1" {
  run proj_after 'echo 1 > "$HOME/.proj/schema_version"' doctor
  assert_success  # warn doesn't fail
  assert_output --partial "v1"
  assert_output --partial "run proj migrate"
}

@test "proj doctor: fails when machine-id missing" {
  run proj_after 'rm -f "$HOME/.proj/machine-id"' doctor
  assert_failure
  assert_output --partial "machine-id"
  assert_output --partial "missing"
}

@test "proj doctor: does NOT regenerate machine-id as a side effect" {
  # Doctor should be a pure read-only diagnostic. If machine-id is missing,
  # it must report the failure WITHOUT silently writing a fresh UUID (which
  # would break path.<old-id> lookups for existing projects).
  #
  # Use proj_after so the rm fires inside the zsh subshell, AFTER the
  # source-time migrate runs. Then call doctor and assert the file is
  # still absent afterwards.
  run proj_after '
    rm -f "$HOME/.proj/machine-id"
    proj doctor >/dev/null 2>&1 || true
    [[ -f "$HOME/.proj/machine-id" ]] && echo "REGENERATED" || echo "READ_ONLY"
  ' --version
  assert_output --partial "READ_ONLY"
}

@test "proj doctor: reports sync_repo from config" {
  set_sync_repo "file:///tmp/fake-bare"
  run proj doctor
  assert_success
  assert_output --partial "file:///tmp/fake-bare"
}

@test "proj doctor: sync repo not configured shows info line" {
  run proj doctor
  assert_success
  assert_output --partial "not configured"
}

@test "proj doctor: help text mentions doctor subcommand" {
  run proj help
  assert_success
  assert_output --partial "doctor"
}

#!/usr/bin/env bats
# Tests for `proj stale` — list projects not updated in N days.

load '../test_helper'

# Cross-platform date arithmetic helper: print "YYYY-MM-DD HH:MM" for N days ago.
_days_ago() {
  local n="$1"
  date -v-"${n}d" +"%Y-%m-%d %H:%M" 2>/dev/null \
    || date -d "$n days ago" +"%Y-%m-%d %H:%M"
}

# Overwrite the `updated` field of a project (bypasses the normal timestamp).
_set_updated() {
  local name="$1" ts="$2"
  local dir
  dir="$(proj_data_dir)/$name"
  [[ -d "$dir" ]] || return 1
  echo "$ts" > "$dir/updated"
}

_add() {
  local name="$1"
  mkdir -p "$HOME/workspace/$name"
  proj add "$name" "$HOME/workspace/$name" >/dev/null
}

@test "proj stale: empty project list prints no-stale message" {
  run proj stale
  assert_success
  assert_output --partial "No stale projects"
}

@test "proj stale 30: project updated 40 days ago appears" {
  _add stale40
  _set_updated stale40 "$(_days_ago 40)"

  run proj stale 30
  assert_success
  assert_output --partial "stale40"
  assert_output --partial "40d"
}

@test "proj stale 30: project updated yesterday does not appear" {
  _add recently
  _set_updated recently "$(_days_ago 1)"

  run proj stale 30
  assert_success
  refute_output --partial "recently"
}

@test "proj stale: default window is 30 days" {
  _add stale40
  _set_updated stale40 "$(_days_ago 40)"
  _add recently
  _set_updated recently "$(_days_ago 1)"

  run proj stale
  assert_success
  assert_output --partial "stale40"
  refute_output --partial "recently"
}

@test "proj stale 0: lists all projects regardless of age" {
  _add fresh
  _add older
  _set_updated older "$(_days_ago 10)"

  run proj stale 0
  assert_success
  assert_output --partial "fresh"
  assert_output --partial "older"
}

@test "proj stale: sorts by age descending (oldest first)" {
  _add middle
  _set_updated middle "$(_days_ago 50)"
  _add newest
  _set_updated newest "$(_days_ago 31)"
  _add oldest
  _set_updated oldest "$(_days_ago 120)"

  run proj stale 30
  assert_success
  # oldest should appear before middle, middle before newest
  local oldest_line middle_line newest_line
  oldest_line=$(echo "$output" | grep -n "oldest" | head -1 | cut -d: -f1)
  middle_line=$(echo "$output" | grep -n "middle" | head -1 | cut -d: -f1)
  newest_line=$(echo "$output" | grep -n "newest" | head -1 | cut -d: -f1)
  [ "$oldest_line" -lt "$middle_line" ]
  [ "$middle_line" -lt "$newest_line" ]
}

@test "proj stale: empty updated field is skipped" {
  _add broken
  _set_updated broken ""

  run proj stale 0
  assert_success
  refute_output --partial "broken"
}

@test "proj stale: invalid date format is skipped (no crash)" {
  _add malformed
  _set_updated malformed "not-a-date"

  run proj stale 0
  assert_success
  refute_output --partial "malformed"
}

@test "proj stale: rejects non-numeric days argument" {
  run proj stale abc
  assert_failure
  assert_output --partial "Usage: proj stale"
}

@test "proj stale: rejects negative days (not a match for [0-9]+)" {
  run proj stale -5
  assert_failure
}

@test "proj stale 999: zero matches prints empty-state message" {
  _add recent
  _set_updated recent "$(_days_ago 5)"

  run proj stale 999
  assert_success
  assert_output --partial "No stale projects"
}

@test "proj stale: help text mentions stale subcommand" {
  run proj help
  assert_success
  assert_output --partial "stale"
}

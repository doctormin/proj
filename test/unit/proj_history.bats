#!/usr/bin/env bats
# Tests for `proj history` and the history-log append hooks.

load '../test_helper'

_add() {
  local name="$1"
  mkdir -p "$HOME/workspace/$name"
  proj add "$name" "$HOME/workspace/$name" >/dev/null
}

_history_file() {
  echo "$(proj_data_dir)/$1/history.log"
}

# Hook writes

@test "proj status: appends a status event to history.log" {
  _add foo

  run proj status foo paused
  assert_success

  local log="$(_history_file foo)"
  assert [ -f "$log" ]
  run cat "$log"
  assert_output --partial "status|active→paused"
  # Timestamp must be UTC ISO 8601 Z-form for timezone stability
  assert_output --regexp "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"
}

@test "proj status: re-setting the same status still logs (not deduplicated)" {
  _add foo

  proj status foo paused >/dev/null
  proj status foo paused >/dev/null

  local log="$(_history_file foo)"
  local count
  count=$(grep -c '|status|' "$log")
  assert_equal "$count" "2"
}

@test "proj edit: appends an edit event with field name but no value" {
  _add foo

  run proj edit foo desc "sensitive description"
  assert_success

  local log="$(_history_file foo)"
  assert [ -f "$log" ]
  run cat "$log"
  assert_output --partial "edit|desc"
  refute_output --partial "sensitive"
}

@test "proj tag: appends tag add event with + prefix" {
  _add foo

  run proj tag foo work deploy
  assert_success

  local log="$(_history_file foo)"
  run cat "$log"
  assert_output --partial "tag|+work +deploy"
}

@test "proj untag: appends tag remove event with - prefix" {
  _add foo
  proj tag foo work deploy >/dev/null

  run proj untag foo work
  assert_success

  local log="$(_history_file foo)"
  run cat "$log"
  assert_output --partial "tag|-work"
}

# proj history readout

@test "proj history: nonexistent project errors out" {
  run proj history ghost
  assert_failure
  assert_output --partial "does not exist"
}

@test "proj history: no log file prints empty-state message" {
  _add foo
  run proj history foo
  assert_success
  assert_output --partial "No history recorded"
}

@test "proj history: shows recent events newest-first" {
  _add foo
  proj status foo paused >/dev/null
  proj status foo blocked >/dev/null
  proj status foo done >/dev/null

  run proj history foo
  assert_success

  # Most recent transition should appear before earlier ones
  local first_line second_line third_line
  first_line=$(echo "$output" | grep -n 'blocked→done' | head -1 | cut -d: -f1)
  second_line=$(echo "$output" | grep -n 'paused→blocked' | head -1 | cut -d: -f1)
  third_line=$(echo "$output" | grep -n 'active→paused' | head -1 | cut -d: -f1)
  [ -n "$first_line" ]
  [ -n "$second_line" ]
  [ -n "$third_line" ]
  [ "$first_line" -lt "$second_line" ]
  [ "$second_line" -lt "$third_line" ]
}

@test "proj history: shows status, edit, and tag event types" {
  _add foo
  proj status foo paused >/dev/null
  proj edit foo desc "a note" >/dev/null
  proj tag foo work >/dev/null

  run proj history foo
  assert_success
  assert_output --partial "status"
  assert_output --partial "edit"
  assert_output --partial "tag"
  assert_output --partial "active→paused"
  assert_output --partial "desc"
  assert_output --partial "+work"
}

@test "proj history: default caps display at 30 events, --all shows more" {
  _add foo

  # Write a 35-line raw log directly to test the cap.
  # Spread across two months so every date is valid.
  local log="$(_history_file foo)"
  local i
  for i in $(seq 1 30); do
    printf '2026-03-%02dT10:00:00Z|status|active→paused|\n' "$i" >> "$log"
  done
  for i in $(seq 1 5); do
    printf '2026-04-%02dT10:00:00Z|status|active→paused|\n' "$i" >> "$log"
  done

  # Default: 30 entries
  run proj history foo
  assert_success
  local count
  count=$(echo "$output" | grep -c 'active→paused')
  assert_equal "$count" "30"

  # --all: all 35
  run proj history foo --all
  assert_success
  count=$(echo "$output" | grep -c 'active→paused')
  assert_equal "$count" "35"
}

@test "proj history: sorts by parsed timestamp, not file order (multi-machine merge)" {
  _add foo
  local log="$(_history_file foo)"
  # Simulate a merged log where lines are not in chronological order —
  # e.g., machine A's events appear before machine B's older events after
  # git merge. The display should still show the true newest first.
  cat > "$log" <<EOF
2026-04-01T10:00:00Z|status|active→paused|
2026-03-01T10:00:00Z|status|blocked→active|
2026-04-10T10:00:00Z|status|paused→done|
2026-02-15T10:00:00Z|edit|desc|
EOF

  run proj history foo
  assert_success

  # The newest timestamp (2026-04-10 paused→done) should appear first,
  # and 2026-02-15 edit should appear last.
  local newest_line oldest_line
  newest_line=$(echo "$output" | grep -n 'paused→done' | head -1 | cut -d: -f1)
  oldest_line=$(echo "$output" | grep -n 'edit' | head -1 | cut -d: -f1)
  [ -n "$newest_line" ]
  [ -n "$oldest_line" ]
  [ "$newest_line" -lt "$oldest_line" ]
}

@test "proj history: panel close-as-done path logs to history" {
  # Panel close-flow is interactive, so exercise it via the same code path
  # by calling _proj_action close inline. We mock fzf to auto-select
  # "Mark as done" (the first line).
  skip "panel close flow requires interactive fzf; exercised via manual/e2e tests"
}

@test "proj history: skips corrupt lines without crashing" {
  _add foo
  local log="$(_history_file foo)"
  # Good lines + corrupt line
  echo "2026-04-10T10:00:00Z|status|active→paused|" > "$log"
  echo "this is not a valid log line" >> "$log"
  echo "2026-04-11T10:00:00Z|status|paused→active|" >> "$log"

  run proj history foo
  assert_success
  assert_output --partial "active→paused"
  assert_output --partial "paused→active"
  refute_output --partial "this is not a valid"
}

@test "proj history: legacy local-wall-clock lines still parse (backward compat)" {
  # Older proj versions wrote "YYYY-MM-DD HH:MM:SS" without a TZ indicator.
  # The parser still accepts those so upgrading doesn't break existing logs.
  _add foo
  local log="$(_history_file foo)"
  echo "2026-04-10 10:00:00|status|active→paused|" > "$log"

  run proj history foo
  assert_success
  assert_output --partial "active→paused"
}

@test "proj history: missing name argument errors with usage" {
  run proj history
  assert_failure
  assert_output --partial "Usage: proj history"
}

@test "proj history: help text mentions history subcommand" {
  run proj help
  assert_success
  assert_output --partial "history"
}

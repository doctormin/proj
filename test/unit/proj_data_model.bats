#!/usr/bin/env bats
# Data model v2: machine-id routing, legacy path fallback, field accessors.
# These tests pin down the contract that path migration preserves.

load '../test_helper'

@test "machine-id file is created on first proj invocation" {
  run proj --version
  assert_success
  assert [ -f "$HOME/.proj/machine-id" ]

  # UUID format (8-4-4-4-12 hex with hyphens), case-insensitive
  local mid="$(machine_id)"
  [[ "$mid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

@test "machine-id is stable across proj invocations" {
  run proj --version
  local mid1="$(machine_id)"

  run proj --version
  local mid2="$(machine_id)"

  assert_equal "$mid1" "$mid2"
}

@test "schema_version file is 2 after first invocation" {
  run proj --version
  assert_success
  assert [ -f "$HOME/.proj/schema_version" ]
  assert_equal "$(cat $HOME/.proj/schema_version)" "2"
}

@test "proj add writes path to path.<machine-id>, not plain path" {
  mkdir -p "$HOME/workspace/alpha"
  run proj add alpha "$HOME/workspace/alpha"
  assert_success

  local mid="$(machine_id)"
  assert [ -f "$(proj_data_dir)/alpha/path.$mid" ]
  assert [ ! -f "$(proj_data_dir)/alpha/path" ]
}

@test "legacy path file is read when path.<machine-id> missing" {
  # Simulate a legacy v1 project: create by hand with a plain `path` file,
  # then verify proj still reads it back via the fallback branch in _proj_get.
  run proj --version
  mkdir -p "$HOME/workspace/legacy"
  mkdir -p "$(proj_data_dir)/legacy"
  echo "$HOME/workspace/legacy" > "$(proj_data_dir)/legacy/path"
  echo "local" > "$(proj_data_dir)/legacy/type"
  echo "active" > "$(proj_data_dir)/legacy/status"
  echo "2026-04-13 10:00" > "$(proj_data_dir)/legacy/updated"
  touch "$(proj_data_dir)/legacy/desc" "$(proj_data_dir)/legacy/progress" "$(proj_data_dir)/legacy/todo"

  # List should see it
  run proj list
  assert_success
  assert_output --partial "legacy"
}

@test "type field is 'local' after proj add" {
  mkdir -p "$HOME/workspace/beta"
  run proj add beta "$HOME/workspace/beta"
  assert_equal "$(proj_field beta type)" "local"
}

@test "desc/progress/todo start as empty strings" {
  mkdir -p "$HOME/workspace/gamma"
  run proj add gamma "$HOME/workspace/gamma"
  # Files exist (created by _proj_set) but empty
  assert [ -f "$(proj_data_dir)/gamma/desc" ]
  [ -z "$(proj_field gamma desc)" ]
  [ -z "$(proj_field gamma progress)" ]
  [ -z "$(proj_field gamma todo)" ]
}

@test "updated timestamp is recorded on add" {
  mkdir -p "$HOME/workspace/delta"
  run proj add delta "$HOME/workspace/delta"
  local ts="$(proj_field delta updated)"
  # Format: YYYY-MM-DD HH:MM
  [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]]
}

@test "updated timestamp refreshes on status change" {
  mkdir -p "$HOME/workspace/echo"
  run proj add echo "$HOME/workspace/echo"
  local t1="$(proj_field echo updated)"

  # Wait a minute would be ideal but tests should be fast.
  # Force a stale timestamp, then verify status change updates it.
  echo "2020-01-01 00:00" > "$(proj_data_dir)/echo/updated"

  run proj status echo paused
  local t2="$(proj_field echo updated)"
  [[ "$t2" != "2020-01-01 00:00" ]]
}

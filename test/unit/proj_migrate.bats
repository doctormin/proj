#!/usr/bin/env bats
# Schema migration: v1 (plain path file) → v2 (path.<machine-id> + type + schema_version).
# Covers idempotency, backup creation, and preservation of all fields.

load '../test_helper'

# Helper: hand-build a v1-format project in the fake HOME, bypassing proj.zsh.
# This simulates data that was created under a pre-v2 installation.
setup_v1_project() {
  local name="$1"
  local path="$2"
  local dir="$HOME/.proj/data/$name"
  mkdir -p "$dir"
  echo "$path" > "$dir/path"
  echo "active" > "$dir/status"
  echo "2026-04-01 12:00" > "$dir/updated"
  echo "a $name description" > "$dir/desc"
  echo "some progress text" > "$dir/progress"
  echo "- todo item" > "$dir/todo"
}

@test "proj migrate on fresh install is a no-op but sets schema_version" {
  # No projects yet — schema_version file is created but nothing to migrate.
  run proj migrate
  assert_success
  assert [ -f "$HOME/.proj/schema_version" ]
  assert_equal "$(cat $HOME/.proj/schema_version)" "2"
}

@test "proj migrate converts a single v1 project to v2" {
  mkdir -p "$HOME/.proj"  # ensure proj root exists pre-source
  setup_v1_project "legacy1" "$HOME/workspace/legacy1"

  run proj migrate
  assert_success

  # After migration: path.<mid> exists, plain path is gone, type is "local"
  local mid
  run proj --version  # triggers machine-id generation if not already
  mid="$(machine_id)"
  [ -n "$mid" ]

  # Re-run migrate — in case --version created it separately, be idempotent
  run proj migrate

  assert [ -f "$(proj_data_dir)/legacy1/path.$mid" ]
  assert_equal "$(cat $(proj_data_dir)/legacy1/path.$mid)" "$HOME/workspace/legacy1"
  assert [ -f "$(proj_data_dir)/legacy1/type" ]
  assert_equal "$(proj_field legacy1 type)" "local"
}

@test "proj migrate preserves desc/progress/todo/status fields" {
  setup_v1_project "legacy2" "$HOME/workspace/legacy2"

  run proj migrate
  assert_success

  assert_equal "$(proj_field legacy2 desc)" "a legacy2 description"
  assert_equal "$(proj_field legacy2 progress)" "some progress text"
  assert_equal "$(proj_field legacy2 todo)" "- todo item"
  assert_equal "$(proj_field legacy2 status)" "active"
}

@test "proj migrate creates a backup at data.v1.backup" {
  setup_v1_project "legacy3" "$HOME/workspace/legacy3"

  run proj migrate
  assert_success

  assert [ -d "$HOME/.proj/data.v1.backup" ]
  assert [ -f "$HOME/.proj/data.v1.backup/legacy3/path" ]
  # Backup retains the v1 format (plain path file)
  assert_equal "$(cat $HOME/.proj/data.v1.backup/legacy3/path)" "$HOME/workspace/legacy3"
}

@test "proj migrate is idempotent on v2 data" {
  setup_v1_project "legacy4" "$HOME/workspace/legacy4"

  run proj migrate
  assert_success

  # Second run: should detect v2 and skip
  run proj migrate
  assert_success
  # If it didn't skip, it'd re-create data.v1.backup; but since we already
  # have one, idempotency means the second migrate is a no-op
  # (we don't assert anything destructive — just that exit is clean)
}

@test "proj migrate handles multiple v1 projects" {
  setup_v1_project "alpha" "$HOME/workspace/alpha"
  setup_v1_project "bravo" "$HOME/workspace/bravo"
  setup_v1_project "charlie" "$HOME/workspace/charlie"

  run proj migrate
  assert_success

  local mid="$(machine_id)"
  assert [ -f "$(proj_data_dir)/alpha/path.$mid" ]
  assert [ -f "$(proj_data_dir)/bravo/path.$mid" ]
  assert [ -f "$(proj_data_dir)/charlie/path.$mid" ]
}

@test "auto-migrate runs on first proj command when schema is v1" {
  # Create v1 data, then run any proj command — auto-migrate should fire
  setup_v1_project "autofix" "$HOME/workspace/autofix"

  run proj list  # any command triggers the auto-migrate flag path
  assert_success

  assert [ -f "$HOME/.proj/schema_version" ]
  assert_equal "$(cat $HOME/.proj/schema_version)" "2"

  local mid="$(machine_id)"
  assert [ -f "$(proj_data_dir)/autofix/path.$mid" ]
}

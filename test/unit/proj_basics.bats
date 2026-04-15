#!/usr/bin/env bats
# Smoke tests for the core CRUD flow.
# If these pass, the framework itself works and we can trust everything else.

load '../test_helper'

@test "proj --version prints version string" {
  run proj --version
  assert_success
  assert_output --partial "proj 1.1.0-dev"
}

@test "proj -v is alias for --version" {
  run proj -v
  assert_success
  assert_output --partial "proj 1.1.0-dev"
}

@test "sourcing proj.zsh creates ~/.proj/data" {
  run proj --version
  assert_success
  assert [ -d "$HOME/.proj/data" ]
}

@test "proj add creates a local project with expected fields" {
  mkdir -p "$HOME/workspace/myapp"
  run proj add myapp "$HOME/workspace/myapp"
  assert_success

  local dir="$(proj_data_dir)/myapp"
  assert [ -d "$dir" ]
  assert_equal "$(proj_field myapp type)" "local"
  assert_equal "$(proj_field myapp status)" "active"
  [ -n "$(proj_field myapp updated)" ]
}

@test "proj add stores path via machine-id routing" {
  mkdir -p "$HOME/workspace/myapp"
  run proj add myapp "$HOME/workspace/myapp"
  assert_success

  local mid
  mid="$(machine_id)"
  [ -n "$mid" ]
  assert [ -f "$(proj_data_dir)/myapp/path.$mid" ]
  assert_equal "$(cat $(proj_data_dir)/myapp/path.$mid)" "$HOME/workspace/myapp"
}

@test "proj rm removes the project directory" {
  mkdir -p "$HOME/workspace/myapp"
  run proj add myapp "$HOME/workspace/myapp"
  assert_success

  run proj rm myapp
  assert_success
  assert [ ! -d "$(proj_data_dir)/myapp" ]
}

@test "proj status changes the status field" {
  mkdir -p "$HOME/workspace/myapp"
  run proj add myapp "$HOME/workspace/myapp"
  assert_success

  run proj status myapp paused
  assert_success
  assert_equal "$(proj_field myapp status)" "paused"
}

@test "proj status rejects invalid status values" {
  mkdir -p "$HOME/workspace/myapp"
  run proj add myapp "$HOME/workspace/myapp"

  run proj status myapp nonsense
  assert_failure
  assert_equal "$(proj_field myapp status)" "active"
}

@test "proj edit updates desc field" {
  mkdir -p "$HOME/workspace/myapp"
  run proj add myapp "$HOME/workspace/myapp"

  run proj edit myapp desc "A new description"
  assert_success
  assert_equal "$(proj_field myapp desc)" "A new description"
}

@test "proj edit rejects unknown field" {
  mkdir -p "$HOME/workspace/myapp"
  run proj add myapp "$HOME/workspace/myapp"

  run proj edit myapp bogus "value"
  assert_failure
}

@test "proj list prints the project name" {
  mkdir -p "$HOME/workspace/myapp"
  run proj add myapp "$HOME/workspace/myapp"

  run proj list
  assert_success
  assert_output --partial "myapp"
}

#!/usr/bin/env bats
# preview.sh: rendering for local, remote, missing, and unlinked projects.
# preview.sh runs as its own bash subprocess (bash shebang), so we invoke it
# directly rather than through the proj() zsh bridge.

load '../test_helper'

# Helper: run preview.sh against the current $HOME's data dir.
preview() {
  local name="$1"
  bash "$PROJ_ROOT/preview.sh" "$name"
}

@test "preview of a local project shows name and active status" {
  mkdir -p "$HOME/workspace/myapp"
  run proj add myapp "$HOME/workspace/myapp"
  assert_success

  run preview myapp
  assert_success
  assert_output --partial "myapp"
  assert_output --partial "active"
}

@test "preview of a local project shows its path" {
  mkdir -p "$HOME/workspace/myapp"
  run proj add myapp "$HOME/workspace/myapp"

  run preview myapp
  assert_output --partial "$HOME/workspace/myapp"
}

@test "preview of a project with missing local path shows (missing)" {
  # Create project, then delete the underlying directory so path is stale
  mkdir -p "$HOME/workspace/stale"
  run proj add stale "$HOME/workspace/stale"
  rm -rf "$HOME/workspace/stale"

  run preview stale
  assert_output --partial "missing"
}

@test "preview of a remote project shows host:remote_path" {
  run proj add-remote api user@server.example.com:/srv/api
  assert_success

  run preview api
  assert_success
  assert_output --partial "user@server.example.com"
  assert_output --partial "/srv/api"
  assert_output --partial "remote"
}

@test "preview of a remote project does not attempt file listing" {
  run proj add-remote api user@server:/srv/api

  run preview api
  assert_success
  # The "Files" header appears only for local projects with a valid path
  refute_output --partial "Files"
}

@test "preview of a remote project shows SSH hint for Claude sessions" {
  run proj add-remote api user@server:/srv/api

  run preview api
  assert_output --partial "SSH"
}

@test "preview of a nonexistent project errors gracefully" {
  run preview nonexistent
  assert_failure
}

@test "preview shows description when set" {
  mkdir -p "$HOME/workspace/app"
  run proj add app "$HOME/workspace/app"
  run proj edit app desc "A shiny new app"

  run preview app
  assert_output --partial "A shiny new app"
}

@test "preview shows TODO when set" {
  mkdir -p "$HOME/workspace/app"
  run proj add app "$HOME/workspace/app"
  run proj edit app todo "- fix bug
- ship feature"

  run preview app
  assert_output --partial "fix bug"
  assert_output --partial "ship feature"
}

@test "preview respects PROJ_LANG=zh" {
  mkdir -p "$HOME/workspace/app"
  run proj add app "$HOME/workspace/app"
  run proj edit app desc "测试描述"

  PROJ_LANG=zh run preview app
  assert_success
  # "最后跟进" is the zh "Last updated" header — always present.
  # "描述" is the zh "Description" section header — present because desc is set.
  assert_output --partial "最后跟进"
  assert_output --partial "描述"
  assert_output --partial "测试描述"
}

@test "preview of unlinked project (no path.<mid> for this machine)" {
  # Simulate a project that was synced from another machine — it exists in
  # data/ but has no path file for the current machine-id.
  run proj --version  # generate machine-id
  mkdir -p "$(proj_data_dir)/foreign"
  echo "local" > "$(proj_data_dir)/foreign/type"
  echo "active" > "$(proj_data_dir)/foreign/status"
  echo "2026-04-13 10:00" > "$(proj_data_dir)/foreign/updated"
  # Deliberately no path.<mid> file
  touch "$(proj_data_dir)/foreign/desc" \
        "$(proj_data_dir)/foreign/progress" \
        "$(proj_data_dir)/foreign/todo"

  run preview foreign
  assert_success
  assert_output --partial "No local path"
}

@test "preview renders tag chips when tags file exists" {
  mkdir -p "$HOME/workspace/tagged"
  run proj add tagged "$HOME/workspace/tagged"
  run proj tag tagged work deploy
  assert_success

  run preview tagged
  assert_success
  assert_output --partial "Tags:"
  assert_output --partial "#deploy"
  assert_output --partial "#work"
}

@test "preview omits Tags line when no tags set" {
  mkdir -p "$HOME/workspace/untagged"
  run proj add untagged "$HOME/workspace/untagged"

  run preview untagged
  assert_success
  refute_output --partial "Tags:"
}

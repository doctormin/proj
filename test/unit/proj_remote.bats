#!/usr/bin/env bats
# proj add-remote: input validation (R22) + project file creation.
# Critical: this is the security boundary — malicious host/path strings must
# be rejected before any file write or SSH invocation.

load '../test_helper'

@test "add-remote creates project with type=remote and host/remote_path fields" {
  run proj add-remote api server.example.com:/srv/api
  assert_success

  assert_equal "$(proj_field api type)" "remote"
  assert_equal "$(proj_field api host)" "server.example.com"
  assert_equal "$(proj_field api remote_path)" "/srv/api"
  assert_equal "$(proj_field api status)" "active"
}

@test "add-remote accepts user@host format" {
  run proj add-remote api user@server.example.com:/srv/api
  assert_success
  assert_equal "$(proj_field api host)" "user@server.example.com"
}

@test "add-remote rejects host with semicolons" {
  run proj add-remote api "evil;rm -rf /":/srv
  assert_failure
  assert_output --partial "Invalid host"
  # No project file should exist
  assert [ ! -d "$(proj_data_dir)/api" ]
}

@test "add-remote rejects host with spaces" {
  run proj add-remote api "bad host":/srv
  assert_failure
  assert [ ! -d "$(proj_data_dir)/api" ]
}

@test "add-remote rejects host with pipes" {
  run proj add-remote api "host|evil":/srv
  assert_failure
  assert [ ! -d "$(proj_data_dir)/api" ]
}

@test "add-remote rejects host with backticks" {
  run proj add-remote api 'host`whoami`:/srv'
  assert_failure
  assert [ ! -d "$(proj_data_dir)/api" ]
}

@test "add-remote rejects path with command substitution dollar" {
  run proj add-remote api 'server:/srv/$(evil)'
  assert_failure
  assert_output --partial "Invalid path"
  assert [ ! -d "$(proj_data_dir)/api" ]
}

@test "add-remote rejects path with backticks" {
  run proj add-remote api 'server:/srv/`evil`'
  assert_failure
  assert_output --partial "Invalid path"
  assert [ ! -d "$(proj_data_dir)/api" ]
}

@test "add-remote rejects path with pipe metacharacter" {
  run proj add-remote api 'server:/srv|evil'
  assert_failure
  assert_output --partial "Invalid path"
  assert [ ! -d "$(proj_data_dir)/api" ]
}

@test "add-remote rejects path with semicolon" {
  run proj add-remote api 'server:/srv;evil'
  assert_failure
  assert_output --partial "Invalid path"
}

@test "add-remote rejects path with ampersand" {
  run proj add-remote api 'server:/srv&evil'
  assert_failure
  assert_output --partial "Invalid path"
}

@test "add-remote rejects path with single quote" {
  run proj add-remote api "server:/srv/it's-here"
  assert_failure
  assert_output --partial "Invalid path"
  assert [ ! -d "$(proj_data_dir)/api" ]
}

@test "add-remote rejects path with dot-dot traversal" {
  run proj add-remote api 'server:/srv/../etc/passwd'
  assert_failure
  assert_output --partial "Invalid path"
  assert [ ! -d "$(proj_data_dir)/api" ]
}

@test "add-remote rejects invalid format (no colon)" {
  run proj add-remote api servernoColon
  assert_failure
}

@test "add-remote rejects missing path after colon" {
  run proj add-remote api "server:"
  assert_failure
}

@test "add-remote rejects empty arguments" {
  run proj add-remote
  assert_failure
  assert_output --partial "Usage"
}

@test "add-remote rejects duplicate name" {
  run proj add-remote api1 server.example.com:/srv/one
  assert_success

  run proj add-remote api1 other.example.com:/srv/two
  assert_failure
}

@test "add-remote does not trigger Claude scan" {
  # Remote projects should not auto-scan (no local path to read).
  # desc/progress/todo should remain empty after add-remote.
  run proj add-remote api server.example.com:/srv/api
  assert_success

  [ -z "$(proj_field api desc)" ]
  [ -z "$(proj_field api progress)" ]
  [ -z "$(proj_field api todo)" ]
}

# ── Reachability pre-flight tests ──

@test "add-remote runs ssh pre-flight and succeeds when host + path exist" {
  run proj add-remote api server.example.com:/srv/api
  assert_success
  assert_output --partial "SSH"
  assert_output --partial "Remote path exists"
  assert_equal "$(proj_field api type)" "remote"
}

@test "add-remote fails when ssh connectivity check fails" {
  export SSH_MOCK_EXIT=1
  run proj add-remote api server.example.com:/srv/api
  assert_failure
  assert_output --partial "Cannot connect"
  # No project data should be written.
  assert [ ! -d "$(proj_data_dir)/api" ]
}

@test "add-remote fails when remote path does not exist" {
  export SSH_MOCK_DIR_EXIT=1
  run proj add-remote api server.example.com:/srv/missing
  assert_failure
  assert_output --partial "path does not exist"
  assert [ ! -d "$(proj_data_dir)/api" ]
}

@test "add-remote --skip-check bypasses ssh pre-flight" {
  export SSH_MOCK_EXIT=1
  run proj add-remote api server.example.com:/srv/api --skip-check
  assert_success
  assert_output --partial "skipping"
  assert_equal "$(proj_field api type)" "remote"
}

@test "add-remote --skip-check works in any arg position" {
  export SSH_MOCK_EXIT=1
  run proj add-remote --skip-check api server.example.com:/srv/api
  assert_success
  assert_equal "$(proj_field api type)" "remote"
}

@test "add-remote pre-flight logs ssh calls" {
  export SSH_CALLS_LOG="$HOME/ssh-calls.log"
  : > "$SSH_CALLS_LOG"
  run proj add-remote api server.example.com:/srv/api
  assert_success
  # The mock ssh logs all calls. We expect the connectivity check.
  assert [ -f "$SSH_CALLS_LOG" ]
  run grep "true" "$SSH_CALLS_LOG"
  assert_success
}

#!/usr/bin/env bats
# Tests for bin/proj — the Meta Session bash shim (Phase 2d Unit D1).
#
# The shim is a bash script (not zsh!) that Claude Code invokes via its
# Bash tool inside `proj meta`. These tests exercise it directly.
#
# Test confirm strategy: the shim honors PROJ_SHIM_CONFIRM as an override
# for the `read </dev/tty` prompt when the env var is non-empty. This is
# the only test hook; real Meta Session use is unaffected.

load '../test_helper'

SHIM="$PROJ_ROOT/bin/proj"
# Override the shim's "which proj.zsh to source" hook so writes delegate
# into the in-repo proj.zsh (tests don't run install.sh, so $HOME/.proj/
# proj.zsh doesn't exist).
export PROJ_SHIM_ZSH="$PROJ_ROOT/proj.zsh"

# Create a project via the real zsh plugin so machine-id routing, history
# log, etc. all get initialized correctly.
setup_project() {
  local name="$1"
  mkdir -p "$HOME/workspace/$name"
  proj add "$name" "$HOME/workspace/$name" >/dev/null
}

@test "shim with no args prints usage and exits 1" {
  run "$SHIM"
  assert_failure
  assert_output --partial "Meta Session bash shim"
  assert_output --partial "proj list"
}

@test "shim list with no projects prints nothing" {
  run proj --version   # boot ~/.proj
  run "$SHIM" list
  assert_success
  assert_output ""
}

@test "shim list prints project names one per line" {
  setup_project alpha
  setup_project beta
  run "$SHIM" list
  assert_success
  assert_line "alpha"
  assert_line "beta"
}

@test "shim get <name> <allowed-field> prints file content" {
  setup_project alpha
  run "$SHIM" get alpha status
  assert_success
  assert_output "active"
}

@test "shim get rejects the path field (not in allowlist)" {
  setup_project alpha
  run "$SHIM" get alpha path
  assert_failure
  assert_output --partial "field not allowed: path"
}

@test "shim get rejects path.<machine-id> explicitly" {
  setup_project alpha
  local mid; mid="$(machine_id)"
  run "$SHIM" get alpha "path.$mid"
  assert_failure
  assert_output --partial "field not allowed"
}

@test "shim history on project with no history prints (no history)" {
  setup_project alpha
  run "$SHIM" history alpha
  assert_success
  assert_output --partial "no history"
}

@test "shim history --all works" {
  setup_project alpha
  PROJ_SHIM_CONFIRM=y run "$SHIM" status alpha paused
  assert_success
  run "$SHIM" history alpha --all
  assert_success
  assert_output --partial "status"
}

@test "shim status with confirm=y actually changes status" {
  setup_project alpha
  PROJ_SHIM_CONFIRM=y run "$SHIM" status alpha done
  assert_success
  assert_equal "$(proj_field alpha status)" "done"
}

@test "shim status with confirm=n does NOT change status" {
  setup_project alpha
  PROJ_SHIM_CONFIRM=n run "$SHIM" status alpha done
  assert_failure
  assert_output --partial "Cancelled"
  assert_equal "$(proj_field alpha status)" "active"
}

@test "shim refuses 'rm' with restricted-command error" {
  run "$SHIM" rm alpha
  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial "restricted command: rm"
  assert_output --partial "Allowed reads"
  assert_output --partial "Allowed writes"
}

@test "shim refuses 'sync'" {
  run "$SHIM" sync
  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial "restricted command: sync"
}

@test "shim refuses unknown command 'nonsense'" {
  run "$SHIM" nonsense
  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial "restricted command: nonsense"
}

@test "shim rejects path traversal in project name" {
  run "$SHIM" status "../../etc/passwd" done
  assert_failure
  assert_output --partial "invalid project name"
}

@test "shim rejects invalid status value" {
  setup_project alpha
  PROJ_SHIM_CONFIRM=y run "$SHIM" status alpha invalid-status
  assert_failure
  assert_output --partial "invalid status"
}

@test "shim edit rejects path field" {
  setup_project alpha
  PROJ_SHIM_CONFIRM=y run "$SHIM" edit alpha path /tmp/evil
  assert_failure
  assert_output --partial "field not allowed: path"
}

@test "shim edit rejects status field (use proj status instead)" {
  setup_project alpha
  PROJ_SHIM_CONFIRM=y run "$SHIM" edit alpha status done
  assert_failure
  assert_output --partial "proj status"
}

@test "shim edit desc with confirm=y updates desc" {
  setup_project alpha
  PROJ_SHIM_CONFIRM=y run "$SHIM" edit alpha desc "hello world"
  assert_success
  assert_equal "$(proj_field alpha desc)" "hello world"
}

@test "shim tag rejects shell-metachar tag" {
  setup_project alpha
  PROJ_SHIM_CONFIRM=y run "$SHIM" tag alpha "; rm -rf /"
  assert_failure
  assert_output --partial "invalid tag"
}

@test "shim tag with valid tag and confirm=y succeeds" {
  setup_project alpha
  PROJ_SHIM_CONFIRM=y run "$SHIM" tag alpha work urgent
  assert_success
  run "$SHIM" get alpha tags
  assert_success
  assert_output --partial "work"
  assert_output --partial "urgent"
}

@test "shim untag with confirm=y removes tag" {
  setup_project alpha
  PROJ_SHIM_CONFIRM=y run "$SHIM" tag alpha work
  assert_success
  PROJ_SHIM_CONFIRM=y run "$SHIM" untag alpha work
  assert_success
  run "$SHIM" get alpha tags
  assert_success
  refute_output --partial "work"
}

@test "shim rejects name starting with dash" {
  run "$SHIM" status "-foo" done
  assert_failure
  assert_output --partial "invalid project name"
}

@test "shim get on nonexistent project fails clearly" {
  run "$SHIM" get doesnotexist desc
  assert_failure
  assert_output --partial "no such project"
}

@test "shim help prints usage and exits 0" {
  run "$SHIM" --help
  assert_success
  assert_output --partial "Meta Session bash shim"
}

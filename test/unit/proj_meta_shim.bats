#!/usr/bin/env bats
# Tests for bin/proj — the Meta Session bash shim (Phase 2d Unit D1).
#
# The shim is a bash script (not zsh!) that Claude Code invokes via its
# Bash tool inside `proj meta`. These tests exercise it directly.
#
# Test confirm strategy: the shim honors PROJ_SHIM_CONFIRM ONLY when
# PROJ_SHIM_TEST_MODE=1 is also set. This double-gate is what blocks the
# round-1 P0 (a prompt-injected `PROJ_SHIM_CONFIRM=y` prefix would not
# bypass /dev/tty in real Meta Session). Tests therefore set both env
# vars on every write-path invocation. PROJ_SHIM_ZSH (override of the
# proj.zsh source path) is similarly gated on PROJ_SHIM_TEST_MODE.

load '../test_helper'

SHIM="$PROJ_ROOT/bin/proj"
# Override the shim's "which proj.zsh to source" hook so writes delegate
# into the in-repo proj.zsh (tests don't run install.sh, so $HOME/.proj/
# proj.zsh doesn't exist). Both env vars are required for the shim to
# honor either one — see the security comment above.
export PROJ_SHIM_ZSH="$PROJ_ROOT/proj.zsh"
export PROJ_SHIM_TEST_MODE=1

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

# ── Round-1 P0/P2 regression coverage ────────────────────────────────────

@test "PROJ_SHIM_CONFIRM alone (no TEST_MODE) does NOT bypass /dev/tty" {
  setup_project alpha
  # Drop the test-mode sentinel and feed an empty stdin to the read.
  # Without /dev/tty available, the read returns failure and confirm
  # treats it as a No → Cancelled, status unchanged.
  PROJ_SHIM_TEST_MODE="" PROJ_SHIM_CONFIRM=y run bash -c \
    'exec </dev/null; "$0" status alpha done' "$SHIM"
  assert_failure
  assert_equal "$(proj_field alpha status)" "active"
}

@test "PROJ_SHIM_ZSH alone (no TEST_MODE) is ignored — falls back to PROJ_HOME" {
  setup_project alpha
  # Point the override at a bogus path; without TEST_MODE the shim must
  # ignore it. Since $HOME/.proj/proj.zsh also doesn't exist in tests,
  # delegation will fail (proj.zsh not found) — but crucially with the
  # default path, NOT the attacker-controlled one.
  PROJ_SHIM_TEST_MODE="" PROJ_SHIM_ZSH=/tmp/definitely-not-a-script.zsh \
    PROJ_SHIM_CONFIRM=y run "$SHIM" status alpha done
  assert_failure
  # Error references the default $PROJ_HOME path, never /tmp/...
  refute_output --partial "/tmp/definitely-not-a-script.zsh"
}

@test "shim edit refuses 'updated' field (auto-managed)" {
  setup_project alpha
  run "$SHIM" edit alpha updated "2099-01-01 00:00"
  assert_failure
  assert_output --partial "managed automatically"
}

@test "shim get tags returns space-joined single line" {
  setup_project alpha
  PROJ_SHIM_CONFIRM=y run "$SHIM" tag alpha work urgent backend
  assert_success
  run "$SHIM" get alpha tags
  assert_success
  # Exactly one output line, space-joined (proj.zsh stores tags sorted)
  [ "${#lines[@]}" -eq 1 ]
  assert_output "backend urgent work"
}

@test "shim history delegates to zsh and shows formatted output" {
  setup_project alpha
  PROJ_SHIM_CONFIRM=y run "$SHIM" status alpha paused
  assert_success
  PROJ_SHIM_CONFIRM=y run "$SHIM" status alpha done
  assert_success
  run "$SHIM" history alpha
  assert_success
  # Delegated output goes through _proj_history's formatter; the status
  # change should appear in the rendered timeline.
  assert_output --partial "status"
}

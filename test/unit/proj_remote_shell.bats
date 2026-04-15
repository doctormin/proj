#!/usr/bin/env bats
# Tests for the remote_shell resolution chain + auto-detect (Phase 2e
# E1 follow-up). Covers:
#   - _proj_resolve_remote_shell precedence (env > field > config > default)
#   - _proj_valid_remote_shell accept/reject
#   - auto-detection at `proj add-remote` for bash/zsh/fish/unknown
#   - per-project edit via `proj edit foo remote_shell ...`
#   - global config via `proj config remote_shell ...`
#   - bin/proj Meta Session shim allowlist coverage

load '../test_helper'

SHIM="$PROJ_ROOT/bin/proj"
export PROJ_SHIM_ZSH="$PROJ_ROOT/proj.zsh"
export PROJ_SHIM_TEST_MODE=1

setup_rs() {
  setup
  export SSH_CALLS_LOG="$HOME/ssh-calls.log"
  : > "$SSH_CALLS_LOG"
}

# Build a remote project directly on disk (no ssh detect) so resolver
# tests can set fields one at a time without detection noise.
_mk_remote() {
  local name="${1:-srv-a}"
  proj list >/dev/null
  mkdir -p "$HOME/.proj/data/$name"
  echo "remote"          > "$HOME/.proj/data/$name/type"
  echo "active"          > "$HOME/.proj/data/$name/status"
  echo "user@ai4s"       > "$HOME/.proj/data/$name/host"
  echo "/srv/proj"       > "$HOME/.proj/data/$name/remote_path"
  echo "2026-01-01 00:00" > "$HOME/.proj/data/$name/updated"
}

# ── resolution chain ─────────────────────────────────────────────────────

@test "resolve: default wrapper is bash -lc when all layers empty" {
  setup_rs
  _mk_remote srv-a
  run proj cc srv-a
  assert_success
  [[ "$(cat "$SSH_CALLS_LOG")" == *"bash -lc"* ]] || false
}

@test "resolve: env var PROJ_REMOTE_SHELL wins over per-project field" {
  setup_rs
  _mk_remote srv-a
  echo "fish -ic" > "$HOME/.proj/data/srv-a/remote_shell"
  PROJ_REMOTE_SHELL="zsh -ic" run proj cc srv-a
  assert_success
  local logged; logged="$(cat "$SSH_CALLS_LOG")"
  [[ "$logged" == *"zsh -ic"* ]] || false
  [[ "$logged" != *"fish -ic"* ]] || false
  [[ "$logged" != *"bash -lc"* ]] || false
}

@test "resolve: per-project field wins over global config" {
  setup_rs
  _mk_remote srv-a
  mkdir -p "$HOME/.proj"
  echo "remote_shell=bash -lc" > "$HOME/.proj/config"
  echo "zsh -ic" > "$HOME/.proj/data/srv-a/remote_shell"
  run proj cc srv-a
  assert_success
  local logged; logged="$(cat "$SSH_CALLS_LOG")"
  [[ "$logged" == *"zsh -ic"* ]] || false
}

@test "resolve: global config picked up when per-project field is empty" {
  setup_rs
  _mk_remote srv-a
  mkdir -p "$HOME/.proj"
  echo "remote_shell=fish -ic" > "$HOME/.proj/config"
  run proj cc srv-a
  assert_success
  [[ "$(cat "$SSH_CALLS_LOG")" == *"fish -ic"* ]] || false
}

@test "resolve: invalid value in per-project field triggers remote_bad_shell" {
  setup_rs
  _mk_remote srv-a
  printf '%s' 'bash -lc "; evil"' > "$HOME/.proj/data/srv-a/remote_shell"
  run proj cc srv-a
  assert_failure
  assert_output --partial "unsafe characters"
}

@test "resolve: invalid value in global config triggers remote_bad_shell" {
  setup_rs
  _mk_remote srv-a
  mkdir -p "$HOME/.proj"
  echo 'remote_shell=bash | evil' > "$HOME/.proj/config"
  run proj cc srv-a
  assert_failure
  assert_output --partial "unsafe characters"
}

# ── _proj_valid_remote_shell accepts / rejects ───────────────────────────

_validate_rs() {
  zsh -c 'source "$1" && _proj_valid_remote_shell "$2"' _ "$PROJ_ROOT/proj.zsh" "$1"
}

@test "validator accepts common shell wrappers" {
  setup_rs
  _validate_rs 'bash -lc'
  _validate_rs 'zsh -ic'
  _validate_rs 'fish -ic'
  _validate_rs '/usr/bin/env bash -lc'
  _validate_rs '/bin/bash -lc'
}

@test "validator rejects shell metacharacters" {
  setup_rs
  ! _validate_rs 'bash;evil'
  ! _validate_rs 'bash|evil'
  ! _validate_rs 'bash$(evil)'
  ! _validate_rs 'bash`evil`'
  ! _validate_rs 'bash -lc
evil'
  ! _validate_rs 'bash -lc "echo"'
}

# ── auto-detect at add-remote ────────────────────────────────────────────

@test "auto-detect: /bin/zsh writes zsh -ic to per-project field" {
  setup_rs
  SSH_MOCK_DETECT_SHELL=/bin/zsh run proj add-remote srv-a user@ai4s:/srv/proj
  assert_success
  assert_equal "$(proj_field srv-a remote_shell)" "zsh -ic"
  assert_output --partial "zsh -ic"
}

@test "auto-detect: /usr/bin/bash writes bash -lc" {
  setup_rs
  SSH_MOCK_DETECT_SHELL=/usr/bin/bash run proj add-remote srv-a user@ai4s:/srv/proj
  assert_success
  assert_equal "$(proj_field srv-a remote_shell)" "bash -lc"
}

@test "auto-detect: /usr/local/bin/fish writes fish -ic" {
  setup_rs
  SSH_MOCK_DETECT_SHELL=/usr/local/bin/fish run proj add-remote srv-a user@ai4s:/srv/proj
  assert_success
  assert_equal "$(proj_field srv-a remote_shell)" "fish -ic"
}

@test "auto-detect: unknown shell (/bin/dash) leaves field empty" {
  setup_rs
  SSH_MOCK_DETECT_SHELL=/bin/dash run proj add-remote srv-a user@ai4s:/srv/proj
  assert_success
  [ ! -f "$HOME/.proj/data/srv-a/remote_shell" ]
}

@test "auto-detect: ssh failure leaves field empty, add-remote still succeeds" {
  setup_rs
  SSH_MOCK_DETECT_EXIT=255 run proj add-remote srv-a user@ai4s:/srv/proj
  assert_success
  [ ! -f "$HOME/.proj/data/srv-a/remote_shell" ]
  # host/remote_path still written
  assert_equal "$(proj_field srv-a host)" "user@ai4s"
  assert_equal "$(proj_field srv-a remote_path)" "/srv/proj"
}

@test "auto-detect: empty detected output leaves field empty" {
  setup_rs
  # SSH_MOCK_DETECT_SHELL unset → empty stdout
  run proj add-remote srv-a user@ai4s:/srv/proj
  assert_success
  [ ! -f "$HOME/.proj/data/srv-a/remote_shell" ]
}

@test "auto-detect: does not clobber pre-existing per-project field" {
  setup_rs
  # Pre-seed the field BEFORE add-remote runs. Only possible via direct
  # write here, but the invariant matters for re-runs / restores.
  proj list >/dev/null
  mkdir -p "$HOME/.proj/data/srv-a"
  echo "fish -ic" > "$HOME/.proj/data/srv-a/remote_shell"
  # Auto-detect would normally pick zsh -ic; ensure it's NOT overwritten.
  SSH_MOCK_DETECT_SHELL=/bin/zsh run proj add-remote srv-a user@ai4s:/srv/proj
  assert_failure  # pre-existing project dir makes add-remote error out
  assert_equal "$(proj_field srv-a remote_shell)" "fish -ic"
}

# ── per-project edit ─────────────────────────────────────────────────────

@test "edit: proj edit foo remote_shell 'zsh -ic' updates the field" {
  setup_rs
  _mk_remote srv-a
  run proj edit srv-a remote_shell "zsh -ic"
  assert_success
  assert_equal "$(proj_field srv-a remote_shell)" "zsh -ic"
}

@test "edit: proj edit foo remote_shell '; evil' rejected" {
  setup_rs
  _mk_remote srv-a
  run proj edit srv-a remote_shell "; evil"
  assert_failure
  assert_output --partial "unsafe characters"
  [ ! -f "$HOME/.proj/data/srv-a/remote_shell" ]
}

@test "edit: proj edit foo remote_shell '' clears the field" {
  setup_rs
  _mk_remote srv-a
  echo "zsh -ic" > "$HOME/.proj/data/srv-a/remote_shell"
  run proj edit srv-a remote_shell ""
  assert_success
  [ ! -f "$HOME/.proj/data/srv-a/remote_shell" ]
}

# ── global config ────────────────────────────────────────────────────────

@test "config: proj config remote_shell 'zsh -ic' persists to ~/.proj/config" {
  setup_rs
  proj list >/dev/null
  run proj config remote_shell "zsh -ic"
  assert_success
  grep -q '^remote_shell=zsh -ic$' "$HOME/.proj/config"
}

@test "config: proj config remote_shell (read) prints current value" {
  setup_rs
  proj list >/dev/null
  proj config remote_shell "zsh -ic" >/dev/null
  run proj config remote_shell
  assert_success
  assert_output --partial "zsh -ic"
}

@test "config: proj config remote_shell rejects unsafe value" {
  setup_rs
  proj list >/dev/null
  run proj config remote_shell 'bash; evil'
  assert_failure
  assert_output --partial "unsafe characters"
  ! grep -q '^remote_shell=' "$HOME/.proj/config" 2>/dev/null
}

@test "config: global value flows into proj cc for a project with no per-project field" {
  setup_rs
  _mk_remote srv-a
  proj config remote_shell "fish -ic" >/dev/null
  run proj cc srv-a
  assert_success
  [[ "$(cat "$SSH_CALLS_LOG")" == *"fish -ic"* ]] || false
}

# ── bin/proj Meta Session shim ───────────────────────────────────────────

@test "shim: get <name> remote_shell returns the value" {
  setup_rs
  _mk_remote srv-a
  echo "zsh -ic" > "$HOME/.proj/data/srv-a/remote_shell"
  run "$SHIM" get srv-a remote_shell
  assert_success
  assert_output "zsh -ic"
}

@test "shim: edit <name> remote_shell 'zsh -ic' with confirm works" {
  setup_rs
  _mk_remote srv-a
  PROJ_SHIM_CONFIRM=y run "$SHIM" edit srv-a remote_shell "zsh -ic"
  assert_success
  assert_equal "$(proj_field srv-a remote_shell)" "zsh -ic"
}

@test "shim: edit <name> remote_shell '; evil' rejected at shim layer" {
  setup_rs
  _mk_remote srv-a
  PROJ_SHIM_CONFIRM=y run "$SHIM" edit srv-a remote_shell "; evil"
  assert_failure
  assert_output --partial "unsafe characters"
  [ ! -f "$HOME/.proj/data/srv-a/remote_shell" ]
}

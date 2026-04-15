#!/usr/bin/env bats
# Tests for `proj cc <remote-name>` — running claude -c on a remote host
# over ssh -t. Uses a mock ssh binary in fixtures/bin that logs argv to
# $SSH_CALLS_LOG so tests can assert the exact command string proj emits.

load '../test_helper'

setup_cc() {
  setup
  export SSH_CALLS_LOG="$HOME/ssh-calls.log"
  : > "$SSH_CALLS_LOG"
}

_add_remote_project() {
  local name="$1" host="${2:-user@ai4s}" rpath="${3:-/srv/proj}"
  proj list >/dev/null  # trigger schema init
  mkdir -p "$HOME/.proj/data/$name"
  echo "remote" > "$HOME/.proj/data/$name/type"
  echo "active" > "$HOME/.proj/data/$name/status"
  echo "$host" > "$HOME/.proj/data/$name/host"
  echo "$rpath" > "$HOME/.proj/data/$name/remote_path"
  echo "2026-01-01 00:00" > "$HOME/.proj/data/$name/updated"
}

# ── happy paths ──────────────────────────────────────────────────────────

@test "proj cc <remote>: invokes ssh -t with the configured host" {
  setup_cc
  _add_remote_project srv-a user@ai4s /srv/proj
  run proj cc srv-a
  assert_success
  [ -s "$SSH_CALLS_LOG" ]
  local logged; logged="$(cat "$SSH_CALLS_LOG")"
  [[ "$logged" == *"-t"* ]] || false
  [[ "$logged" == *"user@ai4s"* ]] || false
}

@test "proj cc <remote>: cd's into remote_path and runs claude -c" {
  setup_cc
  _add_remote_project srv-a user@ai4s /srv/proj
  run proj cc srv-a
  assert_success
  local logged; logged="$(cat "$SSH_CALLS_LOG")"
  # zsh (qq) wraps the path so it reaches the remote as `cd -- '/srv/proj'`.
  [[ "$logged" == *"cd --"* ]] || false
  [[ "$logged" == *"/srv/proj"* ]] || false
  [[ "$logged" == *"claude -c"* ]] || false
}

@test "proj cc <remote>: default wrapper is bash -lc" {
  setup_cc
  _add_remote_project srv-a
  run proj cc srv-a
  assert_success
  [[ "$(cat "$SSH_CALLS_LOG")" == *"bash -lc"* ]] || false
}

@test "proj cc <remote>: PROJ_REMOTE_SHELL overrides the wrapper" {
  setup_cc
  _add_remote_project srv-a
  PROJ_REMOTE_SHELL="zsh -ic" run proj cc srv-a
  assert_success
  local logged; logged="$(cat "$SSH_CALLS_LOG")"
  [[ "$logged" == *"zsh -ic"* ]] || false
  [[ "$logged" != *"bash -lc"* ]] || false
}

@test "proj cc <remote>: uses exec so claude takes the foreground" {
  setup_cc
  _add_remote_project srv-a
  run proj cc srv-a
  assert_success
  [[ "$(cat "$SSH_CALLS_LOG")" == *"exec claude -c"* ]] || false
}

@test "proj cc <remote>: probes session dir and falls back to fresh claude" {
  # Regression: the original implementation hard-coded `exec claude -c`,
  # which aborts immediately on a freshly added remote project because no
  # ~/.claude/projects/<encoded-cwd>/ session exists yet ("No conversation
  # found to continue"). The remote command must mirror the local
  # _proj_resume_claude branch: probe the encoded session dir and exec
  # `claude -c` only when a *.jsonl session file exists, else exec a
  # fresh `claude`.
  setup_cc
  _add_remote_project srv-a user@ai4s /srv/proj
  run proj cc srv-a
  assert_success
  local logged; logged="$(cat "$SSH_CALLS_LOG")"
  # Probe construction
  [[ "$logged" == *".claude/projects/"* ]] || false
  [[ "$logged" == *"tr / -"* ]] || false
  [[ "$logged" == *"*.jsonl"* ]] || false
  # Both branches present
  [[ "$logged" == *"exec claude -c"* ]] || false
  [[ "$logged" == *"else exec claude"* ]] || false
}

@test "proj cc <remote>: escapes remote_path containing spaces" {
  setup_cc
  _add_remote_project srv-a user@ai4s "/srv/my project"
  run proj cc srv-a
  assert_success
  local logged; logged="$(cat "$SSH_CALLS_LOG")"
  # Path is wrapped in single quotes via zsh (qq).
  [[ "$logged" == *"'/srv/my project'"* ]] || false
}

@test "proj cc <remote>: bumps updated timestamp" {
  setup_cc
  _add_remote_project srv-a
  echo "2020-01-01 00:00" > "$HOME/.proj/data/srv-a/updated"
  run proj cc srv-a
  assert_success
  local after; after="$(proj_field srv-a updated)"
  [ "$after" != "2020-01-01 00:00" ]
}

@test "proj cc <remote>: prints connecting banner with host and path" {
  setup_cc
  _add_remote_project srv-a user@ai4s /srv/proj
  run proj cc srv-a
  assert_output --partial "user@ai4s"
  assert_output --partial "/srv/proj"
}

# ── error paths ──────────────────────────────────────────────────────────

@test "proj cc <remote>: missing host errors out" {
  setup_cc
  proj list >/dev/null
  mkdir -p "$HOME/.proj/data/srv-broken"
  echo "remote" > "$HOME/.proj/data/srv-broken/type"
  echo "active" > "$HOME/.proj/data/srv-broken/status"
  echo "/srv/proj" > "$HOME/.proj/data/srv-broken/remote_path"
  # no host file
  run proj cc srv-broken
  assert_failure
  assert_output --partial "no host"
  [ ! -s "$SSH_CALLS_LOG" ]
}

@test "proj cc <remote>: missing remote_path errors out" {
  setup_cc
  proj list >/dev/null
  mkdir -p "$HOME/.proj/data/srv-broken"
  echo "remote" > "$HOME/.proj/data/srv-broken/type"
  echo "active" > "$HOME/.proj/data/srv-broken/status"
  echo "user@host" > "$HOME/.proj/data/srv-broken/host"
  run proj cc srv-broken
  assert_failure
  [ ! -s "$SSH_CALLS_LOG" ]
}

@test "proj cc <remote>: ssh nonzero exit is propagated" {
  setup_cc
  _add_remote_project srv-a
  SSH_MOCK_EXIT=42 run proj cc srv-a
  assert_equal "$status" "42"
}

# ── local projects still take the local path ───────────────────────────

@test "proj cc <local>: does not invoke ssh" {
  setup_cc
  mkdir -p "$HOME/workspace/localp"
  proj add localp "$HOME/workspace/localp" >/dev/null
  run proj cc localp
  # Local path normally exits successfully via mock claude. We only
  # care that the ssh mock was NOT hit.
  [ ! -s "$SSH_CALLS_LOG" ]
}

# ── regression coverage from round 1 review ─────────────────────────────

@test "proj cc <remote>: ssh invoked with '--' separator before host" {
  setup_cc
  _add_remote_project srv-a user@ai4s /srv/proj
  run proj cc srv-a
  assert_success
  # '--' must appear before the host to defuse -oProxyCommand-style
  # injection via a hand-edited or imported host field.
  [[ "$(cat "$SSH_CALLS_LOG")" == *"-t -- user@ai4s"* ]] || false
}

@test "proj cc <remote>: remote_path with \$ is not expanded on remote" {
  setup_cc
  _add_remote_project srv-a user@ai4s '/srv/a$b/project'
  run proj cc srv-a
  assert_success
  local logged; logged="$(cat "$SSH_CALLS_LOG")"
  # The literal $b must appear inside outer single quotes so the remote
  # sh cannot re-expand it.
  [[ "$logged" == *"'/srv/a\$b/project'"* ]] || false
  # And must NOT appear unquoted in a way that would let remote sh see $b.
  [[ "$logged" != *"cd /srv/a "* ]] || false
}

@test "proj cc <remote>: remote_path with backtick is not command-substituted" {
  setup_cc
  _add_remote_project srv-a user@ai4s '/srv/bt`evil`'
  run proj cc srv-a
  assert_success
  local logged; logged="$(cat "$SSH_CALLS_LOG")"
  # Backticks are present, but inside the outer single quotes they are
  # literal — they cannot trigger remote command substitution.
  [[ "$logged" == *'`evil`'* ]] || false
  [[ "$logged" == *"'/srv/bt"* ]] || false
}

@test "proj cc <remote>: remote_path with single quote is escaped via '\\\\''" {
  setup_cc
  _add_remote_project srv-a user@ai4s "/srv/it's"
  run proj cc srv-a
  assert_success
  # zsh (qq) uses the classic '\'' escape inside a single-quoted block.
  [[ "$(cat "$SSH_CALLS_LOG")" == *"'\\'\\''"* ]] || false
}

@test "proj cc <remote>: PROJ_REMOTE_SHELL with quoting metacharacters is refused" {
  setup_cc
  _add_remote_project srv-a
  PROJ_REMOTE_SHELL='bash -lc "echo pwned;' run proj cc srv-a
  assert_failure
  assert_output --partial "unsafe characters"
  [ ! -s "$SSH_CALLS_LOG" ]
}

@test "proj cc <remote>: missing-fields error message includes the project name" {
  setup_cc
  proj list >/dev/null
  mkdir -p "$HOME/.proj/data/srv-broken"
  echo "remote" > "$HOME/.proj/data/srv-broken/type"
  echo "active" > "$HOME/.proj/data/srv-broken/status"
  # no host, no remote_path
  run proj cc srv-broken
  assert_failure
  # Name must appear literally (not be swallowed by a %s/arg-count mismatch).
  assert_output --partial "'srv-broken'"
  assert_output --partial "proj edit srv-broken"
}

@test "proj cc <remote>: type file with trailing CR still routes to remote" {
  setup_cc
  _add_remote_project srv-a user@ai4s /srv/proj
  # Simulate a cross-machine-synced file with a Windows-style CRLF.
  printf 'remote\r\n' > "$HOME/.proj/data/srv-a/type"
  run proj cc srv-a
  assert_success
  [ -s "$SSH_CALLS_LOG" ]
}

@test "proj cc (no arg): does not silently auto-select a remote project" {
  setup_cc
  _add_remote_project srv-remote user@ai4s /srv/proj
  cd "$HOME"   # cwd does not match any project
  run proj cc
  # Must NOT have invoked ssh against the remote just because its empty
  # path field produced a wildcard prefix match.
  [ ! -s "$SSH_CALLS_LOG" ]
}

@test "proj cc (no arg): local cwd match is preferred over any remote" {
  setup_cc
  _add_remote_project srv-remote user@ai4s /srv/proj
  mkdir -p "$HOME/workspace/localp"
  proj add localp "$HOME/workspace/localp" >/dev/null
  cd "$HOME/workspace/localp"
  run proj cc
  # Auto-detect picked the local project, no ssh.
  [ ! -s "$SSH_CALLS_LOG" ]
}

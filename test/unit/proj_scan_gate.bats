#!/usr/bin/env bats
# proj add / proj scan — scan-gate (token burn protection).
#
# Tests _proj_dev_markers + _proj_assess_scan_size + _proj_scan_gated +
# the new flags --no-scan / -y / --force-scan on `proj add` and `proj scan`.
#
# Threshold env vars:
#   PROJ_SCAN_PROMPT_THRESHOLD  (default 500)   — below = always safe
#   PROJ_SCAN_HUGE_THRESHOLD    (default 10000) — at or above = huge
# Tests set them to small values (e.g. 5 / 10) so a few touched files
# trigger the medium / huge branches without creating thousands of files.

load '../test_helper'

# ── _proj_dev_markers helper ──────────────────────────────────────────────

@test "_proj_dev_markers: returns 1 on empty directory" {
  mkdir -p "$HOME/empty"
  run zsh -c 'source "$1" && _proj_dev_markers "$2"' _ "$PROJ_ROOT/proj.zsh" "$HOME/empty"
  assert_failure
}

@test "_proj_dev_markers: returns 0 when .git directory exists" {
  mkdir -p "$HOME/proj/.git"
  run zsh -c 'source "$1" && _proj_dev_markers "$2"' _ "$PROJ_ROOT/proj.zsh" "$HOME/proj"
  assert_success
}

@test "_proj_dev_markers: returns 0 when package.json exists" {
  mkdir -p "$HOME/node-app"
  echo '{}' > "$HOME/node-app/package.json"
  run zsh -c 'source "$1" && _proj_dev_markers "$2"' _ "$PROJ_ROOT/proj.zsh" "$HOME/node-app"
  assert_success
}

@test "_proj_dev_markers: returns 0 when pyproject.toml exists" {
  mkdir -p "$HOME/py-app"
  : > "$HOME/py-app/pyproject.toml"
  run zsh -c 'source "$1" && _proj_dev_markers "$2"' _ "$PROJ_ROOT/proj.zsh" "$HOME/py-app"
  assert_success
}

@test "_proj_dev_markers: returns 0 when Cargo.toml exists" {
  mkdir -p "$HOME/rust-app"
  : > "$HOME/rust-app/Cargo.toml"
  run zsh -c 'source "$1" && _proj_dev_markers "$2"' _ "$PROJ_ROOT/proj.zsh" "$HOME/rust-app"
  assert_success
}

@test "_proj_dev_markers: returns 0 when go.mod exists" {
  mkdir -p "$HOME/go-app"
  : > "$HOME/go-app/go.mod"
  run zsh -c 'source "$1" && _proj_dev_markers "$2"' _ "$PROJ_ROOT/proj.zsh" "$HOME/go-app"
  assert_success
}

@test "_proj_dev_markers: returns 0 when README.md exists" {
  mkdir -p "$HOME/docs"
  : > "$HOME/docs/README.md"
  run zsh -c 'source "$1" && _proj_dev_markers "$2"' _ "$PROJ_ROOT/proj.zsh" "$HOME/docs"
  assert_success
}

@test "_proj_dev_markers: returns 0 for glob marker (.csproj)" {
  mkdir -p "$HOME/dotnet-app"
  : > "$HOME/dotnet-app/MyApp.csproj"
  run zsh -c 'source "$1" && _proj_dev_markers "$2"' _ "$PROJ_ROOT/proj.zsh" "$HOME/dotnet-app"
  assert_success
}

@test "_proj_dev_markers: returns 1 for downloads-style untyped dir" {
  mkdir -p "$HOME/dl"
  : > "$HOME/dl/random-photo.jpg"
  : > "$HOME/dl/notes.txt"
  run zsh -c 'source "$1" && _proj_dev_markers "$2"' _ "$PROJ_ROOT/proj.zsh" "$HOME/dl"
  assert_failure
}

# ── _proj_assess_scan_size helper ─────────────────────────────────────────

@test "_proj_assess_scan_size: small empty dir is safe" {
  mkdir -p "$HOME/x"
  run zsh -c 'source "$1" && _proj_assess_scan_size "$2"' _ "$PROJ_ROOT/proj.zsh" "$HOME/x"
  assert_success
  assert_output "safe|0"
}

@test "_proj_assess_scan_size: small dir with marker is safe" {
  mkdir -p "$HOME/foo"
  : > "$HOME/foo/package.json"
  : > "$HOME/foo/index.js"
  run zsh -c 'source "$1" && _proj_assess_scan_size "$2"' _ "$PROJ_ROOT/proj.zsh" "$HOME/foo"
  assert_success
  assert_output "safe|2"
}

@test "_proj_assess_scan_size: medium untyped dir needs confirm" {
  mkdir -p "$HOME/dl"
  for i in {1..6}; do : > "$HOME/dl/file$i.txt"; done
  PROJ_SCAN_PROMPT_THRESHOLD=5 PROJ_SCAN_HUGE_THRESHOLD=100 \
    run zsh -c 'source "$1" && _proj_assess_scan_size "$2"' _ "$PROJ_ROOT/proj.zsh" "$HOME/dl"
  assert_success
  assert_output "needs-confirm|6"
}

@test "_proj_assess_scan_size: medium dir WITH marker is safe even above prompt threshold" {
  mkdir -p "$HOME/realapp"
  : > "$HOME/realapp/package.json"
  for i in {1..6}; do : > "$HOME/realapp/src$i.js"; done
  PROJ_SCAN_PROMPT_THRESHOLD=5 PROJ_SCAN_HUGE_THRESHOLD=100 \
    run zsh -c 'source "$1" && _proj_assess_scan_size "$2"' _ "$PROJ_ROOT/proj.zsh" "$HOME/realapp"
  assert_success
  assert_output "safe|7"
}

@test "_proj_assess_scan_size: huge directory is refused" {
  mkdir -p "$HOME/huge"
  for i in {1..12}; do : > "$HOME/huge/file$i.txt"; done
  PROJ_SCAN_PROMPT_THRESHOLD=5 PROJ_SCAN_HUGE_THRESHOLD=10 \
    run zsh -c 'source "$1" && _proj_assess_scan_size "$2"' _ "$PROJ_ROOT/proj.zsh" "$HOME/huge"
  assert_success
  # Find -head caps at huge_t+1, so count is exactly huge_t+1
  assert_output "huge|11"
}

# ── proj add: --no-scan flag ──────────────────────────────────────────────

@test "proj add --no-scan: skips scan, prints --no-scan hint" {
  mkdir -p "$HOME/workspace/foo"
  : > "$HOME/workspace/foo/package.json"
  run proj add foo "$HOME/workspace/foo" --no-scan
  assert_success
  assert_output --partial "Added project"
  refute_output --partial "Scanning"
  assert_output --partial "--no-scan"
}

@test "proj add --no-scan: project still registered correctly" {
  mkdir -p "$HOME/workspace/foo"
  : > "$HOME/workspace/foo/package.json"
  proj add foo "$HOME/workspace/foo" --no-scan
  assert_equal "$(proj_field foo type)" "local"
  assert_equal "$(proj_field foo status)" "active"
}

# ── proj add: safe small dir auto-scans ────────────────────────────────────

@test "proj add: small dir with marker scans without prompt" {
  mkdir -p "$HOME/workspace/foo"
  : > "$HOME/workspace/foo/package.json"
  run proj add foo "$HOME/workspace/foo"
  assert_success
  assert_output --partial "Scanning"
  refute_output --partial "Continue scanning"
}

@test "proj add: tiny dir without marker still auto-scans (below prompt threshold)" {
  mkdir -p "$HOME/workspace/foo"
  : > "$HOME/workspace/foo/notes.txt"
  run proj add foo "$HOME/workspace/foo"
  assert_success
  assert_output --partial "Scanning"
  refute_output --partial "Continue scanning"
}

# ── proj add: needs-confirm (medium dir without marker) ───────────────────

@test "proj add: medium untyped dir prompts before scanning" {
  mkdir -p "$HOME/workspace/dl"
  for i in {1..6}; do : > "$HOME/workspace/dl/file$i.txt"; done
  # Decline the prompt with "n" piped via the proj bridge.
  export PROJ_SCAN_PROMPT_THRESHOLD=5
  export PROJ_SCAN_HUGE_THRESHOLD=100
  run bash -c 'echo n | "$@"' _ \
    zsh -c 'source "$1" && shift && proj "$@"' _proj_test "$PROJ_ROOT/proj.zsh" \
    add dl "$HOME/workspace/dl"
  unset PROJ_SCAN_PROMPT_THRESHOLD PROJ_SCAN_HUGE_THRESHOLD
  assert_success
  assert_output --partial "does not look like a development project"
  assert_output --partial "Continue scanning"
  assert_output --partial "Skipped scan"
  refute_output --partial "Scanning project with Claude"
}

@test "proj add -y: medium untyped dir is auto-confirmed" {
  mkdir -p "$HOME/workspace/dl"
  for i in {1..6}; do : > "$HOME/workspace/dl/file$i.txt"; done
  PROJ_SCAN_PROMPT_THRESHOLD=5 PROJ_SCAN_HUGE_THRESHOLD=100 \
    run proj add dl "$HOME/workspace/dl" -y
  assert_success
  assert_output --partial "Scanning project with Claude"
  refute_output --partial "Continue scanning"
}

@test "proj add: medium typed dir with marker auto-scans (no prompt)" {
  mkdir -p "$HOME/workspace/realapp"
  : > "$HOME/workspace/realapp/package.json"
  for i in {1..6}; do : > "$HOME/workspace/realapp/src$i.js"; done
  PROJ_SCAN_PROMPT_THRESHOLD=5 PROJ_SCAN_HUGE_THRESHOLD=100 \
    run proj add realapp "$HOME/workspace/realapp"
  assert_success
  assert_output --partial "Scanning project with Claude"
  refute_output --partial "Continue scanning"
}

# ── proj add: huge directory refused ───────────────────────────────────────

@test "proj add: huge dir is refused, project still registered" {
  mkdir -p "$HOME/workspace/huge"
  for i in {1..12}; do : > "$HOME/workspace/huge/file$i.txt"; done
  PROJ_SCAN_PROMPT_THRESHOLD=5 PROJ_SCAN_HUGE_THRESHOLD=10 \
    run proj add huge "$HOME/workspace/huge"
  assert_success
  assert_output --partial "Added project"
  assert_output --partial "Skipping scan"
  assert_output --partial "--force"
  refute_output --partial "Scanning project with Claude"
  # Project is still registered
  assert_equal "$(proj_field huge type)" "local"
}

@test "proj add --force-scan: bypasses huge refusal" {
  mkdir -p "$HOME/workspace/huge"
  for i in {1..12}; do : > "$HOME/workspace/huge/file$i.txt"; done
  PROJ_SCAN_PROMPT_THRESHOLD=5 PROJ_SCAN_HUGE_THRESHOLD=10 \
    run proj add huge "$HOME/workspace/huge" --force-scan
  assert_success
  assert_output --partial "Forcing scan"
  assert_output --partial "Scanning project with Claude"
}

# ── proj scan (manual) ─────────────────────────────────────────────────────

@test "proj scan --no-scan: rejected (nonsensical combination)" {
  mkdir -p "$HOME/workspace/foo"
  : > "$HOME/workspace/foo/package.json"
  proj add foo "$HOME/workspace/foo" --no-scan
  run proj scan foo --no-scan
  assert_failure
  assert_output --partial "--no-scan"
}

@test "proj scan: respects the gate on huge dirs without --force" {
  mkdir -p "$HOME/workspace/huge"
  for i in {1..12}; do : > "$HOME/workspace/huge/file$i.txt"; done
  PROJ_SCAN_PROMPT_THRESHOLD=5 PROJ_SCAN_HUGE_THRESHOLD=10 \
    proj add huge "$HOME/workspace/huge"
  PROJ_SCAN_PROMPT_THRESHOLD=5 PROJ_SCAN_HUGE_THRESHOLD=10 \
    run proj scan huge
  assert_success
  assert_output --partial "Skipping scan"
  refute_output --partial "Scanning project with Claude"
}

@test "proj scan --force: bypasses huge refusal on rescan" {
  mkdir -p "$HOME/workspace/huge"
  for i in {1..12}; do : > "$HOME/workspace/huge/file$i.txt"; done
  PROJ_SCAN_PROMPT_THRESHOLD=5 PROJ_SCAN_HUGE_THRESHOLD=10 \
    proj add huge "$HOME/workspace/huge"
  PROJ_SCAN_PROMPT_THRESHOLD=5 PROJ_SCAN_HUGE_THRESHOLD=10 \
    run proj scan huge --force
  assert_success
  assert_output --partial "Forcing scan"
  assert_output --partial "Scanning project with Claude"
}

#!/usr/bin/env bats
# Tests for `proj add <git-url>` — clone a remote repo and register it
# as a project in one command. Uses local file:// URLs pointing at bare
# repos so tests never touch the network.

load '../test_helper'

# Build a local bare git repo with a single commit and return its path.
# The file:// URL pointing at this path is what tests pass to `proj add`.
_make_fake_remote() {
  local name="$1"
  local src="$TEST_HOME/src-$name"
  local bare="$TEST_HOME/remote/$name.git"

  mkdir -p "$src" "$(dirname "$bare")"
  (
    cd "$src"
    git init --quiet -b main
    git config user.email test@example.com
    git config user.name test
    echo "# $name" > README.md
    git add README.md
    git commit --quiet -m "initial"
  )
  git clone --bare --quiet "$src" "$bare"
  echo "$bare"
}

# ── happy paths ──────────────────────────────────────────────────────────

@test "proj add <url>: clones to default dir and registers project" {
  local bare; bare="$(_make_fake_remote widget)"
  PROJ_CLONE_DIR="$TEST_HOME/clones" run proj add "file://$bare"
  assert_success
  assert_output --partial "Cloning"
  assert_output --partial "Added project"
  # Checkout exists with a .git dir
  [ -d "$TEST_HOME/clones/widget/.git" ]
  # Project is registered
  local mid; mid="$(machine_id)"
  [ -f "$(proj_data_dir)/widget/path.$mid" ]
  assert_equal "$(proj_field widget type)" "local"
}

@test "proj add <url>: explicit target directory is honored" {
  local bare; bare="$(_make_fake_remote thing)"
  run proj add "file://$bare" "$TEST_HOME/custom/thing"
  assert_success
  [ -d "$TEST_HOME/custom/thing/.git" ]
  local mid; mid="$(machine_id)"
  local stored; stored="$(cat "$(proj_data_dir)/thing/path.$mid")"
  assert_equal "$stored" "$TEST_HOME/custom/thing"
}

@test "proj add <url>: strips .git suffix from derived name" {
  local bare; bare="$(_make_fake_remote foo)"
  PROJ_CLONE_DIR="$TEST_HOME/clones" run proj add "file://$bare"
  assert_success
  # Bare dir is foo.git; derived name must be foo (no .git)
  [ -d "$(proj_data_dir)/foo" ]
  [ ! -d "$(proj_data_dir)/foo.git" ]
}

@test "proj add <url>: reuses existing matching checkout without re-cloning" {
  local bare; bare="$(_make_fake_remote widget)"
  local target="$TEST_HOME/clones/widget"
  git clone --quiet "file://$bare" "$target"

  run proj add "file://$bare" "$target"
  assert_success
  assert_output --partial "already cloned"
  assert_output --partial "Added project"
  [ -d "$(proj_data_dir)/widget" ]
}

# ── error paths ──────────────────────────────────────────────────────────

@test "proj add <url>: target is a git repo with different origin → error" {
  local bare1; bare1="$(_make_fake_remote one)"
  local bare2; bare2="$(_make_fake_remote two)"
  local target="$TEST_HOME/clones/widget"
  git clone --quiet "file://$bare1" "$target"

  run proj add "file://$bare2" "$target"
  assert_failure
  assert_output --partial "different origin"
  # Did NOT register
  [ ! -d "$(proj_data_dir)/two" ]
}

@test "proj add <url>: target is non-empty non-git directory → error" {
  local bare; bare="$(_make_fake_remote widget)"
  local target="$TEST_HOME/clones/widget"
  mkdir -p "$target"
  echo "junk" > "$target/existing.txt"

  run proj add "file://$bare" "$target"
  assert_failure
  assert_output --partial "not empty"
  [ ! -d "$(proj_data_dir)/widget" ]
}

@test "proj add <url>: clone failure leaves no registered project" {
  # Point at a bare-repo path that doesn't exist
  run proj add "file://$TEST_HOME/does-not-exist.git"
  assert_failure
  assert_output --partial "clone failed"
  [ ! -d "$(proj_data_dir)/does-not-exist" ]
}

@test "proj add <url>: URL without a path segment is rejected" {
  # https://example.com/ has only a host, no path → no repo name to derive.
  # Must fail at the URL parser before touching git clone.
  run proj add "https://example.com/"
  assert_failure
  assert_output --partial "repo name"
  # Did not reach the clone stage.
  refute_output --partial "Cloning"
}

# ── URL format coverage ─────────────────────────────────────────────────

@test "proj add <url>: non-URL first arg still works as legacy name+path" {
  mkdir -p "$HOME/workspace/legacy"
  run proj add legacy "$HOME/workspace/legacy"
  assert_success
  assert_output --partial "Added project"
  [ -d "$(proj_data_dir)/legacy" ]
}

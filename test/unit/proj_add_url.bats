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

# ── regression coverage from round 1 review ─────────────────────────────

@test "proj add <url>: PROJ_CLONE_DIR starting with '-' is refused (argv injection defense)" {
  local bare; bare="$(_make_fake_remote widget)"
  # If the target slipped through into git clone unguarded, git would
  # parse `--upload-pack=touch …` as an option and execute it. The
  # canary file MUST NOT exist after the run.
  local canary="$TEST_HOME/pwned-canary"
  PROJ_CLONE_DIR="--upload-pack=touch $canary;true" \
    run proj add "file://$bare"
  assert_failure
  [ ! -e "$canary" ]
  # Project is NOT registered.
  [ ! -d "$(proj_data_dir)/widget" ]
}

@test "proj add <url>: explicit target starting with '-' is refused" {
  local bare; bare="$(_make_fake_remote widget)"
  run proj add "file://$bare" "-evil/widget"
  assert_failure
  assert_output --partial "begins with '-'"
}

@test "proj add <url>: name collision refused BEFORE cloning (no orphaned checkout)" {
  # Pre-register a project named 'widget' at an unrelated path.
  mkdir -p "$HOME/workspace/widget"
  proj add widget "$HOME/workspace/widget" >/dev/null

  local bare; bare="$(_make_fake_remote widget)"
  PROJ_CLONE_DIR="$TEST_HOME/clones" run proj add "file://$bare"
  assert_failure
  assert_output --partial "already exists"
  # Original project unchanged
  local mid; mid="$(machine_id)"
  assert_equal "$(cat "$(proj_data_dir)/widget/path.$mid")" "$HOME/workspace/widget"
  # No clone was performed (no orphaned checkout)
  [ ! -d "$TEST_HOME/clones/widget" ]
  refute_output --partial "Cloning"
}

@test "proj add <url>: existing checkout reused even if .git suffix differs" {
  local bare; bare="$(_make_fake_remote widget)"
  local target="$TEST_HOME/clones/widget"
  # Clone manually using URL with .git suffix
  git clone --quiet "file://$bare" "$target"
  # Pass the URL WITHOUT the trailing .git — should normalize and reuse
  local short_url="file://${bare%.git}"
  run proj add "$short_url" "$target"
  assert_success
  assert_output --partial "already cloned"
  [ -d "$(proj_data_dir)/widget" ]
}

@test "proj add <url>: existing checkout reused even with trailing slash difference" {
  local bare; bare="$(_make_fake_remote widget)"
  local target="$TEST_HOME/clones/widget"
  git clone --quiet "file://$bare" "$target"
  run proj add "file://$bare/" "$target"
  assert_success
  assert_output --partial "already cloned"
}

@test "proj add <url>: URL with credentials is scrubbed in display output" {
  local bare; bare="$(_make_fake_remote widget)"
  # https-shaped URL with embedded user:token; clone will fail (file://
  # behind the credentials is not a real https URL), but we only care
  # that the printed messages don't echo the token.
  run proj add "https://alice:supersecrettoken@example.invalid/widget.git" \
    "$TEST_HOME/clones/widget"
  assert_failure
  refute_output --partial "supersecrettoken"
  refute_output --partial "alice:"
  # The scrubbed form (https://example.invalid/widget.git) should still appear
  assert_output --partial "example.invalid/widget.git"
}

@test "proj add <url>: query string in URL is stripped from derived name" {
  local bare; bare="$(_make_fake_remote widget)"
  PROJ_CLONE_DIR="$TEST_HOME/clones" run proj add "file://$bare?ref=main"
  # Either succeeds (after stripping ?ref=main) or fails cleanly — but
  # NOT with 'invalid repo name' that includes the query string.
  if [[ "$status" -eq 0 ]]; then
    [ -d "$(proj_data_dir)/widget" ]
  else
    refute_output --partial "?ref=main"
  fi
}

@test "proj add <url>: scrub helper handles plain URL unchanged" {
  # Direct unit-style coverage of _proj_scrub_url via a plain URL clone.
  local bare; bare="$(_make_fake_remote widget)"
  PROJ_CLONE_DIR="$TEST_HOME/clones" run proj add "file://$bare"
  assert_success
  # No-op scrub path — the file:// URL appears verbatim
  assert_output --partial "file://$bare"
}

@test "proj add <url>: post-clone scan is triggered through recursion" {
  local bare; bare="$(_make_fake_remote widget)"
  PROJ_CLONE_DIR="$TEST_HOME/clones" run proj add "file://$bare"
  assert_success
  # Composition check: the clone path recurses into _proj_add, which
  # MUST then call _proj_scan_with_claude (visible as the "Scanning"
  # marker). A future regression that breaks the recursion would make
  # this assertion fail.
  assert_output --partial "Scanning project with Claude"
  # Standard project-init files must exist.
  [ -f "$(proj_data_dir)/widget/desc" ]
  [ -f "$(proj_data_dir)/widget/status" ]
}

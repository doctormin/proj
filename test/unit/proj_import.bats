#!/usr/bin/env bats
# Tests for `proj import <dir>` — batch register git repos as projects.

load '../test_helper'

_make_repo() {
  local path="$1"
  mkdir -p "$path"
  git init --quiet "$path"
}

_add() {
  local name="$1"
  mkdir -p "$HOME/workspace/$name"
  proj add "$name" "$HOME/workspace/$name" >/dev/null
}

@test "proj import: --yes adds all git repos found" {
  _make_repo "$HOME/code/alpha"
  _make_repo "$HOME/code/beta"
  _make_repo "$HOME/code/gamma"

  run proj import "$HOME/code" --yes
  assert_success
  assert_output --partial "Found 3 git repo"
  assert_output --partial "3 added"
  assert [ -d "$(proj_data_dir)/alpha" ]
  assert [ -d "$(proj_data_dir)/beta" ]
  assert [ -d "$(proj_data_dir)/gamma" ]
}

@test "proj import: registered projects have type=local and status=active" {
  _make_repo "$HOME/code/one"

  run proj import "$HOME/code" --yes
  assert_success
  assert_equal "$(proj_field one type)" "local"
  assert_equal "$(proj_field one status)" "active"
  [ -n "$(proj_field one updated)" ]
}

@test "proj import: path.<machine-id> written for each registered project" {
  _make_repo "$HOME/code/alpha"

  run proj import "$HOME/code" --yes
  assert_success

  local mid
  mid="$(machine_id)"
  [ -n "$mid" ]
  assert [ -f "$(proj_data_dir)/alpha/path.$mid" ]
  assert_equal "$(cat $(proj_data_dir)/alpha/path.$mid)" "$HOME/code/alpha"
}

@test "proj import --dry-run: reports repos without creating projects" {
  _make_repo "$HOME/code/alpha"
  _make_repo "$HOME/code/beta"

  run proj import "$HOME/code" --dry-run
  assert_success
  assert_output --partial "dry-run"
  assert_output --partial "alpha"
  assert_output --partial "beta"
  assert_output --partial "Dry run — no changes made."
  assert [ ! -d "$(proj_data_dir)/alpha" ]
  assert [ ! -d "$(proj_data_dir)/beta" ]
}

@test "proj import: empty directory prints no-repos message" {
  mkdir -p "$HOME/empty"

  run proj import "$HOME/empty" --yes
  assert_success
  assert_output --partial "No git repositories found"
}

@test "proj import: nonexistent directory errors out" {
  run proj import "$HOME/nonexistent" --yes
  assert_failure
  assert_output --partial "Directory does not exist"
}

@test "proj import: already-registered project with same path is skipped" {
  _make_repo "$HOME/code/alpha"

  run proj import "$HOME/code" --yes
  assert_success
  assert_output --partial "1 added"

  # Run again — should skip, not re-add
  run proj import "$HOME/code" --yes
  assert_success
  assert_output --partial "already registered"
  assert_output --partial "0 added"
}

@test "proj import: --depth 1 limits scan to direct children" {
  _make_repo "$HOME/code/direct"
  _make_repo "$HOME/code/deep/nested"

  run proj import "$HOME/code" --depth 1 --yes
  assert_success
  assert_output --partial "direct"
  refute_output --partial "nested"
}

@test "proj import: --depth 3 finds deeper repos" {
  _make_repo "$HOME/code/a/b/deep"

  run proj import "$HOME/code" --depth 3 --yes
  assert_success
  assert_output --partial "deep"
}

@test "proj import: default dir is cwd" {
  mkdir -p "$HOME/work"
  _make_repo "$HOME/work/proj1"

  cd "$HOME/work"
  run proj import --yes
  assert_success
  assert_output --partial "proj1"
}

@test "proj import: name collision with --yes skips the collision silently" {
  _make_repo "$HOME/ws1/shared"
  _make_repo "$HOME/ws2/shared"

  run proj import "$HOME/ws1" --yes
  assert_success
  assert_output --partial "1 added"

  # ws2/shared has same basename but different path — should skip
  run proj import "$HOME/ws2" --yes
  assert_success
  assert_output --partial "name collision"
  assert_output --partial "0 added"
}

@test "proj import: --depth without value fails fast (no hang)" {
  mkdir -p "$HOME/code"
  run proj import "$HOME/code" --depth
  assert_failure
  assert_output --partial "--depth requires a value"
}

@test "proj import: rejects repo with whitespace in basename" {
  # Spaces break `_proj_names`' word-split iteration; skip with a message.
  _make_repo "$HOME/code/Client App"

  run proj import "$HOME/code" --yes
  assert_success
  assert_output --partial "invalid characters"
  # Should not register the project
  assert [ ! -d "$(proj_data_dir)/Client" ]
  assert [ ! -d "$(proj_data_dir)/Client App" ]
}

@test "proj import: rejects repo with leading dot in basename" {
  # _proj_names filters dot-prefixed entries; dotfile repos can't be
  # round-tripped so we reject them explicitly.
  _make_repo "$HOME/code/.dotfiles"

  run proj import "$HOME/code" --yes
  assert_success
  assert_output --partial "invalid characters"
  assert [ ! -d "$(proj_data_dir)/.dotfiles" ]
}

@test "proj import: collision-override name is re-validated" {
  # Set up a valid repo named "foo" and a pre-existing unrelated project
  # with the same name, to trigger the collision-rename prompt in
  # interactive mode. Feed an invalid override ("bad name" with space) and
  # expect import to reject and skip.
  _add foo                       # creates project "foo" at $HOME/workspace/foo
  _make_repo "$HOME/code/foo"    # unrelated local checkout, same basename

  # Pipe invalid override into the interactive prompt. Use the raw proj()
  # bridge, feeding the response via stdin.
  run bash -c "echo 'bad name' | zsh -c 'source \"$PROJ_ROOT/proj.zsh\" && proj import \"$HOME/code\"'"
  assert_success
  assert_output --partial "invalid characters"
  # The unrelated project "bad name" must NOT exist
  assert [ ! -d "$(proj_data_dir)/bad name" ]
  assert [ ! -d "$(proj_data_dir)/bad" ]
}

@test "proj import: accepts alnum-plus-hyphen-dot-underscore basenames" {
  _make_repo "$HOME/code/my-app"
  _make_repo "$HOME/code/my_lib"
  _make_repo "$HOME/code/v2.0"

  run proj import "$HOME/code" --yes
  assert_success
  assert [ -d "$(proj_data_dir)/my-app" ]
  assert [ -d "$(proj_data_dir)/my_lib" ]
  assert [ -d "$(proj_data_dir)/v2.0" ]
}

@test "proj import: does NOT re-link when existing project is remote" {
  # A remote project has no local path by design. A local checkout with the
  # same basename must NOT hijack the remote entry — it must be treated as a
  # collision and require a new name (or, with --yes, be skipped).
  run proj add-remote api user@server.example.com:/srv/api
  assert_success

  _make_repo "$HOME/code/api"

  run proj import "$HOME/code" --yes
  assert_success
  assert_output --partial "name collision"
  assert_output --partial "remote project"

  # The remote entry is untouched: type is still remote, no local path written.
  assert_equal "$(proj_field api type)" "remote"
  local mid
  mid="$(machine_id)"
  assert [ ! -f "$(proj_data_dir)/api/path.$mid" ]
}

@test "proj import: discovers git worktrees (.git is a file, not a dir)" {
  # Create a regular repo and a worktree of it — the worktree has a `.git`
  # FILE containing `gitdir: ...`, not a directory.
  # CI runners have no global git identity, so set one explicitly for
  # the `git commit` call inside this test (same pattern the sync tests
  # use via setup_git_identity).
  export GIT_AUTHOR_NAME="Test User"
  export GIT_AUTHOR_EMAIL="test@example.com"
  export GIT_COMMITTER_NAME="Test User"
  export GIT_COMMITTER_EMAIL="test@example.com"

  _make_repo "$HOME/code/parent"
  (
    cd "$HOME/code/parent"
    git commit --allow-empty --quiet -m init
    git worktree add --quiet "$HOME/code/wt" 2>/dev/null
  )

  # Sanity: worktree's .git is a file
  assert [ -f "$HOME/code/wt/.git" ]

  run proj import "$HOME/code" --yes
  assert_success
  assert_output --partial "parent"
  assert_output --partial "wt"
  assert [ -d "$(proj_data_dir)/parent" ]
  assert [ -d "$(proj_data_dir)/wt" ]
}

@test "proj import: --yes does NOT auto-relink unlinked synced project (must confirm)" {
  # A basename match is not proof of same-repo identity. --yes must not
  # silently clobber synced metadata with an unrelated local checkout.
  run proj --version
  mkdir -p "$(proj_data_dir)/synced"
  echo "local"  > "$(proj_data_dir)/synced/type"
  echo "paused" > "$(proj_data_dir)/synced/status"
  echo "2026-04-10 10:00" > "$(proj_data_dir)/synced/updated"
  echo "sync description" > "$(proj_data_dir)/synced/desc"

  _make_repo "$HOME/code/synced"

  run proj import "$HOME/code" --yes
  assert_success
  assert_output --partial "synced project needs interactive re-link"
  assert_output --partial "0 added"

  # Synced metadata is untouched
  assert_equal "$(proj_field synced status)" "paused"
  assert_equal "$(proj_field synced desc)"   "sync description"
  local mid
  mid="$(machine_id)"
  assert [ ! -f "$(proj_data_dir)/synced/path.$mid" ]
}

@test "proj import: --dry-run does NOT auto-relink synced project" {
  run proj --version
  mkdir -p "$(proj_data_dir)/synced"
  echo "local"  > "$(proj_data_dir)/synced/type"
  echo "active" > "$(proj_data_dir)/synced/status"

  _make_repo "$HOME/code/synced"

  run proj import "$HOME/code" --dry-run
  assert_success
  assert_output --partial "synced project needs interactive re-link"
}

@test "proj import: rejects unknown flag" {
  mkdir -p "$HOME/code"
  run proj import "$HOME/code" --bogus
  assert_failure
  assert_output --partial "Unknown flag"
}

@test "proj import: rejects non-numeric --depth" {
  mkdir -p "$HOME/code"
  run proj import "$HOME/code" --depth foo
  assert_failure
  assert_output --partial "--depth must be a non-negative integer"
}

@test "proj import: rejects --depth above upper bound (prevents arithmetic overflow)" {
  mkdir -p "$HOME/code"
  run proj import "$HOME/code" --depth 99999999999999999999
  assert_failure
  assert_output --partial "--depth must be <= 20"
}

@test "proj import: rejects --depth 21 (one past bound)" {
  mkdir -p "$HOME/code"
  run proj import "$HOME/code" --depth 21
  assert_failure
  assert_output --partial "--depth must be <= 20"
}

@test "proj import: help text mentions import subcommand" {
  run proj help
  assert_success
  assert_output --partial "import"
}

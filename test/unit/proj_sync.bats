#!/usr/bin/env bats
# proj sync: three modes (first push, clone-merge, subsequent) against a
# local bare git repo. No network required.

load '../test_helper'

# Use git with a stable identity inside the fake HOME (git complains otherwise)
setup_git_identity() {
  export GIT_AUTHOR_NAME="Test User"
  export GIT_AUTHOR_EMAIL="test@example.com"
  export GIT_COMMITTER_NAME="Test User"
  export GIT_COMMITTER_EMAIL="test@example.com"
  # Explicit init branch for reproducibility across git versions
  git config --global init.defaultBranch main 2>/dev/null || true
}

@test "proj sync without sync_repo configured errors with helpful message" {
  setup_git_identity
  run proj sync
  assert_failure
  assert_output --partial "No sync repo"
}

@test "proj sync first push (mode 1): init, commit, push to bare repo" {
  setup_git_identity

  # Create one project so there's something to commit
  mkdir -p "$HOME/workspace/proj1"
  run proj add proj1 "$HOME/workspace/proj1"
  assert_success

  local bare="$HOME/remote.git"
  local url
  url=$(make_bare_repo "$bare")

  set_sync_repo "$url"

  # First push prompts "Continue? [y/N]" — proj_yes pipes "y"
  run proj_yes sync
  assert_success
  assert_output --partial "Sync initialized"

  # Verify the bare repo now has commits
  run bash -c "git --git-dir='$bare' log --oneline"
  assert_success
  assert_output --partial "initial sync"
}

@test "proj sync first push warns about private repo" {
  setup_git_identity
  mkdir -p "$HOME/workspace/p"
  run proj add p "$HOME/workspace/p"

  local url
  url=$(make_bare_repo "$HOME/remote.git")
  set_sync_repo "$url"

  run proj_yes sync
  assert_success
  assert_output --partial "PRIVATE"
}

@test "proj sync first push aborts on 'no' confirmation" {
  setup_git_identity
  mkdir -p "$HOME/workspace/p"
  run proj add p "$HOME/workspace/p"

  local url
  url=$(make_bare_repo "$HOME/remote.git")
  set_sync_repo "$url"

  # Pipe 'n' via inline shell
  run bash -c "echo n | zsh -c 'source \"$PROJ_ROOT/proj.zsh\" && proj sync'"
  assert_output --partial "Cancelled"
  # .git directory should not exist (no init happened)
  assert [ ! -d "$HOME/.proj/data/.git" ]
}

@test "proj sync subsequent push (mode 3) commits local changes" {
  setup_git_identity

  mkdir -p "$HOME/workspace/p1"
  run proj add p1 "$HOME/workspace/p1"

  local url
  url=$(make_bare_repo "$HOME/remote.git")
  set_sync_repo "$url"

  # First push
  run proj_yes sync
  assert_success

  # Make a local change
  run proj status p1 paused
  assert_success

  # Subsequent sync
  run proj sync
  assert_success
  assert_output --partial "Sync complete"
}

@test "proj sync second machine (mode 2): clone then merge local projects" {
  setup_git_identity

  # --- Machine A: create one project and push ---
  mkdir -p "$HOME/workspace/onlyA"
  run proj add onlyA "$HOME/workspace/onlyA"

  local bare="$HOME/remote.git"
  local url
  url=$(make_bare_repo "$bare")
  set_sync_repo "$url"
  run proj_yes sync
  assert_success

  # --- Switch to "Machine B": fresh HOME with the same bare repo URL ---
  local old_home="$HOME"
  export HOME="$(mktemp -d -t proj-test-B.XXXXXX)"
  mkdir -p "$HOME"

  # Create a local-only project on machine B before sync
  mkdir -p "$HOME/workspace/onlyB"
  run proj add onlyB "$HOME/workspace/onlyB"

  set_sync_repo "$url"
  run proj sync
  assert_success

  # Both projects should now exist on B
  assert [ -d "$HOME/.proj/data/onlyA" ]
  assert [ -d "$HOME/.proj/data/onlyB" ]

  # Cleanup: restore HOME for teardown (the outer TEST_HOME)
  rm -rf "$HOME"
  export HOME="$old_home"
}

@test "proj sync first push creates .gitattributes with history.log merge=union" {
  # Without this, concurrent history.log appends from two machines produce
  # a git merge conflict on every sync pull. The union merge driver makes
  # them auto-merge into a combined file.
  setup_git_identity
  mkdir -p "$HOME/workspace/p"
  run proj add p "$HOME/workspace/p"

  local url
  url=$(make_bare_repo "$HOME/remote.git")
  set_sync_repo "$url"

  run proj_yes sync
  assert_success

  assert [ -f "$HOME/.proj/data/.gitattributes" ]
  run cat "$HOME/.proj/data/.gitattributes"
  assert_output --partial "*/history.log merge=union"
}

@test "proj sync subsequent push adds .gitattributes if missing (v1 upgrade path)" {
  # Users who first-synced under v1 have a data repo with no
  # .gitattributes. The next sync after upgrading should add it
  # opportunistically so history.log merges work.
  setup_git_identity
  mkdir -p "$HOME/workspace/p"
  run proj add p "$HOME/workspace/p"

  local url
  url=$(make_bare_repo "$HOME/remote.git")
  set_sync_repo "$url"

  run proj_yes sync
  assert_success

  # Simulate a v1 sync repo by deleting the .gitattributes file in-place
  # and committing the removal
  cd "$HOME/.proj/data"
  rm .gitattributes
  git add -A
  git commit -q -m "simulate v1 state"
  git push -q origin main
  cd - >/dev/null

  # Trigger another sync
  run proj status p paused
  run proj sync
  assert_success

  # .gitattributes should have been re-created by ensure helper
  assert [ -f "$HOME/.proj/data/.gitattributes" ]
  run cat "$HOME/.proj/data/.gitattributes"
  assert_output --partial "*/history.log merge=union"
}

@test "sync data directory excludes dotfiles from _proj_names listing" {
  setup_git_identity

  mkdir -p "$HOME/workspace/realproj"
  run proj add realproj "$HOME/workspace/realproj"

  local url
  url=$(make_bare_repo "$HOME/remote.git")
  set_sync_repo "$url"
  run proj_yes sync
  assert_success

  # After sync, .git/ exists inside $HOME/.proj/data/
  assert [ -d "$HOME/.proj/data/.git" ]

  # But `proj list` should not show ".git" as a project
  run proj list
  assert_success
  refute_output --regexp '^\s*\.git'
}

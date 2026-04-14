#!/usr/bin/env bats
# proj rm tombstone sync (Phase 2d Unit D2).
#
# Ensures `proj rm <name>` writes a tombstone under data/.tombstones/<name>
# so the deletion can propagate to other machines via the existing git sync
# mechanism. Mirrors the dual-HOME + shared bare-repo pattern used in
# proj_sync.bats.

load '../test_helper'

setup_git_identity() {
  export GIT_AUTHOR_NAME="Test User"
  export GIT_AUTHOR_EMAIL="test@example.com"
  export GIT_COMMITTER_NAME="Test User"
  export GIT_COMMITTER_EMAIL="test@example.com"
  git config --global init.defaultBranch main 2>/dev/null || true
}

# ── Local-only (no sync) behavior ──────────────────────────────────────

@test "proj rm writes tombstone file with deleted-at and by-machine" {
  mkdir -p "$HOME/workspace/foo"
  run proj add foo "$HOME/workspace/foo"
  assert_success

  run proj rm foo
  assert_success
  assert_output --partial "Removed project: foo"
  assert_output --partial "tombstone recorded"

  # Data dir removed
  assert [ ! -d "$HOME/.proj/data/foo" ]

  # Tombstone present with correct fields
  local tfile="$HOME/.proj/data/.tombstones/foo"
  assert [ -f "$tfile" ]
  run cat "$tfile"
  assert_output --partial "deleted-at="
  assert_output --partial "by-machine="

  # Timestamp is UTC ISO 8601 Z form
  run grep -E '^deleted-at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$tfile"
  assert_success

  # by-machine matches the current machine-id
  local mid
  mid=$(machine_id)
  run grep -F "by-machine=$mid" "$tfile"
  assert_success
}

@test "proj rm of non-existent project errors without creating tombstone" {
  run proj rm nope
  assert_failure
  assert [ ! -f "$HOME/.proj/data/.tombstones/nope" ]
}

@test "proj ls / _proj_names does not list a tombstoned project" {
  mkdir -p "$HOME/workspace/alpha" "$HOME/workspace/beta"
  run proj add alpha "$HOME/workspace/alpha"
  run proj add beta "$HOME/workspace/beta"
  run proj rm alpha
  assert_success

  # The .tombstones dotfile must not appear in _proj_names output
  run bash -c "zsh -c 'source \"$PROJ_ROOT/proj.zsh\" && _proj_names'"
  assert_success
  refute_output --partial "alpha"
  refute_output --partial ".tombstones"
  assert_output --partial "beta"
}

@test "proj rm after proj add clears tombstone and restores project" {
  mkdir -p "$HOME/workspace/foo"
  run proj add foo "$HOME/workspace/foo"
  run proj rm foo
  assert_success
  assert [ -f "$HOME/.proj/data/.tombstones/foo" ]

  # Re-add should clear tombstone
  run proj add foo "$HOME/workspace/foo"
  assert_success
  assert_output --partial "cleared tombstone"
  assert [ ! -f "$HOME/.proj/data/.tombstones/foo" ]
  assert [ -d "$HOME/.proj/data/foo" ]
}

@test "proj add with no prior tombstone does not mention clearing" {
  mkdir -p "$HOME/workspace/fresh"
  run proj add fresh "$HOME/workspace/fresh"
  assert_success
  refute_output --partial "cleared tombstone"
}

@test "_proj_migrate creates .tombstones directory idempotently" {
  # First invocation
  run bash -c "zsh -c 'source \"$PROJ_ROOT/proj.zsh\" && _proj_migrate'"
  assert_success
  assert [ -d "$HOME/.proj/data/.tombstones" ]

  # Drop a marker so we can verify the directory isn't recreated (clobber)
  touch "$HOME/.proj/data/.tombstones/.marker"
  run bash -c "zsh -c 'source \"$PROJ_ROOT/proj.zsh\" && _proj_migrate'"
  assert_success
  assert [ -f "$HOME/.proj/data/.tombstones/.marker" ]
}

@test "_proj_migrate preserves existing tombstones" {
  mkdir -p "$HOME/workspace/foo"
  run proj add foo "$HOME/workspace/foo"
  run proj rm foo
  assert [ -f "$HOME/.proj/data/.tombstones/foo" ]

  # Simulate a subsequent session sourcing proj.zsh (which re-runs migrate)
  run bash -c "zsh -c 'source \"$PROJ_ROOT/proj.zsh\" && true'"
  assert_success
  assert [ -f "$HOME/.proj/data/.tombstones/foo" ]
}

@test "_proj_sync_purge_tombstoned removes matching local dirs" {
  mkdir -p "$HOME/workspace/alpha" "$HOME/workspace/beta"
  run proj add alpha "$HOME/workspace/alpha"
  run proj add beta "$HOME/workspace/beta"

  # Plant a tombstone directly for alpha, simulating one that arrived via
  # git pull while alpha's data dir still exists locally.
  mkdir -p "$HOME/.proj/data/.tombstones"
  printf 'deleted-at=2026-04-14T00:00:00Z\nby-machine=other\n' \
    > "$HOME/.proj/data/.tombstones/alpha"

  run bash -c "zsh -c 'source \"$PROJ_ROOT/proj.zsh\" && _proj_sync_purge_tombstoned'"
  assert_success
  assert_output --partial "purged tombstoned: alpha"
  assert [ ! -d "$HOME/.proj/data/alpha" ]
  assert [ -d "$HOME/.proj/data/beta" ]
  # Tombstone itself is preserved (still needed for other machines)
  assert [ -f "$HOME/.proj/data/.tombstones/alpha" ]
}

@test "_proj_sync_purge_tombstoned is a no-op when .tombstones dir missing" {
  # No projects, no sync — should not error
  run bash -c "zsh -c 'source \"$PROJ_ROOT/proj.zsh\" && rm -rf \$HOME/.proj/data/.tombstones && _proj_sync_purge_tombstoned'"
  assert_success
}

@test "_proj_sync_purge_tombstoned skips names with shell metacharacters" {
  # Planted tombstone with an invalid basename (leading dot already
  # filtered, so use `..` which would be dangerous under rm -rf)
  mkdir -p "$HOME/.proj/data/.tombstones"
  touch "$HOME/.proj/data/.tombstones/..evil"
  # And a matching "project" dir
  mkdir -p "$HOME/.proj/data/..evil" 2>/dev/null || true

  run bash -c "zsh -c 'source \"$PROJ_ROOT/proj.zsh\" && _proj_sync_purge_tombstoned'"
  assert_success
  # If anything got removed it should only be the tombstone pseudo-file,
  # never the real PROJ_DATA. Guard: PROJ_DATA still exists.
  assert [ -d "$HOME/.proj/data" ]
}

@test "proj rm refuses metachar names (defense in depth)" {
  mkdir -p "$HOME/workspace/foo"
  run proj add foo "$HOME/workspace/foo"
  # Hand-plant a badly-named directory (bypasses proj add validation)
  mkdir -p "$HOME/.proj/data/..evil"
  run proj rm "..evil"
  assert_failure
  # No tombstone written for the invalid name
  assert [ ! -f "$HOME/.proj/data/.tombstones/..evil" ]
}

@test "proj doctor survives presence of .tombstones directory" {
  mkdir -p "$HOME/workspace/foo"
  run proj add foo "$HOME/workspace/foo"
  run proj rm foo
  run proj doctor
  # doctor may exit 1 if it finds issues like missing schema hints, but
  # it must not crash or surface `.tombstones` as a project
  refute_output --partial ".tombstones"
}

# ── Cross-machine sync (dual HOME + shared bare repo) ──────────────────

@test "sync: A deletes, B pulls — local copy is purged on B" {
  setup_git_identity

  # Machine A: create foo + bar, first push
  mkdir -p "$HOME/workspace/foo" "$HOME/workspace/bar"
  run proj add foo "$HOME/workspace/foo"
  run proj add bar "$HOME/workspace/bar"

  local bare="$HOME/remote.git"
  local url
  url=$(make_bare_repo "$bare")
  set_sync_repo "$url"
  run proj_yes sync
  assert_success

  # Machine B: clone-merge
  local home_a="$HOME"
  export HOME="$(mktemp -d -t proj-test-B.XXXXXX)"
  mkdir -p "$HOME"
  set_sync_repo "$url"
  run proj sync
  assert_success
  assert [ -d "$HOME/.proj/data/foo" ]
  assert [ -d "$HOME/.proj/data/bar" ]
  local home_b="$HOME"

  # Back to A: remove foo, sync (pushes tombstone)
  export HOME="$home_a"
  run proj rm foo
  assert_success
  assert [ -f "$HOME/.proj/data/.tombstones/foo" ]
  run proj sync
  assert_success

  # Back to B: sync — foo should be gone (via tombstone purge OR direct
  # git removal from the fast-forward), bar preserved, tombstone present.
  export HOME="$home_b"
  run proj sync
  assert_success
  assert [ ! -d "$HOME/.proj/data/foo" ]
  assert [ -d "$HOME/.proj/data/bar" ]
  # Tombstone persists on B
  assert [ -f "$HOME/.proj/data/.tombstones/foo" ]

  rm -rf "$home_b"
  export HOME="$home_a"
}

@test "sync: tombstone for a project B never had is a no-op" {
  setup_git_identity

  # A: creates foo, pushes
  mkdir -p "$HOME/workspace/foo"
  run proj add foo "$HOME/workspace/foo"
  local url
  url=$(make_bare_repo "$HOME/remote.git")
  set_sync_repo "$url"
  run proj_yes sync
  assert_success

  # A: immediately deletes foo and pushes tombstone (B never pulled)
  run proj rm foo
  run proj sync
  assert_success

  # B: first sync (clone-merge). B should end up with no foo dir.
  local home_a="$HOME"
  export HOME="$(mktemp -d -t proj-test-B.XXXXXX)"
  mkdir -p "$HOME"
  set_sync_repo "$url"
  run proj sync
  assert_success
  assert [ ! -d "$HOME/.proj/data/foo" ]
  # But the tombstone did come down
  assert [ -f "$HOME/.proj/data/.tombstones/foo" ]

  rm -rf "$HOME"
  export HOME="$home_a"
}

@test "sync: A re-adds after rm — B sees project, not deletion" {
  setup_git_identity

  # A: add + push
  mkdir -p "$HOME/workspace/foo"
  run proj add foo "$HOME/workspace/foo"
  local url
  url=$(make_bare_repo "$HOME/remote.git")
  set_sync_repo "$url"
  run proj_yes sync
  assert_success

  # A: rm, then re-add (before any pull on B)
  run proj rm foo
  assert [ -f "$HOME/.proj/data/.tombstones/foo" ]
  run proj add foo "$HOME/workspace/foo"
  assert_success
  assert [ ! -f "$HOME/.proj/data/.tombstones/foo" ]
  assert [ -d "$HOME/.proj/data/foo" ]
  run proj sync
  assert_success

  # B: first sync. Should see foo present and no tombstone
  local home_a="$HOME"
  export HOME="$(mktemp -d -t proj-test-B.XXXXXX)"
  mkdir -p "$HOME"
  set_sync_repo "$url"
  run proj sync
  assert_success
  assert [ -d "$HOME/.proj/data/foo" ]
  assert [ ! -f "$HOME/.proj/data/.tombstones/foo" ]

  rm -rf "$HOME"
  export HOME="$home_a"
}

@test "sync: B's local-only project is NOT resurrected if A tombstoned same name" {
  setup_git_identity

  # A: add foo + push
  mkdir -p "$HOME/workspace/foo"
  run proj add foo "$HOME/workspace/foo"
  local url
  url=$(make_bare_repo "$HOME/remote.git")
  set_sync_repo "$url"
  run proj_yes sync
  assert_success

  # A: rm foo + push tombstone
  run proj rm foo
  run proj sync
  assert_success

  # B: fresh HOME, create local-only foo with same name, then sync (mode 2 clone-merge)
  local home_a="$HOME"
  export HOME="$(mktemp -d -t proj-test-B.XXXXXX)"
  mkdir -p "$HOME"
  mkdir -p "$HOME/workspace/foo"
  run proj add foo "$HOME/workspace/foo"
  set_sync_repo "$url"
  run proj sync
  assert_success
  # The clone-merge must not re-introduce foo from the backup
  assert [ ! -d "$HOME/.proj/data/foo" ]
  assert [ -f "$HOME/.proj/data/.tombstones/foo" ]

  rm -rf "$HOME"
  export HOME="$home_a"
}

@test "sync mode-2 rescues pre-existing local tombstones from backup dir" {
  # Scenario: machine B tombstoned a project BEFORE ever configuring
  # sync-repo, then joins an existing sync. The * glob in the merge-back
  # loop skips dotdirs, so without an explicit rescue the local
  # .tombstones/ would be stranded in the backup and the delete intent
  # silently lost. Machine A meanwhile still has the project alive.
  setup_git_identity

  # A: add foo, push
  mkdir -p "$HOME/workspace/foo"
  run proj add foo "$HOME/workspace/foo"
  local url
  url=$(make_bare_repo "$HOME/remote.git")
  set_sync_repo "$url"
  run proj_yes sync
  assert_success

  # B: fresh HOME, add foo, then tombstone it BEFORE configuring sync.
  local home_a="$HOME"
  export HOME="$(mktemp -d -t proj-test-B.XXXXXX)"
  mkdir -p "$HOME/workspace/foo"
  run proj add foo "$HOME/workspace/foo"
  run proj rm foo
  assert_success
  assert [ -f "$HOME/.proj/data/.tombstones/foo" ]
  # Nothing else under data (besides dotdirs); remove any stray files to
  # make the backup glob loop fully exercise the dotdir-skip edge case.

  # Now configure sync-repo and run mode-2 (clone + merge local).
  set_sync_repo "$url"
  run proj sync
  assert_success

  # The rescued tombstone must survive the clone-merge.
  assert [ -f "$HOME/.proj/data/.tombstones/foo" ]
  # And the purge should have removed the just-cloned foo dir.
  assert [ ! -d "$HOME/.proj/data/foo" ]

  # A: sync again — should see the deletion propagate back via the
  # tombstone that B rescued and pushed.
  export HOME="$home_a"
  run proj sync
  assert_success
  assert [ ! -d "$HOME/.proj/data/foo" ]
  assert [ -f "$HOME/.proj/data/.tombstones/foo" ]
}

@test "_proj_sync_ensure_gitattributes adds tombstone union-merge rule" {
  mkdir -p "$HOME/.proj/data"
  run bash -c "zsh -c 'source \"$PROJ_ROOT/proj.zsh\" && _proj_sync_ensure_gitattributes'"
  assert_success
  local gaf="$HOME/.proj/data/.gitattributes"
  assert [ -f "$gaf" ]
  run grep -qxF '*/history.log merge=union' "$gaf"
  assert_success
  run grep -qxF '.tombstones/* merge=union' "$gaf"
  assert_success

  # Idempotent: a second call must not duplicate either line.
  run bash -c "zsh -c 'source \"$PROJ_ROOT/proj.zsh\" && _proj_sync_ensure_gitattributes'"
  assert_success
  run bash -c "grep -c '^\*/history.log merge=union$' '$gaf'"
  assert_output "1"
  run bash -c "grep -c '^\.tombstones/\* merge=union$' '$gaf'"
  assert_output "1"
}

@test "_proj_sync_ensure_gitattributes migrates a legacy file with only history.log rule" {
  mkdir -p "$HOME/.proj/data"
  printf '%s\n' '*/history.log merge=union' > "$HOME/.proj/data/.gitattributes"
  run bash -c "zsh -c 'source \"$PROJ_ROOT/proj.zsh\" && _proj_sync_ensure_gitattributes'"
  assert_success
  run grep -qxF '.tombstones/* merge=union' "$HOME/.proj/data/.gitattributes"
  assert_success
  # History line preserved exactly once
  run bash -c "grep -c '^\*/history.log merge=union$' '$HOME/.proj/data/.gitattributes'"
  assert_output "1"
}

@test "_proj_add keeps tombstone if data writes fail after the first" {
  # Create a tombstone for foo without proj rm (simulates a state where
  # foo was deleted on another machine and the tombstone pulled in).
  mkdir -p "$HOME/.proj/data/.tombstones"
  printf 'deleted-at=2026-04-14T00:00:00Z\nby-machine=other\n' \
    > "$HOME/.proj/data/.tombstones/foo"
  mkdir -p "$HOME/workspace/foo"

  # Stub _proj_set and _proj_scan_with_claude before _proj_add runs its
  # data writes, then invoke _proj_add. The stub records that _proj_set
  # was called but returns failure (simulating a write error). Because
  # the tombstone clear is now deferred to AFTER all data writes, the
  # tombstone must still be present when _proj_add returns.
  local driver="$HOME/drv.zsh"
  cat > "$driver" <<'EOF'
source "$PROJ_ROOT/proj.zsh"
_proj_scan_with_claude() { return 0; }
_proj_set() { return 1; }
_proj_add foo "$HOME/workspace/foo" >/dev/null 2>&1 || true
[[ -f "$HOME/.proj/data/.tombstones/foo" ]] && echo TOMBSTONE_KEPT
EOF
  run env PROJ_ROOT="$PROJ_ROOT" HOME="$HOME" zsh "$driver"
  assert_success
  assert_output --partial "TOMBSTONE_KEPT"
}

@test "sync: tombstone file is committed + tracked in the bare repo" {
  setup_git_identity

  mkdir -p "$HOME/workspace/foo"
  run proj add foo "$HOME/workspace/foo"
  local bare="$HOME/remote.git"
  local url
  url=$(make_bare_repo "$bare")
  set_sync_repo "$url"
  run proj_yes sync
  assert_success

  run proj rm foo
  assert_success
  run proj sync
  assert_success

  # Bare repo HEAD tree should now contain .tombstones/foo
  run bash -c "git --git-dir='$bare' ls-tree -r HEAD"
  assert_success
  assert_output --partial ".tombstones/foo"
}

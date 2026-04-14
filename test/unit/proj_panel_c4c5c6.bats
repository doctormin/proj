#!/usr/bin/env bats
# Tests for Phase 2c Units C4 (multi-select + batch ops), C5 (smart filter
# prefix), and C6 (sort toggle). Three units, one file — they all touch
# _proj_interactive, so the coverage is naturally shared.

load '../test_helper'

_add() {
  local name="$1"
  mkdir -p "$HOME/workspace/$name"
  proj add "$name" "$HOME/workspace/$name" >/dev/null
}

_add_remote() {
  local name="$1" host="${2:-user@ai4s}"
  proj list >/dev/null  # trigger schema init
  mkdir -p "$HOME/.proj/data/$name"
  echo remote > "$HOME/.proj/data/$name/type"
  echo active > "$HOME/.proj/data/$name/status"
  echo "$host" > "$HOME/.proj/data/$name/host"
  echo "/srv/$name" > "$HOME/.proj/data/$name/remote_path"
  echo "2026-01-01 00:00" > "$HOME/.proj/data/$name/updated"
}

# Invoke a proj internal zsh helper (like _proj_filter_names) inside the
# same subshell that sources proj.zsh. Returns stdout verbatim.
proj_helper() {
  local fn="$1"; shift
  zsh -c '
    source "$1"; shift
    fn="$1"; shift
    "$fn" "$@"
  ' _proj_test "$PROJ_ROOT/proj.zsh" "$fn" "$@"
}

# ── C5: _proj_filter_names ──────────────────────────────────────────────

@test "_proj_filter_names :active returns only active projects" {
  _add foo
  _add bar
  proj status bar paused >/dev/null

  run proj_helper _proj_filter_names :active
  assert_success
  assert_line "foo"
  refute_line "bar"
}

@test "_proj_filter_names :paused returns only paused projects" {
  _add foo
  _add bar
  proj status foo paused >/dev/null

  run proj_helper _proj_filter_names :paused
  assert_success
  assert_line "foo"
  refute_line "bar"
}

@test "_proj_filter_names :stale returns projects older than 30d" {
  _add fresh
  _add ancient
  echo "2020-01-01 00:00" > "$(proj_data_dir)/ancient/updated"

  run proj_helper _proj_filter_names :stale
  assert_success
  assert_line "ancient"
  refute_line "fresh"
}

@test "_proj_filter_names :remote returns only remote projects" {
  _add foo
  _add_remote srv-a

  run proj_helper _proj_filter_names :remote
  assert_success
  assert_line "srv-a"
  refute_line "foo"
}

@test "_proj_filter_names :local excludes remote projects" {
  _add foo
  _add_remote srv-a

  run proj_helper _proj_filter_names :local
  assert_success
  assert_line "foo"
  refute_line "srv-a"
}

@test "_proj_filter_names :missing returns projects whose path is gone" {
  _add keep
  _add gone
  rm -rf "$HOME/workspace/gone"

  run proj_helper _proj_filter_names :missing
  assert_success
  assert_line "gone"
  refute_line "keep"
}

@test "_proj_filter_names :tag=work matches tagged projects only" {
  _add foo
  _add bar
  proj tag foo work >/dev/null
  proj tag bar personal >/dev/null

  run proj_helper _proj_filter_names :tag=work
  assert_success
  assert_line "foo"
  refute_line "bar"
}

@test "_proj_filter_names :tag= (empty) errors out" {
  _add foo
  run proj_helper _proj_filter_names :tag=
  assert_failure
  assert_output --partial "Empty tag"
}

@test "_proj_filter_names :unknown-thing errors out with keyword list" {
  _add foo
  run proj_helper _proj_filter_names :bogus
  assert_failure
  assert_output --partial "Unknown filter"
  assert_output --partial ":active"
}

# ── C5: dispatch routing for `proj :keyword` ───────────────────────────

@test "proj :active: dispatch routes to panel with filter" {
  _add foo
  proj status foo paused >/dev/null
  # With no active projects, the filtered panel prints "No projects match".
  run proj :active
  assert_success
  assert_output --partial "No projects match"
  assert_output --partial ":active"
}

@test "proj :bogus: dispatch propagates filter error" {
  _add foo
  run proj :bogus
  assert_failure
  assert_output --partial "Unknown filter"
}

# ── C6: _proj_sort_names ───────────────────────────────────────────────

@test "_proj_sort_names name: alphabetical ascending" {
  _add zebra
  _add apple
  _add mango
  local out
  out="$(printf '%s\n' zebra apple mango | proj_helper _proj_sort_names name)"
  local expected="apple
mango
zebra"
  assert_equal "$out" "$expected"
}

@test "_proj_sort_names updated: newest first, ties broken by name" {
  _add foo
  _add bar
  _add baz
  echo "2026-03-01 10:00" > "$(proj_data_dir)/foo/updated"
  echo "2026-01-01 10:00" > "$(proj_data_dir)/bar/updated"
  echo "2026-03-01 10:00" > "$(proj_data_dir)/baz/updated"

  local out
  out="$(printf '%s\n' foo bar baz | proj_helper _proj_sort_names updated)"
  # foo and baz tie at 2026-03-01; alphabetical break → baz before foo.
  local expected="baz
foo
bar"
  assert_equal "$out" "$expected"
}

@test "_proj_sort_names status: active < paused < blocked < done" {
  _add a
  _add b
  _add c
  _add d
  proj status a active  >/dev/null
  proj status b paused  >/dev/null
  proj status c blocked >/dev/null
  proj status d done    >/dev/null

  local out
  out="$(printf '%s\n' d c b a | proj_helper _proj_sort_names status)"
  local expected="a
b
c
d"
  assert_equal "$out" "$expected"
}

@test "_proj_sort_names empty input is a no-op" {
  # Pipe an empty stdin straight into the helper — mustn't crash.
  run bash -c "printf '' | zsh -c 'source \"\$1\" && _proj_sort_names name' _proj_test \"$PROJ_ROOT/proj.zsh\""
  assert_success
  [ -z "$output" ]
}

@test "_proj_sort_next cycles updated → name → status → progress → updated" {
  assert_equal "$(proj_helper _proj_sort_next updated)" "name"
  assert_equal "$(proj_helper _proj_sort_next name)" "status"
  assert_equal "$(proj_helper _proj_sort_next status)" "progress"
  assert_equal "$(proj_helper _proj_sort_next progress)" "updated"
}

# ── C6: proj config sort persistence ────────────────────────────────────

@test "proj config sort <mode>: persists to config" {
  run proj config sort name
  assert_success
  assert_output --partial "sort"
  grep -q "^sort=name" "$HOME/.proj/config"
}

@test "proj config sort: shows current when no arg" {
  # Seed the config first via the setter so the directory exists.
  proj config sort status >/dev/null
  run proj config sort
  assert_success
  assert_output --partial "status"
}

@test "proj config sort <bogus>: refuses invalid mode" {
  run proj config sort frobnitz
  assert_failure
  assert_output --partial "Invalid sort mode"
}

# ── C4: batch action parsing (unit-level) ──────────────────────────────
#
# The batch-status and batch-delete dispatch uses zsh word-splitting
# `${=target}` to expand a space-separated list of names from fzf's
# `{+1}` marker. These tests pre-seed FZF_TEST_RESPONSES to simulate:
#   call 1: panel returns `batch-status:foo bar`  (Ctrl-S with 2 selected)
#   call 2: prompt returns the new status (`paused`)

@test "panel batch-status: updates all selected projects" {
  _add foo
  _add bar
  export FZF_TEST_RESPONSES=$'batch-status:foo bar\npaused'
  export FZF_TEST_STATE="$HOME/fzf-state"

  run proj
  assert_success
  assert_output --partial "paused"
  assert_equal "$(proj_field foo status)" "paused"
  assert_equal "$(proj_field bar status)" "paused"
}

@test "panel batch-status: empty selection warns and bails" {
  _add foo
  export FZF_TEST_RESPONSES=$'batch-status:\n'
  export FZF_TEST_STATE="$HOME/fzf-state"

  run proj
  assert_success
  assert_output --partial "No projects selected"
  # foo's status is unchanged.
  assert_equal "$(proj_field foo status)" "active"
}

@test "panel batch-delete → Mark as done: flips every selected status" {
  _add foo
  _add bar
  export FZF_TEST_RESPONSES=$'batch-delete:foo bar\n✓ Mark as done'
  export FZF_TEST_STATE="$HOME/fzf-state"

  run proj
  assert_success
  assert_equal "$(proj_field foo status)" "done"
  assert_equal "$(proj_field bar status)" "done"
}

@test "panel batch-delete → Remove: erases every selected project" {
  _add foo
  _add bar
  export FZF_TEST_RESPONSES=$'batch-delete:foo bar\n✗ Remove project'
  export FZF_TEST_STATE="$HOME/fzf-state"

  run proj
  assert_success
  [ ! -d "$(proj_data_dir)/foo" ]
  [ ! -d "$(proj_data_dir)/bar" ]
}

# ── C4: multi-select bindings exist in the fzf invocation ──────────────

@test "panel fzf invocation includes --multi and ctrl-s/d/o bindings" {
  _add foo
  export FZF_CALLS_LOG="$HOME/fzf-calls.log"
  : > "$FZF_CALLS_LOG"
  export FZF_TEST_RESPONSE=""
  run proj
  local logged; logged="$(cat "$FZF_CALLS_LOG")"
  [[ "$logged" == *"--multi"* ]] || false
  [[ "$logged" == *"ctrl-s:become"* ]] || false
  [[ "$logged" == *"ctrl-d:become"* ]] || false
  [[ "$logged" == *"ctrl-o:become"* ]] || false
}

@test "panel header line shows current sort mode" {
  _add foo
  export FZF_CALLS_LOG="$HOME/fzf-calls.log"
  : > "$FZF_CALLS_LOG"
  export FZF_TEST_RESPONSE=""
  _PROJ_SORT_OVERRIDE=name run proj
  [[ "$(cat "$FZF_CALLS_LOG")" == *"sort: name"* ]] || false
}

@test "panel border label shows active filter when given" {
  _add foo
  export FZF_CALLS_LOG="$HOME/fzf-calls.log"
  : > "$FZF_CALLS_LOG"
  export FZF_TEST_RESPONSE=""
  run proj :active
  [[ "$(cat "$FZF_CALLS_LOG")" == *":active"* ]] || false
}

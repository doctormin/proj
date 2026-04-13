#!/usr/bin/env bats
# Tests for the tag system: proj tag / proj untag / proj tags.

load '../test_helper'

_add() {
  local name="$1"
  mkdir -p "$HOME/workspace/$name"
  proj add "$name" "$HOME/workspace/$name" >/dev/null
}

# proj tag

@test "proj tag: creates tags file with multiple tags, sorted, deduped" {
  _add foo
  run proj tag foo work client-a
  assert_success
  assert_output --partial "Tagged foo"

  local f="$(proj_data_dir)/foo/tags"
  assert [ -f "$f" ]
  local content="$(cat "$f")"
  [[ "$content" == *"work"* ]]
  [[ "$content" == *"client-a"* ]]
  # Sorted: client-a should come before work (alphabetical)
  local first_line="$(head -1 "$f")"
  assert_equal "$first_line" "client-a"
}

@test "proj tag: idempotent union (no duplicates)" {
  _add foo
  proj tag foo work >/dev/null
  proj tag foo work >/dev/null

  local count
  count=$(grep -c '^work$' "$(proj_data_dir)/foo/tags")
  assert_equal "$count" "1"
}

@test "proj tag: updates the 'updated' timestamp" {
  _add foo
  # Overwrite updated to a known stale value
  echo "2020-01-01 00:00" > "$(proj_data_dir)/foo/updated"

  run proj tag foo work
  assert_success

  local after
  after="$(proj_field foo updated)"
  [ "$after" != "2020-01-01 00:00" ]
}

@test "proj tag: rejects tag with uppercase" {
  _add foo
  run proj tag foo BAD
  assert_failure
  assert_output --partial "Invalid tag"
  assert [ ! -f "$(proj_data_dir)/foo/tags" ]
}

@test "proj tag: rejects tag with space" {
  _add foo
  run proj tag foo "bad tag"
  assert_failure
  assert_output --partial "Invalid tag"
}

@test "proj tag: rejects empty tag" {
  _add foo
  run proj tag foo ""
  assert_failure
  assert_output --partial "Invalid tag"
}

@test "proj tag: rejects tag starting with hyphen" {
  _add foo
  run proj tag foo "-bad"
  assert_failure
  assert_output --partial "Invalid tag"
}

@test "proj tag: rejects special characters" {
  _add foo
  run proj tag foo "work!"
  assert_failure
  assert_output --partial "Invalid tag"
}

@test "proj tag: rejects mixed valid and invalid (atomic)" {
  _add foo
  run proj tag foo good BAD
  assert_failure
  assert [ ! -f "$(proj_data_dir)/foo/tags" ]
}

@test "proj tag: errors on nonexistent project" {
  run proj tag ghost work
  assert_failure
  assert_output --partial "does not exist"
}

@test "proj tag: shows usage when called without tag args" {
  _add foo
  run proj tag foo
  assert_failure
  assert_output --partial "Usage"
}

# proj untag

@test "proj untag: rejects tag with embedded newline (history log injection defense)" {
  _add foo
  proj tag foo work >/dev/null

  # A newline-containing arg would otherwise let the user append a forged
  # history.log line via _proj_history_append. Validate before doing
  # anything.
  run proj untag foo $'bad\nline'
  assert_failure
  assert_output --partial "Invalid tag"
}

@test "proj untag: rejects tag with uppercase (same validation as proj tag)" {
  _add foo
  proj tag foo work >/dev/null

  run proj untag foo WORK
  assert_failure
  assert_output --partial "Invalid tag"
}

@test "proj tag: duplicate args are deduped (no +work +work in history)" {
  _add foo

  run proj tag foo work work work
  assert_success

  local log="$(proj_data_dir)/foo/history.log"
  # History should show a single `+work`, not `+work +work +work`
  local detail
  detail=$(grep '|tag|' "$log" | head -1 | cut -d'|' -f3)
  assert_equal "$detail" "+work"
}

@test "proj untag: duplicate args are deduped (no -work -work in history)" {
  _add foo
  proj tag foo work >/dev/null

  run proj untag foo work work work
  assert_success

  local log="$(proj_data_dir)/foo/history.log"
  # Last tag event should show a single `-work`
  local detail
  detail=$(grep '|tag|' "$log" | tail -1 | cut -d'|' -f3)
  assert_equal "$detail" "-work"
}

@test "proj tag: re-adding existing tag is a no-op (no bump, no history event)" {
  _add foo
  proj tag foo work >/dev/null

  # Pin updated to a known old value
  echo "2020-01-01 00:00" > "$(proj_data_dir)/foo/updated"

  run proj tag foo work
  assert_success
  assert_output --partial "Already tagged"

  # updated was NOT bumped
  assert_equal "$(proj_field foo updated)" "2020-01-01 00:00"

  # history.log has only the first tag event, not two
  local log="$(proj_data_dir)/foo/history.log"
  local count
  count=$(grep -c '|tag|' "$log")
  assert_equal "$count" "1"
}

@test "proj untag: removing non-existent tag is a no-op (no bump, no history event)" {
  _add foo
  proj tag foo work >/dev/null
  echo "2020-01-01 00:00" > "$(proj_data_dir)/foo/updated"

  run proj untag foo nonexistent
  assert_success
  assert_output --partial "Not tagged"

  assert_equal "$(proj_field foo updated)" "2020-01-01 00:00"

  local log="$(proj_data_dir)/foo/history.log"
  [ -f "$log" ] && ! grep -q '|tag|-nonexistent' "$log"
}

@test "proj untag: removes a single tag, leaves others" {
  _add foo
  proj tag foo work client-a deploy >/dev/null

  run proj untag foo work
  assert_success

  local content="$(cat "$(proj_data_dir)/foo/tags")"
  refute [[ "$content" == *"work"* ]]
  [[ "$content" == *"client-a"* ]]
  [[ "$content" == *"deploy"* ]]
}

@test "proj untag: deletes tags file when last tag removed" {
  _add foo
  proj tag foo work >/dev/null

  run proj untag foo work
  assert_success
  assert [ ! -f "$(proj_data_dir)/foo/tags" ]
}

@test "proj untag: removes multiple tags in one call" {
  _add foo
  proj tag foo work client-a deploy >/dev/null

  run proj untag foo work client-a
  assert_success

  local content="$(cat "$(proj_data_dir)/foo/tags")"
  [[ "$content" == *"deploy"* ]]
  refute [[ "$content" == *"work"* ]]
  refute [[ "$content" == *"client-a"* ]]
}

@test "proj untag: no-op on missing tags file prints helpful message" {
  _add foo
  run proj untag foo work
  assert_success
  assert_output --partial "no tags"
}

@test "proj untag: errors on nonexistent project" {
  run proj untag ghost work
  assert_failure
  assert_output --partial "does not exist"
}

# proj tags

@test "proj tags: lists all tags across projects with counts" {
  _add foo
  _add bar
  _add baz
  proj tag foo work client-a >/dev/null
  proj tag bar work >/dev/null
  proj tag baz deploy >/dev/null

  run proj tags
  assert_success
  assert_output --partial "#work"
  assert_output --partial "#client-a"
  assert_output --partial "#deploy"
  # work appears on 2 projects
  assert_output --regexp "#work[[:space:]]+.*2.*bar"
}

@test "proj tags: empty project list prints empty-state message" {
  run proj tags
  assert_success
  assert_output --partial "No tags yet"
}

@test "proj tags: project without any tags is excluded" {
  _add foo
  _add bar
  proj tag foo work >/dev/null

  run proj tags
  assert_success
  assert_output --partial "work"
  # bar should not appear — it has no tags
  refute_output --regexp "#.*bar"
}

@test "proj tag: help text mentions tag subcommands" {
  run proj help
  assert_success
  assert_output --partial "tag"
  assert_output --partial "untag"
  assert_output --partial "tags"
}

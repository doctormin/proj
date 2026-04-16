#!/usr/bin/env bats
# proj ls: compact/verbose rendering, filter logic, edge cases.
# Added to cover the P2/P3 review findings batch.

load '../test_helper'

# Helper: create N test projects with known fields.
create_projects() {
  local i
  for i in "$@"; do
    mkdir -p "$HOME/code/$i"
    proj add "$i" "$HOME/code/$i"
  done
}

@test "proj ls shows projects in compact mode by default" {
  create_projects alpha bravo
  run proj ls
  assert_success
  assert_output --partial "alpha"
  assert_output --partial "bravo"
}

@test "proj ls -v shows verbose output" {
  create_projects alpha
  run proj ls -v
  assert_success
  # Verbose mode includes the arrow path indicator.
  assert_output --partial "→"
}

@test "proj ls rejects double filter" {
  create_projects alpha
  run proj ls active done
  assert_failure
  assert_output --partial "one filter"
}

@test "proj ls accepts single filter" {
  create_projects alpha
  run proj ls active
  assert_success
}

@test "proj ls active -v is equivalent to proj ls -v active" {
  create_projects alpha
  run proj ls active -v
  assert_success
  assert_output --partial "→"
}

@test "proj ls rejects unknown argument" {
  run proj ls bogus
  assert_failure
  assert_output --partial "Unknown"
}

@test "proj ls done filter hides active projects" {
  create_projects alpha
  # alpha defaults to active, so 'done' filter should show nothing useful
  run proj ls done
  assert_success
  # Should not contain "alpha" in the project listing
  refute_output --partial "alpha"
}

@test "proj ls truncates long project names in compact mode" {
  # Create a project with name >16 chars
  local longname="abcdefghijklmnopqrstuvwxyz"
  mkdir -p "$HOME/code/$longname"
  proj add "$longname" "$HOME/code/$longname"
  run proj ls
  assert_success
  # The name column should show truncated form (15 chars + …).
  # The path column may still contain the full name — that's fine.
  assert_output --partial "abcdefghijklmno…"
}

@test "proj ls handles project with no updated timestamp gracefully" {
  mkdir -p "$HOME/code/alpha"
  proj add alpha "$HOME/code/alpha"
  # Remove the updated file to simulate missing timestamp
  rm -f "$HOME/.proj/data/alpha/updated"
  run proj ls
  assert_success
  assert_output --partial "unknown"
}

@test "proj ls with COLUMNS=0 does not crash" {
  create_projects alpha
  COLUMNS=0 run proj ls
  assert_success
}

@test "proj ls with non-numeric COLUMNS falls back gracefully" {
  create_projects alpha
  COLUMNS="notanumber" run proj ls
  assert_success
}

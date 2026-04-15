#!/usr/bin/env bats
# Smoke tests for the core CRUD flow.
# If these pass, the framework itself works and we can trust everything else.

load '../test_helper'

@test "proj --version prints version string" {
  run proj --version
  assert_success
  assert_output --partial "proj 1.1.0-dev"
}

@test "proj -v is alias for --version" {
  run proj -v
  assert_success
  assert_output --partial "proj 1.1.0-dev"
}

@test "sourcing proj.zsh creates ~/.proj/data" {
  run proj --version
  assert_success
  assert [ -d "$HOME/.proj/data" ]
}

@test "_proj_names survives a hostile ls alias defined before source" {
  # Regression: if the user's .zshrc aliases `ls` to `eza --icons --color=always`
  # (or similar) before sourcing proj.zsh, zsh bakes the alias into every
  # function body that uses bare `ls`. The ANSI/icon prefixes then break
  # _proj_names' basename regex and the panel reports "no projects".
  # _proj_names (and the other ls call sites) must use `command ls` so they
  # bypass user-defined aliases at function-definition time.
  mkdir -p "$HOME/workspace/myapp"
  run proj add myapp "$HOME/workspace/myapp"
  assert_success

  # Source proj.zsh in a subshell where `ls` is aliased BEFORE the source —
  # this mirrors the real .zshrc execution order. The fake `ls` prints
  # ANSI-wrapped output that would fail a `^[a-zA-Z0-9]` anchor.
  run zsh -c '
    alias ls='\''printf "\033[34mPOISONED\033[0m\n"'\''
    source "$1"
    _proj_names
  ' _proj_test "$PROJ_ROOT/proj.zsh"
  assert_success
  assert_output --partial "myapp"
  refute_output --partial "POISONED"
}

@test "proj add creates a local project with expected fields" {
  mkdir -p "$HOME/workspace/myapp"
  run proj add myapp "$HOME/workspace/myapp"
  assert_success

  local dir="$(proj_data_dir)/myapp"
  assert [ -d "$dir" ]
  assert_equal "$(proj_field myapp type)" "local"
  assert_equal "$(proj_field myapp status)" "active"
  [ -n "$(proj_field myapp updated)" ]
}

@test "proj add stores path via machine-id routing" {
  mkdir -p "$HOME/workspace/myapp"
  run proj add myapp "$HOME/workspace/myapp"
  assert_success

  local mid
  mid="$(machine_id)"
  [ -n "$mid" ]
  assert [ -f "$(proj_data_dir)/myapp/path.$mid" ]
  assert_equal "$(cat $(proj_data_dir)/myapp/path.$mid)" "$HOME/workspace/myapp"
}

@test "proj rm removes the project directory" {
  mkdir -p "$HOME/workspace/myapp"
  run proj add myapp "$HOME/workspace/myapp"
  assert_success

  run proj rm myapp
  assert_success
  assert [ ! -d "$(proj_data_dir)/myapp" ]
}

@test "proj status changes the status field" {
  mkdir -p "$HOME/workspace/myapp"
  run proj add myapp "$HOME/workspace/myapp"
  assert_success

  run proj status myapp paused
  assert_success
  assert_equal "$(proj_field myapp status)" "paused"
}

@test "proj status rejects invalid status values" {
  mkdir -p "$HOME/workspace/myapp"
  run proj add myapp "$HOME/workspace/myapp"

  run proj status myapp nonsense
  assert_failure
  assert_equal "$(proj_field myapp status)" "active"
}

@test "proj edit updates desc field" {
  mkdir -p "$HOME/workspace/myapp"
  run proj add myapp "$HOME/workspace/myapp"

  run proj edit myapp desc "A new description"
  assert_success
  assert_equal "$(proj_field myapp desc)" "A new description"
}

@test "proj edit rejects unknown field" {
  mkdir -p "$HOME/workspace/myapp"
  run proj add myapp "$HOME/workspace/myapp"

  run proj edit myapp bogus "value"
  assert_failure
}

@test "proj list prints the project name" {
  mkdir -p "$HOME/workspace/myapp"
  run proj add myapp "$HOME/workspace/myapp"

  run proj list
  assert_success
  assert_output --partial "myapp"
}

@test "proj list shows host:remote_path for remote projects (B3)" {
  # Regression: before B3, _proj_list read only the `path` field for every
  # row, so remote projects (whose `path` is empty on this machine) rendered
  # as a dangling `→` with nothing after it. Should now show host:remote_path
  # the same way preview.sh renders it.
  run proj add-remote api-server user@server.example.com:/srv/api
  assert_success

  run proj list
  assert_success
  assert_output --partial "api-server"
  assert_output --partial "user@server.example.com:/srv/api"
  # The dangling arrow case must not surface: no line that is just "→ "
  # with only whitespace after. Looking for the specific broken form.
  refute_output --regexp '→ $'
}

@test "proj list still shows the local path for type=local projects" {
  # Sanity: the B3 fix must not regress the local rendering path.
  mkdir -p "$HOME/workspace/localapp"
  run proj add localapp "$HOME/workspace/localapp"
  assert_success

  run proj list
  assert_success
  assert_output --partial "localapp"
  assert_output --partial "$HOME/workspace/localapp"
}

# ── compact `proj ls` (default, one line per project) ────────────────────

# Helper: number of non-blank lines in bats $output.
_count_nonblank_lines() {
  printf '%s\n' "$output" | grep -cE '.'
}

@test "proj ls compact: one non-blank line per project" {
  mkdir -p "$HOME/workspace/a" "$HOME/workspace/b" "$HOME/workspace/c"
  proj add a "$HOME/workspace/a"
  proj add b "$HOME/workspace/b"
  proj add c "$HOME/workspace/c"

  run proj ls
  assert_success
  # Three projects → three data rows (plus possible leading/trailing blanks).
  local n
  n=$(printf '%s\n' "$output" | grep -cE '.')
  [ "$n" -eq 3 ]
}

@test "proj ls compact: row contains name, status, rel-time token, path" {
  mkdir -p "$HOME/workspace/myapp"
  proj add myapp "$HOME/workspace/myapp"

  run proj ls
  assert_success
  assert_output --partial "myapp"
  assert_output --partial "active"
  # Fresh project: either "just now" or "Nm ago" — both acceptable.
  printf '%s\n' "$output" | grep -qE '(just now|[0-9]+m ago)'
  assert_output --partial "$HOME/workspace/myapp"
}

@test "proj ls compact: active icon ● appears" {
  mkdir -p "$HOME/workspace/x"
  proj add x "$HOME/workspace/x"
  run proj ls
  assert_success
  assert_output --partial "●"
}

@test "proj ls compact: remote project renders host:remote_path" {
  run proj add-remote api user@host.example.com:/srv/api
  assert_success
  run proj ls
  assert_success
  assert_output --partial "api"
  assert_output --partial "user@host.example.com:/srv/api"
  refute_output --regexp '→ $'
}

@test "proj ls compact: indices start at 1 and increment" {
  mkdir -p "$HOME/workspace/one" "$HOME/workspace/two"
  proj add one "$HOME/workspace/one"
  proj add two "$HOME/workspace/two"
  run proj ls
  assert_success
  printf '%s\n' "$output" | grep -qE '^[[:space:]]*1[[:space:]]'
  printf '%s\n' "$output" | grep -qE '^[[:space:]]*2[[:space:]]'
}

@test "proj ls active filters out done projects" {
  mkdir -p "$HOME/workspace/live" "$HOME/workspace/shipped"
  proj add live "$HOME/workspace/live"
  proj add shipped "$HOME/workspace/shipped"
  proj status shipped done

  run proj ls active
  assert_success
  assert_output --partial "live"
  refute_output --partial "shipped"
}

@test "proj ls done shows only done projects" {
  mkdir -p "$HOME/workspace/live" "$HOME/workspace/shipped"
  proj add live "$HOME/workspace/live"
  proj add shipped "$HOME/workspace/shipped"
  proj status shipped done

  run proj ls done
  assert_success
  assert_output --partial "shipped"
  refute_output --partial "live"
}

@test "proj ls -v triggers verbose mode (multi-line briefing)" {
  mkdir -p "$HOME/workspace/myapp"
  proj add myapp "$HOME/workspace/myapp"
  proj edit myapp desc "my description"

  run proj ls -v
  assert_success
  assert_output --partial "myapp"
  # Verbose output has the "Last updated:" line; compact does not.
  assert_output --partial "Last updated:"
  assert_output --partial "my description"
}

@test "proj ls --verbose is an alias for -v" {
  mkdir -p "$HOME/workspace/myapp"
  proj add myapp "$HOME/workspace/myapp"

  run proj ls --verbose
  assert_success
  assert_output --partial "Last updated:"
}

@test "proj ls -v active combines flag and filter" {
  mkdir -p "$HOME/workspace/live" "$HOME/workspace/shipped"
  proj add live "$HOME/workspace/live"
  proj add shipped "$HOME/workspace/shipped"
  proj status shipped done

  run proj ls -v active
  assert_success
  assert_output --partial "live"
  assert_output --partial "Last updated:"
  refute_output --partial "shipped"
}

@test "proj ls active -v combines filter and flag (order-independent)" {
  mkdir -p "$HOME/workspace/live" "$HOME/workspace/shipped"
  proj add live "$HOME/workspace/live"
  proj add shipped "$HOME/workspace/shipped"
  proj status shipped done

  run proj ls active -v
  assert_success
  assert_output --partial "live"
  assert_output --partial "Last updated:"
  refute_output --partial "shipped"
}

@test "proj ls bogus fails with list_bad_arg error" {
  run proj ls bogus
  assert_failure
  assert_output --partial "bogus"
}

@test "proj ls compact: relative time 2h ago when updated was 2h in the past" {
  mkdir -p "$HOME/workspace/myapp"
  proj add myapp "$HOME/workspace/myapp"
  # Rewrite updated to now - 2h in the same YYYY-MM-DD HH:MM format.
  local ts
  ts=$(date -v-2H '+%Y-%m-%d %H:%M' 2>/dev/null || date -d '2 hours ago' '+%Y-%m-%d %H:%M')
  echo "$ts" > "$(proj_data_dir)/myapp/updated"

  run proj ls
  assert_success
  assert_output --partial "2h ago"
}

@test "proj ls compact: relative time 5d ago when updated was 5d in the past" {
  mkdir -p "$HOME/workspace/myapp"
  proj add myapp "$HOME/workspace/myapp"
  local ts
  ts=$(date -v-5d '+%Y-%m-%d %H:%M' 2>/dev/null || date -d '5 days ago' '+%Y-%m-%d %H:%M')
  echo "$ts" > "$(proj_data_dir)/myapp/updated"

  run proj ls
  assert_success
  assert_output --partial "5d ago"
}

@test "proj ls compact: empty updated field renders as unknown" {
  mkdir -p "$HOME/workspace/myapp"
  proj add myapp "$HOME/workspace/myapp"
  : > "$(proj_data_dir)/myapp/updated"

  run proj ls
  assert_success
  assert_output --partial "unknown"
}

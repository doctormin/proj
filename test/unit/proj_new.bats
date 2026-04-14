#!/usr/bin/env bats
# Tests for `proj new <template>` (Phase 2d Unit D3).
#
# Each test points PROJ_TEMPLATE_DIR at the repo's templates/ tree so we
# don't depend on the on-disk ~/.proj/templates/ layout (which install.sh
# writes, but bats never runs install.sh). The mock `claude` on PATH is
# silent-on-miss, so the post-add scan is a no-op and never flakes.

load '../test_helper'

setup() {
  TEST_HOME=$(mktemp -d -t proj-test.XXXXXX)
  export TEST_HOME
  export HOME="$TEST_HOME"
  export PATH="$PROJ_ROOT/test/fixtures/bin:$PATH"
  export LANG="en_US.UTF-8"
  unset PROJ_LANG

  # Point every `proj new` call at the templates bundled in this repo —
  # install.sh isn't part of the test harness, so $PROJ_DIR/templates/
  # would otherwise be empty.
  export PROJ_TEMPLATE_DIR="$PROJ_ROOT/templates"

  mkdir -p "$HOME"
}

# ── happy paths ──────────────────────────────────────────────────────────

@test "proj new node: creates target, substitutes NAME, registers project" {
  run proj new node myapp "$TEST_HOME/out/myapp"
  assert_success
  assert_output --partial "Created"
  assert_output --partial "Added project"

  [ -f "$TEST_HOME/out/myapp/package.json" ]
  [ -f "$TEST_HOME/out/myapp/README.md" ]
  [ -f "$TEST_HOME/out/myapp/.gitignore" ]

  # NAME substitution worked.
  run cat "$TEST_HOME/out/myapp/package.json"
  assert_output --partial '"name": "myapp"'
  refute_output --partial '"name": "NAME"'

  # Project was registered.
  local mid; mid="$(machine_id)"
  [ -f "$(proj_data_dir)/myapp/path.$mid" ]
  assert_equal "$(proj_field myapp type)" "local"
}

@test "proj new node: .proj-init.sh is removed after run" {
  run proj new node myapp "$TEST_HOME/out/myapp"
  assert_success
  [ ! -f "$TEST_HOME/out/myapp/.proj-init.sh" ]
}

@test "proj new node: README.md has NAME replaced with project name" {
  run proj new node myapp "$TEST_HOME/out/myapp"
  assert_success
  run cat "$TEST_HOME/out/myapp/README.md"
  assert_output --partial "# myapp"
  refute_output --partial "# NAME"
}

@test "proj new python: hyphen in name → underscore in src/ dirname" {
  run proj new python my-app "$TEST_HOME/out/my-app"
  assert_success
  # PEP 621 keeps the hyphen in project.name.
  run cat "$TEST_HOME/out/my-app/pyproject.toml"
  assert_output --partial 'name = "my-app"'
  # But the package directory must be a valid Python identifier.
  [ -d "$TEST_HOME/out/my-app/src/my_app" ]
  [ ! -d "$TEST_HOME/out/my-app/src/NAME" ]
  [ ! -d "$TEST_HOME/out/my-app/src/my-app" ]
}

@test "proj new rust: creates Cargo.toml with substituted name" {
  run proj new rust myapp "$TEST_HOME/out/myapp"
  assert_success
  [ -f "$TEST_HOME/out/myapp/Cargo.toml" ]
  run cat "$TEST_HOME/out/myapp/Cargo.toml"
  assert_output --partial 'name = "myapp"'
  refute_output --partial 'name = "NAME"'
  run cat "$TEST_HOME/out/myapp/src/main.rs"
  assert_output --partial "Hello from myapp"
}

@test "proj new zsh-plugin: renames NAME.plugin.zsh → <name>.plugin.zsh" {
  run proj new zsh-plugin myplugin "$TEST_HOME/out/myplugin"
  assert_success
  [ -f "$TEST_HOME/out/myplugin/myplugin.plugin.zsh" ]
  [ ! -f "$TEST_HOME/out/myplugin/NAME.plugin.zsh" ]
  run cat "$TEST_HOME/out/myplugin/myplugin.plugin.zsh"
  refute_output --partial "NAME"
}

@test "proj new: PROJ_CLONE_DIR drives default target when \$3 omitted" {
  PROJ_CLONE_DIR="$TEST_HOME/clones" run proj new node myapp
  assert_success
  [ -d "$TEST_HOME/clones/myapp" ]
  [ -f "$TEST_HOME/clones/myapp/package.json" ]
}

@test "proj new: registered path matches the resolved target dir" {
  run proj new rust widget "$TEST_HOME/out/widget"
  assert_success
  local mid; mid="$(machine_id)"
  local stored; stored="$(cat "$(proj_data_dir)/widget/path.$mid")"
  assert_equal "$stored" "$TEST_HOME/out/widget"
}

@test "proj new: claude scan hook triggered after register" {
  # The mock `claude` writes its invocation to CLAUDE_CALL_LOG when the
  # env var is set. Here we just assert the scan message is printed by
  # _proj_add, which proves _proj_scan_with_claude ran.
  run proj new node myapp "$TEST_HOME/out/myapp"
  assert_success
  assert_output --partial "Scanning project with Claude"
}

# ── error / guard paths ───────────────────────────────────────────────────

@test "proj new: nonexistent template → error names available templates" {
  run proj new nosuch myapp "$TEST_HOME/out/myapp"
  assert_failure
  assert_output --partial "Template not found"
  assert_output --partial "node"
  assert_output --partial "python"
}

@test "proj new: target directory already exists → refuses (no clobber)" {
  mkdir -p "$TEST_HOME/out/myapp"
  echo "precious" > "$TEST_HOME/out/myapp/keepme.txt"
  run proj new node myapp "$TEST_HOME/out/myapp"
  assert_failure
  assert_output --partial "already exists"
  # File untouched.
  run cat "$TEST_HOME/out/myapp/keepme.txt"
  assert_output "precious"
  # Project not registered.
  [ ! -d "$(proj_data_dir)/myapp" ]
}

@test "proj new: project name containing .. is rejected" {
  run proj new node "../evil" "$TEST_HOME/out/evil"
  assert_failure
  assert_output --partial "Invalid project name"
  [ ! -d "$TEST_HOME/out/evil" ]
}

@test "proj new: project name with leading - is rejected" {
  run proj new node "-rf" "$TEST_HOME/out/dashname"
  assert_failure
  assert_output --partial "Invalid project name"
  [ ! -d "$TEST_HOME/out/dashname" ]
}

@test "proj new: template name containing .. is rejected" {
  run proj new "../etc" myapp "$TEST_HOME/out/myapp"
  assert_failure
  assert_output --partial "Invalid template"
  [ ! -d "$TEST_HOME/out/myapp" ]
}

@test "proj new: already-registered project blocks second new" {
  run proj new node myapp "$TEST_HOME/out/myapp1"
  assert_success
  run proj new node myapp "$TEST_HOME/out/myapp2"
  assert_failure
  assert_output --partial "already exists"
  [ ! -d "$TEST_HOME/out/myapp2" ]
}

@test "proj new: missing arguments prints usage" {
  run proj new
  assert_failure
  assert_output --partial "Usage: proj new"
  run proj new node
  assert_failure
  assert_output --partial "Usage: proj new"
}

@test "proj new node: registered name recoverable via proj get/list" {
  run proj new node myapp "$TEST_HOME/out/myapp"
  assert_success
  run proj list all
  assert_success
  assert_output --partial "myapp"
}

#!/usr/bin/env bash
# proj new rust: single-project init hook.
# $1 = project name  $2 = absolute target path  cwd = target
# Substitutes NAME in Cargo.toml / src / README and git-inits. Does NOT
# run `cargo init` — cargo may not be installed on the user's box.
set -euo pipefail

name="${1:?name required}"

_subst() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local tmpf
  tmpf="$(mktemp)"
  sed "s/NAME/${name}/g" "$file" > "$tmpf" && mv "$tmpf" "$file"
}

_subst Cargo.toml
_subst src/main.rs
_subst README.md

if [[ ! -d .git ]]; then
  git init -q 2>/dev/null || true
fi

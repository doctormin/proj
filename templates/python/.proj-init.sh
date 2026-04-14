#!/usr/bin/env bash
# proj new python: single-project init hook.
# $1 = project name  $2 = absolute target path  cwd = target
# Renames src/NAME → src/<module_name> and substitutes NAME in text files.
set -euo pipefail

name="${1:?name required}"

# Python module names can't contain hyphens — map to underscores for the
# package directory, but keep the original hyphenated name in pyproject's
# [project].name (PEP 621 allows hyphens there).
module_name="${name//-/_}"

_subst() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local tmpf
  tmpf="$(mktemp)"
  sed "s/NAME/${name}/g" "$file" > "$tmpf" && mv "$tmpf" "$file"
}

_subst pyproject.toml
_subst README.md

if [[ -d src/NAME && "$module_name" != "NAME" ]]; then
  mv src/NAME "src/${module_name}"
fi

if [[ ! -d .git ]]; then
  git init -q 2>/dev/null || true
fi

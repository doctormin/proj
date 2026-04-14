#!/usr/bin/env bash
# proj new node: single-project init hook.
# $1 = project name  $2 = absolute target path  cwd = target
# Must be idempotent. Invoked by _proj_new after copying the template.
set -euo pipefail

name="${1:?name required}"
# $2 is accepted but unused — cwd is already the target.

_subst() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local tmpf
  tmpf="$(mktemp)"
  # No sed -i for BSD/GNU portability. NAME is a fixed literal placeholder;
  # $name has already been validated by _proj_new against the basename regex,
  # so no sed-metachar escaping is needed here.
  sed "s/NAME/${name}/g" "$file" > "$tmpf" && mv "$tmpf" "$file"
}

_subst package.json
_subst README.md

if [[ ! -d .git ]]; then
  git init -q 2>/dev/null || true
fi

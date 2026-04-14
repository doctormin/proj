#!/usr/bin/env bash
# proj new zsh-plugin: single-project init hook.
# $1 = project name  $2 = absolute target path  cwd = target
# Renames NAME.plugin.zsh → <name>.plugin.zsh and substitutes NAME in the
# plugin body + README.
set -euo pipefail

name="${1:?name required}"

_subst() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local tmpf
  tmpf="$(mktemp)"
  sed "s/NAME/${name}/g" "$file" > "$tmpf" && mv "$tmpf" "$file"
}

if [[ -f "NAME.plugin.zsh" && "$name" != "NAME" ]]; then
  mv "NAME.plugin.zsh" "${name}.plugin.zsh"
fi

_subst "${name}.plugin.zsh"
_subst README.md

if [[ ! -d .git ]]; then
  git init -q 2>/dev/null || true
fi

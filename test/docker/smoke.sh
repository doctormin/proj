#!/bin/bash
# test/docker/smoke.sh — end-to-end smoke test inside a container.
#
# This covers three things bats alone does not:
#   1. install.sh itself, in local mode, against a clean HOME
#   2. the post-install source path (zsh sourcing ~/.proj/proj.zsh the same
#      way a real user's .zshrc would)
#   3. the bats suite against Linux coreutils (GNU sed/stat) — the thing
#      v1 Unit 11 was supposed to verify but never did
#
# Runs as root inside the container because containers are ephemeral and
# HOME=/root is fine for proj's per-machine data dir convention.

set -euo pipefail

header() {
  echo ""
  echo "=== $* ==="
}

header "Platform"
uname -a
if command -v lsb_release &>/dev/null; then
  lsb_release -a 2>/dev/null
else
  cat /etc/os-release | head -5
fi

header "Tool versions"
zsh --version
bats --version
fzf --version
jq --version
git --version

header "Install proj via install.sh (local mode)"
cd /app
bash install.sh

header "Verify installed files"
test -f "$HOME/.proj/proj.zsh"       || { echo "missing: proj.zsh"; exit 1; }
test -x "$HOME/.proj/preview.sh"     || { echo "missing or non-exec: preview.sh"; exit 1; }
test -f "$HOME/.proj/version"        || { echo "missing: version"; exit 1; }
echo "  proj version: $(cat "$HOME/.proj/version")"

header "Exercise proj via the zshrc source path"
zsh -c 'source "$HOME/.proj/proj.zsh" && proj --version'

header "Add a project + check status through the installed path"
mkdir -p /tmp/sample-project
# Put the test's mock claude on PATH so _proj_scan_with_claude succeeds
# without needing real auth. Use zsh -e so any step in the chain — add,
# status, list filtering — fails the whole smoke test instead of being
# silently swallowed (original version masked failures via `|| true`).
PATH="/app/test/fixtures/bin:$PATH" zsh -ec '
  source "$HOME/.proj/proj.zsh"
  proj add sample /tmp/sample-project
  proj list | grep -q sample
  proj status sample done
  proj list | grep -q done
  echo "  add -> status -> list cycle OK"
'

header "Run full bats suite against Linux coreutils"
cd /app
./test/run.sh

header "All docker smoke checks passed"

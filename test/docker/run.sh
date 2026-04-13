#!/bin/bash
# test/docker/run.sh — build and run Ubuntu docker smoke tests locally.
#
# Usage:
#   ./test/docker/run.sh           # both 22.04 and 24.04
#   ./test/docker/run.sh 22        # just 22.04
#   ./test/docker/run.sh 24        # just 24.04
#
# This mirrors the CI Ubuntu matrix for offline reproduction. CI already
# runs the same steps on GitHub's runners, so this is belt-and-suspenders
# coverage and a faster local feedback loop when debugging Linux-specific
# issues without pushing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if ! command -v docker &>/dev/null; then
  echo "error: docker not installed" >&2
  echo "  macOS:  brew install --cask docker-desktop  (or: brew install colima && colima start)" >&2
  exit 127
fi

if ! docker info &>/dev/null; then
  echo "error: docker daemon not reachable" >&2
  echo "  Start the daemon with: colima start  (or: open -a 'Docker Desktop')" >&2
  exit 1
fi

declare -a versions
if [[ $# -eq 0 ]]; then
  versions=("22" "24")
else
  versions=("$@")
fi

for v in "${versions[@]}"; do
  if [[ ! -f "$SCRIPT_DIR/Dockerfile.ubuntu${v}" ]]; then
    echo "error: no such Dockerfile: Dockerfile.ubuntu${v}" >&2
    exit 2
  fi
done

for v in "${versions[@]}"; do
  echo ""
  echo "=================================================="
  echo "  Ubuntu ${v}.04"
  echo "=================================================="

  docker build \
    --file "$SCRIPT_DIR/Dockerfile.ubuntu${v}" \
    --tag "proj-test-ubuntu${v}:latest" \
    "$REPO_ROOT"

  docker run --rm "proj-test-ubuntu${v}:latest"
done

echo ""
echo "=================================================="
echo "  All Ubuntu docker smoke checks passed."
echo "=================================================="

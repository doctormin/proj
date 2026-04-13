#!/usr/bin/env bash
# test/run.sh — run the full bats suite.
#
# Usage:
#   ./test/run.sh              # run all tests
#   ./test/run.sh proj_basics  # run one file (stem name, no .bats suffix)
#   ./test/run.sh -v           # pass -v (verbose) through to bats
#
# Exit code propagates from bats.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Sanity: bats installed?
if ! command -v bats &>/dev/null; then
  echo "error: bats is not installed" >&2
  echo "  macOS:  brew install bats-core" >&2
  echo "  Ubuntu: apt install bats" >&2
  exit 127
fi

# Sanity: vendored helpers present?
for lib in bats-support bats-assert; do
  if [[ ! -f "test/lib/$lib/load.bash" ]]; then
    echo "error: test/lib/$lib not vendored" >&2
    echo "  Restore with: cd test/lib && git clone --depth 1 https://github.com/bats-core/$lib.git" >&2
    exit 127
  fi
done

# Select tests: either a specific stem or all .bats files under test/unit/
declare -a targets=()
declare -a bats_flags=()

for arg in "$@"; do
  case "$arg" in
    -*)
      bats_flags+=("$arg")
      ;;
    *)
      if [[ -f "test/unit/${arg}.bats" ]]; then
        targets+=("test/unit/${arg}.bats")
      else
        echo "error: no such test file: test/unit/${arg}.bats" >&2
        exit 2
      fi
      ;;
  esac
done

if [[ ${#targets[@]} -eq 0 ]]; then
  targets=(test/unit/*.bats)
fi

echo "Running ${#targets[@]} test file(s) with bats $(bats --version | awk '{print $2}')..."
echo ""

exec bats "${bats_flags[@]}" "${targets[@]}"

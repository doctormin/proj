#!/usr/bin/env bash
# docs/_screenshot-src/render.sh — regenerate docs/screenshot-panel-*.png.
#
# Usage:
#   ./render.sh           # both en + zh, write to docs/
#   ./render.sh en        # just en
#   ./render.sh zh        # just zh
#
# Pipeline:
#   generate-panel.zsh <lang>  →  <lang>.ansi  →  freeze  →  docs/screenshot-panel-<lang>.png
#
# Dependencies:
#   - zsh (for the generator)
#   - python3 (for display-width calculation via unicodedata)
#   - freeze (https://github.com/charmbracelet/freeze)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCS_DIR="$REPO_ROOT/docs"

if ! command -v freeze &>/dev/null; then
  echo "error: freeze is not installed" >&2
  echo "  install: brew install charmbracelet/tap/freeze" >&2
  exit 127
fi

if ! command -v python3 &>/dev/null; then
  echo "error: python3 is required for display-width calculation" >&2
  exit 127
fi

# Freeze parameters — keep in sync with the other screenshots so style matches.
FREEZE_ARGS=(
  --font.family "JetBrains Mono"
  --font.size 14
  --line-height 1.35
  --theme base16
  --window
  --padding "28,32,28,32"
  --margin "44,44,44,44"
  --background "#0b0b12"
  --border.radius 14
  --width 1200
  --shadow.blur 12
  --shadow.x 0
  --shadow.y 4
  -l ansi
)

langs=()
if [[ $# -eq 0 ]]; then
  langs=(en zh)
else
  langs=("$@")
fi

for lang in "${langs[@]}"; do
  if [[ "$lang" != "en" && "$lang" != "zh" ]]; then
    echo "error: unknown language: $lang (expected en or zh)" >&2
    exit 2
  fi

  ansi_out="$SCRIPT_DIR/panel-$lang.ansi"
  png_out="$DOCS_DIR/screenshot-panel-$lang.png"

  echo "  generating $lang → $ansi_out"
  "$SCRIPT_DIR/generate-panel.zsh" "$lang" > "$ansi_out"

  echo "  rendering   $lang → $png_out"
  freeze "$ansi_out" -o "$png_out" "${FREEZE_ARGS[@]}" >/dev/null

  echo "  done: $png_out ($(wc -c < "$png_out" | tr -d ' ') bytes)"
done

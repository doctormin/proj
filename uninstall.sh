#!/usr/bin/env bash
# proj uninstaller
set -e

PROJ_DIR="$HOME/.proj"

echo ""
echo "  Uninstalling proj..."
echo ""

# Remove plugin files (keep user data by default)
rm -f "$PROJ_DIR/proj.zsh" "$PROJ_DIR/preview.sh" "$PROJ_DIR/version" "$PROJ_DIR/schema_version" "$PROJ_DIR/machine-id"

# Remove source line from .zshrc
if [[ -f "$HOME/.zshrc" ]] && grep -q 'proj.zsh' "$HOME/.zshrc" 2>/dev/null; then
  tmpf=$(mktemp)
  grep -v 'proj.zsh' "$HOME/.zshrc" | grep -v '# proj — terminal project manager' > "$tmpf"
  mv "$tmpf" "$HOME/.zshrc"
  echo "  Removed from .zshrc"
fi

if [[ "$1" == "--all" ]]; then
  rm -rf "$PROJ_DIR"
  echo "  Removed all data at $PROJ_DIR"
else
  echo "  Plugin files removed. Project data preserved at $PROJ_DIR/data/"
  echo "  To remove everything: ./uninstall.sh --all"
fi

echo ""
echo "  Done. Restart your shell."
echo ""

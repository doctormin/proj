#!/usr/bin/env bash
# proj installer
set -e

PROJ_DIR="$HOME/.proj"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "  Installing proj..."
echo ""

# Copy files
mkdir -p "$PROJ_DIR/data"
cp "$REPO_DIR/proj.zsh" "$PROJ_DIR/proj.zsh"
cp "$REPO_DIR/preview.sh" "$PROJ_DIR/preview.sh"
chmod +x "$PROJ_DIR/preview.sh"

# Add to shell config if not already present
SHELL_RC=""
if [[ -f "$HOME/.zshrc" ]]; then
  SHELL_RC="$HOME/.zshrc"
elif [[ -f "$HOME/.bashrc" ]]; then
  SHELL_RC="$HOME/.bashrc"
fi

if [[ -n "$SHELL_RC" ]]; then
  if ! grep -q 'proj.zsh' "$SHELL_RC" 2>/dev/null; then
    echo '' >> "$SHELL_RC"
    echo '# proj — terminal project manager' >> "$SHELL_RC"
    echo '[ -f "$HOME/.proj/proj.zsh" ] && source "$HOME/.proj/proj.zsh"' >> "$SHELL_RC"
    echo "  Added to $SHELL_RC"
  else
    echo "  Already in $SHELL_RC"
  fi
fi

# Optional: starship integration
if command -v starship &>/dev/null; then
  STARSHIP_CONFIG="${STARSHIP_CONFIG:-$HOME/.config/starship.toml}"
  if [[ -f "$STARSHIP_CONFIG" ]] && ! grep -q 'custom.projects' "$STARSHIP_CONFIG" 2>/dev/null; then
    cat >> "$STARSHIP_CONFIG" << 'TOML'

# proj — active project counter
[custom.projects]
command = 'echo "$PROJ_ACTIVE_COUNT"'
when = '[ "${PROJ_ACTIVE_COUNT:-0}" -gt 0 ]'
format = '[📋 $output proj](bold cyan) '
shell = ['bash', '--noprofile', '--norc']
TOML
    echo "  Starship integration added"
  fi
fi

echo ""
echo "  Done! Restart your shell or run:"
echo "    source $PROJ_DIR/proj.zsh"
echo ""

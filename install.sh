#!/usr/bin/env bash
# proj installer — works both from local clone and curl pipe
set -e

PROJ_VERSION="1.0.0"
PROJ_DIR="$HOME/.proj"
GITHUB_REPO="doctormin/proj"

# ── Colors ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { echo -e "  ${GREEN}✓${RESET} $1"; }
warn()  { echo -e "  ${YELLOW}!${RESET} $1"; }
fail()  { echo -e "  ${RED}✗${RESET} $1"; exit 1; }

# ── Dependency checks ──
check_deps() {
  # Required: zsh
  if ! command -v zsh &>/dev/null; then
    fail "zsh is required but not installed.
    Install with:
      macOS:  zsh is the default shell
      Ubuntu: sudo apt install zsh
      Arch:   sudo pacman -S zsh"
  fi

  # Required: fzf
  if ! command -v fzf &>/dev/null; then
    fail "fzf is required but not installed.
    Install with:
      macOS:  brew install fzf
      Ubuntu: sudo apt install fzf
      Arch:   sudo pacman -S fzf"
  fi

  # Optional: claude
  if ! command -v claude &>/dev/null; then
    warn "claude CLI not found — AI features (scan, cc, meta) will be unavailable"
  fi

  # Optional: jq
  if ! command -v jq &>/dev/null; then
    warn "jq not found — Claude session preview will be limited"
  fi

  # Optional info (silent)
  command -v eza &>/dev/null || true
  command -v starship &>/dev/null || true
}

# ── Detect pipe vs local mode ──
is_pipe_mode() {
  # When piped from curl, $0 is "bash" or "sh", not a file path
  [[ ! -f "$0" ]]
}

# ── Download files from GitHub Release ──
download_release() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local url="https://github.com/${GITHUB_REPO}/archive/refs/tags/v${PROJ_VERSION}.tar.gz"

  echo -e "  ${CYAN}Downloading proj v${PROJ_VERSION}...${RESET}"

  if command -v curl &>/dev/null; then
    curl -fsSL "$url" | tar xz -C "$tmpdir" 2>/dev/null
  elif command -v wget &>/dev/null; then
    wget -qO- "$url" | tar xz -C "$tmpdir" 2>/dev/null
  else
    # Fallback: download individual files from main branch
    local raw="https://raw.githubusercontent.com/${GITHUB_REPO}/main"
    curl -fsSL "$raw/proj.zsh" -o "$tmpdir/proj.zsh" || fail "Download failed"
    curl -fsSL "$raw/preview.sh" -o "$tmpdir/preview.sh" || fail "Download failed"
    REPO_DIR="$tmpdir"
    return
  fi

  # Find the extracted directory
  REPO_DIR=$(find "$tmpdir" -maxdepth 1 -type d -name "proj-*" | head -1)
  [[ -z "$REPO_DIR" ]] && REPO_DIR="$tmpdir"
}

# ── Install files ──
install_files() {
  mkdir -p "$PROJ_DIR/data"
  cp "$REPO_DIR/proj.zsh" "$PROJ_DIR/proj.zsh"
  cp "$REPO_DIR/preview.sh" "$PROJ_DIR/preview.sh"
  chmod +x "$PROJ_DIR/preview.sh"
  echo "$PROJ_VERSION" > "$PROJ_DIR/version"
  info "Files installed to $PROJ_DIR"
}

# ── Add to .zshrc ──
setup_shell() {
  local shell_rc="$HOME/.zshrc"

  if [[ ! -f "$shell_rc" ]]; then
    warn "No .zshrc found — create one first, then add:"
    echo "    [ -f \"\$HOME/.proj/proj.zsh\" ] && source \"\$HOME/.proj/proj.zsh\""
    return
  fi

  if ! grep -q 'proj.zsh' "$shell_rc" 2>/dev/null; then
    echo '' >> "$shell_rc"
    echo '# proj — terminal project manager' >> "$shell_rc"
    echo '[ -f "$HOME/.proj/proj.zsh" ] && source "$HOME/.proj/proj.zsh"' >> "$shell_rc"
    info "Added to $shell_rc"
  else
    info "Already in $shell_rc"
  fi
}

# ── Starship integration ──
setup_starship() {
  if ! command -v starship &>/dev/null; then return; fi

  local cfg="${STARSHIP_CONFIG:-$HOME/.config/starship.toml}"
  if [[ -f "$cfg" ]] && ! grep -q 'custom.projects' "$cfg" 2>/dev/null; then
    cat >> "$cfg" << 'TOML'

# proj — active project counter
[custom.projects]
command = 'echo "$PROJ_ACTIVE_COUNT"'
when = '[ "${PROJ_ACTIVE_COUNT:-0}" -gt 0 ]'
format = '[📋 $output proj](bold cyan) '
shell = ['bash', '--noprofile', '--norc']
TOML
    info "Starship integration added"
  fi
}

# ══════════════════════════════════════════════════════════════
# Main
# ══════════════════════════════════════════════════════════════

echo ""
echo -e "  ${BOLD}Installing proj v${PROJ_VERSION}${RESET}"
echo ""

check_deps

if is_pipe_mode; then
  download_release
else
  REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

install_files
setup_shell
setup_starship

echo ""
echo -e "  ${GREEN}${BOLD}Done!${RESET} Restart your shell or run:"
echo -e "    ${CYAN}source $PROJ_DIR/proj.zsh${RESET}"
echo ""
echo -e "  ${DIM}Then try: proj add${RESET}"
echo ""

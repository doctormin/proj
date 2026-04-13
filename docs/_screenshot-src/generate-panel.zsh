#!/usr/bin/env zsh
# docs/_screenshot-src/generate-panel.zsh
#
# Generate a deterministic ANSI-text representation of the proj interactive
# panel, suitable for feeding to `freeze` as a static screenshot source.
#
# Usage:
#   ./generate-panel.zsh en > panel-en.ansi
#   ./generate-panel.zsh zh > panel-zh.ansi
#
# Why hand-crafted: the live-capture pipeline (tmux + fzf + freeze) has a
# long-standing CJK width bug where fzf counts wide chars as 1 cell but
# tmux renders them as 2, causing content to overflow the panel bottom in
# zh screenshots and border discontinuities when column counts don't
# divide cleanly. A hand-written ANSI file bypasses the TUI pipeline.

set -e

lang="${1:-en}"
if [[ "$lang" != "en" && "$lang" != "zh" ]]; then
  echo "usage: $0 <en|zh>" >&2
  exit 1
fi

# ══════════════════════════════════════════════════════════════
# Palette — Dracula-leaning, matches freeze --theme choice below.
# ══════════════════════════════════════════════════════════════
R=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
GREEN=$'\033[38;2;80;250;123m'
YELLOW=$'\033[38;2;241;250;140m'
RED=$'\033[38;2;255;85;85m'
CYAN=$'\033[38;2;139;233;253m'
PURPLE=$'\033[38;2;189;147;249m'
GRAY=$'\033[38;2;98;114;164m'
WHITE=$'\033[38;2;248;248;242m'
# Highlight row background (dark purple, matches Dracula selection)
BG_HL=$'\033[48;2;68;71;90m'
BG_OFF=$'\033[49m'

# ══════════════════════════════════════════════════════════════
# Layout constants
# ══════════════════════════════════════════════════════════════
# INNER = usable cells between the outer │ │ borders.
# LEFT + 1 (divider) + RIGHT = INNER.
# Calibrated for freeze @ 1200px wide, JetBrains Mono 14px,
# padding 28/32/28/32, margin 44/44/44/44.
INNER=120
LEFT=40
# Row format is:  │ <LEFT> │ <RIGHT> │
# Total row chars = LEFT + RIGHT + 7 (3 borders + 4 padding spaces)
# Top border total = INNER + 2 (╭ + hlines + ╮)
# For equality: LEFT + RIGHT + 7 = INNER + 2  →  RIGHT = INNER - LEFT - 5
RIGHT=$((INNER - LEFT - 5))

# ══════════════════════════════════════════════════════════════
# Width helper
# ══════════════════════════════════════════════════════════════
# display_width(): terminal cell width of a string.
# Uses python's unicodedata.east_asian_width — only W (Wide) and F (Fullwidth)
# chars are 2 cells. Ambiguous (A) chars like box-drawing and status icons
# (●◐■✓▶─│) are 1 cell, which matches freeze's go-runewidth rendering.
display_width() {
  python3 -c '
import sys
from unicodedata import east_asian_width as e
s = sys.argv[1]
print(sum(2 if e(c) in ("W","F") else 1 for c in s))
' "$1"
}

# hline(): $1 cells of "─".
hline() {
  local n="$1"
  printf '─%.0s' {1..$n}
}

# ══════════════════════════════════════════════════════════════
# Row renderer — single source of truth for every content row.
#
#   row <left_plain> <left_colored> <right_plain> <right_colored>
#
# plain versions are used for width computation; colored versions carry
# the ANSI codes and are what actually gets printed. Both must have the
# same visible width.
# ══════════════════════════════════════════════════════════════
row() {
  local lp="$1" lc="$2" rp="$3" rc="$4"
  local lw rw lpad rpad
  lw=$(display_width "$lp")
  rw=$(display_width "$rp")
  lpad=$((LEFT - lw)); (( lpad < 0 )) && lpad=0
  rpad=$((RIGHT - rw)); (( rpad < 0 )) && rpad=0
  # Format: │ <left>[pad] │ <right>[pad] │
  printf '%s│%s %s%*s %s│%s %s%*s %s│%s\n' \
    "$GRAY" "$R" \
    "$lc" "$lpad" "" \
    "$GRAY" "$R" \
    "$rc" "$rpad" "" \
    "$GRAY" "$R"
}

blank() { row "" "" "" ""; }

# ══════════════════════════════════════════════════════════════
# Language strings
# ══════════════════════════════════════════════════════════════
if [[ "$lang" == "zh" ]]; then
  T_TITLE=" Projects "
  T_HOTKEYS=" 快捷键 "
  T_DESC="描述"
  T_PROGRESS="进展"
  T_TODO="TODO"
  T_SESSIONS="Claude 会话"
  T_LAST_UPDATED="最后跟进"
  T_HK_ENTER="回车 跳转"
  T_HK_CE="^E Claude"
  T_HK_CR="^R 重扫"
  T_HK_CX="^X 关闭"
  T_HK_LABEL_ACTIVE="active"
  T_HK_LABEL_PAUSED="paused"
  T_HK_LABEL_BLOCKED="blocked"
  T_HK_LABEL_DONE="done"
  T_COUNT_SUFFIX="个项目"
  T_PROMPT="> "
  DESC_BODY="JWT 鉴权 + PostgreSQL 的 REST API"
  PROG_LINES=(
    "- JWKS 端点已完成"
    "- JWT 认证 + refresh token 轮转"
    "- Redis 限流器已配置"
  )
  TODO_LINES=(
    "- 添加 WebSocket 通知"
    "- 补集成测试"
    "- 配置 CI/CD 流水线"
  )
  SESSIONS=(
    "04-13 19:04  a8a97b6…  初始化 TypeScript 项目"
    "04-13 15:32  9b7e812…  配置 PostgreSQL 连接池"
    "04-13 10:10  4d12a43…  添加角色数据库迁移"
  )
else
  T_TITLE=" Projects "
  T_HOTKEYS=" hotkeys "
  T_DESC="Description"
  T_PROGRESS="Progress"
  T_TODO="TODO"
  T_SESSIONS="Claude Sessions"
  T_LAST_UPDATED="Last updated"
  T_HK_ENTER="Enter Resume"
  T_HK_CE="^E Claude"
  T_HK_CR="^R Rescan"
  T_HK_CX="^X Close"
  T_HK_LABEL_ACTIVE="active"
  T_HK_LABEL_PAUSED="paused"
  T_HK_LABEL_BLOCKED="blocked"
  T_HK_LABEL_DONE="done"
  T_COUNT_SUFFIX="projects"
  T_PROMPT="> "
  DESC_BODY="REST API with JWT auth and PostgreSQL"
  PROG_LINES=(
    "- JWKS endpoints implemented"
    "- JWT auth with refresh token rotation"
    "- Redis rate limiter configured"
  )
  TODO_LINES=(
    "- Add WebSocket notifications"
    "- Write integration tests"
    "- Set up CI/CD pipeline"
  )
  SESSIONS=(
    "04-13 19:04  a8a97b6…  Initialize TypeScript project"
    "04-13 15:32  9b7e812…  Setup PostgreSQL connection pool"
    "04-13 10:10  4d12a43…  Add database migration for roles"
  )
fi

# ══════════════════════════════════════════════════════════════
# Project data (names are identifiers, not translated)
# ══════════════════════════════════════════════════════════════
projects=(
  "s1-pipeline|active|2026-04-13 22:17"
  "s1-api|active|2026-04-13 15:32"
  "landing-page|paused|2026-04-12 11:28"
  "ui-refactor|blocked|2026-04-12 09:47"
  "docs|active|2026-04-11 16:51"
  "dash-api|active|2026-04-11 14:05"
  "cli|done|2026-04-10 20:04"
  "ml-ops|active|2026-04-10 16:48"
)
HIGHLIGHT_NAME="s1-api"

# ══════════════════════════════════════════════════════════════
# Status icon / color helpers
# ══════════════════════════════════════════════════════════════
icon_for() {
  case "$1" in
    active)  printf '%s' "●" ;;
    paused)  printf '%s' "◐" ;;
    blocked) printf '%s' "■" ;;
    done)    printf '%s' "✓" ;;
    *)       printf '%s' "○" ;;
  esac
}
icon_color() {
  case "$1" in
    active)  printf '%s' "$GREEN" ;;
    paused)  printf '%s' "$YELLOW" ;;
    blocked) printf '%s' "$RED" ;;
    done)    printf '%s' "$DIM" ;;
    *)       printf '%s' "$CYAN" ;;
  esac
}

# ══════════════════════════════════════════════════════════════
# Build left-pane rows (project list)
# ══════════════════════════════════════════════════════════════
# Each row: "  ● name          status    YYYY-MM-DD HH:MM"
# Highlighted row gets a ▶ prefix in place of the leading two spaces.
typeset -a left_plain left_colored
for entry in "${projects[@]}"; do
  name="${entry%%|*}"
  rest="${entry#*|}"
  st="${rest%%|*}"
  ts="${rest#*|}"
  icon=$(icon_for "$st")
  ic=$(icon_color "$st")
  sc=$ic  # status label uses same color as icon
  name_pad=$(printf '%-13s' "$name")
  st_pad=$(printf '%-8s' "$st")

  if [[ "$name" == "$HIGHLIGHT_NAME" ]]; then
    # Highlighted row: wrap content in a dark background that spans the
    # full LEFT-cell width via row_override_hl (handled below in the render loop).
    local plain="▶ $icon $name_pad $st_pad  $ts"
    left_plain+=("$plain")
    # Pre-pad inside the background so the whole LEFT cell is tinted.
    local plain_w=$(display_width "$plain")
    local pad_n=$((LEFT - plain_w)); (( pad_n < 0 )) && pad_n=0
    local pad_str=$(printf '%*s' "$pad_n" "")
    # Use a bright pink-ish arrow for visual priority (Doubao feedback).
    local PINK=$'\033[38;2;255;121;198m'
    left_colored+=("${BG_HL}${PINK}${BOLD}▶${R}${BG_HL} ${ic}${icon}${R}${BG_HL} ${BOLD}${WHITE}${name_pad}${R}${BG_HL} ${BOLD}${WHITE}${st_pad}${R}${BG_HL}  ${WHITE}${ts}${R}${BG_HL}${pad_str}${BG_OFF}")
  else
    left_plain+=("  $icon $name_pad $st_pad  $ts")
    left_colored+=("  ${ic}${icon}${R} ${BOLD}${WHITE}${name_pad}${R} ${sc}${st_pad}${R}  ${DIM}${ts}${R}")
  fi
done

# ══════════════════════════════════════════════════════════════
# Build right-pane rows (preview)
# ══════════════════════════════════════════════════════════════
typeset -a right_plain right_colored

# Header lines
right_plain+=("s1-api  ● active")
right_colored+=("${BOLD}${CYAN}s1-api${R}  ${GREEN}●${R} ${GREEN}active${R}")

right_plain+=("/tmp/work/s1-api")
right_colored+=("${DIM}/tmp/work/s1-api${R}")

right_plain+=("${T_LAST_UPDATED}: 2026-04-13 15:32")
right_colored+=("${DIM}${T_LAST_UPDATED}: 2026-04-13 15:32${R}")

right_plain+=("")
right_colored+=("")

right_plain+=("$T_DESC")
right_colored+=("${BOLD}${T_DESC}${R}")

right_plain+=("$DESC_BODY")
right_colored+=("$DESC_BODY")

right_plain+=("")
right_colored+=("")

right_plain+=("$T_PROGRESS")
right_colored+=("${BOLD}${CYAN}${T_PROGRESS}${R}")

for l in "${PROG_LINES[@]}"; do
  right_plain+=("$l")
  right_colored+=("$l")
done

right_plain+=("")
right_colored+=("")

right_plain+=("$T_TODO")
right_colored+=("${BOLD}${YELLOW}${T_TODO}${R}")

for l in "${TODO_LINES[@]}"; do
  right_plain+=("$l")
  right_colored+=("$l")
done

right_plain+=("")
right_colored+=("")

right_plain+=("${T_SESSIONS} (3 total)")
right_colored+=("${BOLD}${GREEN}${T_SESSIONS}${R} ${DIM}(3 total)${R}")

for l in "${SESSIONS[@]}"; do
  right_plain+=("$l")
  right_colored+=("${DIM}${l}${R}")
done

# ══════════════════════════════════════════════════════════════
# RENDER
# ══════════════════════════════════════════════════════════════

# --- Top border with Projects label ---
title_width=$(display_width "$T_TITLE")
top_bar_len=$((INNER - title_width - 1))
printf '%s╭─%s%s%s' "$GRAY" "$CYAN" "$T_TITLE" "$GRAY"
hline "$top_bar_len"
printf '╮%s\n' "$R"

# --- Prompt row (left "> ", right shows project header) ---
row \
  "$T_PROMPT" "${CYAN}${T_PROMPT}${R}" \
  "${right_plain[1]}" "${right_colored[1]}"

blank

# --- Main body: max(len(left), len(right)) rows ---
max_rows=${#left_plain[@]}
(( ${#right_plain[@]} > max_rows )) && max_rows=${#right_plain[@]}
# Start right pane at index 2 (skip the header that we already rendered)
right_idx=2

for i in {1..$max_rows}; do
  lp="${left_plain[$i]:-}"
  lc="${left_colored[$i]:-}"
  rp="${right_plain[$right_idx]:-}"
  rc="${right_colored[$right_idx]:-}"
  row "$lp" "$lc" "$rp" "$rc"
  right_idx=$((right_idx + 1))
done

# Render any remaining right-pane lines with empty left side
while (( right_idx <= ${#right_plain[@]} )); do
  rp="${right_plain[$right_idx]:-}"
  rc="${right_colored[$right_idx]:-}"
  row "" "" "$rp" "$rc"
  right_idx=$((right_idx + 1))
done

blank

# --- Count row ---
count_plain="${#projects[@]}/${#projects[@]} ${T_COUNT_SUFFIX}"
count_colored="${DIM}${count_plain}${R}"
row "$count_plain" "$count_colored" "" ""

# --- Inner horizontal separator ---
printf '%s├' "$GRAY"
hline "$((LEFT + 2))"
printf '┼'
hline "$((RIGHT + 2))"
printf '┤%s\n' "$R"

# --- Hotkey footer row (spans the full width) ---
hk_plain="  ${T_HK_ENTER}   ${T_HK_CE}   ${T_HK_CR}   ${T_HK_CX}"
hk_colored="  ${DIM}${T_HK_ENTER}${R}   ${DIM}${T_HK_CE}${R}   ${DIM}${T_HK_CR}${R}   ${DIM}${T_HK_CX}${R}"
hk_w=$(display_width "$hk_plain")
hk_pad=$((INNER - hk_w - 1))
(( hk_pad < 0 )) && hk_pad=0
printf '%s│%s %s%*s%s│%s\n' \
  "$GRAY" "$R" \
  "$hk_colored" "$hk_pad" "" \
  "$GRAY" "$R"

# --- Bottom border with hotkey label ---
hk_label_w=$(display_width "$T_HOTKEYS")
bottom_bar=$((INNER - hk_label_w - 1))
printf '%s╰─%s%s%s' "$GRAY" "$CYAN" "$T_HOTKEYS" "$GRAY"
hline "$bottom_bar"
printf '╯%s\n' "$R"

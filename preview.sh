#!/usr/bin/env bash
# fzf preview helper — show project details
# Usage: preview.sh <project_name>

PROJ_DATA="$HOME/.proj/data"
name="$1"
dir="$PROJ_DATA/$name"

# ── i18n ──
# PROJ_LANG is set by proj.zsh; fallback to config file, then $LANG
if [[ -z "$PROJ_LANG" ]]; then
  PROJ_LANG=$(grep -m1 '^lang=' "$HOME/.proj/config" 2>/dev/null | cut -d= -f2-)
fi
if [[ -z "$PROJ_LANG" || "$PROJ_LANG" == "auto" ]]; then
  lang="${LANG:-en_US.UTF-8}"
  [[ "$lang" == zh* ]] && PROJ_LANG="zh" || PROJ_LANG="en"
fi
if [[ "$PROJ_LANG" == zh* ]]; then
  L_DESC="描述"
  L_PROGRESS="进展"
  L_TODO="TODO"
  L_CLAUDE="Claude 会话"
  L_CLAUDE_TOTAL="(共 %s 个)"
  L_CLAUDE_RECENT="最近: %s  %s"
  L_CLAUDE_HINT="Ctrl-E 恢复"
  L_NO_SESSION="无 Claude 历史会话"
  L_FILES="目录内容"
  L_NOT_EXIST="项目不存在"
  L_LAST_UPDATED="最后跟进: %s"
else
  L_DESC="Description"
  L_PROGRESS="Progress"
  L_TODO="TODO"
  L_CLAUDE="Claude Sessions"
  L_CLAUDE_TOTAL="(%s total)"
  L_CLAUDE_RECENT="Latest: %s  %s"
  L_CLAUDE_HINT="^E to resume"
  L_NO_SESSION="No Claude session history"
  L_FILES="Files"
  L_NOT_EXIST="Project does not exist"
  L_LAST_UPDATED="Last updated: %s"
fi

[[ ! -d "$dir" ]] && echo "$L_NOT_EXIST" && exit 1

get() { [[ -f "$dir/$1" ]] && cat "$dir/$1" || echo ""; }

st=$(get status)
path=$(get path)
desc=$(get desc)
updated=$(get updated)
progress=$(get progress)
todo=$(get todo)

# 状态图标
case "$st" in
  active)  icon="● active"  ;;
  paused)  icon="◐ paused"  ;;
  blocked) icon="■ blocked" ;;
  done)    icon="✓ done"    ;;
  *)       icon="○ $st"     ;;
esac

C='\033[36m'; Y='\033[33m'; G='\033[32m'; D='\033[2m'; B='\033[1m'; R='\033[0m'

echo ""
echo -e "  ${B}${C}$name${R}  $icon"
echo -e "  ${D}$path${R}"
[[ -n "$updated" ]] && printf "  ${D}${L_LAST_UPDATED}${R}\n" "$updated"
echo ""

if [[ -n "$desc" ]]; then
  echo -e "  ${B}${L_DESC}${R}"
  echo "$desc" | while IFS= read -r line; do echo "  $line"; done
  echo ""
fi

if [[ -n "$progress" ]]; then
  echo -e "  ${B}${C}${L_PROGRESS}${R}"
  echo "$progress" | while IFS= read -r line; do echo "  $line"; done
  echo ""
fi

if [[ -n "$todo" ]]; then
  echo -e "  ${B}${Y}${L_TODO}${R}"
  echo "$todo" | while IFS= read -r line; do echo "  $line"; done
  echo ""
fi

# Claude session info
claude_dir="${path//\//-}"
session_dir="$HOME/.claude/projects/${claude_dir}"
if [[ -d "$session_dir" ]]; then
  sessions=$(command ls -t "$session_dir"/*.jsonl 2>/dev/null | head -5)
  total=$(command ls "$session_dir"/*.jsonl 2>/dev/null | wc -l | tr -d ' ')

  if [[ -n "$sessions" ]]; then
    printf "  ${B}${G}${L_CLAUDE}${R}  ${D}${L_CLAUDE_TOTAL}${R}\n" "$total"
    echo ""

    echo "$sessions" | while IFS= read -r sf; do
      sid=$(basename "$sf" .jsonl)
      stime=$(stat -f "%Sm" -t "%m-%d %H:%M" "$sf" 2>/dev/null || stat -c "%y" "$sf" 2>/dev/null | cut -d. -f1)

      # Extract first user message as summary
      summary=$(grep -m1 '"type":"user"' "$sf" 2>/dev/null \
        | jq -r '.message.content // "" | tostring | .[0:60]' 2>/dev/null)
      # Collapse whitespace
      summary=$(echo "$summary" | tr '\n' ' ' | sed 's/  */ /g')
      [[ ${#summary} -ge 60 ]] && summary="${summary:0:57}..."

      if [[ -n "$summary" ]]; then
        echo -e "  ${D}${stime}${R}  ${sid:0:8}…"
        echo -e "  ${D}  ${summary}${R}"
      else
        echo -e "  ${D}${stime}${R}  ${sid:0:8}…"
      fi
    done

    echo ""
    echo -e "  ${D}${L_CLAUDE_HINT}${R}"
  fi
else
  echo -e "  ${D}${L_NO_SESSION}${R}"
fi

# File listing
echo ""
echo -e "  ${B}${L_FILES}${R}"
if command -v eza &>/dev/null; then
  eza --icons --color=always -1 "$path" 2>/dev/null | head -15 | while IFS= read -r line; do echo "  $line"; done
else
  ls -1 "$path" 2>/dev/null | head -15 | while IFS= read -r line; do echo "  $line"; done
fi

#!/bin/bash
# Claude Code status line (global default).
# Line 1: model | session cost | ctx bar | today's total across all projects
# Line 2: rate limit bars (5-hour session, 7-day week), cached across sessions
#         so a fresh session still shows them before rate_limits arrives.

input=$(cat)

model_name=$(printf '%s' "$input" | jq -r '.model.display_name // "Claude"')
used_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
session_cost=$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // empty')

cache_dir="$HOME/.claude/.cache"
limits_cache="$HOME/.claude/statusline-limits.json"
mkdir -p "$cache_dir" 2>/dev/null

# --- ccusage (today's total, all projects), cached 60s -----------------------

ccusage_bin=""
if command -v ccusage >/dev/null 2>&1; then
  ccusage_bin="ccusage"
elif command -v npx >/dev/null 2>&1; then
  ccusage_bin="npx --yes ccusage@latest"
fi

# fetch_cached <cache-file-name> <ccusage args...>
# Reuses a cached response under 60s old; falls back to a stale cache if the
# live call fails so a flaky npx call never blanks the line.
fetch_cached() {
  local cache_file="$cache_dir/$1"
  shift
  local now mtime
  now=$(date +%s)
  if [ -f "$cache_file" ]; then
    mtime=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null)
    if [ -n "$mtime" ] && [ $((now - mtime)) -lt 60 ]; then
      cat "$cache_file"
      return
    fi
  fi
  local output=""
  if [ -n "$ccusage_bin" ]; then
    output=$($ccusage_bin "$@" 2>/dev/null)
  fi
  if [ -n "$output" ]; then
    printf '%s' "$output" > "$cache_file"
    printf '%s' "$output"
  elif [ -f "$cache_file" ]; then
    cat "$cache_file"
  fi
}

daily_json=$(fetch_cached "ccusage-daily.json" daily --json)
today=$(date +%F)
today_cost=$(printf '%s' "$daily_json" | jq -r --arg today "$today" \
  '[.daily[]? | select((.period // .date) == $today) | .totalCost] | add // empty' 2>/dev/null)

fmt_cost() {
  if [ -z "$1" ] || [ "$1" = "null" ]; then
    printf '$0.00'
  else
    printf '$%.2f' "$1"
  fi
}

# --- bars ---------------------------------------------------------------------

reset='\033[0m'
green='\033[32m'
yellow='\033[33m'
red='\033[31m'

# make_bar <pct> [suffix] -> "<colored 10-block bar> NN%<suffix>"
# Green <50, yellow 50-80, red >80.
make_bar() {
  local pct_int filled empty bar="" color i
  pct_int=$(printf '%.0f' "${1:-0}" 2>/dev/null || echo 0)
  [ "$pct_int" -lt 0 ] && pct_int=0
  [ "$pct_int" -gt 100 ] && pct_int=100

  filled=$(( (pct_int + 5) / 10 ))
  [ "$filled" -gt 10 ] && filled=10
  empty=$((10 - filled))
  for ((i = 0; i < filled; i++)); do bar="${bar}▓"; done
  for ((i = 0; i < empty; i++)); do bar="${bar}░"; done

  if [ "$pct_int" -lt 50 ]; then
    color="$green"
  elif [ "$pct_int" -le 80 ]; then
    color="$yellow"
  else
    color="$red"
  fi
  printf '%b%s%b %d%%%s' "$color" "$bar" "$reset" "$pct_int" "$2"
}

# to_epoch <resets_at> -> epoch seconds (accepts epoch numbers or ISO 8601)
to_epoch() {
  local v="$1"
  if [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    printf '%s' "${v%%.*}"
  elif [ -n "$v" ]; then
    local iso="${v%%.*}"; iso="${iso%Z}"; iso="${iso%+00:00}"
    TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%S' "$iso" +%s 2>/dev/null \
      || date -d "$v" +%s 2>/dev/null
  fi
}

# format_reset <epoch> -> "resets 6:20 PM" today, "resets Tue 2:00 PM" otherwise
format_reset() {
  local epoch="$1" hm
  hm=$(date -r "$epoch" '+%I:%M %p' 2>/dev/null || date -d "@$epoch" '+%I:%M %p')
  hm="${hm#0}"
  if [ "$(date -r "$epoch" +%F 2>/dev/null || date -d "@$epoch" +%F)" = "$(date +%F)" ]; then
    printf 'resets %s' "$hm"
  else
    printf 'resets %s %s' "$(date -r "$epoch" +%a 2>/dev/null || date -d "@$epoch" +%a)" "$hm"
  fi
}

# --- line 1 -------------------------------------------------------------------

if [ -n "$used_pct" ] && [ "$used_pct" != "null" ]; then
  ctx_bar=$(make_bar "$used_pct")
else
  ctx_bar=$(make_bar 0)
fi

printf '%s | session %s | ctx %s | today %s (all projects)\n' \
  "$model_name" "$(fmt_cost "$session_cost")" "$ctx_bar" "$(fmt_cost "$today_cost")"

# --- line 2: rate limits ------------------------------------------------------

limits=$(printf '%s' "$input" | jq -c '.rate_limits // empty' 2>/dev/null)
cached=""
if [ -n "$limits" ] && [ "$limits" != "null" ]; then
  tmp="$limits_cache.$$"
  printf '%s\n' "$limits" > "$tmp" && mv "$tmp" "$limits_cache"
elif [ -f "$limits_cache" ]; then
  limits=$(cat "$limits_cache")
  cached=" ·"
fi

now=$(date +%s)

# limit_part <label> <window-key>
limit_part() {
  local label="$1" key="$2" pct at epoch
  pct=$(printf '%s' "$limits" | jq -r --arg k "$key" '.[$k].used_percentage // empty' 2>/dev/null)
  at=$(printf '%s' "$limits" | jq -r --arg k "$key" '.[$k].resets_at // empty' 2>/dev/null)
  [ -z "$pct" ] && return
  epoch=$(to_epoch "$at")
  if [ -n "$epoch" ] && [ "$epoch" -le "$now" ]; then
    # Window already rolled over: usage is back to zero.
    printf '%s %s' "$label" "$(make_bar 0)"
  elif [ -n "$epoch" ]; then
    printf '%s %s %s' "$label" "$(make_bar "$pct" "$cached")" "$(format_reset "$epoch")"
  else
    printf '%s %s' "$label" "$(make_bar "$pct" "$cached")"
  fi
}

if [ -n "$limits" ]; then
  s=$(limit_part session five_hour)
  w=$(limit_part week seven_day)
  if [ -n "$s" ] && [ -n "$w" ]; then
    printf '%s | %s\n' "$s" "$w"
  elif [ -n "$s$w" ]; then
    printf '%s\n' "$s$w"
  fi
fi

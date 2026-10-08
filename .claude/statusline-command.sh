#!/bin/bash

# ANSI color codes
CYAN='\033[36m'
MAGENTA='\033[35m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
WHITE='\033[97m'
DIM='\033[2m'
RESET='\033[0m'

# Read JSON input
input=$(cat)

# Extract values
model_name=$(echo "$input" | jq -r '.model.display_name')
effort_level=$(echo "$input" | jq -r '.effort.level // "default"')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
input_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
output_tokens=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')

# Plan usage limits (same numbers as claude.ai > Settings > Usage)
session_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
session_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Session value at API prices (includes cache discounts; not billed on a plan)
session_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

# Prompt cache state
cache_warm=$(echo "$input" | jq -r '.prompt_cache.warm // false')
cache_expires=$(echo "$input" | jq -r '.prompt_cache.expires_at // empty')

# Working folder and git branch
current_dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')

# Build a bar of $2 blocks for percentage $1
make_bar() {
    local pct="$1" width="$2" bar=""
    local filled=$(printf "%.0f" "$(echo "scale=2; $pct * $width / 100" | bc)")
    [ "$filled" -gt "$width" ] && filled=$width
    for ((i=1; i<=width; i++)); do
        if [ $i -le "$filled" ]; then bar="${bar}█"; else bar="${bar}░"; fi
    done
    echo "$bar"
}

# Green under 50%, yellow under 80%, red from 80%
color_for() {
    local pct=$(printf "%.0f" "$1")
    if [ "$pct" -ge 80 ]; then echo "$RED"
    elif [ "$pct" -ge 50 ]; then echo "$YELLOW"
    else echo "$GREEN"; fi
}

# Format a reset epoch: time only if today, otherwise weekday + time (e.g. "2:10am", "Mon 4:00am")
format_reset() {
    local ts="$1"
    if [ "$(date -r "$ts" +%Y-%m-%d)" = "$(date +%Y-%m-%d)" ]; then
        date -r "$ts" '+%-I:%M%p' | tr 'A-Z' 'a-z'
    else
        date -r "$ts" '+%a %-I:%M%p' | sed 's/AM$/am/;s/PM$/pm/'
    fi
}

# Context window
total_tokens=$((input_tokens + output_tokens))
if [ "$total_tokens" -ge 1000 ]; then
    tokens_display=$(printf "%.0fk" "$(echo "scale=1; $total_tokens / 1000" | bc)")
else
    tokens_display="${total_tokens}"
fi
if [ -n "$used_pct" ]; then
    context_info=$(printf "ctx:[%s] %.0f%% %s" "$(make_bar "$used_pct" 10)" "$used_pct" "$tokens_display")
else
    context_info="ctx:[░░░░░░░░░░] 0% 0"
fi

# Plan limit segment: label, percentage, reset epoch
limit_segment() {
    local label="$1" pct="$2" reset="$3"
    if [ -z "$pct" ]; then
        printf "${DIM}%s: n/a${RESET}" "$label"
        return
    fi
    local c=$(color_for "$pct")
    local reset_txt=""
    [ -n "$reset" ] && reset_txt=" ${DIM}↻ $(format_reset "$reset")${RESET}"
    printf "${WHITE}%s:${RESET} ${c}[%s] %.0f%%${RESET}%b" "$label" "$(make_bar "$pct" 10)" "$pct" "$reset_txt"
}

# Folder (with ~ for home) and git branch
dir_display="${current_dir/#$HOME/~}"
branch=""
[ -n "$current_dir" ] && branch=$(git --no-optional-locks -C "$current_dir" branch --show-current 2>/dev/null)
if [ -n "$branch" ]; then
    location="${dir_display} ${MAGENTA}(${branch})${RESET}"
else
    location="${dir_display}"
fi

# Cache countdown: minutes until the prompt cache expires
now=$(date +%s)
if [ "$cache_warm" = "true" ] && [ -n "$cache_expires" ] && [ "$cache_expires" -gt "$now" ]; then
    cache_info="${GREEN}cache: warm $(( (cache_expires - now + 59) / 60 ))m${RESET}"
else
    cache_info="${DIM}cache: cold${RESET}"
fi

cost_info=$(printf "${YELLOW}\$%.2f${RESET}" "$session_cost")

# Output status line with colors
printf "${WHITE}%b${RESET} | ${CYAN}%s${RESET} ${MAGENTA}%s${RESET} | ${GREEN}%s${RESET} | %b\n%b | %b | %b" \
    "$location" "$model_name" "$effort_level" "$context_info" "$cost_info" \
    "$(limit_segment session "$session_pct" "$session_reset")" \
    "$(limit_segment week "$week_pct" "$week_reset")" \
    "$cache_info"

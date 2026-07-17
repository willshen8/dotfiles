#!/bin/bash

# ANSI color codes
CYAN='\033[36m'
MAGENTA='\033[35m'
GREEN='\033[32m'
YELLOW='\033[33m'
WHITE='\033[97m'
RESET='\033[0m'

# Read JSON input
input=$(cat)

# Extract values
model_name=$(echo "$input" | jq -r '.model.display_name')
effort_level=$(echo "$input" | jq -r '.output_style.name // "default"')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
input_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
output_tokens=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
session_id=$(echo "$input" | jq -r '.session_id')
model_id=$(echo "$input" | jq -r '.model.id')

# Cost calculation function (per million tokens)
# Sonnet 4.5: $3.00 input, $15.00 output
# Opus 4.6: $15.00 input, $75.00 output
# Haiku: $0.25 input, $1.25 output
get_costs_for_model() {
    local mid="$1"
    if [[ "$mid" == *"opus"* ]]; then
        echo "15.00 75.00"
    elif [[ "$mid" == *"haiku"* ]]; then
        echo "0.25 1.25"
    else
        # Default to Sonnet pricing
        echo "3.00 15.00"
    fi
}

costs=($(get_costs_for_model "$model_id"))
input_cost_per_mtok=${costs[0]}
output_cost_per_mtok=${costs[1]}

# Calculate cost in dollars
input_cost=$(echo "scale=4; $input_tokens * $input_cost_per_mtok / 1000000" | bc)
output_cost=$(echo "scale=4; $output_tokens * $output_cost_per_mtok / 1000000" | bc)
# bc only honors scale= for division, so round to cents with printf (also adds leading zero)
total_cost=$(printf "%.2f" "$(echo "$input_cost + $output_cost" | bc)")

# Calculate total tokens and format with 'k' suffix
total_tokens=$((input_tokens + output_tokens))
if [ "$total_tokens" -ge 1000 ]; then
    tokens_display=$(printf "%.0fk" "$(echo "scale=1; $total_tokens / 1000" | bc)")
else
    tokens_display="${total_tokens}"
fi

# Build context bar graph
bar=""
if [ -n "$used_pct" ]; then
    # Convert percentage to number of filled blocks (out of 10)
    filled=$(printf "%.0f" "$(echo "scale=2; $used_pct / 10" | bc)")
    [ "$filled" -gt 10 ] && filled=10

    # Build bar with Unicode block characters
    for ((i=1; i<=10; i++)); do
        if [ $i -le "$filled" ]; then
            bar="${bar}█"
        else
            bar="${bar}░"
        fi
    done

    context_info=$(printf "ctx:[%s] %.0f%% %s" "$bar" "$used_pct" "$tokens_display")
else
    context_info="ctx:[░░░░░░░░░░] 0% 0"
fi

# Store session data for daily tracking
daily_log_dir="$HOME/.claude/daily-usage"
mkdir -p "$daily_log_dir"
today=$(date +%Y-%m-%d)
session_log="$daily_log_dir/$today.log"

# Append current session data (session_id, model_id, input_tokens, output_tokens)
echo "$session_id|$model_id|$input_tokens|$output_tokens" >> "$session_log"

# Calculate daily totals across all sessions
daily_input=0
daily_output=0
daily_cost=0
opus_tokens=0
sonnet_tokens=0
haiku_tokens=0

# Read all unique sessions from today's log
if [ -f "$session_log" ]; then
    # Get the latest entry for each unique session_id (last occurrence wins)
    while IFS='|' read -r sid mid itok otok; do
        # Calculate cost for this session using model-specific pricing
        costs=($(get_costs_for_model "$mid"))
        in_cost_mtok=${costs[0]}
        out_cost_mtok=${costs[1]}

        session_cost=$(echo "scale=4; ($itok * $in_cost_mtok / 1000000) + ($otok * $out_cost_mtok / 1000000)" | bc)
        session_tokens=$((itok + otok))

        # Track tokens by model type
        if [[ "$mid" == *"opus"* ]]; then
            opus_tokens=$((opus_tokens + session_tokens))
        elif [[ "$mid" == *"haiku"* ]]; then
            haiku_tokens=$((haiku_tokens + session_tokens))
        else
            sonnet_tokens=$((sonnet_tokens + session_tokens))
        fi

        daily_input=$((daily_input + itok))
        daily_output=$((daily_output + otok))
        daily_cost=$(echo "scale=2; $daily_cost + $session_cost" | bc)
    done < <(awk -F'|' '{ key=$1"|"$2; lines[key] = $0 } END { for (k in lines) print lines[k] }' "$session_log")
fi

# Round daily cost to cents (bc accumulated 4-decimal session costs above)
daily_cost=$(printf "%.2f" "$daily_cost")

# Format daily total tokens with 'k' suffix
daily_total=$((daily_input + daily_output))
if [ "$daily_total" -ge 1000 ]; then
    daily_tokens_display=$(printf "%.0fk" "$(echo "scale=1; $daily_total / 1000" | bc)")
else
    daily_tokens_display="${daily_total}"
fi

# Build multi-colored bar graph for daily usage
daily_bar=""
if [ "$daily_total" -gt 0 ]; then
    bar_width=20

    # Calculate blocks for each model (proportional to their token usage)
    opus_blocks=$(printf "%.0f" "$(echo "scale=2; $opus_tokens * $bar_width / $daily_total" | bc)")
    sonnet_blocks=$(printf "%.0f" "$(echo "scale=2; $sonnet_tokens * $bar_width / $daily_total" | bc)")
    haiku_blocks=$(printf "%.0f" "$(echo "scale=2; $haiku_tokens * $bar_width / $daily_total" | bc)")

    # Adjust for rounding to ensure total equals bar_width
    total_blocks=$((opus_blocks + sonnet_blocks + haiku_blocks))
    if [ $total_blocks -lt $bar_width ]; then
        # Add remaining to the largest segment
        if [ $opus_tokens -ge $sonnet_tokens ] && [ $opus_tokens -ge $haiku_tokens ]; then
            opus_blocks=$((opus_blocks + bar_width - total_blocks))
        elif [ $sonnet_tokens -ge $haiku_tokens ]; then
            sonnet_blocks=$((sonnet_blocks + bar_width - total_blocks))
        else
            haiku_blocks=$((haiku_blocks + bar_width - total_blocks))
        fi
    elif [ $total_blocks -gt $bar_width ]; then
        # Subtract excess from the largest segment
        if [ $opus_tokens -ge $sonnet_tokens ] && [ $opus_tokens -ge $haiku_tokens ]; then
            opus_blocks=$((opus_blocks - (total_blocks - bar_width)))
        elif [ $sonnet_tokens -ge $haiku_tokens ]; then
            sonnet_blocks=$((sonnet_blocks - (total_blocks - bar_width)))
        else
            haiku_blocks=$((haiku_blocks - (total_blocks - bar_width)))
        fi
    fi

    # Build colored bar segments — solid full-block fill █ per model (cyan Opus / green Sonnet / yellow Haiku)
    daily_bar="["

    # Opus blocks (cyan)
    for ((i=0; i<opus_blocks; i++)); do
        daily_bar="${daily_bar}${CYAN}█${RESET}"
    done

    # Sonnet blocks (green)
    for ((i=0; i<sonnet_blocks; i++)); do
        daily_bar="${daily_bar}${GREEN}█${RESET}"
    done

    # Haiku blocks (yellow)
    for ((i=0; i<haiku_blocks; i++)); do
        daily_bar="${daily_bar}${YELLOW}█${RESET}"
    done

    daily_bar="${daily_bar}]"
else
    # Empty bar if no usage
    daily_bar="[░░░░░░░░░░░░░░░░░░░░]"
fi

# Output status line with colors
printf "${CYAN}%s${RESET} ${MAGENTA}%s${RESET} | ${GREEN}%s${RESET} | ${YELLOW}\$%s${RESET} | ${WHITE}today: %b %s \$%s${RESET}" "$model_name" "$effort_level" "$context_info" "$total_cost" "$daily_bar" "$daily_tokens_display" "$daily_cost"

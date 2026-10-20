#!/bin/sh
# Claude Code status line - mirrors Powerlevel10k prompt style
input=$(cat)

# Subscription usage for herdr's tab bar (~/.config/herdr/scripts/claude-usage.sh):
# the rate limits Claude Code passes here, with the time they were seen.
state="$HOME/.local/state"
mkdir -p "$state"
echo "$input" | jq -c '{seen_at: now | floor, rate_limits}' > "$state/claude-usage.json.$$" 2>/dev/null &&
  mv "$state/claude-usage.json.$$" "$state/claude-usage.json"

# Directory (basename of cwd, like \W in PS1)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
if [ -n "$cwd" ]; then
    dir=$(basename "$cwd")
else
    dir=$(basename "$(pwd)")
fi

# Git branch (skip optional lock to avoid blocking)
git_branch=""
if git -C "$cwd" rev-parse --git-dir --no-optional-locks >/dev/null 2>&1; then
    git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
fi

# Model display name
model=$(echo "$input" | jq -r '.model.display_name // empty')

# Context remaining
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# Build the status line with ANSI colors (dimmed-friendly)
output=""

# Directory segment
printf "\033[34m%s\033[0m" "$dir"

# Git branch segment
if [ -n "$git_branch" ]; then
    printf " \033[32m\xef\x9c\xa8 %s\033[0m" "$git_branch"
fi

# Model segment
if [ -n "$model" ]; then
    printf " \033[90m%s\033[0m" "$model"
fi

# Context remaining segment
if [ -n "$remaining" ]; then
    printf " \033[90mctx:%s%%\033[0m" "$(printf '%.0f' "$remaining")"
fi

echo ""

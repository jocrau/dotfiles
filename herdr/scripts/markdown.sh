#!/bin/sh
# Toggle a full-tab Markdown reader for the focused pane's repo: splits the
# focused pane, zooms it, and runs md-pick.sh (fzf picker with rendered
# preview, glow pager). Only panes opened by this script are tracked/closed.
HERDR=/opt/homebrew/bin/herdr
JQ=/opt/homebrew/bin/jq
PICK="$HOME/.config/herdr/scripts/md-pick.sh"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/herdr/markdown-panes"
mkdir -p "$(dirname "$STATE")" && touch "$STATE"

cur=$("$HERDR" pane current) || exit 1
pane=$(printf '%s' "$cur" | "$JQ" -r '.result.pane.pane_id')
tab=$(printf '%s' "$cur" | "$JQ" -r '.result.pane.tab_id')
cwd=$(printf '%s' "$cur" | "$JQ" -r '.result.pane.foreground_cwd // .result.pane.cwd')

# Forget tracked panes that no longer exist.
live=$("$HERDR" pane list | "$JQ" -r '.result.panes[] | "\(.tab_id) \(.pane_id)"')
printf '%s\n' "$live" | grep -Fxf "$STATE" > "$STATE.tmp"; mv "$STATE.tmp" "$STATE"

# Toggle off: close this tab's reader if there is one.
existing=$(awk -v t="$tab" '$1 == t { print $2; exit }' "$STATE")
if [ -n "$existing" ]; then
  "$HERDR" pane close "$existing" >/dev/null
  grep -v " $existing\$" "$STATE" > "$STATE.tmp"; mv "$STATE.tmp" "$STATE"
  exit 0
fi

# Start at the repo root (falls back to the pane's cwd outside git).
dir=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || dir=$cwd

new=$("$HERDR" pane split "$pane" --direction right --cwd "$dir" ${FOCUS:---focus} \
  | "$JQ" -r '.result.pane.pane_id // empty')
[ -n "$new" ] || exit 1
printf '%s %s\n' "$tab" "$new" >> "$STATE"

# Wait for the shell prompt before typing (slow shell startups drop input).
i=0
while [ $i -lt 30 ]; do
  "$HERDR" pane read "$new" --source visible 2>/dev/null | grep -q '[^[:space:]]' && break
  sleep 0.1; i=$((i + 1))
done
"$HERDR" pane run "$new" "exec $PICK" >/dev/null
"$HERDR" pane zoom "$new" --on >/dev/null

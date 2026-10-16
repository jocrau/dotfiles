#!/bin/sh
# Toggle a live git view in the focused herdr tab: a herdr-sidebar Source Control
# pane launched with HERDR_SIDEBAR_BACKGROUND_REFRESH=1, so it keeps polling git
# status while unfocused. Only panes opened by this script are tracked/closed.
HERDR=/opt/homebrew/bin/herdr
JQ=/opt/homebrew/bin/jq
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/herdr/live-git-panes"
mkdir -p "$(dirname "$STATE")" && touch "$STATE"

cur=$("$HERDR" pane current) || exit 1
pane=$(printf '%s' "$cur" | "$JQ" -r '.result.pane.pane_id')
tab=$(printf '%s' "$cur" | "$JQ" -r '.result.pane.tab_id')
cwd=$(printf '%s' "$cur" | "$JQ" -r '.result.pane.foreground_cwd // .result.pane.cwd')

# Forget tracked panes that no longer exist.
live=$("$HERDR" pane list | "$JQ" -r '.result.panes[] | "\(.tab_id) \(.pane_id)"')
printf '%s\n' "$live" | grep -Fxf "$STATE" > "$STATE.tmp"; mv "$STATE.tmp" "$STATE"

# Toggle off: close this tab's live git pane if there is one.
existing=$(awk -v t="$tab" '$1 == t { print $2; exit }' "$STATE")
if [ -n "$existing" ]; then
  "$HERDR" pane close "$existing" >/dev/null
  grep -v " $existing\$" "$STATE" > "$STATE.tmp"; mv "$STATE.tmp" "$STATE"
  exit 0
fi

# Toggle on: open below the focused pane, rooted at its working directory.
new=$("$HERDR" plugin pane open --plugin herdr-sidebar --entrypoint source-control \
  --placement split --direction down --target-pane "$pane" --cwd "$cwd" \
  --env HERDR_SIDEBAR_BACKGROUND_REFRESH=1 --no-focus \
  | "$JQ" -r '.result.plugin_pane.pane.pane_id // empty')
[ -n "$new" ] && printf '%s %s\n' "$tab" "$new" >> "$STATE"

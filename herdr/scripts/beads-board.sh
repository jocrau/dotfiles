#!/bin/sh
# Toggle the herdr-beads board as a full-tab overlay, opened on the Table view,
# scoped to the focused pane's repo. Replaces the plugin's open-dock action,
# whose toggle needs bash 4 (mapfile) and never closes on macOS's bash 3.2.
HERDR=/opt/homebrew/bin/herdr
JQ=/opt/homebrew/bin/jq
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/herdr/beads-board-panes"
mkdir -p "$(dirname "$STATE")" && touch "$STATE"

cur=$("$HERDR" pane current) || exit 1
tab=$(printf '%s' "$cur" | "$JQ" -r '.result.pane.tab_id')
cwd=$(printf '%s' "$cur" | "$JQ" -r '.result.pane.foreground_cwd // .result.pane.cwd')

# Forget tracked panes that no longer exist (e.g. closed with q).
live=$("$HERDR" pane list | "$JQ" -r '.result.panes[] | "\(.tab_id) \(.pane_id)"')
printf '%s\n' "$live" | grep -Fxf "$STATE" > "$STATE.tmp"; mv "$STATE.tmp" "$STATE"

# Toggle off: close this tab's board if there is one.
existing=$(awk -v t="$tab" '$1 == t { print $2; exit }' "$STATE")
if [ -n "$existing" ]; then
  "$HERDR" pane close "$existing" >/dev/null
  grep -v " $existing\$" "$STATE" > "$STATE.tmp"; mv "$STATE.tmp" "$STATE"
  exit 0
fi

new=$("$HERDR" plugin pane open --plugin herdr-beads --entrypoint board \
  --placement overlay --env "HERDR_BEADS_CWD=$cwd" ${FOCUS:---focus} \
  | "$JQ" -r '.result.plugin_pane.pane | "\(.tab_id) \(.pane_id)" // empty')
[ -n "$new" ] || exit 1
printf '%s\n' "$new" >> "$STATE"

# The board always starts in Kanban; once it has drawn, cycle K twice
# (Kanban -> List -> Table) to land on the Table view.
id=${new#* }
i=0
while [ $i -lt 40 ]; do
  "$HERDR" pane read "$id" --source visible 2>/dev/null | grep -q 'Kanban' && break
  sleep 0.1; i=$((i + 1))
done
"$HERDR" pane send-text "$id" K >/dev/null
sleep 0.1
"$HERDR" pane send-text "$id" K >/dev/null

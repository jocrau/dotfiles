#!/bin/sh
# Toggle a full-tab live beads tree (`bd list --watch`) for the focused pane's
# repo: splits the focused pane and zooms the new pane. Only panes opened by
# this script are tracked/closed.
HERDR=/opt/homebrew/bin/herdr
JQ=/opt/homebrew/bin/jq
BD=/opt/homebrew/bin/bd
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/herdr/beads-tree-panes"
mkdir -p "$(dirname "$STATE")" && touch "$STATE"

cur=$("$HERDR" pane current) || exit 1
pane=$(printf '%s' "$cur" | "$JQ" -r '.result.pane.pane_id')
tab=$(printf '%s' "$cur" | "$JQ" -r '.result.pane.tab_id')
cwd=$(printf '%s' "$cur" | "$JQ" -r '.result.pane.foreground_cwd // .result.pane.cwd')

# Forget tracked panes that no longer exist.
live=$("$HERDR" pane list | "$JQ" -r '.result.panes[] | "\(.tab_id) \(.pane_id)"')
printf '%s\n' "$live" | grep -Fxf "$STATE" > "$STATE.tmp"; mv "$STATE.tmp" "$STATE"

# Toggle off: close this tab's tree pane if there is one.
existing=$(awk -v t="$tab" '$1 == t { print $2; exit }' "$STATE")
if [ -n "$existing" ]; then
  "$HERDR" pane close "$existing" >/dev/null
  grep -v " $existing\$" "$STATE" > "$STATE.tmp"; mv "$STATE.tmp" "$STATE"
  exit 0
fi

# Root at the nearest .beads ancestor below $HOME. Without one, bd would fail
# and the pane would vanish at once, so say so instead of opening anything.
dir=$cwd
while [ "$dir" != "/" ] && [ "$dir" != "$HOME" ] && [ ! -d "$dir/.beads" ]; do dir=$(dirname "$dir"); done
if [ "$dir" = "$HOME" ] || [ ! -d "$dir/.beads" ]; then
  "$HERDR" notification show "No beads repo" --body "No .beads above $(printf %s "$cwd" | sed "s#^$HOME#~#")" --sound none >/dev/null
  exit 0
fi

new=$("$HERDR" pane split "$pane" --direction right --cwd "$dir" ${FOCUS:---focus} \
  | "$JQ" -r '.result.pane.pane_id // empty')
[ -n "$new" ] || exit 1
printf '%s %s\n' "$tab" "$new" >> "$STATE"

# Type the command only once the new shell has drawn its prompt (up to 3s);
# keystrokes sent during a slow shell startup can be dropped.
i=0
while [ $i -lt 30 ]; do
  "$HERDR" pane read "$new" --source visible 2>/dev/null | grep -q '[^[:space:]]' && break
  sleep 0.1; i=$((i + 1))
done
# No exec: if bd exits with an error, the pane stays open showing it.
"$HERDR" pane run "$new" "$BD list --limit 0 --watch" >/dev/null
"$HERDR" pane zoom "$new" --on >/dev/null

#!/bin/sh
# Toggle a full-tab beads browser (b9s: live tree, epic focus with x, detail,
# search) for the focused pane's repo, showing open (not closed) beads: splits
# the focused pane and zooms the new pane. Quitting b9s closes the pane too.
# Only panes opened by this script are tracked/closed.
HERDR=/opt/homebrew/bin/herdr
JQ=/opt/homebrew/bin/jq
B9S=/opt/homebrew/bin/b9s
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

# Root at the nearest .beads ancestor below $HOME. Without one there is
# nothing to browse, so say so instead of opening anything.
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
# Quitting b9s closes the pane; if b9s fails, the pane waits so the error
# stays readable. (Typed into the pane's zsh, hence zsh's read syntax.)
"$HERDR" pane run "$new" "$B9S || read '?b9s failed. Press Enter to close.'; exit" >/dev/null
"$HERDR" pane zoom "$new" --on >/dev/null

# b9s has no setting for the startup status filter, so once its header has
# drawn, press o (show open issues: everything but closed).
i=0
while [ $i -lt 50 ]; do
  "$HERDR" pane read "$new" --source visible 2>/dev/null | grep -q 'Issue \[' && break
  sleep 0.1; i=$((i + 1))
done
"$HERDR" pane send-text "$new" o >/dev/null

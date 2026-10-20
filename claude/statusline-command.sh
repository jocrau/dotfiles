#!/bin/sh
# Claude Code status line (statusLine in ~/.claude/settings.json runs this):
# hands over to statusline.py next to the real file this link points to.
here=$(dirname "$(readlink "$0" || echo "$0")")
exec /usr/bin/python3 -I "$here/statusline.py"

#!/bin/sh
# Claude Code status line (statusLine in ~/.claude/settings.json runs this):
# hands over to statusline.py next to the real file this link points to,
# itself a link to herdr-layout's extras/claude-statusline.py (cloned beside
# this repo, shared with others).
here=$(dirname "$(readlink "$0" || echo "$0")")
exec /usr/bin/python3 -I "$here/statusline.py"

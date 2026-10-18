# herdr + Ghostty

Ghostty starts herdr (`initial-command`) and hands it the Cmd keys below by unbinding them in `ghostty/config.ghostty`. Run `../install.sh` to link everything into place.

| Key | Does |
|---|---|
| `cmd+shift+w` | workspace picker |
| `cmd+shift+a` | give every Claude background session that isn't in herdr its own workspace (`scripts/attach-sessions.py`) |
| `cmd+o` | file sidebar (herdr-sidebar) |
| `cmd+g` | live git view: sidebar Source Control that keeps refreshing (`scripts/live-git.sh`) |
| `cmd+b` | beads browser for the current repo, showing open beads (b9s: tree, `x` focuses an epic, `Enter` detail, `/` search, `a` all, `ctrl+c` closes; `scripts/beads-tree.sh`). Needs `brew install vanderheijden86/tap/b9s` |

The Spaces sidebar shows each workspace's Claude session summary on a third line. `scripts/claude-summary.py` writes it from Claude Code hooks (`../claude/herdr-summary-hooks.json`), finding the session's pane by its live process, so renaming workspaces and moving panes is safe.

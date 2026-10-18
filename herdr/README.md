# herdr + Ghostty

Ghostty starts herdr (`initial-command`) and hands it the Cmd keys below by unbinding them in `ghostty/config.ghostty`. Run `../install.sh` to link everything into place.

| Key | Does |
|---|---|
| `cmd+shift+w` | workspace picker |
| `cmd+shift+a` | give every Claude background session that isn't in herdr its own workspace (`scripts/attach-sessions.py`) |
| `cmd+o` | file sidebar (herdr-sidebar) |
| `cmd+g` | live git view: sidebar Source Control that keeps refreshing (`scripts/live-git.sh`) |
| `cmd+b` | beads view for the current repo (`scripts/beads-view`, opened by `scripts/beads-tree.sh`): bd's own `bd list` tree with a `bd show` detail pane, open beads by default, refreshing by itself. `Enter` focuses a bead's subtree, `Backspace` goes back up, `Tab` folds, `Ctrl-A` open/all, type to filter, `Esc` closes. Needs `fzf` |

The Spaces sidebar shows each workspace's Claude session summary on a third line. `scripts/claude-summary.py` writes it from Claude Code hooks (`../claude/herdr-summary-hooks.json`), finding the session's pane by its live process, so renaming workspaces and moving panes is safe.

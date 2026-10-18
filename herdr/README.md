# herdr + Ghostty

Ghostty starts herdr (`initial-command`) and hands it the Cmd keys below by unbinding them in `ghostty/config.ghostty`. Run `../install.sh` to link everything into place.

| Key | Does |
|---|---|
| `cmd+shift+w` | workspace picker |
| `cmd+shift+a` | give every Claude background session that isn't in herdr its own workspace (`scripts/attach-sessions.py`) |
| `cmd+o` | file sidebar (herdr-sidebar) |
| `cmd+g` | live git view: sidebar Source Control that keeps refreshing (`scripts/live-git.sh`) |
| `cmd+b` | beads view for the current repo (`scripts/beads-view`, opened by `scripts/beads-tree.sh`): bd's own `bd list` tree with short, parent-relative IDs and a detail pane, open beads by default, refreshing by itself. `Enter` focuses a bead's subtree, `Backspace` goes back up, `Tab` folds, `1`–`9` (empty filter) fold the tree to that many levels and `0` unfolds it, `Ctrl-L` edits labels (ticked = kept, type a new one), `Ctrl-A` open/all, type to filter, `Esc` closes. Needs `fzf`. Which labels show in rows, which are read-only and which are suggested is set in `../beads-view/config.json` (linked to `~/.config/beads-view/config.json`) |

The Spaces sidebar shows each workspace's Claude session summary on a third line. `scripts/claude-summary.py` writes it from Claude Code hooks (`../claude/herdr-summary-hooks.json`), finding the session's pane by its live process, so renaming workspaces and moving panes is safe.

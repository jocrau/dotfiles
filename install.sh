#!/bin/sh
# Link the herdr and Ghostty setup from this repo into place, like ~/.zshrc.
# Existing files are moved aside as <file>.bak-<timestamp> before linking.
# Safe to re-run: paths that already point here are left alone.
set -eu
REPO=$(cd "$(dirname "$0")" && pwd)
STAMP=$(date +%Y%m%d-%H%M%S)

link() {
  src=$REPO/$1
  dst=$2
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    echo "ok      $dst"
    return
  fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    mv "$dst" "$dst.bak-$STAMP"
    echo "backup  $dst -> $dst.bak-$STAMP"
  fi
  ln -s "$src" "$dst"
  echo "linked  $dst -> $src"
}

link herdr/config.toml "$HOME/.config/herdr/config.toml"
for script in "$REPO"/herdr/scripts/*; do
  [ -f "$script" ] || continue  # not __pycache__
  name=$(basename "$script")
  link "herdr/scripts/$name" "$HOME/.config/herdr/scripts/$name"
done
# herdr-app: only the files that are mine; the app writes the rest of
# ~/.config/herdr-app itself (AGENTS.md, *.d.ts, view.json, shared.json, ...).
for f in keys.json settings.json layouts/my-main.json; do
  link "herdr-app/$f" "$HOME/.config/herdr-app/$f"
done
for mod in "$REPO"/herdr-app/mods/*/; do
  name=$(basename "$mod")
  # A mod that imports its own modules is linked as a whole folder: herdr-app
  # refuses an import whose real path is outside the mod's folder.
  if ls "$mod"*.js | grep -qv '/main\.js$'; then
    link "herdr-app/mods/$name" "$HOME/.config/herdr-app/mods/$name"
    continue
  fi
  for f in "$mod"*; do
    link "herdr-app/mods/$name/$(basename "$f")" "$HOME/.config/herdr-app/mods/$name/$(basename "$f")"
  done
done
link ghostty/config.ghostty "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
link beads-view/config.json "$HOME/.config/beads-view/config.json"
link claude/statusline-command.sh "$HOME/.claude/statusline-command.sh"
link claude/skills/app-browser/SKILL.md "$HOME/.claude/skills/app-browser/SKILL.md"
link herdr/scripts/herdr-up "$HOME/.local/bin/herdr-up"
link bin/agent-browser "$HOME/bin/agent-browser"

# The repo is public: scan staged changes for secrets before every commit.
git -C "$REPO" config core.hooksPath git-hooks
echo "hooks   core.hooksPath -> git-hooks (gitleaks pre-commit)"

cat <<EOF

Not linked (do once by hand on a new machine):
  - herdr-app:          curl -fsSL https://releases.herdr.dev/app/install.sh | sh  (also installs herdr-core, hc)
  - herdr:              curl -fsSL https://herdr.dev/install.sh | sh  (not Homebrew: herdr update and live handoff need it); later updates: herdr-up
  - herdr plugins:      while read p; do herdr plugin install --yes "\$p"; done < "$REPO/herdr/plugins.txt"
  - herdr link plugin:  herdr plugin link "$REPO/herdr/plugins/open-in-editor"  (Ctrl-click file links -> VS Code)
  - herdr-sidebar:      press s in the sidebar, turn Auto-open off and dock left
  - Claude Code hooks:  merge claude/herdr-summary-hooks.json into ~/.claude/settings.json
  - agent-browser:      npm install -g agent-browser  (bin/agent-browser wraps it: one visible Chrome and login profile per repo)
  - Private shell setup: create ~/.zshrc.local (work paths, aliases) and ~/.zsh_secrets; neither is in this repo
  - Commit identity:    git -C "$REPO" config user.email <id>+<login>@users.noreply.github.com
  - Reload:             herdr server reload-config; kill -USR2 \$(pgrep -x ghostty)
EOF

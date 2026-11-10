#!/bin/sh
# Link the herdr-app and Ghostty setup from this repo into place, like ~/.zshrc.
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

# herdr-app: only the files that are mine; the app writes the rest of
# ~/.config/herdr-app itself (AGENTS.md, *.d.ts, view.json, shared.json, ...).
for f in keys.json settings.json layouts/my-main.json; do
  link "herdr-app/$f" "$HOME/.config/herdr-app/$f"
done
# Mods shared with others live in the herdr-layout repo (github.com/jocrau/herdr-layout),
# cloned beside this one; only personal mods stay here. Mods are linked as whole
# folders: herdr-app refuses an import whose real path is outside the mod's folder.
LAYOUT=${HERDR_LAYOUT:-$(dirname "$REPO")/herdr-layout}
for mod in "$REPO"/herdr-app/mods/*/ "$LAYOUT"/mods/*/; do
  [ -d "$mod" ] || continue
  name=$(basename "$mod")
  dst="$HOME/.config/herdr-app/mods/$name"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "${mod%/}" ]; then echo "ok      $dst"; continue; fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then mv "$dst" "$dst.bak-$STAMP"; echo "backup  $dst -> $dst.bak-$STAMP"; fi
  ln -s "${mod%/}" "$dst"; echo "linked  $dst -> ${mod%/}"
done
[ -d "$LAYOUT/mods" ] || echo "missing $LAYOUT: clone github.com/jocrau/herdr-layout beside this repo (or set HERDR_LAYOUT)"
link ghostty/config.ghostty "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
link beads-view/config.json "$HOME/.config/beads-view/config.json"
[ -f "$LAYOUT/mods/beads/beads-view" ] && ln -sfn "$LAYOUT/mods/beads/beads-view" "$HOME/.local/bin/beads-view"  # beads-view on PATH too
link claude/statusline-command.sh "$HOME/.claude/statusline-command.sh"
link claude/skills/app-browser/SKILL.md "$HOME/.claude/skills/app-browser/SKILL.md"
link bin/agent-browser "$HOME/bin/agent-browser"

# The repo is public: scan staged changes for secrets before every commit.
git -C "$REPO" config core.hooksPath git-hooks
echo "hooks   core.hooksPath -> git-hooks (gitleaks pre-commit)"

cat <<EOF

Not linked (do once by hand on a new machine):
  - herdr-app:          curl -fsSL https://releases.herdr.dev/app/install.sh | sh  (also installs herdr-core, hc)
  - herdr-layout:       git clone git@github.com:jocrau/herdr-layout.git "$(dirname "$REPO")/herdr-layout"  (the shared mods and the Claude status line; before running this script)
  - agent-browser:      npm install -g agent-browser  (bin/agent-browser wraps it: one visible Chrome and login profile per repo)
  - Private shell setup: create ~/.zshrc.local (work paths, aliases) and ~/.zsh_secrets; neither is in this repo
  - Commit identity:    git -C "$REPO" config user.email <id>+<login>@users.noreply.github.com
  - Reload:             Ghostty: kill -USR2 \$(pgrep -x ghostty); herdr-app reloads its files itself
EOF

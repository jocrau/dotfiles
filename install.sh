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
  name=$(basename "$script")
  link "herdr/scripts/$name" "$HOME/.config/herdr/scripts/$name"
done
link ghostty/config.ghostty "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"

# The repo is public: scan staged changes for secrets before every commit.
git -C "$REPO" config core.hooksPath git-hooks
echo "hooks   core.hooksPath -> git-hooks (gitleaks pre-commit)"

cat <<EOF

Not linked (do once by hand on a new machine):
  - herdr plugins:      while read p; do herdr plugin install --yes "\$p"; done < "$REPO/herdr/plugins.txt"
  - herdr-sidebar:      press s in the sidebar, turn Auto-open off and dock left
  - Claude Code hooks:  merge claude/herdr-summary-hooks.json into ~/.claude/settings.json
  - Private shell setup: create ~/.zshrc.local (work paths, aliases) and ~/.zsh_secrets; neither is in this repo
  - Commit identity:    git -C "$REPO" config user.email <id>+<login>@users.noreply.github.com
  - Reload:             herdr server reload-config; kill -USR2 \$(pgrep -x ghostty)
EOF

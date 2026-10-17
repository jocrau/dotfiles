#!/bin/sh
# Pick a Markdown file in the current directory tree and read it rendered.
# Runs inside the pane opened by markdown.sh: fzf lists the files with a
# rendered preview; Enter opens the file in glow's pager, q returns to the
# list, Esc closes the pane.
GLOW=/opt/homebrew/bin/glow
FZF=/opt/homebrew/bin/fzf
export CLICOLOR_FORCE=1

list() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files --cached --others --exclude-standard -- '*.md' '*.markdown'
  else
    find . -type f \( -name '*.md' -o -name '*.markdown' \) -not -path '*/node_modules/*' -not -path '*/.git/*' | sed 's#^\./##'
  fi | sort
}

while :; do
  file=$(list | "$FZF" --prompt 'markdown> ' --height 100% --layout reverse \
    --preview "$GLOW -s dark -w \$FZF_PREVIEW_COLUMNS {}" --preview-window 'right,65%') || exit 0
  [ -n "$file" ] && "$GLOW" -p -s dark "$file"
done

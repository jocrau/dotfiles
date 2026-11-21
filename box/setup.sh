#!/bin/bash
# Sets up an always-on Mac as the agent box: the machine the agent fleet and pr-flow run on, which this
# laptop's Herdr reaches with `hc machine add` (see herdr-layout's README, "The fleet and pr-flow on another
# machine"). Run it on the box itself, as the user the agents run as, over ssh or in Terminal:
#
#   git clone https://github.com/jocrau/dotfiles.git ~/Code/dotfiles && ~/Code/dotfiles/box/setup.sh
#
# Safe to run again: each step checks first and says "ok" when there's nothing to do. It runs in two passes:
# the first installs everything that needs no account and lists the logins (gh, Claude, Tailscale); run it
# again after them for what needs them (plugins, fleet, repositories). Private values (git identity, plugin
# marketplaces, repositories) come from ~/.config/agent-box/box.conf, never from this public repo; see
# box.conf.example beside this script. Nothing here stores a token.
set -euo pipefail

CONF=${AGENT_BOX_CONF:-$HOME/.config/agent-box/box.conf}
CODE=${AGENT_BOX_CODE:-$HOME/Code}
GIT_NAME="" GIT_EMAIL="" MARKETPLACES="" PLUGINS="" REPOS=""
# shellcheck source=/dev/null
[ -f "$CONF" ] && . "$CONF"

ok()   { printf '  ok      %s\n' "$*"; }
did()  { printf '  done    %s\n' "$*"; }
todo() { printf '  todo    %s\n' "$*"; TODO=$((TODO + 1)); }
step() { printf '\n%s\n' "$*"; }
TODO=0
# Runs a command quietly; on failure shows what it said and stops.
quiet() { local out; if ! out=$("$@" 2>&1); then printf '%s\n' "$out" | tail -20; echo "failed: $*"; exit 1; fi; }

[ "$(uname -s)" = Darwin ] || { echo "This is for macOS."; exit 1; }
[ "$(id -u)" != 0 ] || { echo "Run it as the agents' user, not root (it asks for sudo where needed)."; exit 1; }

step "Admin rights"
# Asks for the password once (later sudo calls reuse it); not at all where sudo needs none (`sudo -v` would).
sudo -n true 2>/dev/null || sudo -v
ok "sudo"

step "Homebrew (installs the Command Line Tools too)"
if [ -x /opt/homebrew/bin/brew ]; then ok "brew"; else
  quiet env NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  did "brew"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1

step "Login PATH (herdr-core, the fleet board and the PR board run tools through the login shell)"
# A command herdr-core runs here gets only the system PATH; the boards ask the login shell for the real one.
add_line() { # add_line <file> <line>
  touch "$1"
  if grep -qxF "$2" "$1"; then ok "$1: $2"; else printf '%s\n' "$2" >> "$1"; did "$1: $2"; fi
}
add_line "$HOME/.zprofile" 'eval "$(/opt/homebrew/bin/brew shellenv)"'
add_line "$HOME/.zprofile" 'export PATH="$HOME/.local/bin:$PATH"'
# Secrets the agents need (CLAUDE_CODE_OAUTH_TOKEN), kept out of every repo; the agents' shells are login shells.
add_line "$HOME/.zprofile" '[ -f "$HOME/.zsh_secrets" ] && . "$HOME/.zsh_secrets"'
export PATH="$HOME/.local/bin:$PATH"

step "Tools"
# git, gh, node (pr-flow), python3 (beads-view), bd and fzf (the beads view), jq; tailscale: the open-source
# daemon, which runs without anyone logged in (the App Store app needs a GUI session).
for f in git gh node python jq fzf beads tailscale; do
  if brew list --formula "$f" >/dev/null 2>&1; then ok "$f"; else quiet brew install --quiet "$f"; did "$f"; fi
done

step "Claude Code"
if command -v claude >/dev/null 2>&1; then ok "claude $(claude --version 2>/dev/null | head -1)"; else
  quiet bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
  did "claude (~/.local/bin)"
fi

step "Power: never sleep, start again after a power cut"
pm() { pmset -g | awk -v k="$1" '$1 == k { print $2 }'; }
# autorestart: a Mac mini has it; a virtual machine doesn't list it (then it's left out).
can_restart=$(pmset -g cap 2>/dev/null | grep -qw autorestart && echo 1 || echo 0)
if [ "$(pm sleep)" = 0 ] && [ "$(pm disksleep)" = 0 ] && { [ "$can_restart" = 0 ] || [ "$(pm autorestart)" = 1 ]; }; then
  ok "pmset sleep 0, disksleep 0$([ "$can_restart" = 1 ] && echo ", autorestart 1" || echo " (no autorestart here)")"
else
  quiet sudo pmset -a sleep 0 disksleep 0 displaysleep 10
  [ "$can_restart" = 1 ] && quiet sudo pmset -a autorestart 1
  did "pmset sleep 0, disksleep 0$([ "$can_restart" = 1 ] && echo ", autorestart 1" || echo " (no autorestart here)")"
fi

step "macOS updates: downloaded, installed by you (an update restarts the box)"
SU=/Library/Preferences/com.apple.SoftwareUpdate
if [ "$(defaults read $SU AutomaticallyInstallMacOSUpdates 2>/dev/null || echo unset)" = 0 ]; then ok "no automatic macOS installs"; else
  sudo defaults write $SU AutomaticallyInstallMacOSUpdates -bool false
  did "no automatic macOS installs"
fi

step "Remote Login (ssh: how the laptop's Herdr reaches the box)"
if sudo systemsetup -getremotelogin 2>/dev/null | grep -q On; then ok "Remote Login on"
elif sudo systemsetup -setremotelogin on >/dev/null 2>&1; then did "Remote Login on"
else todo "turn on Remote Login: System Settings > General > Sharing (Terminal lacks Full Disk Access to do it)"; fi

step "Tailscale (reach the box from anywhere)"
if sudo brew services list 2>/dev/null | awk '$1 == "tailscale" { print $2 }' | grep -q started; then ok "tailscaled running"; else
  quiet sudo brew services start tailscale; did "tailscaled started (at boot too)"
fi
if tailscale status >/dev/null 2>&1; then ok "tailscale up ($(tailscale ip -4 2>/dev/null | head -1))"; else todo "log in to Tailscale: sudo tailscale up --ssh=false"; fi

step "Git identity"
if [ -n "$GIT_NAME" ] && [ -n "$GIT_EMAIL" ]; then
  [ "$(git config --global user.name || true)" = "$GIT_NAME" ] || git config --global user.name "$GIT_NAME"
  [ "$(git config --global user.email || true)" = "$GIT_EMAIL" ] || git config --global user.email "$GIT_EMAIL"
  ok "$GIT_NAME"
elif git config --global user.email >/dev/null; then ok "$(git config --global user.name)"
else todo "set GIT_NAME and GIT_EMAIL in $CONF"; fi

step "Logins"
GH=0 CLAUDE=0
if gh auth status >/dev/null 2>&1; then GH=1; ok "gh"; gh auth setup-git >/dev/null 2>&1 || true
else todo "gh auth login   (then run this script again)"; fi
# A long-lived token from `claude setup-token` (made on the laptop) in the agents' environment, or a login here.
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] || claude auth status >/dev/null 2>&1; then CLAUDE=1; ok "claude"
else todo "claude: run 'claude' once and log in, or put CLAUDE_CODE_OAUTH_TOKEN (from 'claude setup-token') in ~/.zsh_secrets"; fi

step "Claude Code plugins (from $CONF)"
if [ -z "$MARKETPLACES$PLUGINS" ]; then ok "none named"
elif [ $GH = 0 ]; then todo "plugins wait for gh auth login"
else
  have=$(claude plugin marketplace list 2>/dev/null || true)
  for m in $MARKETPLACES; do
    if printf '%s' "$have" | grep -qF "$m"; then ok "marketplace $m"; else claude plugin marketplace add "$m" >/dev/null && did "marketplace $m"; fi
  done
  installed=$(cat "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null || true)
  for p in $PLUGINS; do
    if printf '%s' "$installed" | grep -qF "\"$p\""; then ok "plugin $p"; else claude plugin install "$p" >/dev/null && did "plugin $p"; fi
  done
fi

step "The fleet's command (fleet install-cli: ~/.local/bin/fleet)"
FLEET_SCRIPT=$(ls -d "$HOME"/.claude/plugins/cache/*/agent-fleet/*/scripts/fleet 2>/dev/null | sort -V | tail -1 || true)
if command -v fleet >/dev/null 2>&1; then ok "fleet ($(fleet --version 2>/dev/null | head -1))"
elif [ -n "$FLEET_SCRIPT" ]; then "$FLEET_SCRIPT" install-cli >/dev/null && did "fleet"
else ok "no agent-fleet plugin installed: nothing to do"; fi

step "Repositories in $CODE (from $CONF)"
mkdir -p "$CODE"
if [ -z "$REPOS" ]; then ok "none named"
elif [ $GH = 0 ]; then todo "repositories wait for gh auth login"
else
  for r in $REPOS; do
    d="$CODE/${r##*/}"
    if [ -d "$d/.git" ]; then ok "$r"; else gh repo clone "$r" "$d" -- --quiet && did "$r"; fi
  done
fi

step "Summary"
if [ $TODO = 0 ]; then
  echo "  The box is set up. On the laptop:"
  echo "    hc machine add <user>@<box>          (installs herdr-core here)"
  echo "    workbench.json: \"fleet_machine\" and \"pr_flow_machine\": the name it got"
else
  echo "  $TODO to do (above); run this script again after them."
fi

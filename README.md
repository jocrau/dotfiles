# dotfiles

My Mac setup: the shell, Ghostty, the Herdr desktop app and Claude Code's status line on the laptop,
and a setup script for the always-on agent box the agent fleet runs on.

This repository is public. Secrets and work-specific values never go in it: they live in files next to
it that aren't version controlled (see [Private files](#private-files)), and a pre-commit hook scans every
commit for secrets.

## Using this as a starting point

You're welcome to build your own setup from this one. A few things to know first:

- **Fork it rather than use it as is.** It's mine: my key bindings and Herdr settings, and a `.zshrc` that
  loads work tools (AWS, kubectl, Terraform) you may not need. In a fork you change what you like and can
  still pull in later improvements from here.
- **Follow [Laptop](#laptop) and skip [Agent box](#agent-box)**, which is for running agents on a separate
  machine. Claude Code can follow the steps for you: start it in an empty folder and ask it to set up the
  Mac from the Laptop section of your fork's README, asking before each install.
- **Bring your own accounts**: GitHub, and a Claude plan for Claude Code. Nothing here signs you in to
  anything.
- **Two of the Herdr boards need tools that aren't public**: the fleet board (agent-fleet) and the PR board
  (pr-flow). Without them those boards just don't appear; everything else in
  [herdr-layout](https://github.com/jocrau/herdr-layout) works. Its README lists what each part needs.
- **Ideas and fixes for the layout** are welcome as issues or pull requests on herdr-layout.

## Laptop

On a new Mac, in this order:

1. **Homebrew and the tools**

   ```sh
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   brew install git gh gitleaks fzf beads python jq
   brew install --cask ghostty 1password
   gh auth login
   ```

2. **Oh My Zsh and the prompt** (`.zshrc` uses them)

   ```sh
   sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
   ZC=~/.oh-my-zsh/custom
   git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $ZC/themes/powerlevel10k
   git clone https://github.com/zsh-users/zsh-autosuggestions $ZC/plugins/zsh-autosuggestions
   git clone https://github.com/joshskidmore/zsh-fzf-history-search $ZC/plugins/zsh-fzf-history-search
   ```

3. **This repository and herdr-layout, side by side in `~/Code`** (install.sh links mods and the status
   line from herdr-layout)

   ```sh
   mkdir -p ~/Code && cd ~/Code
   git clone https://github.com/jocrau/dotfiles.git
   git clone https://github.com/jocrau/herdr-layout.git
   ```

4. **The shell**: `.zshrc` is linked by hand (install.sh leaves it alone)

   ```sh
   mv ~/.zshrc ~/.zshrc.bak 2>/dev/null; ln -s ~/Code/dotfiles/.zshrc ~/.zshrc
   ```

   It also loads work tools when they're there (nvm, kubectl, AWS, Terraform, LLVM, OpenSSL from
   Homebrew); install those as needed.

5. **Herdr and Claude Code**

   ```sh
   curl -fsSL https://releases.herdr.dev/app/install.sh | sh   # the app, and herdr-core (hc)
   curl -fsSL https://claude.ai/install.sh | bash              # Claude Code
   ```

6. **Link everything else**

   ```sh
   ~/Code/dotfiles/install.sh
   ```

   It links the files in the table below (moving any existing file aside as `<file>.bak-<time>`), turns on
   the secret-scanning pre-commit hook, says which of herdr-layout's keys differ from this repo's
   `keys.json`, and lists what it doesn't do. Safe to run again.

7. **The rest by hand**
   - Claude Code's status line: in `~/.claude/settings.json`,
     `"statusLine": { "type": "command", "command": "sh ~/.claude/statusline-command.sh" }`.
   - The Herdr layout: `herdr-app do layout.switch '{"name":"workbench"}'` once.
   - agent-browser: `npm install -g agent-browser` (`bin/agent-browser` wraps it: one visible Chrome and
     login profile per repository; it finds the real one on PATH or under nvm, or `AGENT_BROWSER_BIN`).
   - Commit identity for this repository: `git -C ~/Code/dotfiles config user.email <id>+<login>@users.noreply.github.com`.
   - The private files below.
   - Reload Ghostty: `kill -USR2 $(pgrep -x ghostty)`; Herdr reloads its files itself.

### What install.sh links

| In this repository | Linked to |
|---|---|
| `herdr-app/keys.json`, `herdr-app/settings.json` | `~/.config/herdr-app/` (the app writes the rest of that folder itself) |
| herdr-layout's `mods/*` (and any in `herdr-app/mods/`) | `~/.config/herdr-app/mods/` |
| herdr-layout's `layouts/workbench.json` | `~/.config/herdr-app/layouts/` |
| `ghostty/config.ghostty` | `~/Library/Application Support/com.mitchellh.ghostty/` |
| `beads-view/config.json` | `~/.config/beads-view/` (and herdr-layout's `beads-view` on PATH as `~/.local/bin/beads-view`) |
| `claude/statusline-command.sh` | `~/.claude/` (it runs `claude/statusline.py`, a link to herdr-layout's `extras/claude-statusline.py`) |
| `claude/skills/app-browser/SKILL.md` | `~/.claude/skills/app-browser/` |
| `bin/agent-browser` | `~/bin/` |

Mods are linked as whole folders: Herdr refuses an import whose real path is outside the mod's folder.
`HERDR_LAYOUT` points install.sh at a herdr-layout clone elsewhere.

## Agent box

The agent fleet and pr-flow can run on a separate, always-on Mac (a Mac mini) that the laptop's Herdr
reaches over ssh and Tailscale, so they keep working while the laptop sleeps or travels. Setting it up:

1. **On the box**, as the user the agents run as (over ssh or in Terminal):

   ```sh
   git clone https://github.com/jocrau/dotfiles.git ~/Code/dotfiles && ~/Code/dotfiles/box/setup.sh
   ```

   The first pass needs no accounts: Homebrew (with the Command Line Tools), git, gh, node, python, jq,
   fzf, bd and tailscaled, Claude Code, a login PATH in `~/.zprofile` (Homebrew and `~/.local/bin`, which
   the boards need), no sleep and restart after a power cut, no automatic macOS updates, Remote Login.
   It ends with the logins it still needs.

2. **The private values and the logins**

   ```sh
   mkdir -p ~/.config/agent-box
   cp ~/Code/dotfiles/box/box.conf.example ~/.config/agent-box/box.conf   # fill in: git identity, plugins, repositories
   sudo tailscale up --ssh=false
   gh auth login
   claude                     # log in once, or put CLAUDE_CODE_OAUTH_TOKEN (from `claude setup-token`) in ~/.zsh_secrets
   ```

3. **On the box, the second pass**: `~/Code/dotfiles/box/setup.sh` again adds the plugin marketplaces and
   plugins, runs `fleet install-cli` and clones the repositories. Every step checks first, so the script
   can run any time.

4. **On the laptop**

   ```sh
   hc machine add <user>@<box>      # installs herdr-core on the box
   ```

   and in `~/.config/herdr-app/data/workbench.json`, the name it got:

   ```json
   { "fleet_machine": "<box>", "pr_flow_machine": "<box>" }
   ```

   See herdr-layout's README, "The fleet and pr-flow on another machine". The beads view needs no setting.

The second pass (plugins, fleet, repositories) hasn't run on a real box yet.

## Private files

Not in this repository, on each machine where they're needed:

| File | What |
|---|---|
| `~/.zshrc.local` | Work paths, aliases, credential helpers (`.zshrc` sources it) |
| `~/.zsh_secrets` | Tokens as `export` lines (`.zshrc`, and on the box `.zprofile`, source it) |
| `~/.config/agent-box/box.conf` | The box's git identity, plugins and repositories (`box/box.conf.example`) |

## Committing

install.sh sets `core.hooksPath` to `git-hooks/`, whose pre-commit runs
[gitleaks](https://github.com/gitleaks/gitleaks) on the staged changes and refuses a commit with a secret
in it (`brew install gitleaks`). For a known false positive: `git commit --no-verify`.


# ===== PERFORMANCE MONITORING =====
# Uncomment to profile shell startup (optional for debugging)
# zmodload zsh/zprof

# Enable Powerlevel10k instant prompt
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ===== ENVIRONMENT VARIABLES =====
export LC_ALL=en_US.utf-8
export LANG=en_US.utf-8
export KUBECONFIG=$HOME/.kube/config
export AWS_HOME=$HOME/.aws
export ACCEPT_HIGHCHARTS_LICENSE=YES
export OP_BIOMETRIC_UNLOCK_ENABLED=true

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
    export EDITOR='vim'
else
    export EDITOR='cursor'
fi

# ===== OH-MY-ZSH CONFIGURATION =====
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
ZSH_COLORIZE_STYLE="monokai"

# Disable Oh-My-Zsh's auto-update check (7.23% of startup time)
DISABLE_AUTO_UPDATE="true"

# Skip Oh-My-Zsh's completion security check (7.23% of startup time)
ZSH_DISABLE_COMPFIX="true"

# Configure Powerlevel10k for faster startup
POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true

# Essential plugins - keep these loaded on every startup
plugins=(
    zsh-autosuggestions 
    zsh-fzf-history-search 
    git 
    macos
    terraform 
    docker 
    docker-compose 
    aws 
    wd 
    kubectl 
    kubectx 
    kube-ps1 
    rust 
    npm 
)

# Lazy-load less frequently used plugins
lazy_load_plugins() {
    # Add the rest of your plugins here
    plugins+=(
        autoupdate
        yarn 
        colorize 
        git-extras 
        httpie 
        helm 
        H-S-MW
    )
    
    # Reload just the plugins (not all of Oh-My-Zsh)
    for plugin in ${plugins[@]}; do
        if [ -f "$ZSH/plugins/$plugin/$plugin.plugin.zsh" ]; then
            source "$ZSH/plugins/$plugin/$plugin.plugin.zsh"
        elif [ -f "$ZSH/custom/plugins/$plugin/$plugin.plugin.zsh" ]; then
            source "$ZSH/custom/plugins/$plugin/$plugin.plugin.zsh"
        fi
    done
}

# ===== PATH CONFIGURATION =====
# Create an array of paths to add
path_additions=(
    "$HOME/bin"
    "/usr/local/bin"
    "/usr/local/sbin"
    "$HOME/.krew/bin"
    "$HOME/.jenv/bin"
    "$HOME/.aws"
    "$GOPATH/bin"
    "$GOROOT/bin"
    "/opt/homebrew/opt/mysql@8.0/bin"
    "/opt/homebrew/opt/llvm/bin"
    "/opt/homebrew/opt/openssl@1.1/bin"
    "/opt/homebrew/Cellar/tfenv/3.0.0/bin"
    "$HOME/.wasmer/bin"
    "$HOME/.wasmtime/bin"
    "$HOME/.local/bin"
    "$PNPM_HOME"    "/opt/homebrew/Cellar/tfenv/3.0.0/bin"
)

# Add all paths
for new_path in "${path_additions[@]}"; do
    # Only add the path if it exists and isn't already in PATH
    if [[ -d "$new_path" ]] && [[ ":$PATH:" != *":$new_path:"* ]]; then
        PATH="$new_path:$PATH"
    fi
done
export PATH

# ===== COMPILER FLAGS =====
# LLVM
export LDFLAGS="-L/opt/homebrew/opt/llvm/lib"
export CPPFLAGS="-I/opt/homebrew/opt/llvm/include"

# OpenSSL
export LDFLAGS="$LDFLAGS -L/opt/homebrew/opt/openssl@1.1/lib"
export CPPFLAGS="$CPPFLAGS -I/opt/homebrew/opt/openssl@1.1/include"
export PKG_CONFIG_PATH="/opt/homebrew/opt/openssl@1.1/lib/pkgconfig"
export OPENSSL_DIR="/opt/homebrew/opt/openssl@1.1"

# ===== LANGUAGE/TOOL CONFIGURATION =====
# Golang
export GOPATH="${HOME}/.go"
# Uncomment if needed, but this is slow and can be optimized
# export GOROOT="$(brew --prefix golang)/libexec" 

# NVM (Node Version Manager)
export NVM_DIR="$HOME/.nvm"
# Lazy load NVM for faster shell startup
nvm() {
    unset -f nvm
    [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && . "/opt/homebrew/opt/nvm/nvm.sh"
    [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && . "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"
    nvm "$@"
}

# jenv (Java Version Manager)
eval "$(jenv init -)"

# Wasmer
export WASMER_DIR="$HOME/.wasmer"
[ -s "$WASMER_DIR/wasmer.sh" ] && source "$WASMER_DIR/wasmer.sh"

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"

# ===== COMPLETION CONFIGURATION =====
# Set up paths for completion functions
fpath=(
    $fpath
    ~/.zsh/completion
    ~/.zsh/completions
    $HOME/.wash
)

# Optimize compinit (31.13% of startup time) with cache
# Only rebuild completion cache once a day
autoload -Uz compinit
if [[ -n ${ZDOTDIR}/.zcompdump(#qN.mh+24) ]]; then
    compinit
else
    compinit -C
fi

autoload -Uz vcs_info

# Lazy load bashcompinit and tool-specific completions
load_completions() {
    # Load bash completion compatibility
    autoload -U +X bashcompinit && bashcompinit
    
    # Complete specific tools
    # complete -o nospace -C /usr/local/bin/terraform terraform
    [ -f ~/completions/_istioctl ] && source ~/completions/_istioctl
    eval "$(op completion zsh)"; compdef _op op
}

# ===== SOURCE EXTERNAL CONFIGURATIONS =====
# Load Oh-My-Zsh with our optimized settings
source $ZSH/oh-my-zsh.sh



# Define user commands to load additional functionality on demand
load_all_tools() {
    echo "Loading additional tools and completions..."
    lazy_load_plugins
    load_completions
}

# Create individual command wrappers to load specific tool configurations on first use
gcloud() {
    unfunction gcloud
    if [ -f "$HOME/google-cloud-sdk/path.zsh.inc" ]; then 
        source "$HOME/google-cloud-sdk/path.zsh.inc"
    fi
    if [ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ]; then 
        source "$HOME/google-cloud-sdk/completion.zsh.inc"
    fi
    gcloud "$@"
}

kubectl() {
    unfunction kubectl
    # Load kubectl plugin and kube-ps1 for the prompt
    if [ -f "$ZSH/plugins/kubectl/kubectl.plugin.zsh" ]; then
        source "$ZSH/plugins/kubectl/kubectl.plugin.zsh"
    fi
    if [ -f "$ZSH/plugins/kube-ps1/kube-ps1.plugin.zsh" ]; then
        source "$ZSH/plugins/kube-ps1/kube-ps1.plugin.zsh"
    fi
    kubectl "$@"
}

terraform() {
    unfunction terraform
    if [ -f "$ZSH/plugins/terraform/terraform.plugin.zsh" ]; then
        source "$ZSH/plugins/terraform/terraform.plugin.zsh"
    fi
    terraform "$@"
}

# Only absolutely required configurations
[ -f "$HOME/.p10k.zsh" ] && source "$HOME/.p10k.zsh"

# Define a function for 1Password to be loaded on first use
op() {
    unfunction op
    [ -f ~/.config/op/plugins.sh ] && source ~/.config/op/plugins.sh
    op "$@"
}

# Load haskell environment only when needed
ghcup() {
    unfunction ghcup
    [ -f "$HOME/.ghcup/env" ] && source "$HOME/.ghcup/env"
    ghcup "$@"
}

# ===== CUSTOM FUNCTIONS =====

# ===== FZF CONFIGURATION =====
source <(fzf --zsh)
export FZF_DEFAULT_COMMAND='fd --type f --strip-cwd-prefix --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS='--bind ctrl-f:page-down,ctrl-b:page-up'

# ===== SECRETS MANAGEMENT =====
# Source secrets from a separate file that's not version controlled
[ -f "$HOME/.zsh_secrets" ] && source "$HOME/.zsh_secrets"

# ===== PERFORMANCE DISPLAY =====
# Uncomment to see performance results (works with zprof above)
# zprof

# Claude Code
alias claude="/Users/jocrau/.claude/local/claude"

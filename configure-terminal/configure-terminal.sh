#!/bin/bash

# Installing Git and other tools
sudo pacman -S git unzip eza ttf-dejavu noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-liberation ttf-jetbrains-mono ttf-fira-code ttf-cascadia-code ttf-roboto ttf-ubuntu-font-family ttf-opensans yazi
sudo pacman -S zoxide --needed

# Install Oh My Zsh first
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Installing LazyVim
git clone https://github.com/LazyVim/starter ~/.config/nvim
rm -rf ~/.config/nvim/.git

# Install ohmyposh
curl -s https://ohmyposh.dev/install.sh | bash -s

# Install zsh autosuggestions
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

# Install zsh syntax highlighting
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# Download an Oh My Posh theme
mkdir -p ~/.cache/oh-my-posh/themes
curl -fsSL https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/1_shell.omp.json -o ~/.cache/oh-my-posh/themes/1_shell.omp.json

# Put this line inside .zshrc
cat >~/.zshrc <<EOF
# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Update PATH
export PATH="$HOME/.local/bin:$PATH"

# Oh My Posh
eval "\$(oh-my-posh init zsh --config ~/.cache/oh-my-posh/themes/1_shell.omp.json)"

# Install zoxide
eval "\$(zoxide init zsh)"

# Set name of the theme to load
ZSH_THEME="robbyrussell"

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# HIST_STAMPS="mm/dd/yyyy"

# Which plugins would you like to load?
plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
    zoxide
)

source \$ZSH/oh-my-zsh.sh

# User configuration
# export MANPATH="/usr/local/man:\$MANPATH"

# Preferred editor for local and remote sessions
if [[ -n \$SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  export EDITOR='nvim'
fi

# Aliases
alias ls="eza --icons always" #-a
alias la="eza --icons always -la"
alias ll="eza --icons always -ll"
EOF

echo "Configuration complete. Please restart your terminal or run 'source ~/.zshrc'"
source ~/.zshrc

source ~/.p10k.zsh

autoload -Uz add-zsh-hook

export EDITOR=nvim

# Ctrl+F: cd into a directory below this one, picked with fzf
function fzd() {
    local selection
    selection=$(find . -type d -print | fzf +m --preview "ls -lah {}")

    if [ -n "$selection" ]; then
        cd "$selection" || return 1
        zle reset-prompt
    fi
}

# A desktop notification through kitty, unless kitty has the focus anyway
function notify-command-finished() {
    if ! hyprctl activewindow | grep kitty >/dev/null; then
        printf '\x1b]99;;Command finished\x1b\\'
    fi
}

alias install="yay -Slq | fzf --multi --preview 'yay -Si {1}' | xargs -ro yay -S ; notify-command-finished"
alias uninstall="yay -Qq | fzf --multi --preview 'yay -Qi {1}' | xargs -ro yay -Rns ; notify-command-finished"
alias cat='bat'
alias ls='lsd'
alias la='lsd -lah'
alias fzf='fzf --reverse'
alias upgrade="yay -Syu ; reboot-check ; notify-command-finished"
alias cleanup="sudo pacman -Qdtq | sudo pacman -Rns -"

if command -v kitten >/dev/null 2>&1 && [ "$TERM" = "xterm-kitty" ]; then
    alias ssh="kitten ssh"
fi

zle -N fzd
bindkey '^F' fzd

autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line

# Undo and Redo
bindkey '^_' undo
bindkey '^X^_' redo

# List a directory when changing into it
chpwd() {
    ls
}

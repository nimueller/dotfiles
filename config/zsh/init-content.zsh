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

# kitty notifies when a long command finishes (notify_on_cmd_finish)
alias install="yay -Slq | fzf --multi --preview 'yay -Si {1}' | xargs -ro yay -S"
alias uninstall="yay -Qq | fzf --multi --preview 'yay -Qi {1}' | xargs -ro yay -Rns"
alias cat='bat'
alias ls='lsd'
alias la='lsd -lah'
alias fzf='fzf --reverse'
alias upgrade="yay -Syu ; reboot-check"
alias cleanup="sudo pacman -Qdtq | sudo pacman -Rns -"

if command -v kitten >/dev/null 2>&1 && [ "$TERM" = "xterm-kitty" ]; then
    alias ssh="kitten ssh"
fi

zle -N fzd
bindkey '^F' fzd

# fzf-tab: Tab shows the completions in fzf. Its own menu instead of zsh's
# (oh-my-zsh sets `menu select` with this pattern, which a plain
# ':completion:*' wouldn't override), groups named in brackets so the
# previews below can tell them apart, < and > switch between groups.
zstyle ':completion:*:*:*:*:*' menu no
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*:git-checkout:*' sort false
zstyle ':fzf-tab:*' switch-group '<' '>'

# Previews: a directory's content, a changed file's diff, a process's command
zstyle ':fzf-tab:complete:(cd|j|ls|lsd):*' fzf-preview 'lsd -1 --color=always $realpath'
zstyle ':fzf-tab:complete:git-(add|diff|restore):*' fzf-preview \
    'git diff $word | delta --width=$FZF_PREVIEW_COLUMNS'
zstyle ':completion:*:*:*:*:processes' command 'ps -u $USER -o pid,user,comm -w -w'
zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-preview \
    '[[ $group == "[process ID]" ]] && ps --pid=$word -o cmd --no-headers -w -w'
zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-flags --preview-window=down:3:wrap

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

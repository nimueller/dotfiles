source ~/.p10k.zsh


export EDITOR=nvim


function fzd() {
  local selection=$(find . -type d -print | fzf +m --preview "ls -lah {}")

  if [ -n "$selection" ]; then
    cd "$selection"
    zle reset-prompt
  fi
}

function notify-command-finished() {
  if ! hyprctl activewindow | grep kitty > /dev/null; then 
    printf '\x1b]99;;Command finished\x1b\\'
  fi
}


alias install="yay -Slq | fzf --multi --preview 'yay -Si {1}' | xargs -ro yay -S ; notify-command-finished"
alias uninstall="yay -Qq | fzf --multi --preview 'yay -Qi {1}' | xargs -ro yay -Rns ; notify-command-finished"
alias cat='bat'
alias ls='lsd'
alias la='lsd -lah'
alias fzf='fzf --reverse'
alias upgrade="yay -Syu ; notify-command-finished"
alias cleanup="sudo pacman -Qdtq | sudo pacman -Rns -"

if command -v kitten >/dev/null 2>&1 && [ "$TERM" = "xterm-kitty" ]; then
  alias ssh="kitten ssh"
fi


zle -N fzd
bindkey '^F' fzd


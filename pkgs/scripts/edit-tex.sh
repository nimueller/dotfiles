# shellcheck shell=bash
# Built with writeShellApplication (pkgs/default.nix), which adds the shebang
# Edits a LaTeX document of the current directory (one made by init-tex) in
# Neovim, while latexmk builds the PDF again on every save; asks which one
# if there are several.
#   edit-tex
mapfile -t texfiles < <(find . -maxdepth 1 -type f -name "*.tex")

if [ "${#texfiles[@]}" -eq 0 ]; then
    echo "❌ No .tex file found"
    exit 1
fi

if [ "${#texfiles[@]}" -eq 1 ]; then
    texfile=${texfiles[0]}
else
    texfile=$(printf '%s\n' "${texfiles[@]}" | fzf --prompt="Choose a .tex file ")
fi
if [ -z "$texfile" ]; then
    echo "❌ No choice made"
    exit 1
fi

# Its output would draw over Neovim
latexmk -pvc -pdf -silent "$texfile" >/dev/null 2>&1 &
latexmk_pid=$!

nvim "$texfile"

# latexmk is gone already if it couldn't start
if kill "$latexmk_pid" 2>/dev/null; then
    echo "🛑 Stopped latexmk (PID $latexmk_pid)"
fi

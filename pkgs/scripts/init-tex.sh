# shellcheck shell=bash
# Built with writeShellApplication (pkgs/default.nix), which adds the shebang
# Starts a LaTeX document in the current directory: <name>.tex from a
# template, a .latexmkrc that edit-tex builds it with, and a .gitignore for
# the build directory. Asks for the name, the title and the author.
#   init-tex
default_name=main
default_author=Nico
build_dir=.build

# ask "question" default -> the answer, or the default for an empty one
ask() {
    local question=$1 default=$2 answer
    read -r -p "$question [$default]: " answer
    echo "${answer:-$default}"
}

# Stops unless the user says yes to replacing an existing file
confirm_replace() {
    local file=$1 replace
    if [ ! -f "$file" ]; then
        return 0
    fi
    read -r -p "⚠️ The file $file already exists. Replace it? [y/N] " replace
    if [ "$replace" = "y" ] || [ "$replace" = "yes" ]; then
        return 0
    fi
    echo "Not replacing $file"
    exit 1
}

# write_document file title author
write_document() {
    local date
    date=$(date +"%d.%m.%Y")
    cat >"$1" <<EOF
\\documentclass[12pt,a4paper]{article}

% --- Pakete ---
\\usepackage[utf8]{inputenc}
\\usepackage[T1]{fontenc}
\\usepackage[ngerman]{babel}
\\usepackage{lmodern}
\\usepackage[a4paper,margin=2.5cm]{geometry}
\\usepackage{amsmath,amssymb}
\\usepackage{graphicx}
\\usepackage{enumitem}
\\usepackage{hyperref}
\\usepackage{xcolor}
\\usepackage{parskip}

\\hypersetup{
    colorlinks=true,
    linkcolor=blue,
    urlcolor=blue,
    citecolor=blue
}

\\title{$2}
\\author{$3}
\\date{$date}

\\begin{document}

\\section*{Einleitung}
Hier beginnt dein Text...

\\end{document}
EOF
}

write_latexmkrc() {
    local texfile=$1
    cat >.latexmkrc <<EOF
@default_files = ('$texfile');
\$aux_dir = '$build_dir';
\$out_dir = '.';
\$pdf_mode = 1;
\$pdf_previewer = 'start evince';
EOF
}

# For when the document ever goes into Git
write_gitignore() {
    echo "$build_dir/" >.gitignore
}

echo "📄 New LaTeX document"
name=$(ask "Filename (without .tex)" "$default_name")
title=$(ask "Title" "")
author=$(ask "Author" "$default_author")
texfile=$name.tex

confirm_replace "$texfile"
write_document "$texfile" "$title" "$author"
write_latexmkrc "$texfile"
write_gitignore
mkdir -p "$build_dir"

echo "✅ Created $texfile"

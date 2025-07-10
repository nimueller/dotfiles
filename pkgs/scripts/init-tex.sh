#!/bin/sh

echo "📄 New LaTeX document"
read -p "Filename (without .tex) [main]: " fileName
fileName=${fileName:-main}
read -p "Title []: " title
title=${title:-}
read -p "Author [Nico]: " author
author=${author:-Nico}

date=$(date +"%d.%m.%Y")
texfile="${fileName:-main}.tex"

if [ -f "$texfile" ]; then
    read -p "⚠️ The file $texfile already exists. Do you want to replace it? [n] " replace

    if [ "$replace" != "y" ] && [ "$replace" != "yes" ]; then
        echo "Not replacing $texfile"
        exit 1
    fi
fi


### Main LaTeX file
cat > "$texfile" <<EOF
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

\\title{$title}
\\author{$author}
\\date{$date}

\\begin{document}

\\section*{Einleitung}
Hier beginnt dein Text...

\\end{document}
EOF


### latexmk config
cat > .latexmkrc <<EOF
@default_files = ('$texfile');
\$aux_dir = '.build';
\$out_dir = '.';
\$pdf_mode = 1;
\$pdf_previewer = 'start evince';
EOF

### gitignore (if Git is ever used)
cat > .gitignore <<EOF
.build/
EOF

mkdir -p '.build'

echo "✅ File '$texfile' was created"


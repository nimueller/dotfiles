#!/usr/bin/env bash
# Refresh packages/apps.txt and packages/aur.txt from what this machine has
# installed explicitly (the session packages stay in session.txt).
dir=$(dirname "$(readlink -f "$0")")/packages
session=$(grep -v -E '^\s*(#|$)' "$dir/session.txt" | sort)

{
    echo "# Other packages from the Arch repositories on this machine; refresh with"
    echo "# system/update-package-lists.sh"
    pacman -Qqen | sort | comm -23 - <(echo "$session")
} >"$dir/apps.txt"

{
    echo "# Packages from the AUR (installed with yay); refresh with"
    echo "# system/update-package-lists.sh"
    pacman -Qqem | sort
} >"$dir/aur.txt"

echo "apps.txt: $(grep -c -v '^#' "$dir/apps.txt") packages, aur.txt: $(grep -c -v '^#' "$dir/aur.txt") packages"

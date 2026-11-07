#!/usr/bin/env bash
# The repository's checks, run by CI and by the optional pre-commit hook
# (git config core.hooksPath .githooks). The tools come from the flake's
# devShell (flake.nix), so from the nixpkgs in flake.lock. The formatters fix
# what they complain about:
#   nix fmt
#   ruff format .
#   stylua .
#   shfmt --write .
#   git ls-files -z '*.qml' | xargs -0 qmlformat -i
set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if [ -z "${CHECK_SH_TOOLS:-}" ]; then
    exec env CHECK_SH_TOOLS=1 nix develop .# --command "$0" "$@"
fi

shell_scripts=(
    install.sh
    check.sh
    .github/check-flake.sh
    .githooks/pre-commit
    pkgs/scripts/*.sh
    config/quickshell/menus/*.sh
    system/*.sh
)

status=0

step() {
    echo "== $1"
    shift
    if ! "$@"; then
        status=1
    fi
}

# Syntax errors only: without the Quickshell module's full type information
# qmllint warns about nearly every line, but a syntax error still fails it.
# The output goes into `lint`, not `out`: nix develop exports that, and the
# output would go into grep's environment, too long for it.
# shellcheck disable=SC2329 # called through step
qml_lint() {
    local quickshell lint code
    quickshell=$(dirname "$(dirname "$(readlink -f "$(command -v quickshell)")")")
    lint=$(
        qmllint \
            --max-warnings -1 \
            -I "$quickshell/lib/qt-6/qml" \
            -I config/quickshell/menus \
            config/quickshell/menus/*.qml \
            2>&1
    )
    code=$?
    grep -A2 "\[syntax\]" <<<"$lint"
    return "$code"
}

# qmlformat has no check mode: a file differs from its formatted output
# shellcheck disable=SC2329 # called through step
qml_format() {
    local file status=0
    while IFS= read -r -d '' file; do
        if ! qmlformat "$file" | cmp -s - "$file"; then
            echo "would reformat: $file"
            status=1
        fi
    done < <(git ls-files -z "*.qml")
    return "$status"
}

step "nixfmt" bash -c 'git ls-files -z "*.nix" | xargs -0 nixfmt --check'
step "statix" statix check .
step "deadnix" deadnix --fail .
step "shellcheck" shellcheck "${shell_scripts[@]}"
step "shfmt" shfmt --diff .
step "ruff" ruff check .
step "ruff format" ruff format --check .
step "stylua" stylua --check .
step "pyright" pyright
step "python tests" python3 -m unittest discover --start-directory tests --top-level-directory tests
step "qmlformat" qml_format
step "qmllint" qml_lint

if [ "$status" -eq 0 ]; then
    echo "All checks passed"
else
    echo "Some checks failed"
fi
exit "$status"

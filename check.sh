#!/usr/bin/env bash
# The repository's checks, run by CI and by the optional pre-commit hook
# (git config core.hooksPath .githooks). The tools come from the flake's
# devShell (flake.nix), so from the nixpkgs in flake.lock; `nix fmt` fixes
# what nixfmt complains about, `ruff format .` what ruff format does.
set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if [ -z "${CHECK_SH_TOOLS:-}" ]; then
    exec env CHECK_SH_TOOLS=1 nix develop .# --command "$0" "$@"
fi

status=0
step() {
    echo "== $1"
    shift
    "$@" || status=1
}

# Syntax errors only: without the Quickshell module's full type information
# qmllint warns about nearly every line, but a syntax error still fails it
# shellcheck disable=SC2329 # called through step
# (not `out`: nix develop exports that, and the output would go into grep's
# environment, too long for it)
qml() {
    local qs lint
    qs=$(dirname "$(dirname "$(readlink -f "$(command -v quickshell)")")")
    lint=$(qmllint --max-warnings -1 -I "$qs/lib/qt-6/qml" -I config/quickshell/menus config/quickshell/menus/*.qml 2>&1)
    local code=$?
    grep -A2 "\[syntax\]" <<<"$lint"
    return "$code"
}

step "nixfmt" bash -c 'git ls-files -z "*.nix" | xargs -0 nixfmt --check'
step "statix" statix check .
step "deadnix" deadnix --fail .
step "shellcheck" shellcheck install.sh check.sh .github/check-flake.sh .githooks/pre-commit pkgs/scripts/*.sh config/quickshell/menus/*.sh system/*.sh
step "ruff" ruff check .
step "ruff format" ruff format --check .
step "pyright" pyright
step "python tests" python3 -m unittest discover --start-directory tests --top-level-directory tests
step "qmllint" qml

if [ "$status" = 0 ]; then echo "All checks passed"; else echo "Some checks failed"; fi
exit "$status"

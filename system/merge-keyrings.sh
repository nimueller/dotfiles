#!/usr/bin/env bash
# Runs merge-keyrings.py with a Python that has the secretstorage library.
# Arguments go to the script.
dir=$(dirname "$(readlink -f "$0")")
# shellcheck disable=SC2016 # ${...} is Nix, not shell
exec nix shell --impure --expr \
    'let pkgs = (builtins.getFlake "nixpkgs").legacyPackages.${builtins.currentSystem}; in pkgs.python3.withPackages (p: [ p.secretstorage ])' \
    --command python3 "$dir/merge-keyrings.py" "$@"

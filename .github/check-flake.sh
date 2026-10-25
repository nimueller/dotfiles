#!/usr/bin/env bash
# Evaluates the flake and all Home Manager configurations without building
# them; run by install.yml and by lgtm.yml on a branch it rebased
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1

nix flake check --no-build
for config in headless headless_aarch64 desktop desktop_aarch64 runner; do
    echo "Evaluating $config"
    nix eval --raw ".#homeConfigurations.$config.activationPackage.drvPath"
    echo
done

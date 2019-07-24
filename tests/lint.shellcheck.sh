#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(readlink -m "$(dirname "${0}")")"

cd "${WORKDIR}/.."

readarray -t shell_scripts < <(find . -name '*.sh' -a ! -path '*/.git/*')
echo checking "${shell_scripts[@]}"
shellcheck "${shell_scripts[@]}"

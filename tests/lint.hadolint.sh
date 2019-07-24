#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(readlink -m "$(dirname "${0}")")"

cd "${WORKDIR}/.."

# DL3006 Always tag the version of an image explicitly
# DL3018 Pin versions in apk add. Instead of `apk add <package>` use `apk add <package>=<version>`
docker run --rm -i hadolint/hadolint hadolint \
    --ignore DL3018 \
    --ignore DL3006 \
    - < Dockerfile

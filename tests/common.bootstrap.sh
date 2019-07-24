#!/usr/bin/env bash

set -euo pipefail


mkdir -p "${LOCAL_SRC_DIR}/"{in,ex}clude_dir "${LOCAL_DEST_DIR}"
touch "${LOCAL_SRC_DIR}/"{backup_me.{1,2}.json,exclude_me.jar}
touch "${LOCAL_SRC_DIR}/include_dir/"{backup_me.{1,2}.json,exclude_me.jar}
touch "${LOCAL_SRC_DIR}/exclude_dir/"exclude_me.{1,2}.{json,jar}
tree "${LOCAL_SRC_DIR}"
docker build -t testimg .
echo -e '#!/bin/bash\ntrue' > "${TMP_DIR}/rcon-cli" && chmod +x "${TMP_DIR}/rcon-cli"

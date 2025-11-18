#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export FLASK_APP="main:app"
export PYTHONPATH="${ROOT_DIR}/app:${PYTHONPATH:-}"

FLASK_PORT="${FLASK_RUN_PORT:-5000}"
NODE_CMD="${NODE_CMD:-node}"

( cd "${ROOT_DIR}/app" && gunicorn --bind "0.0.0.0:${FLASK_PORT}" main:app ) &

( cd "${ROOT_DIR}/agent_service" && ${NODE_CMD} server.mjs ) &

wait -n
exit $?

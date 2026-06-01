#!/usr/bin/env bash
# Run Portcullis admin CLI inside the running container.
# Example: ./scripts/user-admin.sh users create --email alice@family.example --name Alice --password 'secret'
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/compose-runtime.sh
source "${SCRIPT_DIR}/lib/compose-runtime.sh"
harbour_ensure_env

runtime="${HARBOUR_RUNTIME:-podman}"
harbour_compose "${runtime}" exec -T portcullis node dist/cli.js "$@"

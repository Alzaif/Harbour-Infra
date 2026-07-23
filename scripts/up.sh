#!/usr/bin/env bash
# Start the Harbour stack with Podman Compose (default on this repo).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/compose-runtime.sh
source "${SCRIPT_DIR}/lib/compose-runtime.sh"
# shellcheck source=lib/check-hosts.sh
source "${SCRIPT_DIR}/lib/check-hosts.sh"

harbour_check_hosts
harbour_ensure_env
harbour_maybe_generate_public_config
harbour_compose podman up --build -d "$@"

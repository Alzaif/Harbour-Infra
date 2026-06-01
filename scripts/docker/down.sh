#!/usr/bin/env bash
# Stop the Harbour stack (Docker Compose).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/compose-runtime.sh
source "${SCRIPT_DIR}/../lib/compose-runtime.sh"

harbour_compose docker down "$@"

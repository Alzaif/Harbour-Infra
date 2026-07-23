#!/usr/bin/env bash
# Unit test: tailscale compose overlay sets tls.certresolver on every HTTPS router.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
OVERLAY="${REPO_ROOT}/compose/docker-compose.tailscale.yml"

required_routers=(
  portcullis
  harbour-ui
  harbour-stack
  notes
  docs
  warehouse
  gym
  recipes
  outline
  board
  board-ws
  board-legacy
)

for router in "${required_routers[@]}"; do
  grep -q "traefik.http.routers.${router}.tls.certresolver=harbour-tailscale" "${OVERLAY}" \
    || { echo "missing certresolver label for router ${router}" >&2; exit 1; }
done

grep -q 'tailscaled.sock:/var/run/tailscale/tailscaled.sock' "${OVERLAY}" \
  || { echo "missing tailscaled.sock volume on traefik" >&2; exit 1; }

echo "docker-compose-tailscale-tls: ok"

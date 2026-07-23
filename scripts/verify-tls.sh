#!/usr/bin/env bash
# Verify Traefik serves a trusted TLS cert for HARBOUR_DNS_ZONE (Tailscale profile).
#
# Usage: ./scripts/verify-tls.sh
# Expects compose/.env with HARBOUR_DNS_ZONE and HOST_HTTPS_PORT.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/compose-runtime.sh
source "${SCRIPT_DIR}/lib/compose-runtime.sh"

harbour_load_compose_env

zone="${HARBOUR_DNS_ZONE:-harbour.local}"
port="${HOST_HTTPS_PORT:-8443}"
url="https://${zone}:${port}/"

if [[ "${HARBOUR_DEPLOY_PROFILE:-local}" != "tailscale" ]]; then
  echo "warn: HARBOUR_DEPLOY_PROFILE is not tailscale — cert may still be self-signed" >&2
fi

if [[ ! -S /var/run/tailscale/tailscaled.sock ]]; then
  echo "error: /var/run/tailscale/tailscaled.sock not found — is tailscaled running on the host?" >&2
  exit 1
fi

if ! tailscale cert "${zone}" --cert-file /dev/null --key-file /dev/null 2>/dev/null; then
  if tailscale cert "${zone}" 2>&1 | grep -q 'Access denied'; then
    echo "error: tailscale cert access denied for ${zone}" >&2
    echo "hint: run once on this host: sudo tailscale set --operator=\"\$USER\"" >&2
    exit 1
  fi
fi

echo "Checking TLS for ${url}"

if ! curl --silent --show-error --fail --max-time 15 -o /dev/null "${url}"; then
  echo "error: HTTPS request failed (curl without -k). Check Traefik logs and Tailscale HTTPS certificates." >&2
  exit 1
fi

echo "HTTPS OK (trusted certificate accepted by curl)"
echo ""
echo "Certificate details:"
openssl s_client -connect "${zone}:${port}" -servername "${zone}" </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates 2>/dev/null \
  || echo "warn: could not read certificate via openssl (remote host may not be reachable from this machine)"

echo ""
echo "Next: on Android Chrome open ${url} → menu → Install app"

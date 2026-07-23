#!/usr/bin/env bash
# Unit test: generate-public-config.sh emits path-based URLs and harbour-apps schema.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
GENERATOR="${REPO_ROOT}/scripts/generate-public-config.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

FAKE_ROOT="${WORK}/harbour-infra"
mkdir -p \
  "${FAKE_ROOT}/compose" \
  "${FAKE_ROOT}/config" \
  "${FAKE_ROOT}/docs" \
  "${WORK}/portcullis/config" \
  "${WORK}/harbour-stack/config" \
  "${WORK}/harbour-platform-ui/public/config"

ln -s "${WORK}/portcullis" "${FAKE_ROOT}/../portcullis"
ln -s "${WORK}/harbour-stack" "${FAKE_ROOT}/../harbour-stack"
ln -s "${WORK}/harbour-platform-ui" "${FAKE_ROOT}/../harbour-platform-ui"

cat >"${FAKE_ROOT}/compose/.env" <<'EOF'
HARBOUR_ROOT=/tmp/Harbour
HARBOUR_DEPLOY_PROFILE=tailscale
HARBOUR_DNS_ZONE=harbour.tailabc123.ts.net
HARBOUR_TAILSCALE_IP=100.64.0.42
HARBOUR_PUBLIC_HTTPS_PORT=8443
EOF

mkdir -p "${FAKE_ROOT}/scripts"
cp "${GENERATOR}" "${FAKE_ROOT}/scripts/generate-public-config.sh"
chmod +x "${FAKE_ROOT}/scripts/generate-public-config.sh"

"${FAKE_ROOT}/scripts/generate-public-config.sh"

APPS_JSON="${FAKE_ROOT}/../portcullis/config/harbour-apps.json"
REGISTRY="${FAKE_ROOT}/../harbour-platform-ui/public/config/services.registry.json"
DNS_RECORDS="${FAKE_ROOT}/docs/tailscale-dns-records.txt"

grep -q '"pathPrefix": "/notes"' "${APPS_JSON}"
grep -q '"host": "harbour.tailabc123.ts.net"' "${APPS_JSON}"
grep -q 'https://harbour.tailabc123.ts.net:8443/board' "${REGISTRY}"
grep -q 'notes.harbour.tailabc123' "${REGISTRY}" && exit 1 || true
grep -q 'path-based routing' "${DNS_RECORDS}"

echo "generate-public-config-path: ok"

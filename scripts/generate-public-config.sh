#!/usr/bin/env bash
# Generate Harbour public hostname config from compose/.env (HARBOUR_DNS_ZONE, etc.).
#
# Usage:
#   ./scripts/generate-public-config.sh
#   ./scripts/generate-public-config.sh --dry-run
#
# Writes:
#   config/harbour-apps.json
#   ../portcullis/config/harbour-apps.json
#   ../harbour-stack/config/harbour-apps.json
#   ../portcullis/config/clients.docker.json
#   ../harbour-platform-ui/public/config/services.registry.json
#   docs/tailscale-dns-records.txt
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_DIR="${INFRA_ROOT}/compose"
ENV_FILE="${HARBOUR_GENERATOR_ENV_FILE:-${COMPOSE_DIR}/.env}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Generate harbour-apps.json, OAuth clients, launcher registry, and DNS notes from compose/.env.

Options:
  --dry-run   Print paths and hostnames without writing files
  -h, --help  Show this help
EOF
}

log() { printf '%s\n' "$*"; }
die() { log "error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

if [[ ! -f "${ENV_FILE}" ]]; then
  die "missing ${ENV_FILE} — copy compose/.env.example first"
fi

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

export HARBOUR_DNS_ZONE="${HARBOUR_DNS_ZONE:-harbour.local}"
export HARBOUR_PUBLIC_HTTPS_PORT="${HARBOUR_PUBLIC_HTTPS_PORT:-8443}"
export HARBOUR_TAILSCALE_IP="${HARBOUR_TAILSCALE_IP:-}"
export DRY_RUN
export INFRA_ROOT

python3 <<'PY'
import json
import os
from pathlib import Path

infra_root = Path(os.environ["INFRA_ROOT"])
dry_run = os.environ.get("DRY_RUN") == "1"
zone = os.environ.get("HARBOUR_DNS_ZONE", "harbour.local")
port = os.environ.get("HARBOUR_PUBLIC_HTTPS_PORT", "8443")
tailscale_ip = os.environ.get("HARBOUR_TAILSCALE_IP") or "100.x.x.x"

if port == "443":
    public_origin = f"https://{zone}"
else:
    public_origin = f"https://{zone}:{port}"


def app_path(app: str) -> str:
    return f"/{app}"


def app_url(app: str) -> str:
    if port == "443":
        return f"https://{zone}{app_path(app)}"
    return f"https://{zone}:{port}{app_path(app)}"


apps = ["notes", "docs", "tasks", "recipes", "outline", "gym", "board", "warehouse"]

apps_json = {
    "apps": [
        {"id": a, "host": zone, "pathPrefix": app_path(a), "scope": f"app:{a}"}
        for a in apps
    ]
}

redirect_uris = [
    f"{public_origin}/oauth/callback",
    "http://localhost:5173/oauth/callback",
]
if port != "443":
    redirect_uris.insert(0, f"https://{zone}/oauth/callback")
    redirect_uris.insert(1, f"http://{zone}/oauth/callback")

clients_json = [
    {
        "client_id": "harbour-shell",
        "name": "Harbour UI Shell",
        "redirect_uris": list(dict.fromkeys(redirect_uris)),
        "allowed_scopes": ["openid", "profile", "email"],
    },
    {
        "client_id": "harbour-gateway",
        "name": "Reverse Proxy / Gateway",
        "redirect_uris": [f"{public_origin}/oauth/callback"],
        "allowed_scopes": ["openid", "profile", "email"],
    },
]

registry_meta = [
    ("board", "Board", "Direct messages, groups, and household board", "Social"),
    ("gym", "Gym", "Track lifts, routines, and progression", "Health"),
    ("docs", "Docs", "Light word processor with PDF and DOCX export", "Productivity"),
    ("notes", "Notes", "Family notes", "Knowledge"),
    ("tasks", "Tasks", "Shared tasks", "Productivity"),
    ("recipes", "Recipes", "Recipes that have been collected and created over the years.", "Home"),
    ("outline", "Outline", "Engineering plan markups", "Design"),
    ("warehouse", "Warehouse", "Shared photos, videos, documents, and music for your household.", "Home"),
]

registry_json = [
    {
        "id": app_id,
        "name": name,
        "url": app_url(app_id),
        "description": desc,
        "category": category,
        "requiredScopes": [f"app:{app_id}"],
    }
    for app_id, name, desc, category in registry_meta
]

dns_lines = [
    "# Harbour uses path-based routing on a single hostname (MagicDNS machine name)",
    "# Rename Tailscale machine to match shell host (e.g. harbour.<tailnet>.ts.net)",
    f"# Shell: https://{zone}" + ("" if port == "443" else f":{port}") + "/",
    f"# Apps:  https://{zone}" + ("" if port == "443" else f":{port}") + "/{{app}}  (notes, chat, docs, …)",
    "",
    f"# Tailnet IP (reference): {tailscale_ip}",
]
dns_text = "\n".join(dns_lines) + "\n"

outputs = [
    (infra_root / "config" / "harbour-apps.json", json.dumps(apps_json, indent=2) + "\n"),
    (infra_root.parent / "portcullis" / "config" / "harbour-apps.json", json.dumps(apps_json, indent=2) + "\n"),
    (infra_root.parent / "harbour-stack" / "config" / "harbour-apps.json", json.dumps(apps_json, indent=2) + "\n"),
    (infra_root.parent / "portcullis" / "config" / "clients.docker.json", json.dumps(clients_json, indent=2) + "\n"),
    (
        infra_root.parent / "harbour-platform-ui" / "public" / "config" / "services.registry.json",
        json.dumps(registry_json, indent=2) + "\n",
    ),
    (infra_root / "docs" / "tailscale-dns-records.txt", dns_text),
]

for path, content in outputs:
    if dry_run:
        print(f"[dry-run] would write {path}")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        print(f"wrote {path}")

print()
print(f"Public origin: {public_origin}")
print(f"DNS zone:      {zone}")
profile = os.environ.get("HARBOUR_DEPLOY_PROFILE", "local")
if profile == "tailscale":
    print("Next: rename Tailscale machine to match HARBOUR_DNS_ZONE, then: ./scripts/up.sh --build")
else:
    print("Next: rebuild images if URLs changed: ./scripts/up.sh --build")
PY

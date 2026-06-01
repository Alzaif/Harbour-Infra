# harbour-infra

Orchestration for the Harbour platform — Compose, Traefik, and local development wiring.

**Default runtime:** [Podman](https://podman.io/) Compose via [`scripts/up.sh`](scripts/up.sh).  
**Docker:** use [`scripts/docker/up.sh`](scripts/docker/up.sh).

This repo does **not** contain application code. Service images are built from sibling repositories:

- [harbour-platform-ui](../harbour-platform-ui) — platform shell
- [portcullis](../portcullis) — authentication BFF
- [harbour-notes](../harbour-notes) — personal wiki (folders, rich text, attachments)
- [harbour-recipes](../harbour-recipes) — household recipes, meal planner, shopping list
- [harbour-warehouse](../harbour-warehouse) — shared household media library
- [harbour-stack](../harbour-stack) — platform metrics API (`/api/stack`)

## Documentation

- [Platform roadmap](../ROADMAP.md) — phase checklist and current priorities
- [Identity & databases plan](../docs/plan/identity-and-databases.md) — users DB, sign-in, app permissions
- [Phase 0 setup guide](docs/phase-0-setup.md)
- [hosts file example](docs/hosts.example)
- [Docker scripts](scripts/docker/README.md)

## Local DNS (required once)

Browsers cannot resolve `harbour.local` until you add it to `/etc/hosts`:

```bash
sudo tee -a /etc/hosts <<'EOF'
127.0.0.1 harbour.local
127.0.0.1 notes.harbour.local
127.0.0.1 warehouse.harbour.local
127.0.0.1 traefik.harbour.local
EOF
```

See [docs/hosts.example](docs/hosts.example) for the full list.

## Quick start (Podman)

```bash
chmod +x scripts/*.sh scripts/docker/*.sh scripts/lib/*.sh
./scripts/up.sh
```

## Quick start (Docker)

```bash
./scripts/docker/up.sh
```

See [docs/phase-0-setup.md](docs/phase-0-setup.md) for hosts entries, HTTPS, and troubleshooting.

**Rootless Podman:** open https://harbour.local:8443 (not port 443). Docker scripts use https://harbour.local on 80/443.

## Security env defaults

Phase 2.5 introduces edge trust + encryption variables used by chat and forward-auth.
For local development they have safe defaults in `compose/.env` / `.env.example`:

- `HARBOUR_PROXY_TOKEN`
- `CHAT_MASTER_KEY_B64`
- `CHAT_MASTER_KEY_ID`
- `REQUIRE_HTTPS_FORWARDED_PROTO`

In production, rotate these values and store them in a secrets manager.

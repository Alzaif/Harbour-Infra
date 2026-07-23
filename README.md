# harbour-infra

Orchestration for the Harbour platform — Compose, Traefik, and local development wiring.

**Default runtime:** [Podman](https://podman.io/) Compose via [`scripts/up.sh`](scripts/up.sh).  
**Docker:** use [`scripts/docker/up.sh`](scripts/docker/up.sh).

This repo does **not** contain application code. Service images are built from sibling repositories:

- [harbour-platform-ui](../harbour-platform-ui) — platform shell
- [portcullis](../portcullis) — authentication BFF
- [harbour-notes](../harbour-notes) — personal wiki (folders, rich text, attachments)
- [harbour-recipes](../harbour-recipes) — household recipes, meal planner, shopping list
- [harbour-outline](../harbour-outline) — engineering plan markups with scale-aware export
- [harbour-warehouse](../harbour-warehouse) — shared household media library
- [harbour-stack](../harbour-stack) — platform metrics API (`/api/stack`)

## Documentation

- [Platform roadmap](../ROADMAP.md) — phase checklist and current priorities
- [Identity & databases plan](../docs/plan/identity-and-databases.md) — users DB, sign-in, app permissions
- [Phase 0 setup guide](docs/phase-0-setup.md)
- [**Deploy with Podman + Tailscale**](docs/deploy-podman-tailscale.md) — full platform, remote access
- [Tailscale remote access](docs/tailscale-remote-access.md)
- [hosts file example](docs/hosts.example)
- [Docker scripts](scripts/docker/README.md)

## Local DNS (required once)

Browsers cannot resolve `harbour.local` until you add it to `/etc/hosts`:

```bash
sudo tee -a /etc/hosts <<'EOF'
127.0.0.1 harbour.local
127.0.0.1 traefik.harbour.local
EOF
```

Satellite apps are served at `https://harbour.local:8443/{app}` (no per-app hostnames).

See [docs/hosts.example](docs/hosts.example).

## Quick start (Podman)

```bash
chmod +x scripts/*.sh scripts/docker/*.sh scripts/lib/*.sh
./scripts/up.sh
```

### Multi-repo git sync

Sibling app repos are pulled with:

```bash
# From workspace root (or from harbour-infra/)
./scripts/git-pull-all.sh --dry-run
./scripts/git-pull-all.sh
```

Commit/push across all satellites remains at the workspace root: `../scripts/git-commit-push-all.sh` (see [scripts/README.md](../scripts/README.md)).

## Quick start (Docker)

```bash
./scripts/docker/up.sh
```

See [docs/phase-0-setup.md](docs/phase-0-setup.md) for hosts entries, HTTPS, and troubleshooting.

**Rootless Podman:** open https://harbour.local:8443 (not port 443). Docker scripts use https://harbour.local on 80/443.

## Tailscale remote access

Access Harbour from outside your home network over a private tailnet (phones/laptops with the Tailscale app), see [docs/tailscale-remote-access.md](docs/tailscale-remote-access.md).

**Full Podman + Tailscale deploy guide:** [docs/deploy-podman-tailscale.md](docs/deploy-podman-tailscale.md)

```bash
cp compose/.env.tailscale.example compose/.env   # edit tailnet name + 100.x IP
./scripts/generate-public-config.sh              # writes harbour-apps.json + launcher registry
./scripts/up.sh --build
./scripts/verify-tls.sh                          # trusted HTTPS (Tailscale LE certs)
```

Run config generator tests:

```bash
./tests/unit/scripts/generate-public-config-path.test.sh
```

## Security env defaults

Phase 2.5 introduces edge trust + encryption variables used by chat and forward-auth.
For local development they have safe defaults in `compose/.env` / `.env.example`:

- `HARBOUR_PROXY_TOKEN`
- `CHAT_MASTER_KEY_B64`
- `CHAT_MASTER_KEY_ID`
- `REQUIRE_HTTPS_FORWARDED_PROTO`

In production, rotate these values and store them in a secrets manager.

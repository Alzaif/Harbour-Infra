# Phase 0 — Local container stack

Run the Harbour platform (Traefik, Portcullis, platform UI, Notes) on a single machine using Compose.

**Remote access over Tailscale:** see [deploy-podman-tailscale.md](./deploy-podman-tailscale.md) (full Podman guide) or [tailscale-remote-access.md](./tailscale-remote-access.md) (overview).

## Prerequisites

- **Podman** 4+ with Compose (`podman compose`) — default scripts in this repo  
  **or** **Docker Engine** 24+ with Compose v2 — use [`scripts/docker/`](../scripts/docker/)
- Node.js 22+ only if building services outside containers
- **`/etc/hosts` entries** so `harbour.local` resolves (see below) — without this you get `ERR_NAME_NOT_RESOLVED`

### Local DNS (`/etc/hosts`)

`harbour.local` is not public DNS. Add once (Linux):

```bash
sudo tee -a /etc/hosts <<'EOF'
127.0.0.1 harbour.local
127.0.0.1 traefik.harbour.local
EOF
```

Satellite apps are served at path prefixes on the shell host (e.g. `https://harbour.local:8443/notes`).

Verify:

```bash
getent hosts harbour.local
# 127.0.0.1       harbour.local
```

Full list: [hosts.example](./hosts.example). `scripts/up.sh` fails fast if names do not resolve.

## Repository layout

Each service is an independent repo (or folder) checked out as siblings:

```text
Harbour/                    # workspace root — set HARBOUR_ROOT to this path
  harbour-infra/            # orchestration (this repo)
  harbour-platform-ui/
  portcullis/
  harbour-notes/            # personal wiki service
```

## Quick start

### Podman (default)

```bash
cd harbour-infra
chmod +x scripts/*.sh scripts/docker/*.sh scripts/lib/*.sh
./scripts/up.sh
```

### Docker

```bash
cd harbour-infra
./scripts/docker/up.sh
```

On first run, `compose/.env` is created from `.env.example`. Edit `SESSION_SECRET` and `POSTGRES_PASSWORD` before any shared environment.

### First user (closed access — `IDP_MODE=local`)

There is no signup page. After the stack is up, create a user and grant app access:

```bash
cd harbour-infra
chmod +x scripts/user-admin.sh
./scripts/user-admin.sh users create --email you@family.example --name "Your Name" --password 'choose-a-strong-password'
./scripts/user-admin.sh users grant-app --email you@family.example --app notes
./scripts/user-admin.sh users list
```

Sign in at https://harbour.local:8443 (Podman) or https://harbour.local (Docker).

**Stub IdP (dev picker):** add `docker-compose.stub.yml` to your compose command and set `IDP_MODE=stub` — see [compose/docker-compose.stub.yml](../compose/docker-compose.stub.yml).

Open:

**Podman (rootless, default scripts)** — ports ≥ 1024:

- https://harbour.local:8443 — platform shell (accept the self-signed certificate warning)
- https://harbour.local:8443/notes — Notes wiki (sign in at harbour.local:8443 first)
- https://harbour.local:8443/docs — Docs word processor
- https://harbour.local:8443/gym — Gym tracker
- https://harbour.local:8443/chat — Chat (Phase 4 includes WebRTC/SFU control-plane APIs)
- http://localhost:9080 — Traefik dashboard (insecure API)

**Docker** (`scripts/docker/up.sh`) — standard ports:

- https://harbour.local — platform shell
- https://harbour.local/notes — Notes wiki
- https://harbour.local/docs — Docs word processor
- https://harbour.local/gym — Gym tracker
- https://harbour.local/chat — Chat
- http://localhost:8080 — Traefik dashboard

Use `https://harbour.local` URLs in `compose/.env` and `services.registry.json` when on Docker; use `:8443` when on rootless Podman (see `.env.example`).

## Compose files

| File | Purpose |
|------|---------|
| `compose/docker-compose.yml` | Stack definition, Traefik labels, image names |
| `compose/docker-compose.build.yml` | Build contexts via `HARBOUR_ROOT` |
| `compose/docker-compose.podman.yml` | Rootless ports + Podman socket (Podman scripts only) |
| `compose/docker-compose.docker.yml` | Ports 80/443 + Docker socket (Docker scripts only) |
| `compose/docker-compose.prod.yml` | Example registry-image overlay (commented) |
| `compose/docker-compose.stub.yml` | Optional stub IdP overlay (dev user picker) |
| `compose/docker-compose.tailscale.yml` | Optional overlay when `HARBOUR_DEPLOY_PROFILE=tailscale` |
| `compose/.env` | Local secrets and paths (gitignored) |
| `compose/.env.tailscale.example` | Example env for tailnet remote access |
| [deploy-podman-tailscale.md](./deploy-podman-tailscale.md) | Full Podman + Tailscale deployment guide |

### Manual commands

**Podman:**

```bash
cd harbour-infra/compose
cp .env.example .env   # once
podman compose -f docker-compose.yml -f docker-compose.build.yml -f docker-compose.podman.yml --env-file .env up --build -d
# (scripts/up.sh passes the same files; do not add docker-compose.docker.yml)
```

**Docker:**

```bash
cd harbour-infra/compose
cp .env.example .env   # once
docker compose -f docker-compose.yml -f docker-compose.build.yml -f docker-compose.docker.yml --env-file .env up --build -d
```

## Environment variables

| Variable | Purpose |
|----------|---------|
| `HARBOUR_ROOT` | Directory containing `portcullis/`, `harbour-platform-ui/`, etc. |
| `HARBOUR_DNS_ZONE` | Shell hostname (`harbour.local` local; `harbour.<tailnet>.ts.net` remote) |
| `HARBOUR_DEPLOY_PROFILE` | `local` (default) or `tailscale` — see [tailscale-remote-access.md](./tailscale-remote-access.md) |
| `HARBOUR_PUBLIC_HTTPS_PORT` | Browser HTTPS port (`8443` Podman rootless; `443` Docker) |
| `HARBOUR_TAILSCALE_IP` | Host tailnet IP for WebRTC when using Tailscale |
| `SESSION_SECRET` | Signs `harbour_session` cookies (min 16 chars) |
| `PORTCULLIS_ISSUER` | Public issuer URL (`https://harbour.local`) |
| `SESSION_COOKIE_DOMAIN` | Cookie domain (`.harbour.local`) |
| `PODMAN_SOCKET` | Podman API socket for Traefik (Podman only; see below) |
| `CHAT_VOICE_TURN_URLS` | ICE URL list exposed to browser clients |
| `TURN_STATIC_AUTH_SECRET` / `CHAT_VOICE_TURN_SECRET` | Shared secret for TURN time-limited credentials |
| `SFU_ANNOUNCED_IP` | Announced RTP IP for mediasoup transport candidates |
| `VITE_*` | Baked into UI image at build time |

## Routing

Traefik terminates HTTPS on `:443` (default self-signed certificate).

| Host | Path | Backend |
|------|------|---------|
| `harbour.local` | `/oauth`, `/auth`, `/.well-known` | Portcullis |
| `harbour.local` | `/api/stack` | harbour-stack (metrics API) + ForwardAuth |
| `harbour.local` | `/notes`, `/docs`, `/gym`, … | Satellite apps + StripPrefix + ForwardAuth |
| `harbour.local` | `/` (default) | Platform UI (nginx static) |

## Split repos

When services live in separate git clones:

```bash
# .env
HARBOUR_ROOT=/home/you/projects/harbour-workspace
```

Each service repo builds its own image in CI; use `docker-compose.prod.yml` to pin `ghcr.io/...` tags without `build:` contexts.

## Troubleshooting

### Certificate warnings

Traefik serves a generated self-signed cert for `*.harbour.local`. Trust it in your browser for local dev, or terminate TLS elsewhere in production.

### Sign-in redirect loops

Confirm `PORTCULLIS_ISSUER` and UI build args both use `https://harbour.local`, and `SESSION_COOKIE_DOMAIN=.harbour.local`.

### Satellite app returns 401

Sign in at https://harbour.local first so the `harbour_session` cookie is set for `.harbour.local`.

### Voice connected but no remote audio

Verify `harbour-chat-sfu` and `harbour-turn` are healthy, confirm `CHAT_VOICE_TURN_URLS` points to `harbour.local:13478`, and ensure `SFU_ANNOUNCED_IP` matches an address reachable from your browsers.

### Build context not found

Set `HARBOUR_ROOT` in `compose/.env` to the parent folder that contains service directories.

### `rootlessport cannot expose privileged port 80` (or 443)

Rootless Podman cannot bind host ports below 1024. Compose **merges** port lists across files, so privileged `80:80` must not live in the base `docker-compose.yml`. `scripts/up.sh` uses `docker-compose.podman.yml` only for Traefik host ports: **8081** (HTTP), **8443** (HTTPS), **9080** (dashboard).

Use **https://harbour.local:8443** in the browser (not port 443). After changing `compose/.env` URLs, rebuild the UI image:

```bash
./scripts/up.sh --build
```

Override ports in `compose/.env`:

```bash
HOST_HTTP_PORT=8081
HOST_HTTPS_PORT=8443
HOST_TRAEFIK_DASHBOARD_PORT=9080
```

On Docker with rootful ports, use `scripts/docker/up.sh` and standard URLs without `:8443`.

### `ERR_NAME_NOT_RESOLVED` for harbour.local

Your OS does not know `harbour.local`. Add the [hosts](#local-dns-etchosts) entries above, then use **https://harbour.local:8443** (with port on Podman).

### Blank page or `chrome-error` / iframe security error

1. Open **https://harbour.local:8443** directly (not `https://harbour.local` without the port).
2. Accept the Traefik self-signed certificate on that URL first (Advanced → proceed).
3. Rebuild after changing `compose/.env` URLs: `./scripts/up.sh --build`
4. Do not use `http://harbour.local:8081` unless you need HTTP; it redirects to HTTPS **with** port 8443 (`traefik.podman.yml`).

If Sign in fails, confirm `portcullis/config/clients.docker.json` includes `https://harbour.local:8443/oauth/callback`.

### Portcullis `EACCES` on `/app/config/harbour-apps.json`

Do not bind-mount `harbour-apps.json` without the `:z` flag on Podman (SELinux). The file is included in the Portcullis image at `portcullis/config/harbour-apps.json`. Rebuild after editing it:

```bash
./scripts/up.sh --build
```

To change app host → scope mappings, edit [portcullis/config/harbour-apps.json](../../portcullis/config/harbour-apps.json) and keep [harbour-infra/config/harbour-apps.json](../config/harbour-apps.json) in sync (reference copy).

### `permission denied` on `/var/lib/containers/storage/tmp`

This often appears when **`harbour-stack`** tries to bind-mount the rootful Podman storage path (`/var/lib/containers/storage`) while you run **rootless** Podman. Your user cannot read that directory.

**Fix:** use the current `compose/docker-compose.podman.yml`, which mounts only the Podman API socket for `harbour-stack` (no host disk bind). Pull the latest `harbour-infra` and run:

```bash
./scripts/up.sh --build -d
```

Remove from `compose/.env` if present:

```bash
STACK_HOST_DISK_SOURCE=...
```

Optional host disk stats (`df`) are enabled only on **Docker** via `docker-compose.docker.yml` (`STACK_HOST_DISK_PATH=/host-docker`). Rootless stacks still get container/volume metrics without that mount.

If the error persists without any `STACK_HOST_DISK_SOURCE` in `.env`, check Podman storage health: `podman info`, `podman system df`, and `systemctl --user status podman.socket`.

### `permission denied` mounting `/run/podman/podman.sock`

You are likely on **rootless Podman**. The default rootful socket path does not exist; Compose then tries to create it and fails.

`./scripts/up.sh` auto-detects the socket via `podman info` and writes `PODMAN_SOCKET` to `compose/.env`. To fix manually:

```bash
# compose/.env
PODMAN_SOCKET=/run/user/$(id -u)/podman/podman.sock
```

Ensure the user socket is running:

```bash
systemctl --user enable --now podman.socket
```

### Traefik crash loop (`permission denied` on `traefik.yml`)

On Fedora/Bazzite with SELinux, bind mounts need the `:z` flag so the container can read config under your home directory. `docker-compose.podman.yml` uses `ro,z` on the Traefik config and Podman socket mounts. If Traefik still restarts, check `podman logs harbour-traefik`.

### Traefik does not discover routes (Podman)

Traefik uses the container API socket. The Podman overlay mounts `PODMAN_SOCKET` from your environment or `compose/.env`.
- **SELinux (Fedora):** the overlay uses the `:Z` volume flag; if mounts fail, check `ausearch -m avc -ts recent`.
- **Verify socket:** `podman info --format '{{.Host.RemoteSocket.Path}}'`

### `podman compose` vs `docker compose`

| Task | Podman | Docker |
|------|--------|--------|
| Start | `./scripts/up.sh` | `./scripts/docker/up.sh` |
| Stop | `./scripts/down.sh` | `./scripts/docker/down.sh` |

## Stop the stack

```bash
./scripts/down.sh          # Podman
./scripts/docker/down.sh   # Docker
```

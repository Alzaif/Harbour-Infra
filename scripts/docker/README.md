# Docker deploy scripts

Use these on hosts with **Docker Engine** and Compose v2 instead of Podman.

```bash
./scripts/docker/up.sh    # build and start
./scripts/docker/down.sh  # stop
```

The default [`../up.sh`](../up.sh) and [`../down.sh`](../down.sh) use **Podman Compose** with [`compose/docker-compose.podman.yml`](../../compose/docker-compose.podman.yml) (rootless ports + socket).

These scripts add [`compose/docker-compose.docker.yml`](../../compose/docker-compose.docker.yml) for ports **80/443** and the Docker socket.

# harbour-infra — shared Compose helpers (source from up/down scripts).
# Usage: source "$(dirname "$0")/lib/compose-runtime.sh"

harbour_infra_root() {
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "${lib_dir}/../.." && pwd
}

harbour_compose_dir() {
  echo "$(harbour_infra_root)/compose"
}

harbour_ensure_env() {
  local compose_dir env_file
  compose_dir="$(harbour_compose_dir)"
  env_file="${compose_dir}/.env"
  if [[ ! -f "${env_file}" ]]; then
    echo "Creating ${env_file} from .env.example — edit SESSION_SECRET before production use."
    cp "${compose_dir}/.env.example" "${env_file}"
  fi
}

harbour_load_deploy_profile() {
  local env_file key value
  env_file="$(harbour_compose_dir)/.env"
  export HARBOUR_DEPLOY_PROFILE="${HARBOUR_DEPLOY_PROFILE:-local}"
  [[ -f "${env_file}" ]] || return 0
  key="$(grep -E '^HARBOUR_DEPLOY_PROFILE=' "${env_file}" | tail -1 || true)"
  [[ -n "${key}" ]] || return 0
  value="${key#HARBOUR_DEPLOY_PROFILE=}"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  export HARBOUR_DEPLOY_PROFILE="${value:-local}"
}

harbour_load_compose_env() {
  local env_file
  env_file="$(harbour_compose_dir)/.env"
  [[ -f "${env_file}" ]] || return 0
  set -a
  # shellcheck disable=SC1090
  source "${env_file}"
  set +a
}

harbour_maybe_generate_public_config() {
  harbour_load_deploy_profile
  if [[ "${HARBOUR_DEPLOY_PROFILE}" != "tailscale" ]]; then
    return 0
  fi
  local script="$(harbour_infra_root)/scripts/generate-public-config.sh"
  if [[ -x "${script}" ]]; then
    echo "HARBOUR_DEPLOY_PROFILE=tailscale — running generate-public-config.sh"
    "${script}"
  fi
}

# Resolve Podman API socket (rootless vs rootful). Exports PODMAN_SOCKET.
harbour_ensure_podman_socket() {
  if [[ -n "${PODMAN_SOCKET:-}" && -S "${PODMAN_SOCKET}" ]]; then
    return 0
  fi

  local detected="" candidate
  if command -v podman >/dev/null 2>&1; then
    detected="$(podman info --format '{{.Host.RemoteSocket.Path}}' 2>/dev/null || true)"
  fi

  if [[ -z "${detected}" || ! -S "${detected}" ]]; then
    for candidate in \
      "${XDG_RUNTIME_DIR}/podman/podman.sock" \
      "/run/user/$(id -u)/podman/podman.sock" \
      "/run/podman/podman.sock" \
      "/var/run/docker.sock"; do
      if [[ -n "${candidate}" && -S "${candidate}" ]]; then
        detected="${candidate}"
        break
      fi
    done
  fi

  if [[ -z "${detected}" || ! -S "${detected}" ]]; then
    echo "Error: Podman API socket not found." >&2
    echo "  Rootless: start the podman socket service, e.g. systemctl --user enable --now podman.socket" >&2
    echo "  Or set PODMAN_SOCKET in compose/.env (see .env.example)." >&2
    return 1
  fi

  export PODMAN_SOCKET="${detected}"
  echo "Using Podman socket: ${PODMAN_SOCKET}"
}

# Persist PODMAN_SOCKET in compose/.env when missing (optional convenience).
# Rootless Podman cannot bind host ports < 1024; set defaults and align public URLs.
harbour_ensure_rootless_host_ports() {
  export HOST_HTTP_PORT="${HOST_HTTP_PORT:-8081}"
  export HOST_HTTPS_PORT="${HOST_HTTPS_PORT:-8443}"
  export HOST_TRAEFIK_DASHBOARD_PORT="${HOST_TRAEFIK_DASHBOARD_PORT:-9080}"

  local zone="${HARBOUR_DNS_ZONE:-harbour.local}"
  local origin="https://${zone}:${HOST_HTTPS_PORT}"
  if [[ -z "${PORTCULLIS_ISSUER:-}" || "${PORTCULLIS_ISSUER}" == "https://harbour.local" || "${PORTCULLIS_ISSUER}" == "https://${zone}" ]]; then
    export PORTCULLIS_ISSUER="${origin}"
  fi
  if [[ -z "${VITE_OIDC_ISSUER:-}" || "${VITE_OIDC_ISSUER}" == "https://harbour.local" || "${VITE_OIDC_ISSUER}" == "https://${zone}" ]]; then
    export VITE_OIDC_ISSUER="${origin}"
  fi
  if [[ -z "${VITE_HARBOUR_SHELL_URL:-}" || "${VITE_HARBOUR_SHELL_URL}" == "https://harbour.local" || "${VITE_HARBOUR_SHELL_URL}" == "https://${zone}" ]]; then
    export VITE_HARBOUR_SHELL_URL="${origin}"
  fi

  echo "Rootless ports: HTTP=${HOST_HTTP_PORT} HTTPS=${HOST_HTTPS_PORT} dashboard=${HOST_TRAEFIK_DASHBOARD_PORT}"
  echo "Public origin: ${origin}"
}

harbour_persist_podman_socket_env() {
  local env_file line
  env_file="$(harbour_compose_dir)/.env"
  [[ -f "${env_file}" && -n "${PODMAN_SOCKET:-}" ]] || return 0
  if grep -q '^PODMAN_SOCKET=' "${env_file}" 2>/dev/null; then
    return 0
  fi
  line="PODMAN_SOCKET=${PODMAN_SOCKET}"
  echo "" >> "${env_file}"
  echo "# Auto-detected by scripts/up.sh ($(date -Iseconds 2>/dev/null || date))" >> "${env_file}"
  echo "${line}" >> "${env_file}"
  echo "Wrote ${line} to ${env_file}"
}

# Compose file stack for the given runtime: podman | docker
harbour_compose_file_args() {
  local runtime="${1:?runtime must be podman or docker}"
  echo -f docker-compose.yml -f docker-compose.build.yml
  harbour_load_deploy_profile
  if [[ "${HARBOUR_DEPLOY_PROFILE}" == "tailscale" ]]; then
    echo -f docker-compose.tailscale.yml
  fi
  if [[ "${runtime}" == "podman" ]]; then
    echo -f docker-compose.podman.yml
  elif [[ "${runtime}" == "docker" ]]; then
    echo -f docker-compose.docker.yml
  fi
}

harbour_compose() {
  local runtime="${1:?}"
  shift
  local compose_dir bin
  compose_dir="$(harbour_compose_dir)"

  if [[ "${runtime}" == "podman" ]]; then
    bin=(podman compose)
  elif [[ "${runtime}" == "docker" ]]; then
    bin=(docker compose)
  else
    echo "Unknown runtime: ${runtime} (use podman or docker)" >&2
    return 1
  fi

  if ! command -v "${bin[0]}" >/dev/null 2>&1; then
    echo "Error: ${bin[*]} not found. Install ${runtime} and compose support." >&2
    return 1
  fi

  if [[ "${runtime}" == "podman" ]]; then
    harbour_load_compose_env
    harbour_ensure_podman_socket || return 1
    harbour_persist_podman_socket_env
    harbour_ensure_rootless_host_ports
  fi

  cd "${compose_dir}"
  # shellcheck disable=SC2046
  "${bin[@]}" $(harbour_compose_file_args "${runtime}") --env-file .env "$@"
}

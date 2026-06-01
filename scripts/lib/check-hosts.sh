# Verify *.harbour.local resolves (requires /etc/hosts). Source from up.sh.

harbour_check_hosts() {
  local missing=()
  local host

  for host in harbour.local notes.harbour.local traefik.harbour.local; do
    if ! getent hosts "${host}" >/dev/null 2>&1; then
      missing+=("${host}")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi

  echo "ERROR: These hostnames do not resolve: ${missing[*]}" >&2
  echo "" >&2
  echo "Add local DNS entries (requires sudo once). From this repo:" >&2
  echo "  sudo cp docs/hosts.example /tmp/harbour-hosts.snippet" >&2
  echo "  sudo bash -c 'grep -v \"^#\" /tmp/harbour-hosts.snippet >> /etc/hosts'" >&2
  echo "" >&2
  echo "Or paste into /etc/hosts:" >&2
  grep -v '^#' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/docs/hosts.example" | grep -v '^[[:space:]]*$' >&2
  echo "" >&2
  echo "Then open: https://harbour.local:8443  (Podman rootless)" >&2
  echo "" >&2
  echo "Deploy continues anyway. Test without /etc/hosts:" >&2
  echo "  curl -k -I --resolve harbour.local:8443:127.0.0.1 https://harbour.local:8443/" >&2
  if [[ "${HARBOUR_REQUIRE_HOSTS:-}" == "1" ]]; then
    return 1
  fi
  return 0
}

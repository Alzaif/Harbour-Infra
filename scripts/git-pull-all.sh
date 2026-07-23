#!/usr/bin/env bash
# Pull every Harbour satellite repo under the workspace root in parallel.
#
# Lives in harbour-infra but operates on sibling checkouts (and optionally the
# workspace umbrella root). Discovery matches scripts/git-commit-push-all.sh.
#
# Usage:
#   ./scripts/git-pull-all.sh
#   ./scripts/git-pull-all.sh --dry-run
#   ./scripts/git-pull-all.sh --include-root
#   ./scripts/git-pull-all.sh --only harbour-chat,harbour-infra
#   ./scripts/git-pull-all.sh --ff-only
#
# Run from the workspace root:
#   ./harbour-infra/scripts/git-pull-all.sh
# Or from harbour-infra:
#   ./scripts/git-pull-all.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# harbour-infra/scripts → harbour-infra → workspace root
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

DRY_RUN=0
INCLUDE_ROOT=0
SEQUENTIAL=0
FF_ONLY=0
ONLY_FILTER=""

usage() {
  cat <<'EOF'
Pull all Harbour child git repositories in parallel.

Usage:
  git-pull-all.sh [options]

Options:
  --dry-run             Print actions without network or git writes
  --include-root        Include the workspace root repo (Harbour umbrella)
  --only LIST           Comma-separated repo directory names (e.g. harbour-chat,portcullis)
  --ff-only             Use git pull --ff-only (fail instead of merging)
  --sequential          Run repos one at a time (easier to read logs)
  -h, --help            Show this help

Examples:
  ./harbour-infra/scripts/git-pull-all.sh
  ./harbour-infra/scripts/git-pull-all.sh --dry-run
  ./harbour-infra/scripts/git-pull-all.sh --only harbour-chat,harbour-infra
  ./harbour-infra/scripts/git-pull-all.sh --include-root --ff-only
EOF
}

log() {
  printf '%s\n' "$*"
}

die() {
  log "error: $*" >&2
  exit 1
}

discover_repos() {
  local repos=()
  local entry name

  if [[ "$INCLUDE_ROOT" -eq 1 && -d "${ROOT_DIR}/.git" ]]; then
    repos+=("$ROOT_DIR")
  fi

  for entry in "${ROOT_DIR}"/*/; do
    [[ -d "${entry}.git" ]] || continue
    name="$(basename "${entry%/}")"
    if [[ -n "$ONLY_FILTER" ]]; then
      case ",${ONLY_FILTER}," in
        *,"${name}",*) repos+=("${entry%/}") ;;
      esac
    else
      repos+=("${entry%/}")
    fi
  done

  if [[ "${#repos[@]}" -eq 0 ]]; then
    die "no repositories found (use --include-root or check --only names)"
  fi

  mapfile -t repos < <(printf '%s\n' "${repos[@]}" | sort)
  printf '%s\n' "${repos[@]}"
}

pull_repo() {
  local repo_path="$1"
  local name
  name="$(basename "$repo_path")"

  (
    repo_log() { log "[$name] $*"; }

    cd "$repo_path"

    if [[ ! -d .git ]]; then
      repo_log "skip: not a git repository"
      exit 2
    fi

    if ! git remote 2>/dev/null | grep -q .; then
      repo_log "skip: no git remote configured"
      exit 0
    fi

    local branch
    branch="$(git branch --show-current 2>/dev/null || true)"
    if [[ -z "$branch" ]]; then
      repo_log "skip: detached HEAD"
      exit 3
    fi

    local dirty=""
    dirty="$(git status --porcelain 2>/dev/null || true)"
    if [[ -n "$dirty" ]]; then
      repo_log "warning: working tree has local changes; pull may fail or merge"
    fi

    local pull_args=(pull)
    if [[ "$FF_ONLY" -eq 1 ]]; then
      pull_args+=(--ff-only)
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
      repo_log "would: git ${pull_args[*]} (branch ${branch})"
      exit 0
    fi

    git "${pull_args[@]}"
    repo_log "pulled (${branch})"
  )
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --include-root)
        INCLUDE_ROOT=1
        shift
        ;;
      --sequential)
        SEQUENTIAL=1
        shift
        ;;
      --ff-only)
        FF_ONLY=1
        shift
        ;;
      --only)
        [[ $# -ge 2 ]] || die "--only requires a comma-separated list"
        ONLY_FILTER="$2"
        shift 2
        ;;
      -*)
        die "unknown option: $1 (try --help)"
        ;;
      *)
        die "unexpected argument: $1 (try --help)"
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  mapfile -t REPOS < <(discover_repos)

  log "Harbour multi-repo pull"
  log "  root:       ${ROOT_DIR}"
  log "  repos:      ${#REPOS[@]}"
  log "  dry-run:    ${DRY_RUN}"
  log "  ff-only:    ${FF_ONLY}"
  log "  parallel:   $([[ "$SEQUENTIAL" -eq 1 ]] && echo no || echo yes)"
  log ""

  local -a pids=()
  local -a names=()
  local repo_path name status
  local failed=0

  for repo_path in "${REPOS[@]}"; do
    name="$(basename "$repo_path")"
    names+=("$name")

    if [[ "$SEQUENTIAL" -eq 1 ]]; then
      if ! pull_repo "$repo_path"; then
        failed=$((failed + 1))
      fi
      continue
    fi

    pull_repo "$repo_path" &
    pids+=("$!")
  done

  if [[ "$SEQUENTIAL" -eq 0 ]]; then
    for i in "${!pids[@]}"; do
      status=0
      wait "${pids[$i]}" || status=$?
      if [[ "$status" -ne 0 ]]; then
        log "error: ${names[$i]} exited with status ${status}" >&2
        failed=$((failed + 1))
      fi
    done
  fi

  log ""
  if [[ "$failed" -gt 0 ]]; then
    die "${failed} repository operation(s) failed"
  fi
  log "done (${#REPOS[@]} repositories)"
}

main "$@"

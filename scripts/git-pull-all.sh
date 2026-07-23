#!/usr/bin/env bash
# Clone (if missing) and pull every Harbour satellite repo under the workspace root.
#
# Usage:
#   ./scripts/git-pull-all.sh
#   ./scripts/git-pull-all.sh --dry-run
#   ./scripts/git-pull-all.sh --skip-root
#   ./scripts/git-pull-all.sh --only harbour-chat,harbour-infra
#   ./scripts/git-pull-all.sh --ff-only
#   ./scripts/git-pull-all.sh --ssh
#
# Repo list: scripts/harbour-repos.list (local dir + GitHub repo name).
# Missing directories are cloned from GitHub; existing .git checkouts are pulled.
# Extra local child repos with .git (not in the list) are also pulled.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_LIST="${ROOT_DIR}/scripts/harbour-repos.list"
GIT_ORG="${HARBOUR_GIT_ORG:-Alzaif}"

DRY_RUN=0
INCLUDE_ROOT=1
SEQUENTIAL=0
FF_ONLY=0
USE_SSH=0
ONLY_FILTER=""

usage() {
  cat <<'EOF'
Clone missing Harbour repos (from the canonical list) and pull all of them.

Usage:
  git-pull-all.sh [options]

Repo list:
  scripts/harbour-repos.list — one "local-dir  GitHub-repo-name" per line.
  Clone base: https://github.com/$HARBOUR_GIT_ORG/<repo>.git
  (default org: Alzaif; override with HARBOUR_GIT_ORG; --ssh uses git@github.com:…)

Options:
  --dry-run             Print actions without network or git writes
  --skip-root           Skip the workspace root umbrella repo
  --include-root        Include the workspace root (default; pull only if it has a remote)
  --only LIST           Comma-separated local directory names
  --ff-only             Use git pull --ff-only (fail instead of merging)
  --ssh                 Clone/pull via SSH (git@github.com:ORG/REPO.git)
  --sequential          Run repos one at a time (easier to read logs)
  -h, --help            Show this help

Examples:
  ./scripts/git-pull-all.sh
  ./scripts/git-pull-all.sh --dry-run
  ./scripts/git-pull-all.sh --only harbour-chat,harbour-infra
  HARBOUR_GIT_ORG=Alzaif ./scripts/git-pull-all.sh --ssh
EOF
}

log() {
  printf '%s\n' "$*"
}

die() {
  log "error: $*" >&2
  exit 1
}

repo_label() {
  local repo_path="$1"
  if [[ "$repo_path" == "$ROOT_DIR" ]]; then
    printf '%s\n' "$(basename "$ROOT_DIR")"
  else
    printf '%s\n' "$(basename "$repo_path")"
  fi
}

clone_url_for() {
  local github_repo="$1"
  if [[ "$USE_SSH" -eq 1 ]]; then
    printf 'git@github.com:%s/%s.git\n' "$GIT_ORG" "$github_repo"
  else
    printf 'https://github.com/%s/%s.git\n' "$GIT_ORG" "$github_repo"
  fi
}

only_matches() {
  local name="$1"
  [[ -z "$ONLY_FILTER" ]] && return 0
  case ",${ONLY_FILTER}," in
    *,"${name}",*) return 0 ;;
    *) return 1 ;;
  esac
}

# Populate CANONICAL_DIRS and CANONICAL_GITHUB associative arrays from the list file.
load_repo_list() {
  [[ -f "$REPO_LIST" ]] || die "missing repo list: ${REPO_LIST}"

  declare -gA CANONICAL_GITHUB=()
  declare -ga CANONICAL_ORDER=()

  local line dir github
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$line" ]] && continue
    # shellcheck disable=SC2086
    set -- $line
    dir="${1:-}"
    github="${2:-}"
    [[ -n "$dir" && -n "$github" ]] || die "invalid line in ${REPO_LIST}: ${line}"
    CANONICAL_ORDER+=("$dir")
    CANONICAL_GITHUB["$dir"]="$github"
  done <"$REPO_LIST"

  [[ "${#CANONICAL_ORDER[@]}" -gt 0 ]] || die "repo list is empty: ${REPO_LIST}"
}

# Ensure each canonical repo exists (clone if needed). Prints paths to process.
prepare_repos() {
  local dirs=()
  local dir github path url name
  local root_name
  root_name="$(basename "$ROOT_DIR")"

  if [[ "$INCLUDE_ROOT" -eq 1 && -d "${ROOT_DIR}/.git" ]]; then
    if [[ -z "$ONLY_FILTER" ]] || only_matches "$root_name" || only_matches "." || only_matches "Harbour"; then
      dirs+=("$ROOT_DIR")
    fi
  fi

  for dir in "${CANONICAL_ORDER[@]}"; do
    only_matches "$dir" || continue
    github="${CANONICAL_GITHUB[$dir]}"
    path="${ROOT_DIR}/${dir}"
    url="$(clone_url_for "$github")"

    if [[ -d "${path}/.git" ]]; then
      dirs+=("$path")
    elif [[ -e "$path" ]]; then
      # stderr: stdout is the path list for the caller
      log "[$dir] skip: path exists but is not a git checkout (remove or move it to clone)" >&2
    else
      if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[$dir] would: git clone ${url} ${path}" >&2
        dirs+=("$path")
      else
        log "[$dir] cloning ${url}" >&2
        git clone "$url" "$path"
        dirs+=("$path")
      fi
    fi
  done

  # Also pull any extra local child repos not in the canonical list
  local entry
  for entry in "${ROOT_DIR}"/*/; do
    [[ -d "${entry}.git" ]] || continue
    name="$(basename "${entry%/}")"
    only_matches "$name" || continue
    if [[ -z "${CANONICAL_GITHUB[$name]+x}" ]]; then
      dirs+=("${entry%/}")
    fi
  done

  if [[ "${#dirs[@]}" -eq 0 ]]; then
    die "no repositories to process (check --only / harbour-repos.list)"
  fi

  # Deduplicate while preserving order
  local -A seen=()
  local -a unique=()
  local p
  for p in "${dirs[@]}"; do
    [[ -n "${seen[$p]+x}" ]] && continue
    seen["$p"]=1
    unique+=("$p")
  done

  mapfile -t unique < <(printf '%s\n' "${unique[@]}" | sort)
  printf '%s\n' "${unique[@]}"
}

pull_repo() {
  local repo_path="$1"
  local name
  name="$(repo_label "$repo_path")"

  (
    repo_log() { log "[$name] $*"; }

    # Dry-run clone may list a path that does not exist yet
    if [[ ! -d "$repo_path" ]]; then
      if [[ "$DRY_RUN" -eq 1 ]]; then
        repo_log "would: git pull (after clone)"
        exit 0
      fi
      repo_log "skip: directory missing"
      exit 2
    fi

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
      --skip-root)
        INCLUDE_ROOT=0
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
      --ssh)
        USE_SSH=1
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
  load_repo_list

  mapfile -t REPOS < <(prepare_repos)

  log "Harbour multi-repo pull"
  log "  root:         ${ROOT_DIR}"
  log "  list:         ${REPO_LIST}"
  log "  org:          ${GIT_ORG}"
  log "  repos:        ${#REPOS[@]}"
  log "  dry-run:      ${DRY_RUN}"
  log "  ff-only:      ${FF_ONLY}"
  log "  ssh:          ${USE_SSH}"
  log "  include-root: ${INCLUDE_ROOT}"
  log "  parallel:     $([[ "$SEQUENTIAL" -eq 1 ]] && echo no || echo yes)"
  log ""

  local -a pids=()
  local -a names=()
  local repo_path name status
  local failed=0

  for repo_path in "${REPOS[@]}"; do
    name="$(repo_label "$repo_path")"
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

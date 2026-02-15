#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
workspace_root="$(cd "$REPO_ROOT/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  ./verify-workspace-script-boundaries.sh [--workspace-root <path>]

Checks sibling repositories in a workspace and fails if shared scripts are tracked
outside the scripts repository.
USAGE
}

fail_usage() {
  echo "[verify-workspace-script-boundaries] ERROR: $*" >&2
  echo >&2
  usage >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root)
      [[ $# -ge 2 ]] || fail_usage "Missing value for --workspace-root"
      workspace_root="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail_usage "Unknown argument: $1"
      ;;
  esac
done

[[ -d "$workspace_root" ]] || fail_usage "Workspace root does not exist: $workspace_root"

pattern='(^|/)(build-all-mods\.sh|build-all-mods 2\.sh|verify-hytale-mod-install\.sh|verify-hytale-mod-install 2\.sh|verify-module-boundaries\.sh)$'

declare -a candidates=()
candidates+=("$workspace_root")

while IFS= read -r -d '' dir; do
  candidates+=("$dir")
done < <(find "$workspace_root" -mindepth 1 -maxdepth 1 -type d -print0)

seen=''
checked=0
violations=0

echo "[verify-workspace-script-boundaries] Workspace root: $workspace_root"

for repo_dir in "${candidates[@]}"; do
  [[ -d "$repo_dir/.git" ]] || continue

  # De-duplicate repo paths in case of overlap.
  if printf '%s\n' "$seen" | rg -qxF "$repo_dir"; then
    continue
  fi
  seen+="$repo_dir"$'\n'

  repo_name="$(basename "$repo_dir")"
  if [[ "$repo_name" == "scripts" ]]; then
    echo "[SKIP] $repo_dir (canonical scripts repo)"
    continue
  fi

  checked=$((checked + 1))

  matches="$(git -C "$repo_dir" ls-files | rg -n "$pattern" || true)"
  if [[ -n "$matches" ]]; then
    violations=$((violations + 1))
    echo "[FAIL] $repo_dir"
    echo "$matches" | sed 's/^/  /'
  else
    echo "[OK] $repo_dir"
  fi
done

if [[ $checked -eq 0 ]]; then
  echo "[verify-workspace-script-boundaries] WARNING: no sibling git repos detected."
fi

if [[ $violations -gt 0 ]]; then
  echo "[verify-workspace-script-boundaries] ERROR: scripts must live only in Shieldudaram/scripts."
  exit 1
fi

echo "[verify-workspace-script-boundaries] OK: no script ownership boundary violations found."

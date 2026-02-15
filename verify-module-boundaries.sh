#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "[verify-module-boundaries] ERROR: $*" >&2
  exit 1
}

cd "$WORKSPACE_ROOT"

if git ls-files | rg -q '^fight-caves/'; then
  fail "fight-caves/ is still tracked by Colonists repo. It must live only in Shieldudaram/fight-caves."
fi

search_roots=()
[[ -d Colonists ]] && search_roots+=(Colonists)
[[ -d pest-control ]] && search_roots+=(pest-control)

if [[ ${#search_roots[@]} -gt 0 ]]; then
  if rg -n 'com\.shieldudaram\.fightcaves|FightCavesPlugin|/fightcaves' "${search_roots[@]}"; then
    fail "Fight Caves identifiers found inside Colonists or pest-control paths."
  fi
fi

echo "[verify-module-boundaries] OK: Fight Caves boundaries enforced."

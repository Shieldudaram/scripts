#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODS_DIR="${HYTALE_MODS_DIR:-$HOME/Library/Application Support/Hytale/UserData/Mods}"

fail() {
  echo "[verify-hytale-mod-install] ERROR: $*" >&2
  exit 1
}

require_file() {
  local p="$1"
  [[ -f "$p" ]] || fail "Required file not found: $p"
}

verify_module() {
  local module_dir="$1"
  local module_name="$2"
  local main_class="$3"

  local build_libs="$module_dir/build/libs"
  [[ -d "$build_libs" ]] || fail "Missing build/libs for module '$module_name': $build_libs"

  local latest_hytale_jar
  latest_hytale_jar="$(ls -t "$build_libs"/${module_name}-*-hytale.jar 2>/dev/null | head -n 1 || true)"
  [[ -n "$latest_hytale_jar" ]] || fail "No -hytale artifact found for '$module_name' in $build_libs"

  local latest_core_jar
  latest_core_jar="$(ls -t "$build_libs"/${module_name}-*-core.jar 2>/dev/null | head -n 1 || true)"
  [[ -n "$latest_core_jar" ]] || fail "No -core artifact found for '$module_name' in $build_libs"

  local expected_installed
  expected_installed="$MODS_DIR/$(basename "$latest_hytale_jar")"
  require_file "$expected_installed"

  local legacy
  legacy="$(find "$MODS_DIR" -maxdepth 1 -type f -name "${module_name}-*.jar" ! -name "${module_name}-*-hytale.jar" | head -n 1 || true)"
  [[ -z "$legacy" ]] || fail "Found legacy non-hytale artifact for '$module_name': $legacy"

  jar tf "$expected_installed" | rg -q 'manifest.json' || fail "manifest.json missing in installed jar: $expected_installed"
  local class_path="${main_class//./\/}.class"
  jar tf "$expected_installed" | rg -q "$class_path" || fail "Main class '$main_class' missing in installed jar: $expected_installed"

  echo "[verify-hytale-mod-install] OK: $module_name -> $(basename "$expected_installed")"
}

[[ -d "$MODS_DIR" ]] || fail "Hytale Mods directory not found: $MODS_DIR"

verify_module "$WORKSPACE_ROOT/fight-caves" "fight-caves" "com.shieldudaram.fightcaves.plugin.FightCavesPlugin"
verify_module "$WORKSPACE_ROOT/Colonists" "colonists" "com.shieldudaram.colonists.plugin.ColonistsPlugin"

echo "[verify-hytale-mod-install] All checks passed."

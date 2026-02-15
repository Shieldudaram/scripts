#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/build-all-mods.sh [options]

Builds all Gradle-based mods in this workspace using:
  ./gradlew clean build installToHytaleMods

Options:
  --hytale-home <path>         Override Hytale home path.
  --require-hytale <bool>      true|false. Forwarded as -Prequire_hytale (default: true).
  --module <name>              Include only this module. Repeatable.
  --skip <name>                Exclude this module. Repeatable.
  --dry-run                    Print planned actions without running Gradle.
  --extra-gradle-arg <arg>     Extra Gradle arg appended to every module command. Repeatable.
  --help                       Show this help text.

Examples:
  ./scripts/build-all-mods.sh
  ./scripts/build-all-mods.sh --module DuelArena --module hytalecraft
  ./scripts/build-all-mods.sh --skip SimpleClaims-RR
  ./scripts/build-all-mods.sh --require-hytale false --extra-gradle-arg --no-daemon
EOF
}

fail_usage() {
  echo "[$SCRIPT_NAME] ERROR: $*" >&2
  echo >&2
  usage >&2
  exit 2
}

fail_config() {
  echo "[$SCRIPT_NAME] ERROR: $*" >&2
  exit 2
}

normalize_bool() {
  local raw="$1"
  local lower
  lower="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    true|false) printf '%s' "$lower" ;;
    *) return 1 ;;
  esac
}

contains_exact() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

resolve_hytale_home() {
  local explicit="$1"

  if [[ -n "$explicit" ]]; then
    printf '%s\n' "$explicit"
    return 0
  fi

  if [[ -n "${HYTALE_HOME:-}" ]]; then
    printf '%s\n' "$HYTALE_HOME"
    return 0
  fi

  case "$(uname -s)" in
    Darwin)
      printf '%s\n' "$HOME/Library/Application Support/Hytale"
      ;;
    Linux)
      local flatpak="$HOME/.var/app/com.hypixel.HytaleLauncher/data/Hytale"
      if [[ -d "$flatpak" ]]; then
        printf '%s\n' "$flatpak"
      else
        printf '%s\n' "$HOME/.local/share/Hytale"
      fi
      ;;
    CYGWIN*|MINGW*|MSYS*)
      printf '%s\n' "$HOME/AppData/Roaming/Hytale"
      ;;
    *)
      printf '\n'
      ;;
  esac
}

print_cmd() {
  local first=true
  local arg
  for arg in "$@"; do
    if [[ "$first" == true ]]; then
      first=false
    else
      printf ' '
    fi
    printf '%q' "$arg"
  done
}

discover_modules() {
  local dir base
  for dir in "$WORKSPACE_ROOT"/*; do
    [[ -d "$dir" ]] || continue
    [[ -x "$dir/gradlew" ]] || continue
    if [[ -f "$dir/build.gradle" || -f "$dir/build.gradle.kts" ]]; then
      base="$(basename "$dir")"
      printf '%s\n' "$base"
    fi
  done | sort
}

hytale_home_override=""
require_hytale="true"
dry_run="false"
declare -a include_modules=()
declare -a skip_modules=()
declare -a extra_gradle_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hytale-home)
      [[ $# -ge 2 ]] || fail_usage "Missing value for --hytale-home"
      hytale_home_override="$2"
      shift 2
      ;;
    --require-hytale)
      [[ $# -ge 2 ]] || fail_usage "Missing value for --require-hytale"
      require_hytale="$2"
      shift 2
      ;;
    --module)
      [[ $# -ge 2 ]] || fail_usage "Missing value for --module"
      include_modules+=("$2")
      shift 2
      ;;
    --skip)
      [[ $# -ge 2 ]] || fail_usage "Missing value for --skip"
      skip_modules+=("$2")
      shift 2
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    --extra-gradle-arg)
      [[ $# -ge 2 ]] || fail_usage "Missing value for --extra-gradle-arg"
      extra_gradle_args+=("$2")
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

if ! require_hytale="$(normalize_bool "$require_hytale")"; then
  fail_usage "Invalid boolean for --require-hytale: $require_hytale (expected true or false)"
fi

resolved_hytale_home="$(resolve_hytale_home "$hytale_home_override")"

if [[ "$require_hytale" == "true" ]]; then
  if [[ -z "$resolved_hytale_home" ]]; then
    fail_config "Could not resolve Hytale home. Use --hytale-home <path> or HYTALE_HOME."
  fi
  if [[ ! -d "$resolved_hytale_home" ]]; then
    fail_config "Hytale home does not exist at: $resolved_hytale_home"
  fi
fi

discovered_modules=()
while IFS= read -r mod_name; do
  [[ -n "$mod_name" ]] || continue
  discovered_modules+=("$mod_name")
done < <(discover_modules)
if [[ ${#discovered_modules[@]} -eq 0 ]]; then
  fail_config "No Gradle modules found under: $WORKSPACE_ROOT"
fi

if [[ ${#include_modules[@]} -gt 0 ]]; then
  local_missing=()
  for requested in "${include_modules[@]}"; do
    if ! contains_exact "$requested" "${discovered_modules[@]}"; then
      local_missing+=("$requested")
    fi
  done
  if [[ ${#local_missing[@]} -gt 0 ]]; then
    fail_config "Requested --module not found: ${local_missing[*]}"
  fi
fi

selected_modules=()
if [[ ${#include_modules[@]} -gt 0 ]]; then
  for mod in "${discovered_modules[@]}"; do
    if contains_exact "$mod" "${include_modules[@]}"; then
      selected_modules+=("$mod")
    fi
  done
else
  selected_modules=("${discovered_modules[@]}")
fi

final_modules=()
for mod in "${selected_modules[@]}"; do
  if [[ ${#skip_modules[@]} -gt 0 ]]; then
    if contains_exact "$mod" "${skip_modules[@]}"; then
      continue
    fi
  fi
  final_modules+=("$mod")
done

if [[ ${#final_modules[@]} -eq 0 ]]; then
  fail_config "No modules left to build after applying include/skip filters."
fi

declare -a base_gradle_cmd=(clean build installToHytaleMods "-Prequire_hytale=$require_hytale")
if [[ -n "$resolved_hytale_home" ]]; then
  base_gradle_cmd+=("-Phytale_home=$resolved_hytale_home" "-PhytaleHome=$resolved_hytale_home")
fi
if [[ ${#extra_gradle_args[@]} -gt 0 ]]; then
  base_gradle_cmd+=("${extra_gradle_args[@]}")
fi

echo "[$SCRIPT_NAME] Workspace root: $WORKSPACE_ROOT"
if [[ -n "$resolved_hytale_home" ]]; then
  echo "[$SCRIPT_NAME] Hytale home: $resolved_hytale_home"
else
  echo "[$SCRIPT_NAME] Hytale home: <unresolved>"
fi
echo "[$SCRIPT_NAME] require_hytale: $require_hytale"
echo "[$SCRIPT_NAME] Modules (${#final_modules[@]}): ${final_modules[*]}"

if [[ "$dry_run" == "true" ]]; then
  echo
  echo "[$SCRIPT_NAME] Dry run: planned commands"
  for mod in "${final_modules[@]}"; do
    printf '[%s] %s: (cd %q && ./gradlew ' "$SCRIPT_NAME" "$mod" "$WORKSPACE_ROOT/$mod"
    print_cmd "${base_gradle_cmd[@]}"
    printf ')\n'
  done
  exit 0
fi

echo
declare -i success_count=0
declare -i failure_count=0
declare -a failed_modules=()
declare -a failed_codes=()

for mod in "${final_modules[@]}"; do
  module_dir="$WORKSPACE_ROOT/$mod"
  module_start_secs="$(date +%s)"

  echo "===== BUILD START: $mod ====="

  if (cd "$module_dir" && ./gradlew "${base_gradle_cmd[@]}"); then
    rc=0
    success_count+=1
    echo "[OK] $mod"
  else
    rc=$?
    failure_count+=1
    failed_modules+=("$mod")
    failed_codes+=("$rc")
    echo "[FAIL] $mod (exit $rc)"
  fi

  module_end_secs="$(date +%s)"
  elapsed="$((module_end_secs - module_start_secs))"
  echo "===== BUILD END: $mod (${elapsed}s) ====="
  echo
done

echo "===== SUMMARY ====="
echo "Total modules: ${#final_modules[@]}"
echo "Succeeded: $success_count"
echo "Failed: $failure_count"

if [[ $failure_count -gt 0 ]]; then
  echo "Failed modules:"
  idx=0
  while [[ $idx -lt ${#failed_modules[@]} ]]; do
    echo "  - ${failed_modules[$idx]} (exit ${failed_codes[$idx]})"
    idx=$((idx + 1))
  done
  exit 1
fi

echo "All modules built successfully."
exit 0

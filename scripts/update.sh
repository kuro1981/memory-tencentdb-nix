#!/usr/bin/env bash
set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

readonly NPM_PACKAGE="@tencentdb-agent-memory/memory-tencentdb"
readonly NPM_REGISTRY="https://registry.npmjs.org"
# URL エンコードした形（@ と / を含むため）
readonly NPM_PACKAGE_URL="${NPM_REGISTRY}/@tencentdb-agent-memory%2Fmemory-tencentdb"

readonly DUMMY_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

ensure_in_repository_root() {
  if [[ ! -f "flake.nix" || ! -f "package.nix" || ! -f "package.json" ]]; then
    log_error "flake.nix / package.nix / package.json not found. Run this script from repo root."
    exit 1
  fi
}

ensure_required_tools_installed() {
  command -v jq  >/dev/null 2>&1 || { log_error "jq is required but not installed.";   exit 1; }
  command -v nix >/dev/null 2>&1 || { log_error "nix is required but not installed.";  exit 1; }
  command -v npm >/dev/null 2>&1 || { log_error "npm is required but not installed.";  exit 1; }
  command -v curl >/dev/null 2>&1 || { log_error "curl is required but not installed."; exit 1; }
}

get_current_version() {
  sed -n 's/.*version = "\([^"]*\)".*/\1/p' package.nix | head -1 || echo "unknown"
}

get_latest_version() {
  local version
  version=$(curl -sSf "$NPM_PACKAGE_URL" 2>/dev/null | jq -r '.["dist-tags"].latest' || true)
  if [[ -z "$version" || "$version" == "null" ]]; then
    log_error "Failed to fetch latest version of ${NPM_PACKAGE} from npm registry"
    exit 1
  fi
  echo "$version"
}

update_version_in_package_nix() {
  local version="$1"
  sed -i.bak "s/version = \".*\";/version = \"${version}\";/" package.nix
}

update_version_in_package_json() {
  local version="$1"
  local temp_file
  temp_file=$(mktemp)
  jq --arg v "$version" \
     '.version = $v | .dependencies["'"$NPM_PACKAGE"'"] = "^" + $v' \
     package.json > "$temp_file"
  mv "$temp_file" package.json
}

regenerate_lock_file() {
  log_info "Regenerating package-lock.json..."
  rm -f package-lock.json
  npm install --package-lock-only --ignore-scripts >/dev/null 2>&1
}

set_npm_deps_hash() {
  local hash="$1"
  sed -i.bak "s|npmDepsHash = \".*\";|npmDepsHash = \"${hash}\";|" package.nix
}

# npmDepsHash はビルドを一度失敗させて正しい値を取得する。
# nix は fixed-output derivation の不一致時に got: <hash> を出力する。
resolve_npm_deps_hash() {
  log_info "Resolving npmDepsHash (a failed build is expected here)..."
  set_npm_deps_hash "$DUMMY_HASH"

  local output
  output=$(nix build .#memory-tencentdb 2>&1 || true)

  local new_hash
  new_hash=$(echo "$output" | sed -n 's/.*got: *\(sha256-[A-Za-z0-9+/=]*\).*/\1/p' | head -1)

  if [[ -z "$new_hash" ]]; then
    log_error "Could not determine npmDepsHash. Build output:"
    echo "$output" | tail -20
    exit 1
  fi

  log_info "npmDepsHash: ${new_hash}"
  set_npm_deps_hash "$new_hash"
}

cleanup_backup_files() {
  rm -f package.nix.bak
}

update_flake_lock() {
  log_info "Updating flake.lock..."
  nix flake update
}

verify_build() {
  log_info "Verifying package build..."
  nix build .#memory-tencentdb >/dev/null
  # 本体が bin を公開しているかを確認する（露出が壊れていれば気づける）
  if [[ ! -d result/bin ]] || [[ -z "$(ls -A result/bin 2>/dev/null)" ]]; then
    log_error "Build produced no executables in result/bin"
    exit 1
  fi
  log_info "Build verification passed. Executables: $(ls result/bin | tr '\n' ' ')"
}

show_changes() {
  echo
  log_info "Changes made:"
  git diff --stat package.nix package.json package-lock.json flake.lock 2>/dev/null || true
}

update_to_version() {
  local new_version="$1"

  log_info "Updating to ${NPM_PACKAGE} ${new_version}"
  update_version_in_package_nix "$new_version"
  update_version_in_package_json "$new_version"
  regenerate_lock_file
  resolve_npm_deps_hash
  cleanup_backup_files
  update_flake_lock
  verify_build
}

print_usage() {
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "Options:"
  echo "  --version VERSION  Update to specific version"
  echo "  --check            Only check for updates"
  echo "  --help             Show this help"
  echo
  echo "Examples:"
  echo "  $0                     # Update to latest version"
  echo "  $0 --check             # Check if update is available"
  echo "  $0 --version 1.0.1     # Update to specific version"
}

parse_arguments() {
  local target_version=""
  local check_only="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        target_version="$2"
        shift 2
        ;;
      --check)
        check_only="true"
        shift
        ;;
      --help)
        print_usage
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        print_usage
        exit 1
        ;;
    esac
  done

  echo "${target_version}|${check_only}"
}

main() {
  ensure_in_repository_root
  ensure_required_tools_installed

  local args
  args=$(parse_arguments "$@")

  local target_version
  target_version=$(echo "$args" | cut -d'|' -f1)
  local check_only
  check_only=$(echo "$args" | cut -d'|' -f2)

  local current_version
  current_version=$(get_current_version)
  local latest_version
  latest_version=$(get_latest_version)

  if [[ -n "$target_version" ]]; then
    latest_version="$target_version"
  fi

  log_info "Current version: ${current_version}"
  log_info "Latest version:  ${latest_version}"

  if [[ "$current_version" == "$latest_version" ]]; then
    log_info "Already up to date."
    exit 0
  fi

  if [[ "$check_only" == "true" ]]; then
    log_warn "Update available: ${current_version} -> ${latest_version}"
    exit 1
  fi

  update_to_version "$latest_version"
  show_changes
  log_info "Successfully updated ${NPM_PACKAGE} from ${current_version} to ${latest_version}"
}

main "$@"

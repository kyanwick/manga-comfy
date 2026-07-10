#!/usr/bin/env bash
# Idempotent fetch primitives for bootstrap.sh.
#
# Sourceable: defines functions and counters, performs no work on import.
# DOWNLOADER and CLONER are injectable so tests can stub them.
#
#   DOWNLOADER <dest> <url>
#   CLONER     <url> <dest>

: "${WORKSPACE:=/workspace}"
: "${DOWNLOADER:=_curl_to}"
: "${CLONER:=_git_clone}"

FETCH_DOWNLOADS=0
FETCH_CLONES=0
FETCH_SKIPS=0

fetch_reset_counters() {
  FETCH_DOWNLOADS=0
  FETCH_CLONES=0
  FETCH_SKIPS=0
}

_curl_to() { curl -fsSL -o "$1" "$2"; }
_git_clone() { git clone --depth 1 "$1" "$2"; }

ensure_dirs() {
  local d
  for d in models/checkpoints models/loras models/vae custom_nodes output datasets prompts; do
    mkdir -p "$WORKSPACE/$d"
  done
}

# fetch_file <url> <dest>
# Skips when dest exists and is non-empty. A zero-byte file means a previous
# download died halfway; re-fetch it rather than trusting it.
fetch_file() {
  local url="$1" dest="$2"
  if [ -s "$dest" ]; then
    FETCH_SKIPS=$((FETCH_SKIPS + 1))
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  echo "  fetching $(basename "$dest") ..."
  "$DOWNLOADER" "$dest" "$url"
  FETCH_DOWNLOADS=$((FETCH_DOWNLOADS + 1))
}

# fetch_node <git_url> <dest_dir>
fetch_node() {
  local url="$1" dest="$2"
  if [ -d "$dest/.git" ]; then
    FETCH_SKIPS=$((FETCH_SKIPS + 1))
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  echo "  cloning $(basename "$dest") ..."
  "$CLONER" "$url" "$dest"
  FETCH_CLONES=$((FETCH_CLONES + 1))
}

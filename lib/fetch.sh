#!/usr/bin/env bash
# Idempotent fetch primitives for bootstrap.sh.
#
# Sourceable: defines functions and counters, performs no work on import.
# DOWNLOADER and CLONER are injectable so tests can stub them.
# Their command strings are word-split at invocation (may be multi-word, e.g.
# "bash /path/stub.sh"), so individual tokens must not contain spaces.
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
# Skips when dest exists and is non-empty. Downloads land in "$dest.part" and
# are renamed onto dest only on success, so a download that dies halfway leaves
# only a *.part file behind — dest never matches the -s guard until it is whole.
fetch_file() {
  local url="$1" dest="$2"
  if [ -s "$dest" ]; then
    FETCH_SKIPS=$((FETCH_SKIPS + 1))
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  echo "  fetching $(basename "$dest") ..."
  local tmp="$dest.part"
  # shellcheck disable=SC2086  # intentional word-split: may be a multi-word command
  $DOWNLOADER "$tmp" "$url" || return
  mv -- "$tmp" "$dest" || return
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
  # shellcheck disable=SC2086  # intentional word-split: may be a multi-word command
  $CLONER "$url" "$dest" || return
  FETCH_CLONES=$((FETCH_CLONES + 1))
}

#!/usr/bin/env bash
# Tests for lib/fetch.sh. No network: DOWNLOADER and CLONER are stubbed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILURES=0

assert_eq() {
  if [ "$1" != "$2" ]; then
    echo "FAIL: $3 (expected '$2', got '$1')" >&2
    FAILURES=$((FAILURES + 1))
  else
    echo "ok - $3"
  fi
}

assert_dir() {
  if [ -d "$1" ]; then
    echo "ok - $2"
  else
    echo "FAIL: $2 (missing dir $1)" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

# --- stubs -------------------------------------------------------------
# Signature must match real usage: DOWNLOADER <dest> <url>
stub_download() { mkdir -p "$(dirname "$1")"; echo "fake-weights" > "$1"; }
# Signature must match real usage: CLONER <url> <dest>
stub_clone() { mkdir -p "$2/.git"; }

setup() {
  WORKSPACE="$(mktemp -d)"
  export WORKSPACE
  DOWNLOADER=stub_download
  CLONER=stub_clone
  # shellcheck source=../lib/fetch.sh
  . "$SCRIPT_DIR/../lib/fetch.sh"
  fetch_reset_counters
}

teardown() { rm -rf "$WORKSPACE"; }

# --- tests -------------------------------------------------------------

test_ensure_dirs_creates_all() {
  setup
  ensure_dirs
  for d in models/checkpoints models/loras models/vae custom_nodes output datasets prompts; do
    assert_dir "$WORKSPACE/$d" "ensure_dirs creates $d"
  done
  teardown
}

test_fetch_file_downloads_when_missing() {
  setup
  fetch_file "https://example.invalid/x.safetensors" "$WORKSPACE/models/checkpoints/x.safetensors"
  assert_eq "$FETCH_DOWNLOADS" "1" "fetch_file downloads when missing"
  assert_eq "$FETCH_SKIPS" "0" "fetch_file does not skip when missing"
  teardown
}

test_fetch_file_skips_when_present() {
  setup
  fetch_file "https://example.invalid/x.safetensors" "$WORKSPACE/models/checkpoints/x.safetensors"
  fetch_reset_counters
  fetch_file "https://example.invalid/x.safetensors" "$WORKSPACE/models/checkpoints/x.safetensors"
  assert_eq "$FETCH_DOWNLOADS" "0" "fetch_file skips when file present"
  assert_eq "$FETCH_SKIPS" "1" "fetch_file counts a skip"
  teardown
}

test_fetch_file_redownloads_when_empty() {
  setup
  mkdir -p "$WORKSPACE/models/checkpoints"
  : > "$WORKSPACE/models/checkpoints/x.safetensors"   # zero-byte = failed download
  fetch_file "https://example.invalid/x.safetensors" "$WORKSPACE/models/checkpoints/x.safetensors"
  assert_eq "$FETCH_DOWNLOADS" "1" "fetch_file re-downloads a zero-byte file"
  teardown
}

test_fetch_node_clones_when_missing() {
  setup
  fetch_node "https://example.invalid/repo.git" "$WORKSPACE/custom_nodes/repo"
  assert_eq "$FETCH_CLONES" "1" "fetch_node clones when missing"
  assert_dir "$WORKSPACE/custom_nodes/repo/.git" "fetch_node creates .git"
  teardown
}

test_fetch_node_skips_when_cloned() {
  setup
  fetch_node "https://example.invalid/repo.git" "$WORKSPACE/custom_nodes/repo"
  fetch_reset_counters
  fetch_node "https://example.invalid/repo.git" "$WORKSPACE/custom_nodes/repo"
  assert_eq "$FETCH_CLONES" "0" "fetch_node skips when already cloned"
  assert_eq "$FETCH_SKIPS" "1" "fetch_node counts a skip"
  teardown
}

test_second_run_fetches_nothing() {
  # The design's structural promise, as a test.
  setup
  ensure_dirs
  fetch_file "https://example.invalid/ckpt" "$WORKSPACE/models/checkpoints/ckpt.safetensors"
  fetch_node "https://example.invalid/a.git" "$WORKSPACE/custom_nodes/a"
  fetch_node "https://example.invalid/b.git" "$WORKSPACE/custom_nodes/b"
  fetch_reset_counters

  ensure_dirs
  fetch_file "https://example.invalid/ckpt" "$WORKSPACE/models/checkpoints/ckpt.safetensors"
  fetch_node "https://example.invalid/a.git" "$WORKSPACE/custom_nodes/a"
  fetch_node "https://example.invalid/b.git" "$WORKSPACE/custom_nodes/b"

  assert_eq "$FETCH_DOWNLOADS" "0" "second run downloads nothing"
  assert_eq "$FETCH_CLONES" "0" "second run clones nothing"
  assert_eq "$FETCH_SKIPS" "3" "second run skips all three artifacts"
  teardown
}

test_ensure_dirs_creates_all
test_fetch_file_downloads_when_missing
test_fetch_file_skips_when_present
test_fetch_file_redownloads_when_empty
test_fetch_node_clones_when_missing
test_fetch_node_skips_when_cloned
test_second_run_fetches_nothing

if [ "$FAILURES" -ne 0 ]; then
  echo "$FAILURES test(s) failed" >&2
  exit 1
fi
echo "all tests passed"

#!/usr/bin/env bash
# Runs bootstrap.sh end-to-end against temp dirs with stubbed network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILURES=0

assert_contains() {
  case "$1" in
    *"$2"*) echo "ok - $3" ;;
    *) echo "FAIL: $3 (output lacked '$2')" >&2; FAILURES=$((FAILURES + 1)) ;;
  esac
}

assert_file() {
  if [ -f "$1" ]; then echo "ok - $2"
  else echo "FAIL: $2 (missing $1)" >&2; FAILURES=$((FAILURES + 1)); fi
}

WORKSPACE="$(mktemp -d)"
COMFY_DIR="$(mktemp -d)"
mkdir -p "$COMFY_DIR/custom_nodes"
export WORKSPACE COMFY_DIR
export SKIP_PIP=1

# Stubs exported into bootstrap's environment.
cat > "$WORKSPACE/stub_dl.sh" <<'STUB'
mkdir -p "$(dirname "$1")"; echo "fake" > "$1"
STUB
cat > "$WORKSPACE/stub_clone.sh" <<'STUB'
mkdir -p "$2/.git"
STUB
chmod +x "$WORKSPACE/stub_dl.sh" "$WORKSPACE/stub_clone.sh"
export DOWNLOADER="bash $WORKSPACE/stub_dl.sh"
export CLONER="bash $WORKSPACE/stub_clone.sh"

first="$(bash "$SCRIPT_DIR/../bootstrap.sh" 2>&1)"
assert_contains "$first" "downloads=1" "first run downloads the checkpoint"
assert_contains "$first" "clones=4" "first run clones four node packs"
assert_file "$COMFY_DIR/extra_model_paths.yaml" "bootstrap writes extra_model_paths.yaml"

second="$(bash "$SCRIPT_DIR/../bootstrap.sh" 2>&1)"
assert_contains "$second" "downloads=0" "second run downloads nothing"
assert_contains "$second" "clones=0" "second run clones nothing"
assert_contains "$second" "skips=5" "second run skips all five artifacts"

rm -rf "$WORKSPACE" "$COMFY_DIR"

if [ "$FAILURES" -ne 0 ]; then echo "$FAILURES test(s) failed" >&2; exit 1; fi
echo "all tests passed"

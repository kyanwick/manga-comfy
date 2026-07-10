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

assert_file_contains() {
  if [ -f "$1" ] && grep -q "$2" "$1"; then echo "ok - $3"
  else echo "FAIL: $3 ($1 lacked '$2')" >&2; FAILURES=$((FAILURES + 1)); fi
}

assert_file_lacks() {
  if [ -f "$1" ] && ! grep -q "$2" "$1"; then echo "ok - $3"
  else echo "FAIL: $3 ($1 still had '$2')" >&2; FAILURES=$((FAILURES + 1)); fi
}

WORKSPACE="$(mktemp -d)"
COMFY_DIR="$(mktemp -d)"
mkdir -p "$COMFY_DIR/custom_nodes"
touch "$COMFY_DIR/main.py"   # bootstrap sanity-checks this
# Simulate a stock template with a baked-in node pack — bootstrap must replace it, not nest into it.
mkdir -p "$COMFY_DIR/custom_nodes/ComfyUI-Manager/js"
export WORKSPACE COMFY_DIR
export SKIP_PIP=1

# Stubs exported into bootstrap's environment.
cat > "$WORKSPACE/stub_dl.sh" <<'STUB'
mkdir -p "$(dirname "$1")"; echo "fake" > "$1"
STUB
cat > "$WORKSPACE/stub_clone.sh" <<'STUB'
mkdir -p "$2/.git"
case "$2" in
  *ComfyUI-FluxTrainer)
    mkdir -p "$2/library"
    printf 'from transformers import CLIPFeatureExtractor, CLIPTextModel\n' > "$2/library/sdxl_lpw_stable_diffusion.py"
    printf 'x = CLIPFeatureExtractor()\n' >> "$2/library/sdxl_lpw_stable_diffusion.py"
    ;;
esac
STUB
chmod +x "$WORKSPACE/stub_dl.sh" "$WORKSPACE/stub_clone.sh"
export DOWNLOADER="bash $WORKSPACE/stub_dl.sh"
export CLONER="bash $WORKSPACE/stub_clone.sh"

first="$(bash "$SCRIPT_DIR/../bootstrap.sh" 2>&1)"
assert_contains "$first" "downloads=1" "first run downloads the checkpoint"
assert_contains "$first" "clones=4" "first run clones four node packs"
assert_file "$COMFY_DIR/extra_model_paths.yaml" "bootstrap writes extra_model_paths.yaml"

if [ -e "$COMFY_DIR/custom_nodes/ComfyUI-Manager/ComfyUI-Manager" ]; then
  echo "FAIL: symlink nested inside baked-in template dir instead of replacing it" >&2
  FAILURES=$((FAILURES + 1))
else
  echo "ok - baked-in template node dir replaced, not nested"
fi

FT_VENDORED="$WORKSPACE/custom_nodes/ComfyUI-FluxTrainer/library/sdxl_lpw_stable_diffusion.py"
assert_file_contains "$FT_VENDORED" "CLIPImageProcessor" "FluxTrainer vendored file patched to CLIPImageProcessor"
assert_file_lacks "$FT_VENDORED" "CLIPFeatureExtractor" "FluxTrainer vendored file no longer imports CLIPFeatureExtractor"

second="$(bash "$SCRIPT_DIR/../bootstrap.sh" 2>&1)"
assert_contains "$second" "downloads=0" "second run downloads nothing"
assert_contains "$second" "clones=0" "second run clones nothing"
assert_contains "$second" "skips=5" "second run skips all five artifacts"

# Idempotent: re-running must not double-mangle or fail. The patch finds no
# CLIPFeatureExtractor matches on run 2 and rewrites nothing.
assert_file_contains "$FT_VENDORED" "CLIPImageProcessor" "second run leaves CLIPImageProcessor in place"
assert_file_lacks "$FT_VENDORED" "CLIPFeatureExtractor" "second run does not reintroduce CLIPFeatureExtractor"

rm -rf "$WORKSPACE" "$COMFY_DIR"

if [ "$FAILURES" -ne 0 ]; then echo "$FAILURES test(s) failed" >&2; exit 1; fi
echo "all tests passed"

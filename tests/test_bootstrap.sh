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

# --- Civitai needs an API token; without one, LoRAs skip loudly, never fatally.
noTok="$(CIVITAI_TOKEN= bash "$SCRIPT_DIR/../bootstrap.sh" 2>&1)"; noTokRc=$?
assert_contains "$noTok" "SKIP anime_screencap" "no CIVITAI_TOKEN warns about the skipped LoRA"
assert_contains "$noTok" "downloads=4" "no CIVITAI_TOKEN still downloads the checkpoint and IPAdapter files"
if [ "$noTokRc" -eq 0 ]; then echo "ok - missing CIVITAI_TOKEN is not fatal"
else echo "FAIL: missing CIVITAI_TOKEN aborted bootstrap (rc=$noTokRc)" >&2; FAILURES=$((FAILURES + 1)); fi
if [ -e "$WORKSPACE/models/loras/anime_screencap-IllustriousV2.safetensors" ]; then
  echo "FAIL: LoRA present despite no token" >&2; FAILURES=$((FAILURES + 1))
else echo "ok - no LoRA fetched without a token"; fi
# Reset so the real first-run assertions below see a clean slate.
rm -rf "$WORKSPACE/models" "$WORKSPACE/custom_nodes"
rm -rf "$COMFY_DIR/custom_nodes"; mkdir -p "$COMFY_DIR/custom_nodes/ComfyUI-Manager/js"

export CIVITAI_TOKEN=test-token
first="$(bash "$SCRIPT_DIR/../bootstrap.sh" 2>&1)"
assert_contains "$first" "downloads=6" "first run downloads the checkpoint, two style LoRAs, and three IPAdapter files"
assert_contains "$first" "clones=4" "first run clones four node packs"
assert_file "$COMFY_DIR/extra_model_paths.yaml" "bootstrap writes extra_model_paths.yaml"

# IPAdapter FaceID weights land at their per-entry paths.
assert_file "$WORKSPACE/models/ipadapter/ip-adapter-faceid-plusv2_sdxl.bin" "IPAdapter FaceID model fetched to models/ipadapter"
assert_file "$WORKSPACE/models/loras/ip-adapter-faceid-plusv2_sdxl_lora.safetensors" "IPAdapter FaceID companion LoRA fetched to models/loras"
assert_file "$WORKSPACE/models/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors" "CLIP vision encoder fetched to models/clip_vision"
assert_file_contains "$COMFY_DIR/extra_model_paths.yaml" "ipadapter:" "extra_model_paths.yaml maps ipadapter"
assert_file_contains "$COMFY_DIR/extra_model_paths.yaml" "clip_vision:" "extra_model_paths.yaml maps clip_vision"
assert_file_contains "$COMFY_DIR/extra_model_paths.yaml" "insightface:" "extra_model_paths.yaml maps insightface"

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
assert_contains "$second" "skips=10" "second run skips all ten artifacts"

# Idempotent: re-running must not double-mangle or fail. The patch finds no
# CLIPFeatureExtractor matches on run 2 and rewrites nothing.
assert_file_contains "$FT_VENDORED" "CLIPImageProcessor" "second run leaves CLIPImageProcessor in place"
assert_file_lacks "$FT_VENDORED" "CLIPFeatureExtractor" "second run does not reintroduce CLIPFeatureExtractor"

rm -rf "$WORKSPACE" "$COMFY_DIR"

if [ "$FAILURES" -ne 0 ]; then echo "$FAILURES test(s) failed" >&2; exit 1; fi
echo "all tests passed"

#!/usr/bin/env bash
# Reconstructs a manga-comfy pod from the stock RunPod ComfyUI template.
# Idempotent: safe to run on every pod start. Second run fetches nothing.
#
#   WORKSPACE       network volume mount     (default /workspace)
#   COMFY_DIR       ComfyUI install location (default /ComfyUI)
#   SKIP_PIP=1      skip node requirements   (tests)
#   CIVITAI_TOKEN   API token for Civitai downloads (401 without it).
#                   Create at https://civitai.com/user/account
#                   Absent -> style LoRAs are skipped with a warning, not fatal.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/fetch.sh
. "$SCRIPT_DIR/lib/fetch.sh"

COMFY_DIR="${COMFY_DIR:-/ComfyUI}"
[ -e "$COMFY_DIR/main.py" ] || {
  echo "COMFY_DIR=$COMFY_DIR does not look like a ComfyUI install (no main.py)" >&2
  exit 1
}

CHECKPOINT_NAME="Illustrious-XL-v2.0.safetensors"
CHECKPOINT_URL="https://huggingface.co/OnomaAIResearch/Illustrious-XL-v2.0/resolve/main/${CHECKPOINT_NAME}"

NODES="
https://github.com/ltdrdata/ComfyUI-Manager.git|ComfyUI-Manager
https://github.com/ltdrdata/ComfyUI-Inspire-Pack.git|ComfyUI-Inspire-Pack
https://github.com/pythongosssss/ComfyUI-WD14-Tagger.git|ComfyUI-WD14-Tagger
https://github.com/kijai/ComfyUI-FluxTrainer.git|ComfyUI-FluxTrainer
"

# Style LoRAs. url|filename
#
# LICENSE DISCIPLINE — read before adding a line here.
# Every LoRA must (a) declare allowCommercialUse including "Image" on Civitai,
# and (b) have NO NoobAI in its lineage. NoobAI's licence forbids commercial use
# of *model-generated products*, which would poison every Oberas frame shipped.
# Check the FILENAME, not just the version label: this same LoRA's newest build
# is `anime_screencap-IL-NOOB_v3.safetensors` — contaminated. The v2.0 build
# below matches our base checkpoint and is clean.
#
#   Fine Anime Screencap XL, Illustrious v2.0 build (civitai model 345962)
#   allowCommercialUse: {Image,RentCivit,Rent} — verified 2026-07-09
LORAS="
https://civitai.com/api/download/models/1932613|anime_screencap-IllustriousV2.safetensors
"

write_extra_model_paths() {
  # Non-destructive: points ComfyUI at the volume without touching its own
  # models/ directory. Overwriting this file is safe — bootstrap owns it.
  cat > "$COMFY_DIR/extra_model_paths.yaml" <<EOF
manga_comfy:
  base_path: ${WORKSPACE}/
  checkpoints: models/checkpoints
  loras: models/loras
  vae: models/vae
EOF
}

link_custom_nodes() {
  local dir name target
  for dir in "$WORKSPACE"/custom_nodes/*/; do
    [ -d "$dir" ] || continue
    name="$(basename "$dir")"
    target="$COMFY_DIR/custom_nodes/$name"
    if [ -d "$target" ] && [ ! -L "$target" ]; then
      rm -rf -- "$target"   # template's baked-in copy; the volume clone is canonical
    fi
    ln -sfT "${dir%/}" "$target"
  done
}

patch_fluxtrainer() {
  # FluxTrainer vendors an old kohya sd-scripts that imports CLIPFeatureExtractor,
  # removed in transformers v5. CLIPImageProcessor is the drop-in successor and
  # exists in transformers 4.2x+, so this rewrite is safe on either version.
  # Upstream fix: kohya-ss/sd-scripts PR #2315. Idempotent: a second run finds
  # no matches and rewrites nothing.
  local ft="$WORKSPACE/custom_nodes/ComfyUI-FluxTrainer" f
  [ -d "$ft" ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    sed -i 's/CLIPFeatureExtractor/CLIPImageProcessor/g' "$f"
    echo "  patched $(basename "$f")"
  done < <(grep -rl --include='*.py' 'CLIPFeatureExtractor' "$ft" 2>/dev/null || true)
}

install_node_requirements() {
  [ "${SKIP_PIP:-0}" = "1" ] && return 0
  local req
  for req in "$WORKSPACE"/custom_nodes/*/requirements.txt; do
    [ -f "$req" ] || continue
    echo "  pip install -r $req"
    pip install --quiet -r "$req"
  done
}

main() {
  echo "==> bootstrap: workspace=$WORKSPACE comfy=$COMFY_DIR"
  ensure_dirs
  fetch_file "$CHECKPOINT_URL" "$WORKSPACE/models/checkpoints/$CHECKPOINT_NAME"

  local line url name
  while read -r line; do
    [ -n "$line" ] || continue
    url="${line%%|*}"
    name="${line##*|}"
    fetch_node "$url" "$WORKSPACE/custom_nodes/$name"
  done <<< "$NODES"

  local dest
  while read -r line; do
    [ -n "$line" ] || continue
    url="${line%%|*}"
    name="${line##*|}"
    dest="$WORKSPACE/models/loras/$name"
    # Civitai returns 401 for unauthenticated downloads. A missing token is not
    # fatal — the pod generates fine on the base checkpoint — but never silent.
    if [ ! -s "$dest" ] && [ -z "${CIVITAI_TOKEN:-}" ]; then
      case "$url" in *civitai.com*)
        echo "  SKIP $name — set CIVITAI_TOKEN to fetch style LoRAs (civitai.com/user/account)" >&2
        continue ;;
      esac
    fi
    case "$url" in *civitai.com*) url="${url}?token=${CIVITAI_TOKEN:-}" ;; esac
    fetch_file "$url" "$dest"
  done <<< "$LORAS"

  write_extra_model_paths
  link_custom_nodes
  patch_fluxtrainer
  install_node_requirements

  echo "==> downloads=$FETCH_DOWNLOADS clones=$FETCH_CLONES skips=$FETCH_SKIPS"
}

main "$@"

#!/usr/bin/env bash
# Reconstructs a manga-comfy pod from the stock RunPod ComfyUI template.
# Idempotent: safe to run on every pod start. Second run fetches nothing.
#
#   WORKSPACE   network volume mount     (default /workspace)
#   COMFY_DIR   ComfyUI install location (default /ComfyUI)
#   SKIP_PIP=1  skip node requirements   (tests)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/fetch.sh
. "$SCRIPT_DIR/lib/fetch.sh"

COMFY_DIR="${COMFY_DIR:-/ComfyUI}"

CHECKPOINT_NAME="Illustrious-XL-v2.0.safetensors"
CHECKPOINT_URL="https://huggingface.co/OnomaAIResearch/Illustrious-XL-v2.0/resolve/main/${CHECKPOINT_NAME}"

NODES="
https://github.com/ltdrdata/ComfyUI-Manager.git|ComfyUI-Manager
https://github.com/ltdrdata/ComfyUI-Inspire-Pack.git|ComfyUI-Inspire-Pack
https://github.com/pythongosssss/ComfyUI-WD14-Tagger.git|ComfyUI-WD14-Tagger
https://github.com/kijai/ComfyUI-FluxTrainer.git|ComfyUI-FluxTrainer
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
  local dir name
  for dir in "$WORKSPACE"/custom_nodes/*/; do
    [ -d "$dir" ] || continue
    name="$(basename "$dir")"
    ln -sfn "${dir%/}" "$COMFY_DIR/custom_nodes/$name"
  done
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

  write_extra_model_paths
  link_custom_nodes
  install_node_requirements

  echo "==> downloads=$FETCH_DOWNLOADS clones=$FETCH_CLONES skips=$FETCH_SKIPS"
}

main "$@"

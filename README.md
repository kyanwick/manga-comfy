# manga-comfy

Personal RunPod ComfyUI pod for DeenWell manga and Oberas Co. panels.
Illustrious-XL v2.0. Character and setting LoRAs trained on-pod.

Design: `docs/superpowers/specs/2026-07-09-runpod-comfyui-manga-pod-design.md`

## Nothing here runs locally

Your PC holds this repo — scripts and JSON, under 1MB. The 7GB model, the LoRAs,
the datasets, and every generated image live on the RunPod network volume.
Download keepers to `F:`, never `C:`.

## Working session

1. **Pods → Deploy** in the volume's region. 24GB card (RTX 4090 / A5000),
   official ComfyUI template, network volume `manga-comfy` at `/workspace`,
   expose port `8188`.
2. In the pod terminal:
   ```bash
   source /workspace/venv/bin/activate
   export CIVITAI_TOKEN=<your-token>   # civitai.com/user/account
   cd /workspace/repo && git pull && COMFY_DIR=/workspace/ComfyUI bash bootstrap.sh
   ```
   Run it with the venv active: the official template runs ComfyUI from
   `/workspace/venv`, so node `pip install`s must land there. ComfyUI lives at
   `/workspace/ComfyUI` on that template (not `/ComfyUI`), hence `COMFY_DIR`.
   First ever run: `downloads=4 clones=4` (~7GB, several minutes).
   Every run after: `downloads=0 clones=0 skips=8` in seconds.
   Restart ComfyUI afterwards so `extra_model_paths.yaml` and any new nodes load.
3. Open `https://<pod-id>-8188.proxy.runpod.net`
4. Load `workflows/manga_txt2img.json`
5. **Terminate the pod when done.** Not "Stop" — terminate. The volume keeps
   everything; the GPU is what costs money.

## Two modes, one workflow

| | LoRA loaders | Latent |
|---|---|---|
| Oberas | bypassed (`Ctrl+B`) | 1536×1024 |
| DeenWell manga | enabled, char 0.7 / setting 0.55 | 1536×1024 |
| DeenWell cover | enabled | 1024×1536 |

## Batch a chapter

Put prompts in `/workspace/prompts/<name>.txt` (see `prompts/example_chapter.txt`),
point `Load Prompts From File (Inspire)` at it, set `KSampler` seed to
`increment`, queue once.

`batch_size` on the latent is **not** this. It runs one prompt N times and scales
VRAM ×N.

## Identity

For a consistent face across panels, feed a reference photo into
`IPAdapterUnifiedLoaderFaceID` (preset `FACEID PLUS V2`, provider `CUDA`) →
`IPAdapterFaceID` → `KSampler`. InsightFace downloads its `buffalo_l` face pack
into `models/insightface` on first run. See the non-commercial caveat below.

## Costs

| | |
|---|---|
| Network volume, 100GB | ~$7/month, always |
| 24GB pod | ~$0.30–0.70/hour, only while running |

The 24GB card exists for LoRA **training**. Inference doesn't need it.

## Gotchas

- **Text doesn't render.** The model cannot write legible words. Panels are
  plates; Arabic calligraphy and speech bubbles are composited in Remotion.
- **Unload models before training** or you will OOM.
- **The volume is region-locked.** Pods must launch in its region.
- **Illustrious v2.0 is the ceiling.** v3.0/v3.5 are Stardust-gated, and v3.5 is
  v-pred — not a drop-in swap. LoRAs trained here are eps LoRAs.
- **FluxTrainer vs transformers v5.** The pod's venv ships transformers v5, which
  removed `CLIPFeatureExtractor`; FluxTrainer vendors an old sd-scripts that
  imports it. `bootstrap.sh` rewrites it to `CLIPImageProcessor` (upstream fix:
  kohya-ss/sd-scripts PR #2315). Without that, its SDXL training nodes silently
  fail to register.
- **Civitai needs a token.** Downloads 401 without `CIVITAI_TOKEN`. Absent, style
  LoRAs are skipped with a warning and the pod still works on the base checkpoint.
- **IPAdapter FaceID is non-commercial.** It requires InsightFace's `buffalo_l`
  face pack, licensed for non-commercial research only, and generated images
  inherit that restriction. Deliberate choice for Oberas; do not use these frames
  in anything monetised. The clean identity route is a character LoRA trained on
  your own photos.
- **Never commit weights.** `.gitignore` blocks `*.safetensors`.
- **LoRA licence discipline.** Anything added to `LORAS` in `bootstrap.sh` must declare
  `allowCommercialUse: Image` on Civitai AND have no NoobAI in its lineage — NoobAI
  forbids commercial use of *model-generated products*. Check the **filename**: the
  same LoRA often ships a `-NOOB` build alongside a clean one.
- **Private repo.** Pod-side `git clone`/`pull` wants a fine-grained PAT
  (contents: read) for `kyanwick/manga-comfy`.

## Tests

```bash
bash tests/test_fetch.sh
bash tests/test_bootstrap.sh
```

Both stub the network. They prove the one thing that matters: a second
`bootstrap.sh` run fetches nothing.

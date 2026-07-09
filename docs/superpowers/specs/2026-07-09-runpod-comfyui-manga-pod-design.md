# RunPod ComfyUI pod for DeenWell / Oberas manga generation

**Date:** 2026-07-09
**Status:** Approved design, not yet implemented

## Problem

DeenWell and Oberas Co. visual assets are currently produced by pasting
Midjourney prompts by hand, one at a time. The `deenwell-image-prompter` and
`oberas-image-prompter-v2` skills emit prompts; nothing consumes them. There is
no reproducible way to generate a chapter's worth of panels, and no way to keep a
character looking like themselves from panel 1 to panel 40.

## Goal

A hosted ComfyUI on RunPod, reachable in a browser, with the models and nodes
needed to generate anime/manga-comic panels for both brands. Explicitly **not** a
platform, batch API, or automation layer — that comes later, if at all.

## Non-goals

- Batch prompt ingestion from the prompter skills (later)
- Video / motion generation (later)
- Integration with `oberas-reels` Remotion assembly (later)
- Any dependency on ALETHIA work repos (`clipping-comfy-worker`, `clipping-pipeline-*`)

## Architecture

Two RunPod objects, split by lifetime. The pod holds nothing durable.

```
┌─ Network volume  (persistent, region-locked, survives pod termination) ─┐
│  /workspace/models/checkpoints/   Illustrious-XL-v2.0                   │
│  /workspace/models/loras/         character + setting LoRAs             │
│  /workspace/models/vae/                                                 │
│  /workspace/custom_nodes/         ComfyUI-Manager, safety checker       │
│  /workspace/output/               generated plates                      │
│  /workspace/datasets/             LoRA training images                  │
│  /workspace/bootstrap.sh                                                │
└─────────────────────────────────────────────────────────────────────────┘
                          ▲ mounted at /workspace
┌─ On-demand GPU pod  (disposable, 24GB, terminated when idle) ───────────┐
│  RunPod official ComfyUI template                                       │
│  ComfyUI  :8188  →  https://<pod-id>-8188.proxy.runpod.net              │
│  kohya_ss / ai-toolkit  (LoRA training, invoked via shell)              │
└─────────────────────────────────────────────────────────────────────────┘
```

Terminate the pod when not working; pay only volume storage. Next session: new
pod, same volume, run `bootstrap.sh`, back to work.

### Why a bootstrap script rather than a baked image

`bootstrap.sh` lives on the volume, is idempotent (checks for each artifact,
downloads only what's missing), and is version-controlled in this repo. First run
pulls ~7GB; subsequent runs are near-instant.

Rejected alternatives:

- **Baked Docker image** — fastest cold start, but every model change means
  rebuilding and pushing a multi-GB image. Rejected: maintaining a Dockerfile was
  explicitly out of scope.
- **Manual ComfyUI-Manager clicks, snapshot the volume** — fastest to first
  image, but unreproducible. When the volume dies, the knowledge dies.

## Model

**`OnomaAIResearch/Illustrious-XL-v2.0`**, single checkpoint (~7GB), serving both
brands. One anime/manga-comic style across DeenWell and Oberas.

Chosen over v0.1 / v1.0 after reading [arXiv:2409.19946](https://arxiv.org/abs/2409.19946):

| Version | Native res | Prompt format | License |
|---|---|---|---|
| v0.1 | 1024² | tags-centric | FAIPL 1.0-SD (share-alike) |
| v1.0 / v1.1 | 1536² | tags-centric | contested |
| **v2.0** | **1536² + 0.15MP aug** | **multi-level captions** | **OpenRAIL-M** |

v2.0 is the only version that is simultaneously high-resolution, natural-language
capable, and cleanly licensed for commercial use.

Rejected: **NoobAI-XL**, whose license §II states "We prohibit any form of
commercialization, including but not limited to monetization or commercial use of
the model, derivative models, **or model-generated products**." That last clause
covers the images. The argument that this is unenforceable (NoobAI derives from
Illustrious under FAIPL share-alike and cannot add restrictions) may well be
correct, but is not a foundation to build a brand's asset library on.

Rejected: **FLUX.1/2 [dev]** — non-commercial, paid BFL license required, and the
restriction is viral through any LoRA trained on it.

**Open item:** the v2.0 license tag on the HF model card reads
`creativeml-openrail-m`. The full `LICENSE` file has not been read. Do this before
generating anything shipped.

### Generation parameters

- **1536×1024** — native 3:2 at the model's trained resolution, which is the ratio
  the prompter skills already target for the 9:16 pan.
- v2.0's 0.15MP augmentation means smaller draft sizes degrade gracefully.

### Prompt scaffold

The paper specifies a load-bearing tag order: person count, character names,
rating, general tags, artist, score range, year modifier. `rating` and
`score range` are the primary safety and quality levers.

Scaffold lives in this repo as a template. Tag block first, natural-language body
after — v2.0's multi-level caption training accepts both, so existing
natural-language prompts from the prompter skills do **not** need rewriting into
pure tags.

### Safety

Non-negotiable, not a nicety. The paper's **No-Dropout Tokens** guarantee "100%
accuracy recognition" for character names, artist names, and provocative content —
never dropped during training, suppressed only at inference via CFG or token
exclusion. On a Danbooru-derived base, NSFW concepts are reliably *activated*, not
incidentally present.

DeenWell is Islamic educational content, plausibly reaching minors. Required:

- Pinned negative-prompt scaffold, checked into this repo
- Safety-checker node in the workflow
- `rating` tag pinned in every generation

## Consistency

ComfyUI is stateless. Same seed + changed prompt = a different person. A 40-panel
chapter generated naively yields 40 different-looking people. Identity is
engineered, not remembered.

DeenWell manga needs **character lock and setting lock**. Oberas largely does not.
DeenWell therefore drives the infrastructure.

### Mechanisms

| Mechanism | Controls | Zero-shot | Cost per image in batch |
|---|---|---|---|
| Danbooru character tags | identity | yes | free |
| IPAdapter (FaceID / PlusV2) | face, loosely | yes | image encoder runs every image |
| **Character LoRA** | identity, body, outfit | no | **free, loaded once** |
| ControlNet (pose/depth/lineart) | composition, *not* identity | yes | per-image, cheap |

Character tags are useless here: No-Dropout Tokens give perfect recall for names
**in the Danbooru dataset**. Original DeenWell characters have zero presence.

IPAdapter is rejected for batch work: it re-encodes the reference on every
generation, so VRAM and latency scale with panel count, and its influence drifts
as prompt weight shifts — panel 3 and panel 30 diverge.

**Character LoRA** is the batch answer. Loads once, costs nothing per sample.

### LoRA training

- 20–40 images per character
- 1500–3000 steps; convergence around 3000 on Illustrious
- Save every 5 epochs, compare 5/10/15/20, pick the sweet spot
- Mixed-source images prevent style lock-in (too few images from one source and
  the LoRA memorizes pose and style rather than the character)

**Dataset bootstrap.** Training needs 20–40 consistent images of a character that
doesn't exist yet. The escape is the existing `banana-pro-director` skill: locked
single-image base reference on white seamless → 6-panel multi-angle character
sheet → curate and augment to 20–40 → train. Six panels is a seed set, not a
finished dataset.

### Setting lock

A setting must survive *changing camera angles*. A LoRA learns appearance, not
geometry — it yields "a mosque that feels like the mosque," not the same mosque
from a new angle with pillars in the right place.

| Approach | Locks | Cost |
|---|---|---|
| Setting LoRA + fixed tag | mood, palette, motifs | 1 training run per location |
| Establishing plate → img2img | appearance, if angle barely moves | cheap, brittle |
| ControlNet depth/lineart from greybox | actual geometry, any angle | Blender blockout per location |
| Per-chapter combined LoRA | both, one chapter | dataset per chapter — circular |

### Chosen escalation path

Do not build for the hard case before feeling it.

1. **Character LoRA + setting LoRA, stacked.** Generate one full DeenWell chapter.
   Look at it.
2. If the setting swims between panels — likely on wide shots — add ControlNet
   depth with a Blender greybox, **for that one location only**.
3. Blender enters the pipeline only if step 2 proves necessary.

**Known failure mode:** stacked LoRAs interfere. Identity bleeds into
architecture; palettes collapse toward whichever trained harder. Mitigate with
weights ~0.7 character / ~0.5–0.6 setting. Degrades badly past two or three LoRAs.
A chapter with two characters in one recurring location is the stress case.

## Consequences of the consistency requirement

LoRA training is **not** ComfyUI — it is `kohya_ss` / `ai-toolkit` / OneTrainer:
different dependencies, 16–24GB VRAM, 30–90 min per character on a 4090.

Therefore:

- The pod needs a **second service** in `bootstrap.sh`
- The pod needs a **24GB card**, not a cheap 16GB one
- "Just a hosted ComfyUI" is no longer strictly accurate, and DeenWell is why

## Known constraints

**Text rendering fails.** The paper, verbatim: "generating full sentences or
meaningful words within anime images remain a significant challenge." Arabic
calligraphy, ayah text, and speech bubbles will not come out of the model. The
model produces **plates**; text is composited downstream in Remotion / ffmpeg.

**CLIP instability is architectural.** The authors name it: "CLIP text encoder's
instability in handling character details," noting Flux and Kolors avoid this with
T5 or GLM. SDXL's dual CLIP truncates at 77 tokens per chunk. Long cinematic
prompts hit the encoder ceiling regardless of v2.0's natural-language training.
Not fixable by prompting.

**Sparse concepts degrade.** The paper's own example: "covering wound with left
hand." Islamic historical staging — a specific gesture, a period-correct garment,
a named companion — is sparse on a Danbooru-derived dataset. Expect resistance.

**Aniconism.** Prophets and Imams cannot be depicted, or cannot be shown facially.
Anime models are trained overwhelmingly on character-centric composition and fight
faceless framing. If negative prompting proves insufficient, ControlNet is the
lever — same escalation as setting lock.

**Network volumes are region-locked.** The volume pins the pod to one datacenter.
If that region has no 24GB cards free, you wait or pay for a bigger one. Pick a
region with deep GPU supply, not the cheapest. This is the real cost of the
on-demand model and it bites at the worst moment.

**Proxy request timeouts** (~100–160s, per the ALETHIA worker's README).
Interactive ComfyUI is websocket-driven and unaffected. Any future HTTP-driven
batch layer will need an async submit/poll pattern.

## Repo layout

`C:\localhost\manga-comfy` — personal, deliberately outside `C:\ALETHIA\Repos`.

```
bootstrap.sh              idempotent model + node + trainer fetch
workflows/
  manga_txt2img.json      the one workflow
prompts/
  scaffold.md             tag order + pinned negative prompt
docs/superpowers/specs/   this document
README.md                 pod create → attach volume → bootstrap → open :8188
```

## Verification

Done means:

1. Pod up, `bootstrap.sh` run **twice** — second run downloads nothing
2. ComfyUI reachable at the proxy URL
3. One image generated from `manga_txt2img.json`, judged by eye against a
   Midjourney reference
4. Pod terminated, **fresh pod brought up**, and it reaches a generated image with
   no manual steps

If step 4 needs manual intervention, the bootstrap is lying and the design has
failed its one structural promise.

Consistency is verified separately, and only by looking: one full DeenWell chapter
with stacked character + setting LoRAs, read as a sequence. Drift is a judgment
call, not a metric.

## Cost

Approximate; verify at purchase, RunPod pricing moves.

- Network volume: ~$0.07/GB/month
- On-demand 24GB (RTX 4090 / A5000): ~$0.30–0.70/hr, paid only while working
- LoRA training: 30–90 min per character

## Open questions

- Read the actual `LICENSE` file on `OnomaAIResearch/Illustrious-XL-v2.0` before
  shipping generated assets
- Which RunPod region has reliable 24GB availability
- `kohya_ss` vs `ai-toolkit` — not yet evaluated
- How many recurring DeenWell characters and settings exist (drives LoRA count,
  and the two-to-three-LoRA interference ceiling)

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
needed to **generate** anime/manga-comic panels for both brands and to **train**
the character and setting LoRAs that keep them consistent — both in the same
interface.

A chapter's worth of prompts can be queued from a text file. Explicitly **not** an
API, service, or automation layer wrapping any of it — that comes later, if at
all.

## Non-goals

- **Programmatic** batch — skills write prompts, something POSTs `/prompt`, polls,
  pulls from S3. That is the platform. (File-driven batch *is* in scope; see
  "Batch generation" below.)
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
│  /workspace/custom_nodes/         Manager, Inspire, WD14, FluxTrainer   │
│  /workspace/output/               generated plates                      │
│  /workspace/datasets/             LoRA training images                  │
│  /workspace/prompts/              one .txt per chapter / episode        │
│  /workspace/bootstrap.sh                                                │
└─────────────────────────────────────────────────────────────────────────┘
                          ▲ mounted at /workspace
┌─ On-demand GPU pod  (disposable, 24GB, terminated when idle) ───────────┐
│  RunPod official ComfyUI template                                       │
│  ComfyUI  :8188  →  https://<pod-id>-8188.proxy.runpod.net              │
│    · generation AND LoRA training, same UI, same node graph             │
└─────────────────────────────────────────────────────────────────────────┘
```

One service, one port. Training is a workflow, not a second program.

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

**v2.0 is also the ceiling.** Onoma's site advertises v3.0 EPS, v3.0 VPred, v3.5
VPred, and Illustrious LU — but the `OnomaAIResearch` HuggingFace org publishes
only early-release-v0, v1.0, v1.1, v2.0, and Lumina-v0.03. Everything above v2.0
is behind Onoma's **"Stardust"** sponsorship gate: weights open once a
crowdfunding threshold is met, and the threshold rises for 3.5vpred and later.
Those versions are usable *on their platform*, not downloadable.

Two consequences:

- Choosing v2.0 is not a compromise. It is the newest openly-available version.
- If v3.5 ever opens, it is **not a drop-in swap**. It is v-prediction, not
  epsilon: different sampler/scheduler config in ComfyUI, and eps-trained LoRAs
  do not transfer cleanly. Any LoRA trained under this design is an eps LoRA.

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

## Batch generation

In scope, because it costs one custom node.

ComfyUI's `batch_size` (on Empty Latent) runs N latents through **one** forward
pass with the **same** prompt — VRAM scales ×N, realistically capping around 4 at
1536×1024 on 24GB. Useless for a chapter.

What a chapter needs is N sequential runs with N *different* prompts. ComfyUI core
cannot do this; the native queue re-runs the same workflow. Inspire Pack's own
docs state it plainly: *"You cannot apply a separate prompt to each batch using
the batch parameter; if you want to apply different prompts, you need to use the
list method."*

**`Load Prompts From File (Inspire)`** reads a `.txt` of positive/negative prompts
separated by dashed lines and emits a `ZIPPED_PROMPT` list. Paste a prompter
skill's output into `/workspace/prompts/deenwell_ch03.txt`, queue once, walk away.

Two details that bite otherwise:

- **Seed must be `increment`, not `fixed`** — or 40 different prompts share one
  noise seed and produce suspiciously similar compositions.
- **`SaveImage` `filename_prefix`** like `oberas/ep12/panel_` — the prompt file's
  line order is the panel order. Nothing else preserves it.

### One workflow, two modes

Oberas is DeenWell minus the LoRA loaders. Bypass them (`Ctrl+B`; `mode: 4` in
saved JSON) rather than maintaining a second workflow that drifts.

```
Load Prompts From File ──┐
                         ├─→ CLIP Encode ─→ KSampler ─→ Save Image
Checkpoint (Illustrious) ─┤                    ↑
LoraLoader (character) ───┤  ← bypass for Oberas
LoraLoader (setting)   ───┘  ← bypass for Oberas
Empty Latent ─────────────────────────────────┘
   1536×1024  Oberas (3:2, pans to 9:16)
   1024×1536  DeenWell covers (9:16)
   1216×1216  DeenWell square
```

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

Runs **inside ComfyUI**, not as a second service.

[`kijai/ComfyUI-FluxTrainer`](https://github.com/kijai/ComfyUI-FluxTrainer) wraps
kohya's `sd-scripts` as ComfyUI nodes and — despite the name — ships dedicated
**SDXL** training nodes (widely used for PonyXL; Illustrious is the same family).
Captioning uses a **WD14 Tagger** node. The whole loop lives in one interface:

```
WD14 Tagger  →  FluxTrainer SDXL nodes  →  /workspace/models/loras/  →  LoraLoader
 (auto-tag)         (train)                    (LoRA lands here)        (generate)
```

The trained `.safetensors` writes straight into the folder ComfyUI already reads.
Training becomes another workflow JSON beside `manga_txt2img.json`.

Parameters:

- 20–40 images per character
- 1500–3000 steps; convergence around 3000 on Illustrious
- Save every 5 epochs, compare 5/10/15/20, pick the sweet spot
- Mixed-source images prevent style lock-in (too few images from one source and
  the LoRA memorizes pose and style rather than the character)

**Known costs.** FluxTrainer is a wrapper and SDXL is its secondary target;
node-graph training is fiddlier than a GUI when iterating on hyperparameters. Fine
for a handful of characters, poor for tuning twenty. ComfyUI must free the
checkpoint from VRAM before a training run — expect to unload or restart between
generating and training.

**Fallback, not a rewrite:** the community RunPod template *"Stable Diffusion
Kohya_ss ComfyUI Ultimate"* ships kohya_ss on `:3010` and ComfyUI on `:3020`. If
node-based training frustrates within the first hour, switch. It also drags along
A1111 and someone else's unversioned template, which is the unreproducibility
`bootstrap.sh` exists to avoid.

### Rejected: hosted training

**ILXL's own LoRA trainer** (announced 2025-12-11) trains a character for you and
never lets go of it. Its eight-step tutorial runs upload → auto-tag → train →
preview → thumbnail → *use it in ILXL generation*. There is no export step, and
the docs state "the LoRA model is only applied when you select it through Add
LoRA." Reinforced by the credit design: **Stellar** (the LoRA-training credit)
converts only from **Purchased** Stardust, never free Stardust. It is a closed
loop that monetizes generation on their platform. A LoRA that cannot leave their
web UI cannot reach ComfyUI.

Also noted: their step ceiling is 100–2,000, below the ~3,000 where Illustrious
character LoRAs converge locally.

**Civitai's on-site trainer** does export `.safetensors` and is a technically
valid path. Rejected on non-technical grounds: it means uploading DeenWell
character sheets — Prophetic-era companions, Islamic historical figures — to a
platform whose Illustrious ecosystem is overwhelmingly NSFW. Training on our own
pod is the only option where the dataset never leaves infrastructure we rent
directly. This is a values call, and it is deliberate.

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

Training is 30–90 min per character on a 4090 and wants 16–24GB VRAM.

- The pod needs a **24GB card**, not a cheap 16GB one. **Inference does not need
  this — training does.** With 8-bit Adam and gradient checkpointing SDXL LoRA
  fits in 12–16GB, but you fight for it. If character consistency is ever
  abandoned, the card gets cheaper the same day.
- `bootstrap.sh` installs custom node packs rather than a second service: Inspire
  Pack (batch prompts), WD14 Tagger (captions), FluxTrainer (training) — plus
  ComfyUI-Manager if the base template lacks it.
- DeenWell is why. Oberas alone would run on 16GB with no trainer at all.

### Local machine footprint

Deliberately near-zero. C: has ~50GB free and must stay that way.

| Lives where | What |
|---|---|
| RunPod volume | 7GB checkpoint, LoRAs, custom nodes, datasets, all output |
| RunPod pod | ComfyUI, Python, CUDA, the GPU |
| **Local C:** | **this repo — scripts, JSON, markdown. Under 1MB.** |
| Local F: | downloaded keepers only (~120MB per 40-panel chapter) |

No local ComfyUI, no local model, no local Python env, no local training. Leave
output on the volume; sync down selects only, to F:.

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
bootstrap.sh              idempotent fetch: checkpoint + 3 custom nodes
workflows/
  manga_txt2img.json      generation; LoRA branch bypassable for Oberas
  lora_train.json         WD14 tag → FluxTrainer SDXL
prompts/
  scaffold.md             tag order + pinned negative prompt
  example_chapter.txt     Load-Prompts-From-File format reference
docs/superpowers/specs/   this document
README.md                 pod create → attach volume → bootstrap → open :8188
```

Custom nodes installed by `bootstrap.sh`:

| Node pack | Purpose |
|---|---|
| ComfyUI-Manager | node management |
| ComfyUI-Inspire-Pack | `Load Prompts From File` — batch |
| ComfyUI-WD14-Tagger | auto-captioning training datasets |
| ComfyUI-FluxTrainer | SDXL LoRA training nodes |

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

- ~~Read the actual `LICENSE` file on `OnomaAIResearch/Illustrious-XL-v2.0`~~
  **Resolved 2026-07-09:** Kyan read the license text directly. Verdict: fine —
  commercial use of generated outputs permitted, no share-alike obligation on
  trained LoRAs beyond stock CreativeML OpenRAIL-M use-restrictions. Model
  choice stands.
- Which RunPod region has reliable 24GB availability
- How many recurring DeenWell characters and settings exist (drives LoRA count,
  and the two-to-three-LoRA interference ceiling)

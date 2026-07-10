# RunPod ComfyUI Manga Pod Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a disposable RunPod GPU pod running ComfyUI that generates anime/manga-comic panels for DeenWell and Oberas Co., and trains the character/setting LoRAs that keep them consistent — with all durable state on a persistent network volume and under 1MB on the local machine.

**Architecture:** A cheap, always-on RunPod **network volume** holds the 7GB Illustrious-XL v2.0 checkpoint, custom nodes, LoRAs, datasets, and output. An expensive, **disposable on-demand 24GB pod** mounts it, runs ComfyUI on `:8188`, and is terminated when idle. An idempotent `bootstrap.sh` on the volume reconstructs the pod from the stock RunPod ComfyUI template. Training happens inside ComfyUI via FluxTrainer nodes — no second service.

**Tech Stack:** RunPod (network volume + on-demand pod), ComfyUI, Illustrious-XL v2.0 (SDXL family), ComfyUI-Inspire-Pack (batch prompts), ComfyUI-WD14-Tagger (auto-captioning), ComfyUI-FluxTrainer (SDXL LoRA training), Bash.

**Spec:** `docs/superpowers/specs/2026-07-09-runpod-comfyui-manga-pod-design.md`

---

## A note on what is and isn't testable here

Tasks 3–4 are real TDD: `lib/fetch.sh` is pure shell with injectable download/clone commands, so idempotency is tested with stubs and no network. Run those tests on Windows via Git Bash.

Tasks 5–6 and 8–16 are RunPod console actions and ComfyUI node-graph construction. They cannot be unit tested. Each carries an explicit **observable check** instead — a command to run or a thing to look at, with the expected result stated. Do not skip these; they are the verification.

**Do not hand-author `workflows/*.json`.** ComfyUI workflow files carry generated node IDs and link arrays. A fabricated one will not load. Those tasks tell you which nodes to add and which widget values to set, then have you export from the UI.

## File structure

| File | Responsibility |
|---|---|
| `lib/fetch.sh` | Idempotent fetch primitives. Sourceable, no side effects on import. The only tested code. |
| `bootstrap.sh` | Orchestrator. Declares *what* to fetch; `lib/fetch.sh` knows *how*. |
| `tests/test_fetch.sh` | Proves idempotency with stubbed downloader/cloner. No network. |
| `workflows/manga_txt2img.json` | Generation. LoRA branch bypassable for Oberas. Exported from UI. |
| `workflows/lora_train.json` | WD14 tag → FluxTrainer SDXL. Exported from UI. |
| `prompts/scaffold.md` | Tag order, pinned negative prompt, rating/score levers. |
| `prompts/example_chapter.txt` | `Load Prompts From File` format reference. |
| `README.md` | Pod create → attach volume → bootstrap → open `:8188`. |

`bootstrap.sh` and `lib/fetch.sh` are split so the fetch logic can be sourced by tests without executing a 7GB download.

---

## Task 1: Verify the Illustrious v2.0 license before anything else

This is a blocker. The entire commercial premise of the design rests on one unverified fact: the HF model card *tag* reads `creativeml-openrail-m`, but nobody has read the actual license text. If it turns out to carry FAIPL share-alike or a non-commercial clause, the model choice changes and most of this plan is wasted work.

**Files:**
- Modify: `docs/superpowers/specs/2026-07-09-runpod-comfyui-manga-pod-design.md` (Open questions section)

- [ ] **Step 1: Fetch the license file**

Open `https://huggingface.co/OnomaAIResearch/Illustrious-XL-v2.0/blob/main/LICENSE` in a browser. If no `LICENSE` file exists, check `README.md` for an embedded license section, and check the `license:` field in the model card YAML frontmatter.

- [ ] **Step 2: Answer three questions in writing**

1. Does it permit commercial use of **generated images**?
2. Does it require open-sourcing **derivative models** (LoRAs you train on it)?
3. Does it add restrictions beyond stock CreativeML OpenRAIL-M?

- [ ] **Step 3: Decide**

- All clear → continue to Task 2.
- Non-commercial or share-alike on LoRAs → **stop**. Return to the spec's Model section. FLUX.2 [klein] 4B (Apache-2.0) and SDXL base are the fallbacks; neither is anime-native, so this is a real redesign, not a swap.

- [ ] **Step 4: Record the answer in the spec and commit**

Replace the first bullet under `## Open questions` with the finding, dated. Then:

```bash
cd /c/localhost/manga-comfy
git add docs/superpowers/specs/2026-07-09-runpod-comfyui-manga-pod-design.md
git commit -m "docs: record verified Illustrious-XL v2.0 license terms"
```

---

## Task 2: Repo scaffold

**Files:**
- Create: `.gitignore`
- Create: `lib/.gitkeep`, `tests/.gitkeep`, `workflows/.gitkeep`, `prompts/.gitkeep`

- [ ] **Step 1: Create directories**

```bash
cd /c/localhost/manga-comfy
mkdir -p lib tests workflows prompts
touch lib/.gitkeep tests/.gitkeep workflows/.gitkeep prompts/.gitkeep
```

- [ ] **Step 2: Write `.gitignore`**

Nothing large may ever land in this repo. That is the point of the design.

```gitignore
# Never commit model weights, datasets, or output — they live on the RunPod volume.
*.safetensors
*.ckpt
*.pt
*.pth
datasets/
output/
*.png
*.jpg
*.jpeg

# Local noise
.DS_Store
Thumbs.db
```

- [ ] **Step 3: Verify nothing large is tracked**

Run: `git check-ignore -v test.safetensors`
Expected: `.gitignore:3:*.safetensors	test.safetensors`

- [ ] **Step 4: Commit**

```bash
git add .gitignore lib/.gitkeep tests/.gitkeep workflows/.gitkeep prompts/.gitkeep
git commit -m "chore: scaffold repo directories, ignore weights and output"
```

---

## Task 3: `lib/fetch.sh` — idempotent fetch primitives (TDD)

The design's one structural promise is "second run downloads nothing." That is this file, and it is testable without a network by injecting the downloader and cloner as variables.

**Files:**
- Create: `tests/test_fetch.sh`
- Create: `lib/fetch.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_fetch.sh`:

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_fetch.sh`
Expected: FAIL — `lib/fetch.sh: No such file or directory`

- [ ] **Step 3: Write the minimal implementation**

Create `lib/fetch.sh`:

```bash
#!/usr/bin/env bash
# Idempotent fetch primitives for bootstrap.sh.
#
# Sourceable: defines functions and counters, performs no work on import.
# DOWNLOADER and CLONER are injectable so tests can stub them.
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
# Skips when dest exists and is non-empty. A zero-byte file means a previous
# download died halfway; re-fetch it rather than trusting it.
fetch_file() {
  local url="$1" dest="$2"
  if [ -s "$dest" ]; then
    FETCH_SKIPS=$((FETCH_SKIPS + 1))
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  echo "  fetching $(basename "$dest") ..."
  "$DOWNLOADER" "$dest" "$url"
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
  "$CLONER" "$url" "$dest"
  FETCH_CLONES=$((FETCH_CLONES + 1))
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_fetch.sh`
Expected: 15 `ok -` lines, then `all tests passed`, exit 0

- [ ] **Step 5: Commit**

```bash
git add lib/fetch.sh tests/test_fetch.sh
git commit -m "feat: idempotent fetch primitives with stubbed-network tests"
```

---

## Task 4: `bootstrap.sh` — the orchestrator

Declares what to fetch and wires the volume into ComfyUI. Uses `extra_model_paths.yaml` rather than deleting and symlinking ComfyUI's `models/` directory — non-destructive, and the sanctioned mechanism.

**Files:**
- Create: `bootstrap.sh`
- Create: `tests/test_bootstrap.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_bootstrap.sh`:

```bash
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
```

Note: `DOWNLOADER` here is a two-word command (`bash /path/stub.sh`), so `lib/fetch.sh` must invoke it unquoted-word-split. Step 3 adjusts `fetch.sh` accordingly.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_bootstrap.sh`
Expected: FAIL — `bootstrap.sh: No such file or directory`

- [ ] **Step 3: Allow multi-word DOWNLOADER/CLONER in `lib/fetch.sh`**

Change the two invocation lines in `lib/fetch.sh`. Replace:

```bash
  "$DOWNLOADER" "$dest" "$url"
```

with:

```bash
  # shellcheck disable=SC2086  # intentional word-split: DOWNLOADER may be a multi-word command
  $DOWNLOADER "$dest" "$url"
```

and replace:

```bash
  "$CLONER" "$url" "$dest"
```

with:

```bash
  # shellcheck disable=SC2086  # intentional word-split: CLONER may be a multi-word command
  $CLONER "$url" "$dest"
```

Then re-run the Task 3 tests to confirm no regression:

Run: `bash tests/test_fetch.sh`
Expected: `all tests passed`

- [ ] **Step 4: Write `bootstrap.sh`**

⚠️ **The `while` loop below uses a here-string (`<<< "$NODES"`), not a pipe.**
`echo "$NODES" | while read ...` would run the loop in a subshell, discarding
every counter increment — `bootstrap.sh` would report `clones=0` on a *first*
run while silently working. Do not "simplify" it to a pipe.

```bash
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/test_bootstrap.sh`
Expected: 6 `ok -` lines, then `all tests passed`, exit 0

If `clones=4` fails with `clones=0`, the subshell bug is still present — confirm you used the `<<< "$NODES"` here-string form.

- [ ] **Step 6: Commit**

```bash
chmod +x bootstrap.sh
git add bootstrap.sh tests/test_bootstrap.sh lib/fetch.sh
git commit -m "feat: bootstrap.sh reconstructs pod from stock ComfyUI template"
```

---

## Task 5: Create the RunPod network volume

**Files:** none — RunPod console.

- [ ] **Step 1: Pick a region with deep 24GB supply**

In the RunPod console, open **Storage → New Network Volume**. Before choosing, open **Secure Cloud → GPUs** and check RTX 4090 / A5000 availability per datacenter. The volume pins you to one region permanently; a cheap region with no cards is worse than a costlier one with stock.

- [ ] **Step 2: Create a 50GB volume**

Name: `manga-comfy`. Size: **50 GB**.

Sizing: 7GB checkpoint + ~2GB nodes + ~200MB per LoRA + datasets + output. 50GB is roughly $3.50/month.

- [ ] **Step 3: Observable check**

The volume appears under **Storage** with status `Available` and the region you chose. Write that region down — every future pod must be launched in it.

---

## Task 6: Launch the pod and run bootstrap twice

**Files:** none — RunPod console + pod shell.

- [ ] **Step 1: Deploy a pod**

**Pods → Deploy**, in the volume's region.
- GPU: RTX 4090 or A5000 (**24 GB**)
- Template: RunPod's official **ComfyUI** template
- Network volume: `manga-comfy`, mounted at `/workspace`
- Expose HTTP port `8188`

- [ ] **Step 2: Confirm where ComfyUI actually lives**

Templates move things. Open the pod's web terminal:

```bash
ls -d /ComfyUI 2>/dev/null || ls -d /workspace/ComfyUI 2>/dev/null || find / -maxdepth 3 -name "main.py" -path "*ComfyUI*" 2>/dev/null
```

Note the path. If it is not `/ComfyUI`, every `bootstrap.sh` invocation below needs `COMFY_DIR=<that path>`.

- [ ] **Step 3: Get the repo onto the volume**

```bash
cd /workspace
git clone https://github.com/<your-user>/manga-comfy.git repo 2>/dev/null || \
  echo "no remote yet — upload bootstrap.sh + lib/ via the RunPod file browser instead"
```

If there is no GitHub remote yet, create one and push from `C:\localhost\manga-comfy` first. The volume must hold a copy of the script, not just your laptop.

- [ ] **Step 4: First bootstrap run**

```bash
cd /workspace/repo
bash bootstrap.sh
```

Expected: `downloads=1 clones=4 skips=0`, and roughly 7GB pulled. Takes several minutes.

- [ ] **Step 5: Second bootstrap run — the structural promise**

```bash
bash bootstrap.sh
```

Expected: `downloads=0 clones=0 skips=5`, completes in under two seconds.

**If this prints anything else, stop.** The bootstrap is lying and the whole disposable-pod design fails. Fix it before continuing.

- [ ] **Step 6: Restart ComfyUI and confirm it sees the volume**

```bash
pkill -f "python.*main.py" || true
# then let the template restart it, or start it manually per the template's docs
```

Open `https://<pod-id>-8188.proxy.runpod.net`.

**Observable check:** add a `Load Checkpoint` node. Its dropdown lists `Illustrious-XL-v2.0.safetensors`. If empty, `extra_model_paths.yaml` isn't being read — verify `COMFY_DIR` was correct in Step 2.

---

## Task 7: Prompt scaffold

The paper specifies a load-bearing tag order. `rating` and `score` are the primary safety and quality levers, and DeenWell is educational content on a Danbooru-derived base — this file is not decoration.

**Files:**
- Create: `prompts/scaffold.md`

- [ ] **Step 1: Write the scaffold**

````markdown
# Prompt scaffold — Illustrious-XL v2.0

Tag block first, natural-language body after. v2.0's multi-level caption training
accepts both; the tag order below is the order the model was trained on
(arXiv:2409.19946).

## Order

`<person count>, <character names>, <rating>, <general tags>, <artist>, <score range>, <year modifier>`

## Positive template

```
1girl, solo, <character_lora_trigger>, rating_safe, <general tags>, masterpiece, best quality, absurdres, newest,

<natural-language scene description from the prompter skill>
```

Swap `1girl` / `1boy` / `2boys` / `no humans` to match the panel.
`no humans` is the correct opener for landscape, architecture, and object plates.

## Pinned negative — do not omit

The paper's No-Dropout Tokens guarantee 100% recognition of provocative concepts.
They are suppressed at inference, not absent from the model. Every generation
carries this negative.

```
nsfw, nude, nipples, cleavage, revealing clothes, suggestive, lowres, worst quality, low quality, bad anatomy, bad hands, extra digits, fewer digits, watermark, signature, text, error, jpeg artifacts, blurry
```

`text` and `signature` in the negative are deliberate: the model cannot render
legible words. Panels are plates. Arabic calligraphy, ayah text, and speech
bubbles are composited downstream in Remotion.

## Resolutions

| Use | Size |
|---|---|
| Oberas (3:2, pans to 9:16) | 1536 × 1024 |
| DeenWell cover (9:16) | 1024 × 1536 |
| DeenWell square | 1216 × 1216 |

## Aniconism

Prophets and Imams are not depicted. Anime models are trained on
character-centric composition and resist faceless framing. Start with negatives
plus `from behind`, `facing away`, `silhouette`, `back turned`. If the model
keeps producing faces, escalate to ControlNet — do not fight it with prompt
weights.
````

- [ ] **Step 2: Commit**

```bash
git add prompts/scaffold.md
git commit -m "docs: prompt scaffold with pinned negative and tag order"
```

---

## Task 8: Build `manga_txt2img.json` in the ComfyUI UI

Do not hand-write this file.

**Files:**
- Create: `workflows/manga_txt2img.json` (exported from the UI)

- [ ] **Step 1: Build the graph**

In ComfyUI at the proxy URL, construct:

| Node | Widget values |
|---|---|
| `Load Checkpoint` | `Illustrious-XL-v2.0.safetensors` |
| `LoraLoader` ×2 | placeholders; character then setting, chained |
| `CLIP Text Encode` (positive) | positive template from `prompts/scaffold.md` |
| `CLIP Text Encode` (negative) | pinned negative from `prompts/scaffold.md` |
| `Empty Latent Image` | `1536 × 1024`, batch_size **1** |
| `KSampler` | steps 28, cfg 5.0, sampler `euler_ancestral`, scheduler `normal`, denoise 1.0, **seed control: `increment`** |
| `VAE Decode` | — |
| `Save Image` | `filename_prefix`: `oberas/test/panel_` |

`batch_size` stays **1**. It runs N latents through one forward pass with the *same* prompt and scales VRAM ×N. It is not how you generate a chapter. Task 10 handles that.

Chain: `Load Checkpoint` → `LoraLoader` (character) → `LoraLoader` (setting) → both `CLIP Text Encode` nodes and `KSampler`.

- [ ] **Step 2: Bypass both LoRA loaders**

Select each `LoraLoader`, press `Ctrl+B`. They turn purple. Model and CLIP pass straight through.

This is Oberas mode. DeenWell mode un-bypasses them. One workflow, not two.

- [ ] **Step 3: Generate one image**

Queue it. **Observable check:** an image appears, in an anime/manga style, at 1536×1024.

- [ ] **Step 4: Judge it against a reference**

Open one of your existing Midjourney DeenWell or Oberas panels next to it. This is a taste call, not a metric. If the style is unusable, the problem is the model choice and belongs back in the spec — not something more steps will fix.

- [ ] **Step 5: Export and commit**

**Workflow → Export**. Save as `manga_txt2img.json`. Copy it to `C:\localhost\manga-comfy\workflows\` (RunPod file browser, or `scp`).

```bash
cd /c/localhost/manga-comfy
git add workflows/manga_txt2img.json
git commit -m "feat: manga_txt2img workflow, LoRA branch bypassed for Oberas"
```

---

## Task 9: File-driven batch

**Files:**
- Create: `prompts/example_chapter.txt`
- Modify: `workflows/manga_txt2img.json` (re-export)

- [ ] **Step 1: Write the prompt-file format reference**

Create `prompts/example_chapter.txt`. `Load Prompts From File (Inspire)` reads positive, then negative, separated by dashed lines:

```text
1girl, solo, rating_safe, standing in a desert marketplace at dawn, masterpiece, best quality, absurdres, newest,
A young scholar pauses between stalls, dust catching the low sun, merchants unfolding cloth awnings behind her.
---
nsfw, nude, lowres, worst quality, bad anatomy, bad hands, watermark, signature, text, blurry
---
no humans, rating_safe, interior of a stone library, shafts of light, masterpiece, best quality, absurdres, newest,
Rows of bound manuscripts on cedar shelves, dust suspended in a single window beam.
---
nsfw, nude, lowres, worst quality, bad anatomy, bad hands, watermark, signature, text, blurry
---
1boy, solo, rating_safe, from behind, facing away, walking a night road, masterpiece, best quality, absurdres, newest,
A traveller seen from behind, lantern low, the road curving into unlit hills.
---
nsfw, nude, lowres, worst quality, bad anatomy, bad hands, watermark, signature, text, blurry
```

Note the third entry: `from behind, facing away` is the aniconism pattern from the scaffold.

- [ ] **Step 2: Copy it to the volume**

Place at `/workspace/prompts/example_chapter.txt` via the RunPod file browser.

- [ ] **Step 3: Wire the node**

In ComfyUI: add `Load Prompts From File (Inspire)`, set `prompt_file` to `example_chapter.txt`. Feed its `ZIPPED_PROMPT` output through the Inspire pack's prompt-extraction node into the positive and negative `CLIP Text Encode` nodes, replacing their literal text.

Set `Save Image` `filename_prefix` to `deenwell/ch_test/panel_`.
Confirm `KSampler` seed control is `increment`.

- [ ] **Step 4: Queue once, observable check**

Queue a single prompt. Because the node emits a *list*, ComfyUI runs three times.

Expected in `/workspace/output/deenwell/ch_test/`:
- **three** images
- named `panel_00001_`, `panel_00002_`, `panel_00003_`
- matching the three prompts **in file order**
- visibly different compositions from each other

If all three look near-identical, seed control is `fixed`. Change it to `increment`.

- [ ] **Step 5: Export and commit**

```bash
git add workflows/manga_txt2img.json prompts/example_chapter.txt
git commit -m "feat: file-driven batch via Inspire Pack Load Prompts From File"
```

---

## Task 10: Prove the pod is disposable

The single claim the whole cost model rests on. Do it now, while the setup is small enough to debug.

**Files:** none.

- [ ] **Step 1: Terminate the pod**

RunPod console → **Terminate**. Not "Stop" — terminate. The volume survives; the pod does not.

- [ ] **Step 2: Deploy a fresh pod**

Same region, same template, same volume at `/workspace`, port `8188`.

- [ ] **Step 3: Bootstrap once**

```bash
cd /workspace/repo && bash bootstrap.sh
```

Expected: `downloads=0 clones=0 skips=5`. Nothing re-downloads — it is all on the volume.

- [ ] **Step 4: Observable check**

Open ComfyUI, load `workflows/manga_txt2img.json`, queue it, get an image.

**Zero manual steps between fresh pod and generated image.** If you had to click anything in ComfyUI-Manager, install a node by hand, or move a file — `bootstrap.sh` is incomplete. Fix it, commit, and repeat this task.

- [ ] **Step 5: Record the result in the README**

Covered in Task 15.

---

## Task 11: Build the character LoRA dataset

**Files:**
- Create: `/workspace/datasets/<character_name>/` (on the volume — never committed)

- [ ] **Step 1: Produce a locked base reference**

Use the `banana-pro-director` skill: single-image character outfit on white seamless studio. This is the identity anchor.

- [ ] **Step 2: Produce a multi-angle character sheet**

Same skill, 6-panel multi-angle sheet off that base.

- [ ] **Step 3: Expand to 20–40 images**

Six panels is a seed set, not a dataset. Expand by generating variations — different poses, framings, lighting, backgrounds — using the sheet as an img2img or IPAdapter reference in ComfyUI.

**Vary the source.** Training 20 images that are all the same style and framing teaches the LoRA a *pose*, not a *person*. Mixed sources buy identity without style lock-in.

- [ ] **Step 4: Upload to the volume**

`/workspace/datasets/<character_name>/` — 20–40 PNG or JPG, roughly 1024px on the short edge, subject centred and clearly readable.

- [ ] **Step 5: Observable check**

```bash
ls /workspace/datasets/<character_name>/ | wc -l
```

Expected: a number between 20 and 40.

---

## Task 12: Auto-caption the dataset

Hand-tagging 40 images is the thing ILXL charges for. Don't do it by hand.

**Files:** none — output lands beside the images on the volume.

- [ ] **Step 1: Build a tagging workflow**

New ComfyUI workflow: `Load Image Batch` (or the WD14 pack's directory loader) → `WD14 Tagger`.

Set: `model` = `wd-v1-4-moat-tagger-v2`, `threshold` = `0.35`, `character_threshold` = `0.85`.

- [ ] **Step 2: Run it over the dataset directory**

Point it at `/workspace/datasets/<character_name>/`. It writes a `.txt` beside each image.

- [ ] **Step 3: Add the trigger token**

Prepend a unique trigger to every caption. Pick something the model has never seen — not a real Danbooru tag.

```bash
cd /workspace/datasets/<character_name>
for f in *.txt; do
  sed -i "1s/^/dwchar_amina, /" "$f"
done
```

- [ ] **Step 4: Observable check**

```bash
head -1 /workspace/datasets/<character_name>/*.txt | head -20
```

Expected: every caption begins `dwchar_amina, ` followed by descriptive tags. Read a few. Wrong tags here become wrong learning — delete captions describing things you don't want bound to the character (a specific background, a one-off prop).

---

## Task 13: Train the character LoRA

**Files:**
- Create: `workflows/lora_train.json` (exported from the UI)

- [ ] **Step 1: Free VRAM**

ComfyUI must release the checkpoint before training. In the ComfyUI menu: **Unload Models**, then **Free model and node cache**. If training OOMs anyway, restart ComfyUI.

- [ ] **Step 2: Build the FluxTrainer SDXL graph**

Use the **SDXL** nodes, not the Flux ones:

| Node | Values |
|---|---|
| `Init SDXL LoRA Training` | model: `Illustrious-XL-v2.0.safetensors`; dataset: `/workspace/datasets/<character_name>`; output: `/workspace/models/loras` |
| | network_dim 32, network_alpha 16 |
| | learning_rate `1e-4`, optimizer `adamw8bit` |
| | max_train_steps **3000**, save_every_n_steps **600** |
| | gradient_checkpointing **on**, mixed_precision `bf16` |
| `Train Loop` | steps as above |
| `Save LoRA` | filename `dwchar_amina` |

`adamw8bit` + gradient checkpointing is what keeps SDXL LoRA training inside 24GB. Turning either off will OOM.

3000 steps is where Illustrious character LoRAs converge. Saving every 600 gives you epochs to compare — the last checkpoint is often *not* the best one.

- [ ] **Step 3: Train**

Queue. Expect **30–90 minutes** on a 4090. Watch the loss; it should fall then flatten.

- [ ] **Step 4: Observable check**

```bash
ls -la /workspace/models/loras/
```

Expected: `dwchar_amina-000600.safetensors` through `dwchar_amina.safetensors`, each roughly 50–200MB.

- [ ] **Step 5: Export and commit the workflow**

```bash
cd /c/localhost/manga-comfy
git add workflows/lora_train.json
git commit -m "feat: SDXL LoRA training workflow via FluxTrainer"
```

The `.safetensors` files are gitignored. They live on the volume. That is correct.

---

## Task 14: Pick the best epoch

**Files:** none.

- [ ] **Step 1: Load `manga_txt2img.json`, un-bypass the character LoraLoader**

`Ctrl+B` on the character `LoraLoader` to re-enable it. Leave the setting one bypassed.

- [ ] **Step 2: Generate the same prompt at each saved epoch**

For each of `-000600`, `-001200`, `-001800`, `-002400`, and final: set the LoRA, `strength_model` `0.7`, `strength_clip` `0.7`, and generate the same prompt with the same fixed seed. Include `dwchar_amina` in the positive.

Use a prompt showing the character in a **new** situation — not one from the dataset. That is the test.

- [ ] **Step 3: Observable check — lay them side by side**

You are looking for the epoch where the face is stable and recognisable but the character can still do new things.

- **Too few steps:** generic anime face, doesn't resemble the reference.
- **Too many steps (overfit):** every image reproduces a dataset pose or background; the character can't turn, can't change clothes, can't be somewhere new.

The sweet spot is usually *not* the final checkpoint.

- [ ] **Step 4: Promote the winner**

```bash
cd /workspace/models/loras
cp dwchar_amina-001800.safetensors dwchar_amina_v1.safetensors
```

- [ ] **Step 5: Record which epoch won and why**

Append to `prompts/scaffold.md` under a new `## Trained LoRAs` heading: the trigger token, the winning epoch, the strength you settled on. Future-you will not remember.

```bash
git add prompts/scaffold.md
git commit -m "docs: record dwchar_amina LoRA trigger, epoch, and strength"
```

---

## Task 15: Train the setting LoRA, then generate one full chapter

The real test of the whole design. Everything before this was plumbing.

**Files:** none new.

- [ ] **Step 1: Build the setting dataset**

20–40 images of one recurring DeenWell location, from varied angles and lighting. Same process as Tasks 11–12. Trigger token: `dwset_masjid`.

- [ ] **Step 2: Train it**

Same `lora_train.json`. Change dataset path and output filename. Same 3000 steps.

Settings often need fewer steps than characters — check the 1200 and 1800 epochs first.

- [ ] **Step 3: Stack both LoRAs**

In `manga_txt2img.json`, un-bypass **both** loaders:
- character: `dwchar_amina_v1`, strength `0.7`
- setting: `dwset_masjid_v1`, strength `0.55`

Both strengths below 1.0 on purpose. Stacked LoRAs interfere — identity bleeds into architecture, palettes collapse toward whichever trained harder.

- [ ] **Step 4: Generate a real chapter**

Write a real 20–40 line `deenwell_ch01.txt` from `deenwell-image-prompter` output. Both trigger tokens in every positive. Queue once.

- [ ] **Step 5: Observable check — read it as a sequence**

Download the panels and view them in order. Ask:

1. Is she the same person in panel 3 and panel 30?
2. Is the masjid the same building, or does it swim between panels?
3. Do the wide shots hold up, or does the architecture dissolve?
4. Did any figure that should be faceless acquire a face?

This is a judgment call. There is no metric.

- [ ] **Step 6: Decide the escalation**

- **Character drifts** → retrain at a different epoch, or raise strength to 0.8.
- **Setting swims, especially on wide shots** → this is expected and is what the spec predicted. Escalate to ControlNet depth with a Blender greybox of that one location. **Only that location.**
- **Palettes muddy, architecture wearing her hair colour** → LoRA interference. Drop setting strength to 0.45 before anything else.
- **Everything holds** → you are done. Blender never enters your life.

- [ ] **Step 7: Record the outcome in the spec**

Append a `## Outcome` section to the design doc: which of the four above happened, what strengths you settled on, whether ControlNet is now required.

```bash
git add docs/superpowers/specs/2026-07-09-runpod-comfyui-manga-pod-design.md
git commit -m "docs: record first-chapter consistency results"
```

---

## Task 16: README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write it**

````markdown
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
   cd /workspace/repo && git pull && bash bootstrap.sh
   ```
   Expect `downloads=0 clones=0 skips=5` on any run after the first.
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

## Costs

| | |
|---|---|
| Network volume, 50GB | ~$3.50/month, always |
| 24GB pod | ~$0.30–0.70/hour, only while running |

The 24GB card exists for LoRA **training**. Inference doesn't need it.

## Gotchas

- **Text doesn't render.** The model cannot write legible words. Panels are
  plates; Arabic calligraphy and speech bubbles are composited in Remotion.
- **Unload models before training** or you will OOM.
- **The volume is region-locked.** Pods must launch in its region.
- **Illustrious v2.0 is the ceiling.** v3.0/v3.5 are Stardust-gated, and v3.5 is
  v-pred — not a drop-in swap. LoRAs trained here are eps LoRAs.
- **Never commit weights.** `.gitignore` blocks `*.safetensors`.

## Tests

```bash
bash tests/test_fetch.sh
bash tests/test_bootstrap.sh
```

Both stub the network. They prove the one thing that matters: a second
`bootstrap.sh` run fetches nothing.
````

- [ ] **Step 2: Verify the tests referenced actually pass**

Run: `bash tests/test_fetch.sh && bash tests/test_bootstrap.sh`
Expected: `all tests passed` twice, exit 0

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: README with session workflow, costs, and gotchas"
```

---

## Self-review

**Spec coverage.** Walked each spec section against the plan:

| Spec section | Task |
|---|---|
| Architecture / volume+pod split | 5, 6 |
| Bootstrap script, idempotent | 3, 4; proven in 6 and 10 |
| Model = Illustrious-XL v2.0 | 4 (URL), 8 (checkpoint dropdown) |
| License open question | **1 — promoted to a blocking first task** |
| v2.0 version ceiling | 16 (README gotchas) |
| Generation params, 1536×1024 | 8 |
| Prompt scaffold + tag order | 7 |
| Safety / pinned negative | 7, used in 8, 9 |
| Batch generation, Inspire Pack | 9 |
| One workflow two modes, bypass | 8, 16 |
| Character LoRA | 11, 12, 13, 14 |
| Setting LoRA | 15 |
| Stacked-LoRA interference | 15 (strengths 0.7 / 0.55, step 6) |
| Rejected: hosted training | not a task — a decision, recorded in spec |
| ControlNet escalation | 15 step 6 |
| Text composited downstream | 7, 16 |
| Aniconism | 7, 9 (`from behind`), 15 step 5 |
| Local footprint near-zero | 2 (`.gitignore`), 16 |
| Verification: bootstrap twice, fresh pod | 6, **10** |
| Cost | 16 |

Gap found and closed: the spec's verification demands a fresh-pod reconstruction; it had no task. That is now **Task 10**, placed early — before LoRA work adds variables that make failure hard to localise.

**Placeholder scan.** `<your-user>`, `<character_name>`, `<pod-id>` are user-supplied values, not placeholders for undone thinking. `<character_name>` resolves to the concrete `dwchar_amina` from Task 12 onward. No TBDs, no "add error handling," no "similar to Task N."

**Type consistency.** `fetch_file`, `fetch_node`, `ensure_dirs`, `fetch_reset_counters`, `FETCH_DOWNLOADS`, `FETCH_CLONES`, `FETCH_SKIPS`, `WORKSPACE`, `COMFY_DIR`, `DOWNLOADER`, `CLONER`, `SKIP_PIP` are used identically in Tasks 3, 4, and their tests. Trigger tokens `dwchar_amina` / `dwset_masjid` are consistent across 12–15. The promoted LoRA filename `dwchar_amina_v1` (Task 14) is what Task 15 loads.

**Correctness note.** Task 4 ships one correct `bootstrap.sh`, with a warning above it about the pipe-into-`while` subshell trap — the single most likely way an implementer silently breaks the idempotency guarantee. Task 4 Step 5 names the symptom (`clones=0` on a *first* run) so it is diagnosable rather than mysterious. An earlier draft of this plan demonstrated the bug before fixing it; that was removed, because a plan read out of order would have handed someone broken code.
